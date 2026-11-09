// Creates task worktrees against a temporary bare origin. Git is real; the
// setup commands are faked and nothing touches the network.
import 'dart:io';

import 'package:test/test.dart';

import 'package:planner_dispatcher/src/command_runner.dart';
import 'package:planner_dispatcher/src/role_models.dart';
import 'package:planner_dispatcher/src/task.dart';
import 'package:planner_dispatcher/src/task_worktree.dart';

const _email = 'me@users.noreply.github.com';

String _git(String directory, List<String> args) {
  final result = Process.runSync('git', args, workingDirectory: directory);
  if (result.exitCode != 0) fail('git ${args.join(' ')} failed: ${result.stderr}');
  return (result.stdout as String).trim();
}

final _task = Task.tryParse(
  path: 'docs/backlog/epic-tst/stories/story-01-s/task-01-do-thing/index.md',
  text: '---\nid: TST-01-01\nstatus: ready\ntype: feat\n---\n\n# Do thing\n',
)!;

void main() {
  late String origin;
  late String project;
  final setupCalls = <String>[];
  var setupFails = false;

  Future<CommandResult> run(String executable, List<String> args, {String? workingDirectory}) async {
    if (executable == 'fvm') {
      setupCalls.add('${args.join(' ')} in ${workingDirectory?.split('/').last}');
      return CommandResult(exitCode: setupFails ? 1 : 0, stdout: '', stderr: setupFails ? 'broken' : '');
    }
    return runSystemCommand(executable, args, workingDirectory: workingDirectory);
  }

  Future<TaskWorktree> start({bool resume = false, String email = _email}) => TaskWorktree.start(
    run: run,
    task: _task,
    projectRoot: project,
    baseBranch: 'main',
    setup: [
      ['fvm', 'dart', 'pub', 'get'],
    ],
    tool: 'codex',
    models: RoleModels.suggest(tool: 'codex'),
    email: email,
    emailSuffix: '@users.noreply.github.com',
    resume: resume,
  );

  bool originHas(String branch) =>
      Process.runSync('git', ['rev-parse', '--verify', branch], workingDirectory: origin).exitCode == 0;

  setUp(() {
    setupCalls.clear();
    setupFails = false;
    final root = Directory.systemTemp.createTempSync('task_worktree_test_').resolveSymbolicLinksSync();
    addTearDown(() => Directory(root).deleteSync(recursive: true));
    origin = '$root/origin.git';
    project = '$root/project';
    Directory(origin).createSync();
    _git(origin, ['init', '-q', '--bare', '-b', 'main']);
    _git(root, ['clone', '-q', origin, 'project']);
    _git(project, ['config', 'user.email', _email]);
    _git(project, ['config', 'user.name', 'Me']);
    File('$project/README.md').writeAsStringSync('hi\n');
    _git(project, ['add', '.']);
    _git(project, ['commit', '-q', '-m', 'chore: start']);
    _git(project, ['push', '-q', 'origin', 'main']);
  });

  test('creates the worktree on the task branch, runs the setup in it and claims the branch', () async {
    final worktree = await start();

    expect(worktree.directory, '$project/.worktrees/TST-01-01');
    expect(_git(worktree.directory, ['branch', '--show-current']), _task.branch);
    expect(worktree.tool, 'codex');
    expect(worktree.models[Role.reviewer]?.displayName, 'GPT-6.1 Sol');
    expect(setupCalls, ['dart pub get in TST-01-01']);
    expect(originHas(_task.branch), isTrue);
    expect(_git(project, ['status', '--porcelain']), isEmpty, reason: 'the worktree folder is excluded from git');
    expect(
      File('$project/.git/info/exclude').readAsStringSync(),
      allOf(contains('/.worktrees/'), contains('.runner/')),
    );
  });

  test('refuses a task whose branch is already on the remote, unless resumed', () async {
    final first = await start();
    File('${first.directory}/work.txt').writeAsStringSync('half\n');
    _git(first.directory, ['add', '.']);
    _git(first.directory, ['commit', '-q', '-m', 'wip: half']);
    _git(first.directory, ['push', '-q', 'origin', 'HEAD:${_task.branch}']);
    await first.remove(run: run, projectRoot: project, branch: _task.branch);

    await expectLater(start(), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('--resume'))));

    final resumed = await start(resume: true);
    expect(File('${resumed.directory}/work.txt').readAsStringSync(), 'half\n');
  });

  test('a failing setup removes the worktree and the local branch and claims nothing', () async {
    setupFails = true;

    await expectLater(start(), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('broken'))));
    expect(Directory('$project/.worktrees/TST-01-01').existsSync(), isFalse);
    expect(_git(project, ['branch', '--list', _task.branch]), isEmpty);
    expect(originHas(_task.branch), isFalse);
  });

  test('refuses another git email before changing anything', () async {
    await expectLater(start(email: 'me@work.com'), throwsA(isA<StateError>()));
    expect(Directory('$project/.worktrees').existsSync(), isFalse);
  });

  test('remove deletes the folder and the local branch but keeps the remote branch', () async {
    final worktree = await start();

    await worktree.remove(run: run, projectRoot: project, branch: _task.branch);

    expect(Directory(worktree.directory).existsSync(), isFalse);
    expect(_git(project, ['branch', '--list', _task.branch]), isEmpty);
    expect(originHas(_task.branch), isTrue);
  });
}
