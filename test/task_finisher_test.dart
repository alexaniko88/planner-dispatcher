// Runs the end of a task (commit, finish, block) and the guard against a
// temporary bare origin. Git is real; `gh` and the setup are faked.
import 'dart:io';

import 'package:test/test.dart';

import 'package:planner_dispatcher/src/command_runner.dart';
import 'package:planner_dispatcher/src/config.dart';
import 'package:planner_dispatcher/src/guard.dart';
import 'package:planner_dispatcher/src/pr_body.dart';
import 'package:planner_dispatcher/src/role_models.dart';
import 'package:planner_dispatcher/src/task.dart';
import 'package:planner_dispatcher/src/task_finisher.dart';
import 'package:planner_dispatcher/src/task_worktree.dart';

const _email = 'me@users.noreply.github.com';
const _taskDirectory = 'docs/backlog/epic-tst/stories/story-01-s/task-01-do-thing';
const _taskText = '''---
id: TST-01-01
status: ready
type: feat
touches: [lib/thing.dart]
---

# Do thing

## Acceptance

- [ ] When asked, then it does the thing. Check: `dart test`.
''';

const _config = DispatcherConfig(
  dart: 'dart',
  baseBranch: 'main',
  setup: [],
  check: [
    ['dart', 'test'],
  ],
  rules: [],
  commitTypes: ['feat', 'docs', 'test'],
  gitEmailSuffix: '@users.noreply.github.com',
);

const _report = '''## Summary

Adds the thing.

## Evidence

- `dart test` passed.

## Checks

All checks passed (`dart test`).

## Points to review

None.
''';

String _git(String directory, List<String> args) {
  final result = Process.runSync('git', args, workingDirectory: directory);
  if (result.exitCode != 0) fail('git ${args.join(' ')} failed: ${result.stderr}');
  return (result.stdout as String).trim();
}

void main() {
  late String origin;
  late String project;
  late Task task;
  final ghCalls = <List<String>>[];

  Future<CommandResult> run(String executable, List<String> args, {String? workingDirectory}) async {
    if (executable == 'gh') {
      ghCalls.add(args);
      return const CommandResult(exitCode: 0, stdout: 'https://github.com/owner/repo/pull/7\n', stderr: '');
    }
    return runSystemCommand(executable, args, workingDirectory: workingDirectory);
  }

  Future<TaskFinisher> started() async {
    final worktree = await TaskWorktree.start(
      run: run,
      task: task,
      projectRoot: project,
      baseBranch: 'main',
      setup: const [],
      tool: 'claude',
      models: RoleModels.suggest(tool: 'claude'),
      email: _email,
      emailSuffix: _config.gitEmailSuffix,
    );
    return TaskFinisher(
      run: run,
      task: task,
      worktree: worktree,
      config: _config,
      tool: 'claude',
      models: worktree.models,
      projectRoot: project,
    );
  }

  void write(TaskFinisher finisher, String path, String text) {
    File('${finisher.worktree.directory}/$path')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  String originLog(String format) => _git(origin, ['log', '--format=$format', task.branch]);

  setUp(() {
    ghCalls.clear();
    final root = Directory.systemTemp.createTempSync('task_finisher_test_').resolveSymbolicLinksSync();
    addTearDown(() => Directory(root).deleteSync(recursive: true));
    origin = '$root/github.com/owner/repo.git';
    project = '$root/project';
    Directory(origin).createSync(recursive: true);
    _git(origin, ['init', '-q', '--bare', '-b', 'main']);
    _git(root, ['clone', '-q', origin, 'project']);
    _git(project, ['config', 'user.email', _email]);
    _git(project, ['config', 'user.name', 'Me']);
    for (final MapEntry(:key, :value) in {
      'docs/backlog/epic-tst/index.md': '---\nabbr: TST\n---\n\n# Epic\n\n- [S](stories/story-01-s/index.md)\n',
      'docs/backlog/epic-tst/stories/story-01-s/index.md': '# Story\n\n- [Do thing](task-01-do-thing/index.md)\n',
      '$_taskDirectory/index.md': _taskText,
    }.entries) {
      File('$project/$key')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(value);
    }
    _git(project, ['add', '.']);
    _git(project, ['commit', '-q', '-m', 'docs: add the task']);
    _git(project, ['push', '-q', 'origin', 'main']);
    task = Task.tryParse(path: '$_taskDirectory/index.md', text: _taskText, root: 'docs/backlog')!;
  });

  group('TaskFinisher', () {
    test('commit attributes the stage model and refuses a bad subject', () async {
      final finisher = await started();
      write(finisher, 'lib/thing.dart', 'void thing() {}\n');

      await expectLater(finisher.commit(role: Role.implementer, message: 'Add thing.'), throwsA(isA<StateError>()));
      await finisher.commit(role: Role.implementer, message: 'feat: add the thing');

      final body = _git(finisher.worktree.directory, ['log', '-1', '--format=%B']);
      expect(body, contains('feat: add the thing'));
      expect(body, contains('Co-Authored-By: Claude Sonnet 5.5'));
    });

    test('finish closes the task, pushes, opens the PR and removes the worktree', () async {
      final finisher = await started();
      write(finisher, 'lib/thing.dart', 'void thing() {}\n');
      await finisher.commit(role: Role.implementer, message: 'feat: add the thing');
      write(finisher, '.runner/report.md', _report);

      final url = await finisher.finish();

      expect(url, 'https://github.com/owner/repo/pull/7');
      expect(originLog('%s').split('\n'), [
        'docs: close task tst-01-01 do-thing',
        'feat: add the thing',
        'docs: add the task',
      ]);
      final create = ghCalls.single;
      expect(
        create,
        containsAllInOrder(['pr', 'create', '--base', 'main', '--head', task.branch, '--title', 'feat: do thing']),
      );
      expect(Directory(finisher.worktree.directory).existsSync(), isFalse);
      final done = _git(origin, ['ls-tree', '-r', '--name-only', task.branch]);
      expect(done, contains('docs/backlog/done/epic-tst/stories/done/story-01-s/done/task-01-do-thing/notes.md'));
    });

    test('finish refuses uncommitted work or a missing report and pushes nothing new', () async {
      final finisher = await started();
      write(finisher, 'lib/thing.dart', 'void thing() {}\n');

      await expectLater(
        finisher.finish(),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('uncommitted'))),
      );
      await finisher.commit(role: Role.implementer, message: 'feat: add the thing');
      await expectLater(
        finisher.finish(),
        throwsA(isA<StateError>().having((e) => e.message, 'message', contains('report'))),
      );

      expect(originLog('%s'), 'docs: add the task');
      expect(Directory(finisher.worktree.directory).existsSync(), isTrue);
    });

    test('block writes the question, pushes a wip commit and removes the worktree', () async {
      final finisher = await started();
      write(finisher, 'lib/thing.dart', 'void thing() {}\n');

      await finisher.block('Which store should it use?');

      expect(originLog('%s').split('\n').first, 'wip: tst-01-01 do-thing stopped');
      final notes = _git(origin, ['show', '${task.branch}:$_taskDirectory/notes.md']);
      expect(notes, contains('## Blocked\n\nWhich store should it use?'));
      expect(Directory(finisher.worktree.directory).existsSync(), isFalse);
    });
  });

  group('Guard', () {
    Guard guard(String directory) => Guard(
      run: run,
      directory: directory,
      baseBranch: 'main',
      commitTypes: _config.commitTypes,
      emailSuffix: _config.gitEmailSuffix,
    );

    test('passes a clean task branch', () async {
      final finisher = await started();
      write(finisher, 'lib/thing.dart', 'void thing() {}\n');
      await finisher.commit(role: Role.implementer, message: 'feat: add the thing');

      expect(await guard(finisher.worktree.directory).problems(), isEmpty);
    });

    test('finds the base branch, another email, a bad subject and private data', () async {
      _git(project, ['config', 'user.email', 'me@work.com']);
      final home = [
        '',
        'Us'
            'ers',
        'someone',
        'x',
      ].join('/');
      File('$project/lib/a.dart')
        ..parent.createSync(recursive: true)
        ..writeAsStringSync('const p = "$home";\n');
      _git(project, ['add', '.']);
      _git(project, ['commit', '-q', '-m', 'Add a']);

      final problems = await guard(project).problems();

      expect(problems, hasLength(4));
      expect(
        problems.join('\n'),
        allOf(contains('"main"'), contains('me@work.com'), contains('Add a'), contains('home path')),
      );
    });
  });

  group('PrBody', () {
    String build({String points = 'None.', List<GoldenChange> goldens = const []}) => PrBody.build(
      task: task,
      summary: 'Adds the thing.',
      checks: 'All checks passed.',
      pointsToReview: points,
      goldens: goldens,
      slug: 'owner/repo',
      baseSha: 'b1',
      headSha: 'h1',
      taskPath: 'docs/backlog/done/x/index.md',
    );

    test('has the summary with the task link, the checked acceptance and the checks', () {
      final body = build();

      expect(
        body,
        contains(
          '## Summary\n\nAdds the thing.\n\nTask: [Do thing (TST-01-01)](https://github.com/owner/repo/blob/h1/docs/backlog/done/x/index.md)',
        ),
      );
      expect(body, contains('- [x] When asked, then it does the thing.'));
      expect(body, contains('## Checks\n\nAll checks passed.'));
      expect(body, isNot(contains('## Points to review')));
      expect(body, isNot(contains('## Visual changes')));
    });

    test('shows the points to review and the changed goldens only when there are some', () {
      final body = build(
        points: '- `lib/a.dart:3`: check the name.',
        goldens: const [GoldenChange(path: 'test/goldens/home.png', existedBefore: true)],
      );

      expect(body, contains('## Points to review\n\n- `lib/a.dart:3`: check the name.'));
      expect(
        body,
        contains('| home.png | ![before](https://github.com/owner/repo/blob/b1/test/goldens/home.png?raw=true) |'),
      );
    });
  });
}
