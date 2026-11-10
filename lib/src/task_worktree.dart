import 'dart:convert';
import 'dart:io';

import 'command_runner.dart';
import 'git_publisher.dart';
import 'role_models.dart';
import 'task.dart';

/// The git worktree one task is worked in: `<project>/.worktrees/<task id>`,
/// on the task branch. The folder starts with a dot, so Dart tools in the
/// project ignore it, and git ignores it through `.git/info/exclude`.
class TaskWorktree {
  /// The folder inside the project that holds every task worktree.
  static const folder = '.worktrees';

  /// Scratch files of the run (reports, the PR body), excluded from git.
  static const runnerFolder = '.runner';

  final String directory;

  const TaskWorktree(this.directory);

  String get runnerDirectory => '$directory/$runnerFolder';

  /// Written by [start]: the task file, the tool and the model of each stage.
  String get runFile => '$runnerDirectory/run.json';

  /// The tool [start] recorded, or null when there is no run file.
  String? get tool => switch (_run) {
    {'tool': final String tool} => tool,
    _ => null,
  };

  /// The task [start] recorded, as it was when the run started, so the later
  /// commands need no network and still find it once it is moved to `done/`.
  Task? task({required String root}) => switch (_run) {
    {'taskPath': final String path, 'taskText': final String text} => Task.tryParse(path: path, text: text, root: root),
    _ => null,
  };

  /// The model of each stage [start] recorded.
  Map<Role, RoleModel> get models => switch (_run) {
    {'models': final Map<String, Object?> models} => {
      for (final role in Role.values) role: ?RoleModel.fromJson(models[role.name]),
    },
    _ => const {},
  };

  /// The run file, or null when it is missing or broken.
  Object? get _run {
    final file = File(runFile);
    if (!file.existsSync()) return null;
    try {
      return jsonDecode(file.readAsStringSync());
    } on FormatException {
      return null;
    }
  }

  /// Where the worktree of [task] lives inside [projectRoot].
  static String pathOf({required String projectRoot, required Task task}) => pathOfId(projectRoot, task.id);

  /// Where the worktree of the task [id] lives inside [projectRoot].
  static String pathOfId(String projectRoot, String id) => '$projectRoot/$folder/$id';

  /// Runs the project's [checks] in order inside the worktree and stops at the
  /// first failure. Only the failing command and the end of its output are
  /// kept, so a long test run does not fill the caller's context.
  Future<CheckRun> runChecks({required RunCommand run, required List<List<String>> checks}) async {
    for (final [program, ...args] in checks) {
      final result = await run(program, args, workingDirectory: directory);
      if (result.ok) continue;
      final lines = '${result.stdout}\n${result.stderr}'.trim().split('\n');
      return CheckRun(
        failed: [program, ...args].join(' '),
        tail: lines.skip(lines.length > CheckRun.tailLines ? lines.length - CheckRun.tailLines : 0).join('\n'),
      );
    }
    return const CheckRun();
  }

  /// Creates the worktree and the task branch from `origin/<baseBranch>`,
  /// runs the project's setup commands in it and pushes the branch, so other
  /// threads see the task as busy. When the task
  /// branch is already on the remote and ends with a blocked run's `wip:`
  /// commit, it continues that branch instead, with `origin/<baseBranch>`
  /// merged in. Throws a [StateError] with a
  /// readable message and removes what it created on any error.
  static Future<TaskWorktree> start({
    required RunCommand run,
    required Task task,
    required String projectRoot,
    required String baseBranch,
    required List<List<String>> setup,
    required String tool,
    required Map<Role, RoleModel> models,
    required String email,
    String? emailSuffix,
  }) async {
    if (emailSuffix != null && !email.endsWith(emailSuffix)) {
      throw StateError('The git email "$email" does not end with "$emailSuffix" (git_email_suffix).');
    }
    final worktree = TaskWorktree(pathOf(projectRoot: projectRoot, task: task));
    if (FileSystemEntity.typeSync(worktree.directory) != FileSystemEntityType.notFound) {
      throw StateError('${task.label} already has a worktree at ${worktree.directory}.');
    }

    Future<String> git(List<String> args, {String? inside}) async {
      final result = await run('git', args, workingDirectory: inside ?? projectRoot);
      if (!result.ok) throw StateError('"git ${args.join(' ')}" failed: ${result.stderr.trim()}');
      return result.stdout.trim();
    }

    if ((await run('git', [
      'rev-parse',
      '--verify',
      '--quiet',
      'refs/heads/${task.branch}',
    ], workingDirectory: projectRoot)).ok) {
      throw StateError('The local branch ${task.branch} already exists. Delete it or finish its work first.');
    }
    final resume = (await git(['ls-remote', '--heads', 'origin', task.branch])).isNotEmpty;
    await git(['fetch', '--quiet', 'origin', resume ? task.branch : baseBranch]);
    if (resume && !(await git(['log', '-1', '--format=%s', 'FETCH_HEAD'])).startsWith('wip: ')) {
      throw StateError(
        '${task.label} is already claimed: ${task.branch} is on the remote and is not a blocked run. '
        'If no thread is working on it, delete that remote branch and start again.',
      );
    }
    await _excludeFolder(projectRoot, git);
    await git(['worktree', 'add', '--quiet', '-b', task.branch, worktree.directory, 'FETCH_HEAD']);
    try {
      if (resume) {
        // Bring in what the planner changed on the base since the block, so
        // the stages read the task as it is planned now.
        await git(['fetch', '--quiet', 'origin', baseBranch], inside: worktree.directory);
        final merge = await run('git', [
          'merge',
          '--quiet',
          '--no-edit',
          '-m',
          'wip: take origin/$baseBranch into ${task.id.toLowerCase()}',
          'FETCH_HEAD',
        ], workingDirectory: worktree.directory);
        if (!merge.ok) {
          throw StateError(
            '${task.label}: its blocked branch does not merge with origin/$baseBranch: '
            '${'${merge.stdout}\n${merge.stderr}'.trim()} Merge it by hand, or delete that remote branch and start again.',
          );
        }
      }
      final taskFile = File('${worktree.directory}/${task.indexPath}');
      if (!taskFile.existsSync()) throw StateError('${task.indexPath} is not on ${task.branch}.');
      Directory(worktree.runnerDirectory).createSync();
      File(worktree.runFile).writeAsStringSync(
        jsonEncode({
          'taskPath': task.indexPath,
          'taskText': taskFile.readAsStringSync(),
          'tool': tool,
          'models': {for (final MapEntry(key: role, value: model) in models.entries) role.name: model.toJson()},
        }),
      );
      await _runSetup(run, worktree.directory, baseBranch: baseBranch, setup: setup);
      if (!resume) {
        final error = await GitPublisher(
          workspace: worktree.directory,
          run: run,
          baseBranch: baseBranch,
        ).push(task.branch);
        if (error != null) {
          throw StateError('Could not claim ${task.label}: $error');
        }
      }
    } catch (_) {
      await worktree.remove(run: run, projectRoot: projectRoot, branch: task.branch);
      rethrow;
    }
    return worktree;
  }

  /// Removes the worktree folder and its local branch. The remote branch stays.
  Future<void> remove({required RunCommand run, required String projectRoot, required String branch}) async {
    await run('git', ['worktree', 'remove', '--force', directory], workingDirectory: projectRoot);
    await run('git', ['branch', '-D', branch], workingDirectory: projectRoot);
  }

  /// Adds the worktree and runner folders to the shared `info/exclude` once.
  static Future<void> _excludeFolder(String projectRoot, Future<String> Function(List<String>) git) async {
    final common = await git(['rev-parse', '--path-format=absolute', '--git-common-dir']);
    final exclude = File('$common/info/exclude');
    var text = exclude.existsSync() ? exclude.readAsStringSync() : '';
    for (final line in ['/$folder/', '$runnerFolder/']) {
      if (text.split('\n').contains(line)) continue;
      text = '${text.isEmpty || text.endsWith('\n') ? text : '$text\n'}$line\n';
    }
    exclude.parent.createSync(recursive: true);
    exclude.writeAsStringSync(text);
  }

  /// Runs the setup commands in order, so a runner is never blamed for a base
  /// branch that is already broken.
  static Future<void> _runSetup(
    RunCommand run,
    String directory, {
    required String baseBranch,
    required List<List<String>> setup,
  }) async {
    for (final [program, ...args] in setup) {
      final result = await run(program, args, workingDirectory: directory);
      if (result.ok) continue;
      final lines = '${result.stdout}\n${result.stderr}'.trim().split('\n');
      final tail = lines.skip(lines.length > 20 ? lines.length - 20 : 0).join('\n');
      throw StateError(
        '"${[program, ...args].join(' ')}" failed on a fresh $baseBranch; fix $baseBranch first.\n$tail',
      );
    }
  }
}

/// The result of [TaskWorktree.runChecks]: [failed] is the first command that
/// failed, or null when all passed.
class CheckRun {
  static const tailLines = 40;

  final String? failed;
  final String tail;

  const CheckRun({this.failed, this.tail = ''});

  bool get passed => failed == null;
}
