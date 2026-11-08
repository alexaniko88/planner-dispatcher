import 'dart:convert';
import 'dart:io';

import 'command_runner.dart';
import 'task.dart';

/// The temporary clone one task run works in. It lives in the system temp
/// folder and is deleted when the task ends.
class RunWorkspace {
  /// The folder of the run: `<temp>/<run folder>/<task id>`.
  final String root;

  const RunWorkspace(this.root);

  /// The clone itself.
  String get directory => '$root/repo';

  /// Reports and scratch files; excluded from git.
  String get runnerDirectory => '$directory/.runner';

  String get stateFile => '$root/state.json';

  /// Where every run lives, for the project's `run_folder`.
  static String baseDirectory(String runFolder) => '${Directory.systemTemp.path}/$runFolder';

  /// Clones the base branch, creates (or continues) the task branch and runs
  /// the project's setup commands in the clone. Throws a [StateError] with a readable message on failure, and
  /// cleans up on any error.
  static Future<RunWorkspace> prepare({
    required RunCommand run,
    required Task task,
    required String originUrl,
    required String email,
    required String name,
    required String tool,
    required String baseDirectory,
    required String baseBranch,
    required List<List<String>> setup,
    String? emailSuffix,
    bool skipSetup = false,
  }) async {
    if (emailSuffix != null && !email.endsWith(emailSuffix)) {
      throw StateError('The git email "$email" does not end with "$emailSuffix" (git_email_suffix).');
    }
    final workspace = RunWorkspace('$baseDirectory/${task.id}');
    if (Directory(workspace.root).existsSync()) {
      throw StateError('A run for ${task.id} already exists at ${workspace.root}.');
    }
    Directory(workspace.root).createSync(recursive: true);

    Future<void> step(String executable, List<String> args, {String? inside}) async {
      final result = await run(executable, args, workingDirectory: inside ?? workspace.root);
      if (!result.ok) {
        throw StateError('"$executable ${args.join(' ')}" failed: ${result.stderr.trim()}');
      }
    }

    try {
      workspace.writeState(taskId: task.id, tool: tool, stage: 'prepare');
      await step('git', ['clone', '--quiet', '--branch', baseBranch, originUrl, 'repo']);
      final remote = await run('git', [
        'ls-remote',
        '--heads',
        'origin',
        task.branch,
      ], workingDirectory: workspace.directory);
      if (remote.ok && remote.stdout.trim().isNotEmpty) {
        await step(
          'git',
          ['fetch', '--quiet', 'origin', task.branch],
          inside: workspace.directory,
        );
        await step('git', ['checkout', '--quiet', '-b', task.branch, 'FETCH_HEAD'], inside: workspace.directory);
      } else {
        await step('git', ['checkout', '--quiet', '-b', task.branch], inside: workspace.directory);
      }
      await step('git', ['config', 'user.email', email], inside: workspace.directory);
      await step('git', ['config', 'user.name', name], inside: workspace.directory);
      File('${workspace.directory}/.git/info/exclude').writeAsStringSync('.runner/\n', mode: FileMode.append);
      Directory(workspace.runnerDirectory).createSync();
      if (!skipSetup) await _runSetup(workspace.directory, run, baseBranch: baseBranch, setup: setup);
    } catch (_) {
      workspace.cleanup();
      rethrow;
    }
    return workspace;
  }

  /// Runs the project's setup commands in order, so the clone is ready and a
  /// runner is never blamed for a base branch that is already broken.
  static Future<void> _runSetup(
    String directory,
    RunCommand run, {
    required String baseBranch,
    required List<List<String>> setup,
  }) async {
    for (final [program, ...args] in setup) {
      final result = await run(program, args, workingDirectory: directory);
      if (result.ok) continue;
      final lines = '${result.stdout}\n${result.stderr}'.trim().split('\n');
      final tail = lines.skip(lines.length > 20 ? lines.length - 20 : 0).join('\n');
      final command = [program, ...args].join(' ');
      throw StateError(
        '"$command" failed in a fresh clone of $baseBranch; fix $baseBranch before running tasks.\n$tail',
      );
    }
  }

  /// Records which stage is running, for the `status` command.
  void writeState({required String taskId, required String tool, required String stage}) {
    File(stateFile).writeAsStringSync(
      jsonEncode({
        'taskId': taskId,
        'tool': tool,
        'stage': stage,
        'pid': pid,
        'updated': DateTime.now().toIso8601String(),
      }),
    );
  }

  /// Deletes the clone and its state.
  void cleanup() {
    final folder = Directory(root);
    if (folder.existsSync()) folder.deleteSync(recursive: true);
  }
}
