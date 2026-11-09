// Checks the commit rules, the private data scan, the git writes in a real
// temporary repo, and the archiving of a finished task. No network is used.
import 'dart:io';

import 'package:test/test.dart';

import 'package:planner_dispatcher/src/command_runner.dart';
import 'package:planner_dispatcher/src/git_publisher.dart';
import 'package:planner_dispatcher/src/task.dart';
import 'package:planner_dispatcher/src/task_archiver.dart';

String _git(String directory, List<String> args) {
  final result = Process.runSync('git', args, workingDirectory: directory);
  if (result.exitCode != 0) fail('git ${args.join(' ')} failed: ${result.stderr}');
  return (result.stdout as String).trim();
}

Directory _repo() {
  final directory = Directory.systemTemp.createTempSync('dispatcher_git_test_');
  addTearDown(() => directory.deleteSync(recursive: true));
  _git(directory.path, ['init', '-q', '-b', 'master']);
  _git(directory.path, ['config', 'user.email', 'test@users.noreply.github.com']);
  _git(directory.path, ['config', 'user.name', 'Test']);
  return directory;
}

const _types = ['feat', 'fix', 'refactor', 'chore', 'docs', 'style', 'perf', 'test', 'build'];

void main() {
  group('CommitMessage', () {
    test('accepts a lowercase subject with a configured type', () {
      expect(CommitMessage.problem('feat: add the thing', types: _types), isNull);
      expect(CommitMessage.problem('test: cover `x`', types: _types), isNull);
    });

    test('rejects a type that is not configured, including wip', () {
      expect(CommitMessage.problem('wip: tpl-03-02 stopped', types: _types), isNotNull);
      expect(CommitMessage.problem('feat: add the thing', types: ['fix']), isNotNull);
    });

    test('rejects a missing type, a capital letter, a final period or an empty subject', () {
      expect(CommitMessage.problem('add the thing', types: _types), isNotNull);
      expect(CommitMessage.problem('feat: Add the thing', types: _types), isNotNull);
      expect(CommitMessage.problem('feat: add the thing.', types: _types), isNotNull);
      expect(CommitMessage.problem('', types: _types), isNotNull);
    });
  });

  group('DiffScanner', () {
    final home = [
      '',
      'Us'
          'ers',
      'someone',
      'x.txt',
    ].join('/');

    test('finds a local path in an added line, with its file', () {
      final findings = DiffScanner.scan('+++ b/lib/a.dart\n@@ -0,0 +1 @@\n+const p = "$home";\n');

      expect(findings, ['lib/a.dart has a local home path']);
    });

    test('ignores removed lines and clean additions', () {
      expect(DiffScanner.scan('+++ b/a\n-const p = "$home";\n+const ok = 1;\n'), isEmpty);
    });

    test('adds the project patterns to the built-in ones', () {
      const diff = '+++ b/a.md\n@@ -0,0 +1 @@\n+mail me@example.com\n';

      expect(DiffScanner.scan(diff), isEmpty);
      expect(DiffScanner.scan(diff, extra: {'a company email': RegExp(r'@example\.com')}), [
        'a.md has a company email',
      ]);
    });
  });

  group('GitPublisher', () {
    test('commits everything with the trailer, and does nothing when there is no change', () async {
      final directory = _repo();
      final publisher = GitPublisher(workspace: directory.path, run: runSystemCommand, baseBranch: 'master');

      expect(await publisher.commitAll(subject: 'chore: nothing', trailer: 'Co-Authored-By: Claude'), isNull);
      expect(Process.runSync('git', ['rev-parse', 'HEAD'], workingDirectory: directory.path).exitCode, isNot(0));

      File('${directory.path}/a.txt').writeAsStringSync('a');
      expect(await publisher.commitAll(subject: 'feat: add a', trailer: 'Co-Authored-By: Claude Sonnet 5.5'), isNull);

      expect(_git(directory.path, ['log', '-1', '--format=%s']), 'feat: add a');
      expect(_git(directory.path, ['log', '-1', '--format=%B']), contains('Co-Authored-By: Claude Sonnet 5.5'));
    });

    test('never pushes to the base branch, master or main', () async {
      const publisher = GitPublisher(workspace: '.', run: runSystemCommand, baseBranch: 'develop');

      expect(await publisher.push('develop'), contains('Refusing'));
      expect(await publisher.push('master'), contains('Refusing'));
      expect(await publisher.push('main'), contains('Refusing'));
    });

    test('reports no goldens when the project has no golden folder', () async {
      const publisher = GitPublisher(workspace: '/nowhere', run: runSystemCommand, baseBranch: 'main');

      expect(await publisher.changedGoldens(), isEmpty);
    });
  });

  group('TaskArchiver', () {
    for (final root in ['docs/backlog', 'planning/tasks']) {
      test('moves the task to done/, marks it done and fixes the links under $root', () async {
        final directory = _repo();
        void write(String path, String text) {
          File('${directory.path}/$path')
            ..createSync(recursive: true)
            ..writeAsStringSync(text);
        }

        final task = '$root/e/stories/01-s/01-a';
        write(
          '$task/index.md',
          '---\nid: E-01-01\nstatus: ready\ntype: feat\n---\n\n# Add a\n\nStory: [S](../index.md)\n\nMockup: [m](mockup.html)\n\n'
              '## Acceptance\n\n- [ ] When x, then y.\n\n## Other\n\n- [ ] keep\n',
        );
        write('$task/mockup.html', '<html></html>');
        write('$root/e/stories/01-s/index.md', '# Story\n\n1. [Add a](01-a/index.md)\n');
        _git(directory.path, ['add', '-A']);
        _git(directory.path, ['commit', '-q', '-m', 'seed']);

        final parsed = Task.tryParse(
          path: '$task/index.md',
          text: File('${directory.path}/$task/index.md').readAsStringSync(),
        );
        if (parsed == null) fail('The sample task did not parse.');
        final newDirectory = await TaskArchiver(workspace: directory.path, run: runSystemCommand, tasksDir: root)
            .archive(
              parsed,
              notes: '## Summary\n\nDone.',
            );

        expect(newDirectory, '$root/e/stories/01-s/done/01-a');
        final index = File('${directory.path}/$newDirectory/index.md').readAsStringSync();
        expect(index, contains('status: done'));
        expect(index, contains('- [x] When x, then y.'));
        expect(index, contains('- [ ] keep'));
        expect(index, contains('[S](../../index.md)'));
        expect(index, contains('[m](mockup.html)'));
        expect(File('${directory.path}/$newDirectory/notes.md').readAsStringSync(), contains('Done.'));
        expect(
          File('${directory.path}/$root/e/stories/01-s/index.md').readAsStringSync(),
          contains('(done/01-a/index.md)'),
        );
        expect(Directory('${directory.path}/$task').existsSync(), isFalse);
      });
    }
  });
}
