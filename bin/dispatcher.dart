// Finds the backlog tasks that can start and does the git work of one task
// run. An agent coordinates the run: it starts the task, has a subagent per
// stage (implementer, tests, reviewer) do the work, and finishes or blocks it.
//
//   <dart> run planner_dispatcher:dispatcher check
//   <dart> run planner_dispatcher:dispatcher models <ID> --tool=<tool>
//   <dart> run planner_dispatcher:dispatcher start <ID> --tool=<tool>
//       [--implementer=M[:EFFORT]] [--tests=M[:EFFORT]] [--reviewer=M[:EFFORT]]
//   <dart> run planner_dispatcher:dispatcher checks <ID>
//   <dart> run planner_dispatcher:dispatcher commit <ID> --role=implementer|tests|reviewer --message='<subject>'
//   <dart> run planner_dispatcher:dispatcher finish <ID>
//   <dart> run planner_dispatcher:dispatcher block <ID>
//   <dart> run planner_dispatcher:dispatcher guard
//
// <dart> is the `dart` value of planner_dispatcher.yaml, which every command
// except the usage text reads first. The rules of each part live in lib/src/
// and are unit tested there. `finish` and `block` print one line
// `RESULT {json}` at the end.
import 'dart:convert';
import 'dart:io';

import 'package:planner_dispatcher/src/command_runner.dart';
import 'package:planner_dispatcher/src/config.dart';
import 'package:planner_dispatcher/src/extensions/touch_paths.dart';
import 'package:planner_dispatcher/src/extensions/command_options.dart';
import 'package:planner_dispatcher/src/role_models.dart';
import 'package:planner_dispatcher/src/guard.dart';
import 'package:planner_dispatcher/src/task.dart';
import 'package:planner_dispatcher/src/task_finisher.dart';
import 'package:planner_dispatcher/src/task_loader.dart';
import 'package:planner_dispatcher/src/task_selector.dart';
import 'package:planner_dispatcher/src/task_worktree.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exit(64);
  }
  if (!_commands.contains(args.first)) exit(_usage());
  try {
    _config = DispatcherConfig.load();
  } on ConfigError catch (error) {
    stderr.writeln(error);
    exit(78);
  }
  final rest = args.skip(1).toList();
  try {
    exit(await _run(args.first, rest));
  } on StateError catch (error) {
    // A git or gh call that must work, for example with no network.
    stderr.writeln(error.message);
    exit(1);
  }
}

Future<int> _run(String command, List<String> rest) async {
  return switch (command) {
    'check' => await _check(),
    'start' => await _start(rest),
    'checks' => await _checks(rest),
    'commit' => await _commit(rest),
    'finish' => await _finish(rest),
    'block' => await _block(rest),
    'guard' => await _guard(),
    'models' => await _models(rest),
    _ => _usage(),
  };
}

const _commands = {'check', 'models', 'start', 'checks', 'commit', 'finish', 'block', 'guard'};

late final DispatcherConfig _config;

int _usage() {
  stderr.writeln(
    'Usage: <dart> run planner_dispatcher:dispatcher check | models <ID> --tool=<tool> | start <ID> --tool=<tool> | checks <ID> '
    '| commit <ID> --role=<role> --message=<subject> | finish <ID> | block <ID> | guard',
  );
  return 64;
}

Future<String> _output(String executable, List<String> args) async {
  final result = await runSystemCommand(executable, args);
  return result.ok ? result.stdout.trim() : '';
}

/// The output of a command that must work. Throws a [StateError] with its
/// error, so `check` never shows stale data as if it were current.
Future<String> _required(String executable, List<String> args) async {
  final result = await runSystemCommand(executable, args);
  if (!result.ok) throw StateError('"$executable ${args.join(' ')}" failed: ${result.stderr.trim()}');
  return result.stdout.trim();
}

Future<List<Task>> _tasksOnBase() async {
  await _required('git', ['fetch', 'origin', _config.baseBranch, '--quiet']);
  return TaskLoader.fromGit(
    ref: 'origin/${_config.baseBranch}',
    run: runSystemCommand,
    root: _config.tasksDir,
  ).load();
}

Future<List<String>> _remoteBranches() async {
  final remote = await _required('git', ['ls-remote', '--heads', 'origin']);
  return [
    for (final line in remote.split('\n'))
      if (line.contains('refs/heads/')) line.split('refs/heads/').last.trim(),
  ];
}

Future<List<String>> _openPrHeads() async {
  final pulls = await _required('gh', [
    'pr',
    'list',
    '--state',
    'open',
    '--limit',
    '500',
    '--json',
    'headRefName',
    '--jq',
    '.[].headRefName',
  ]);
  return pulls.split('\n').where((name) => name.isNotEmpty).toList();
}

Map<String, Object?> _taskJson(Task task) => {
  'id': task.id,
  'title': task.title,
  'label': task.label,
  'path': task.indexPath,
  'type': task.type,
  'complexity': task.complexity,
  'dependsOn': task.dependsOn,
  'touches': task.touches,
  'skills': task.skills,
  'branch': task.branch,
};

/// Every task that can start now, with its complexity and the other ready
/// tasks it overlaps with, and why the rest wait.
Future<int> _check() async {
  final tasks = await _tasksOnBase();
  final branches = [...await _remoteBranches(), ...await _openPrHeads()];
  final busy = TaskSelector.busyIdsFromBranches(tasks: tasks, branches: branches);
  final selector = TaskSelector(tasks: tasks, busyIds: busy);
  final ready = selector.candidates();
  final waiting = {
    for (final task in tasks)
      if (task.isReady && !ready.contains(task)) task.label: selector.blockReason(task),
  };
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'ready': [
        for (final task in ready)
          {
            ..._taskJson(task),
            'overlapsWith': [
              for (final other in ready)
                if (other != task && task.touches.overlaps(other.touches)) other.label,
            ],
          },
      ],
      'waiting': waiting,
    }),
  );
  return 0;
}

/// The task named by the one positional argument, or null after printing why.
Future<Task?> _task(List<String> args, {List<Task>? from}) async {
  final ids = args.positional;
  if (ids.length != 1) {
    _usage();
    return null;
  }
  final task = (from ?? await _tasksOnBase()).where((candidate) => candidate.id == ids.first).firstOrNull;
  if (task == null) stderr.writeln('${ids.first} is not a task on origin/${_config.baseBranch}.');
  return task;
}

Map<String, Object?> _modelsJson(Map<Role, RoleModel> models) => {
  for (final MapEntry(key: role, value: model) in models.entries) role.name: model.toJson(),
};

/// The suggested model of each stage of a task for a tool. A tool with no
/// suggestion prints `"suggested": false`, and the user types the models.
Future<int> _models(List<String> args) async {
  final tool = args.options['tool'] ?? '';
  if (tool.isEmpty) return _usage();
  final task = await _task(args);
  if (task == null) return 1;
  final models = RoleModels.suggest(tool: tool, complexity: task.complexity, configModels: _config.models);
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'task': task.label,
      'complexity': task.complexity,
      'tool': tool,
      'suggested': models.length == Role.values.length,
      'models': _modelsJson(models),
    }),
  );
  return 0;
}

/// Creates the task worktree and branch, runs the setup and claims the task,
/// with the suggested models and any the user typed instead. Prints what the
/// coordinating agent needs: the task, the worktree and the subagent call of
/// each stage.
Future<int> _start(List<String> args) async {
  final options = args.options;
  final tool = options['tool'] ?? '';
  if (tool.isEmpty) return _usage();

  final tasks = await _tasksOnBase();
  final task = await _task(args, from: tasks);
  if (task == null) return 1;
  final models = {
    ...RoleModels.suggest(tool: tool, complexity: task.complexity, configModels: _config.models),
    for (final role in Role.values)
      if (options[role.name] case final typed? when typed.trim().isNotEmpty) role: RoleModel.typed(typed),
  };
  final missing = [
    for (final role in Role.values)
      if (!models.containsKey(role)) '--${role.name}',
  ];
  if (missing.isNotEmpty) {
    stderr.writeln('There is no suggested model for $tool: pass ${missing.join(', ')}.');
    return 1;
  }
  final pullRequests = await _openPrHeads();
  if (pullRequests.contains(task.branch)) {
    stderr.writeln('${task.label} already has an open PR.');
    return 1;
  }
  // The task's own branch is checked by TaskWorktree.start: a blocked run is
  // continued, a claimed one refused.
  final branches = [...await _remoteBranches(), ...pullRequests];
  final busy = TaskSelector.busyIdsFromBranches(tasks: tasks, branches: branches)..remove(task.id);
  if (TaskSelector(tasks: tasks, busyIds: busy).blockReason(task) case final reason?) {
    stderr.writeln('${task.label} cannot start: $reason.');
    return 1;
  }
  final TaskWorktree worktree;
  try {
    worktree = await TaskWorktree.start(
      run: runSystemCommand,
      task: task,
      projectRoot: Directory.current.path,
      baseBranch: _config.baseBranch,
      setup: _config.setup,
      tool: tool,
      models: models,
      email: await _output('git', ['config', 'user.email']),
      emailSuffix: _config.gitEmailSuffix,
    );
  } on StateError catch (error) {
    stderr.writeln(error.message);
    return 1;
  }
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      ..._taskJson(task),
      'worktree': worktree.directory,
      'runnerDirectory': worktree.runnerDirectory,
      'tool': tool,
      'stages': {
        for (final MapEntry(key: role, value: model) in models.entries)
          role.name: {'name': model.displayName, 'call': model.callParameters(tool)},
      },
    }),
  );
  return 0;
}

/// Runs the project's check commands in the worktree of a started task and
/// prints only whether they passed, or the failing command and the end of its
/// output. Exits 1 when one fails.
Future<int> _checks(List<String> args) async {
  final ids = args.positional;
  if (ids.length != 1 || !Task.idPattern.hasMatch(ids.first)) return _usage();
  final worktree = TaskWorktree(TaskWorktree.pathOfId(Directory.current.path, ids.first));
  if (!Directory(worktree.directory).existsSync()) {
    stderr.writeln('${ids.first} has no worktree here: run `dispatcher start ${ids.first}` first.');
    return 1;
  }
  final result = await worktree.runChecks(run: runSystemCommand, checks: _config.check);
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'passed': result.passed,
      'commands': [for (final command in _config.check) command.join(' ')],
      if (!result.passed) 'failed': result.failed,
      if (!result.passed) 'tail': result.tail,
    }),
  );
  return result.passed ? 0 : 1;
}

/// The finisher of a task started in this project, or null after printing why.
/// It reads the task from the worktree's run file, so it needs no network.
Future<TaskFinisher?> _finisher(List<String> args) async {
  final ids = args.positional;
  if (ids.length != 1 || !Task.idPattern.hasMatch(ids.first)) {
    _usage();
    return null;
  }
  final worktree = TaskWorktree(TaskWorktree.pathOfId(Directory.current.path, ids.first));
  final task = worktree.task(root: _config.tasksDir);
  final tool = worktree.tool;
  if (task == null || tool == null) {
    stderr.writeln('${ids.first} was not started here: run `dispatcher start ${ids.first}` first.');
    return null;
  }
  return TaskFinisher(
    run: runSystemCommand,
    task: task,
    worktree: worktree,
    config: _config,
    tool: tool,
    models: worktree.models,
    projectRoot: Directory.current.path,
  );
}

/// Runs [action] and prints a [StateError] as one readable message.
Future<int> _orError(Future<void> Function() action) async {
  try {
    await action();
    return 0;
  } on StateError catch (error) {
    stderr.writeln(error.message);
    return 1;
  } on FileSystemException catch (error) {
    stderr.writeln('${error.message}: ${error.path}');
    return 1;
  }
}

Future<int> _commit(List<String> args) async {
  final role = Role.values.asNameMap()[args.options['role'] ?? ''];
  final message = args.options['message'] ?? '';
  if (role == null || message.isEmpty) return _usage();
  final finisher = await _finisher(args);
  if (finisher == null) return 1;
  return _orError(() => finisher.commit(role: role, message: message));
}

Future<int> _finish(List<String> args) async {
  final finisher = await _finisher(args);
  if (finisher == null) return 1;
  return _orError(() async {
    final url = await finisher.finish();
    stdout.writeln('RESULT ${jsonEncode({'taskId': finisher.task.id, 'outcome': 'pullRequest', 'prUrl': url})}');
  });
}

/// Blocks a started task with the question the coordinator wrote to
/// `.runner/question.md` of its worktree. Only that file is read, so no other
/// file of the machine can end up in the pushed notes.
Future<int> _block(List<String> args) async {
  final finisher = await _finisher(args);
  if (finisher == null) return 1;
  final file = File('${finisher.worktree.runnerDirectory}/question.md');
  final question = file.existsSync() ? file.readAsStringSync().trim() : '';
  if (question.isEmpty) {
    stderr.writeln('Write the question to ${file.path} first.');
    return 1;
  }
  return _orError(() async {
    await finisher.block(question);
    stdout.writeln('RESULT ${jsonEncode({'taskId': finisher.task.id, 'outcome': 'blocked', 'message': question})}');
  });
}

/// Checks the current branch before a push, for the planner's branches too.
Future<int> _guard() async {
  final problems = await Guard(
    run: runSystemCommand,
    directory: Directory.current.path,
    baseBranch: _config.baseBranch,
    commitTypes: _config.commitTypes,
    emailSuffix: _config.gitEmailSuffix,
    privatePatterns: _config.privatePatterns,
  ).problems();
  for (final problem in problems) {
    stderr.writeln(problem);
  }
  return problems.isEmpty ? 0 : 1;
}
