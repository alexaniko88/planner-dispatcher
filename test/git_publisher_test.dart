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
      expect(CommitMessage.problem('test: cover the store', types: _types), isNull);
    });

    test('rejects a subject longer than 72 characters or starting with a backtick', () {
      expect(CommitMessage.problem('feat: ${'a' * 66}', types: _types), isNull);
      expect(CommitMessage.problem('feat: ${'a' * 67}', types: _types), isNotNull);
      expect(CommitMessage.problem('test: `x` covered', types: _types), isNotNull);
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
      final findings = DiffScanner.scan(
        'diff --git a/lib/a.dart b/lib/a.dart\n+++ b/lib/a.dart\n@@ -0,0 +1 @@\n+const p = "$home";\n',
      );

      expect(findings, ['lib/a.dart has a local home path']);
    });

    test('ignores removed lines and clean additions', () {
      expect(DiffScanner.scan('diff --git a/a b/a\n+++ b/a\n@@\n-const p = "$home";\n+const ok = 1;\n'), isEmpty);
    });

    test('scans an added line that starts with ++, so it cannot pass as a file header', () {
      final findings = DiffScanner.scan('diff --git a/a b/a\n+++ b/a\n@@ -0,0 +1 @@\n+++ "$home"\n');

      expect(findings, ['a has a local home path']);
    });

    test('finds the current token formats but not a task folder name', () {
      String added(String text) => 'diff --git a/a b/a\n+++ b/a\n@@ -0,0 +1 @@\n+$text\n';
      final key = ['sk', 'ant', 'api03', 'a' * 30].join('-');
      final pat = ['github', 'pat', 'A' * 30].join('_');

      expect(DiffScanner.scan(added('key = $key')), ['a has a secret key']);
      expect(DiffScanner.scan(added('token = $pat')), ['a has a GitHub token']);
      expect(DiffScanner.scan(added('docs/backlog/task-01-save-the-template-of-the-store/index.md')), isEmpty);
    });

    test('adds the project patterns to the built-in ones', () {
      const diff = 'diff --git a/a.md b/a.md\n+++ b/a.md\n@@ -0,0 +1 @@\n+mail me@example.com\n';

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
      test('closes tasks, then their story and epic once nothing is open, under $root', () async {
        final directory = _repo();
        void write(String path, String text) {
          File('${directory.path}/$path')
            ..createSync(recursive: true)
            ..writeAsStringSync(text);
        }

        String task(String id, String title) =>
            '---\nid: $id\nstatus: ready\ntype: feat\n---\n\n# $title\n\nStory: [S](../index.md)\n\n'
            'Epic: [E](../../../index.md)\n\n## Acceptance\n\n- [ ] When x, then y.\n\n## Other\n\n- [ ] keep\n';
        final epic = '$root/epic-e';
        final one = '$epic/stories/story-01-one';
        final two = '$epic/stories/story-02-two';
        write(
          '$epic/index.md',
          '# EPIC: E\n\n1. [One](stories/story-01-one/index.md)\n2. [Two](stories/story-02-two/index.md)\n',
        );
        write(
          '$one/index.md',
          '# STORY 1\n\nEpic: [E](../../index.md)\n\n1. [A](task-01-a/index.md)\n2. [B](task-02-b/index.md)\n',
        );
        write('$two/index.md', '# STORY 2\n\nEpic: [E](../../index.md)\n\n1. [C](task-01-c/index.md)\n');
        write('$one/task-01-a/index.md', task('E-01-01', 'Add a'));
        write('$one/task-01-a/mockup.html', '<html></html>');
        write('$one/task-02-b/index.md', task('E-01-02', 'Add b'));
        write('$two/task-01-c/index.md', task('E-02-01', 'Add c'));
        _git(directory.path, ['add', '-A']);
        _git(directory.path, ['commit', '-q', '-m', 'seed']);

        Future<String> archive(String path) async {
          final parsed = Task.tryParse(
            path: '$path/index.md',
            text: File('${directory.path}/$path/index.md').readAsStringSync(),
          );
          if (parsed == null) fail('The sample task did not parse.');
          final moved = await TaskArchiver(
            workspace: directory.path,
            run: runSystemCommand,
            tasksDir: root,
          ).archive(parsed, notes: '## Summary\n\nDone.');
          _git(directory.path, ['add', '-A']);
          _git(directory.path, ['commit', '-q', '-m', 'close']);
          return moved;
        }

        String read(String path) => File('${directory.path}/$path').readAsStringSync();

        final a = await archive('$one/task-01-a');
        expect(a, '$one/done/task-01-a');
        final index = read('$a/index.md');
        expect(index, contains('status: done'));
        expect(index, contains('- [x] When x, then y.'));
        expect(index, contains('- [ ] keep'));
        expect(index, contains('Story: [S](../../index.md)'));
        expect(read('$a/notes.md'), contains('Done.'));
        expect(read('$one/index.md'), contains('(done/task-01-a/index.md)'));

        final b = await archive('$one/task-02-b');
        final closedOne = '$epic/stories/done/story-01-one';
        expect(b, '$closedOne/done/task-02-b');
        expect(Directory('${directory.path}/$one').existsSync(), isFalse);
        expect(read('$epic/index.md'), contains('(stories/done/story-01-one/index.md)'));
        expect(read('$closedOne/index.md'), contains('Epic: [E](../../../index.md)'));
        expect(read('$closedOne/done/task-01-a/index.md'), contains('Epic: [E](../../../../../index.md)'));
        expect(File('${directory.path}/$closedOne/done/task-01-a/mockup.html').existsSync(), isTrue);

        final c = await archive('$two/task-01-c');
        final closedEpic = '$root/done/epic-e';
        expect(c, '$closedEpic/stories/done/story-02-two/done/task-01-c');
        expect(Directory('${directory.path}/$epic').existsSync(), isFalse);
        expect(read('$closedEpic/index.md'), contains('(stories/done/story-02-two/index.md)'));
        expect(read('$c/index.md'), contains('Story: [S](../../index.md)'));
      });
    }

    test('a standalone task moves to done/ with no story to close', () async {
      final directory = _repo();
      File('${directory.path}/docs/backlog/bugs/task-01-crash/index.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nid: BUG-01\nstatus: ready\ntype: fix\n---\n\n# Fix crash\n');
      _git(directory.path, ['add', '-A']);
      _git(directory.path, ['commit', '-q', '-m', 'seed']);
      final parsed = Task.tryParse(
        path: 'docs/backlog/bugs/task-01-crash/index.md',
        text: File('${directory.path}/docs/backlog/bugs/task-01-crash/index.md').readAsStringSync(),
      );
      if (parsed == null) fail('The sample task did not parse.');

      final moved = await TaskArchiver(
        workspace: directory.path,
        run: runSystemCommand,
      ).archive(parsed, notes: 'Done.');

      expect(moved, 'docs/backlog/bugs/done/task-01-crash');
    });
  });
}
