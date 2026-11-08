// Picks project tasks and runs them with an AI tool, one clean clone per task.
//
//   <dart> run planner_dispatcher:dispatcher next [--skip=ID,ID]
//   <dart> run planner_dispatcher:dispatcher models
//   <dart> run planner_dispatcher:dispatcher launch <ID> --tool=claude|codex|antigravity
//       [--implementer=MODEL] [--tests=MODEL] [--reviewer=MODEL] [--allow=PATTERN,PATTERN]
//   <dart> run planner_dispatcher:dispatcher status
//
// <dart> is the `dart` value of planner_dispatcher.yaml, which every command
// except the usage text reads first. The rules of each part live in lib/src/
// and are unit tested there.
// `launch` runs until the task ends (PR opened, blocked or failed) and prints
// one line `RESULT {json}` at the end.
import 'dart:convert';
import 'dart:io';

import 'package:planner_dispatcher/src/command_runner.dart';
import 'package:planner_dispatcher/src/config.dart';
import 'package:planner_dispatcher/src/extensions/command_options.dart';
import 'package:planner_dispatcher/src/launch_pipeline.dart';
import 'package:planner_dispatcher/src/model_catalog.dart';
import 'package:planner_dispatcher/src/role_models.dart';
import 'package:planner_dispatcher/src/run_workspace.dart';
import 'package:planner_dispatcher/src/stage_runner.dart';
import 'package:planner_dispatcher/src/task.dart';
import 'package:planner_dispatcher/src/task_loader.dart';
import 'package:planner_dispatcher/src/task_selector.dart';

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
  final code = switch (args.first) {
    'next' => await _next(rest),
    'models' => await _models(),
    'launch' => await _launch(rest),
    'status' => await _status(),
    _ => _usage(),
  };
  exit(code);
}

const _commands = {'next', 'models', 'launch', 'status'};

late final DispatcherConfig _config;

int _usage() {
  stderr.writeln('Usage: <dart> run planner_dispatcher:dispatcher next | models | launch <ID> --tool=<tool> | status');
  return 64;
}

Future<String> _output(String executable, List<String> args) async {
  final result = await runSystemCommand(executable, args);
  return result.ok ? result.stdout.trim() : '';
}

Future<List<Task>> _tasksOnBase() async {
  await runSystemCommand('git', ['fetch', 'origin', _config.baseBranch, '--quiet']);
  return TaskLoader.fromGit(ref: 'origin/${_config.baseBranch}', run: runSystemCommand).load();
}

/// The branches on the remote and the heads of the open PRs.
Future<List<String>> _branchNames() async {
  final remote = await _output('git', ['ls-remote', '--heads', 'origin']);
  final names = [
    for (final line in remote.split('\n'))
      if (line.contains('refs/heads/')) line.split('refs/heads/').last.trim(),
  ];
  final pulls = await _output('gh', [
    'pr',
    'list',
    '--state',
    'open',
    '--json',
    'headRefName',
    '--jq',
    '.[].headRefName',
  ]);
  return [...names, ...pulls.split('\n').where((name) => name.isNotEmpty)];
}

Map<String, Object?> _taskJson(Task task) => {
  'id': task.id,
  'title': task.title,
  'path': task.indexPath,
  'type': task.type,
  'complexity': task.complexity,
  'dependsOn': task.dependsOn,
  'touches': task.touches,
  'skills': task.skills,
  'branch': task.branch,
};

Future<int> _next(List<String> args) async {
  final tasks = await _tasksOnBase();
  final busy = {
    ...TaskSelector.busyIdsFromBranches(tasks: tasks, branches: await _branchNames()),
    for (final run in await _runs())
      if (run['running'] == true && run['taskId'] is String) run['taskId'] as String,
  };
  final selector = TaskSelector(tasks: tasks, busyIds: busy);
  final skipped = (args.options['skip'] ?? '').split(',').where((id) => id.isNotEmpty).toSet();
  final candidates = selector.candidates(skipped: skipped);
  final waiting = {
    for (final task in tasks)
      if (task.isReady && !candidates.contains(task)) task.id: selector.blockReason(task, skipped: skipped),
  };
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert({
      'next': candidates.isEmpty ? null : _taskJson(candidates.first),
      'alsoReady': [for (final task in candidates.skip(1)) task.id],
      'waiting': waiting,
    }),
  );
  return 0;
}

Future<int> _models() async {
  final catalogs = {
    Tool.codex: ModelCatalog.parseCodex(await ModelCatalog.output('codex', ['debug', 'models'])),
    Tool.antigravity: ModelCatalog.parseAntigravity(await ModelCatalog.output('agy', ['models'])),
  };
  for (final tool in Tool.values) {
    stdout.writeln('\n${tool.label}');
    final models = catalogs[tool];
    if (models == null) {
      stdout.writeln('  aliases: sonnet, opus (always the newest model of that family)');
    } else if (models.isEmpty) {
      stdout.writeln('  WARNING: could not retrieve available models');
    } else {
      for (final model in ModelCatalog.latestPerFamily(models)) {
        stdout.writeln('  newest: ${model.id}');
      }
      for (final stale in ModelCatalog.staleModels(tool: tool, models: models, configModels: _config.models)) {
        stdout.writeln('  WARNING: fixed model is missing or old: $stale');
      }
    }
    for (final role in Role.values) {
      final model = RoleModels.of(tool: tool, role: role, configModels: _config.models);
      stdout.writeln('  ${role.name}: ${model.model} (${model.effort})');
    }
  }
  return 0;
}

Future<int> _launch(List<String> args) async {
  final options = args.options;
  final ids = args.positional;
  final tool = Tool.fromName(options['tool'] ?? '');
  if (ids.length != 1 || tool == null) return _usage();

  final tasks = await _tasksOnBase();
  final task = tasks.where((candidate) => candidate.id == ids.first).firstOrNull;
  if (task == null || !task.isReady) {
    stderr.writeln('${ids.first} is not a ready task on origin/${_config.baseBranch}.');
    return 1;
  }
  final pipeline = LaunchPipeline(
    tool: tool,
    stages: const StageRunner(),
    run: runSystemCommand,
    originUrl: await _output('git', ['remote', 'get-url', 'origin']),
    email: await _output('git', ['config', 'user.email']),
    name: await _output('git', ['config', 'user.name']),
    baseDirectory: RunWorkspace.baseDirectory(_config.runFolder),
    config: _config,
    overrides: {
      for (final role in Role.values) role: ?options[role.name],
    },
    extraAllowed: (options['allow'] ?? '').split(',').where((pattern) => pattern.isNotEmpty).toList(),
    log: (line) => stdout.writeln('[${DateTime.now().toIso8601String()}] $line'),
  );
  final result = await pipeline.launch(task);
  stdout.writeln('RESULT ${jsonEncode(result.toJson())}');
  return switch (result.outcome) {
    RunOutcome.pullRequest => 0,
    RunOutcome.blocked => 2,
    RunOutcome.failed => 1,
  };
}

/// The runs that left a state file, and whether their process is alive.
Future<List<Map<String, Object?>>> _runs() async {
  final runs = <Map<String, Object?>>[];
  final base = Directory(RunWorkspace.baseDirectory(_config.runFolder));
  if (!base.existsSync()) return runs;
  for (final entity in base.listSync()) {
    final state = File('${entity.path}/state.json');
    if (!state.existsSync()) continue;
    if (jsonDecode(state.readAsStringSync()) case {'pid': final int pid} && final Map<String, Object?> data) {
      final alive = (await runSystemCommand('kill', ['-0', '$pid'])).ok;
      runs.add({...data, 'running': alive, 'workspace': '${entity.path}/repo'});
    }
  }
  return runs;
}

Future<int> _status() async {
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({'runs': await _runs()}));
  return 0;
}
