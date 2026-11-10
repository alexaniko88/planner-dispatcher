import 'dart:io';

import 'command_runner.dart';
import 'config.dart';
import 'extensions/markdown_sections.dart';
import 'extensions/repo_url.dart';
import 'extensions/text_case.dart';
import 'git_publisher.dart';
import 'guard.dart';
import 'pr_body.dart';
import 'role_models.dart';
import 'task.dart';
import 'task_archiver.dart';
import 'task_worktree.dart';

/// The git work of one task run after `start`: a commit per stage, and the end
/// of the run, either an open PR ([finish]) or a pushed `wip:` commit with the
/// question ([block]). Every push passes the [Guard] first. Errors are
/// [StateError]s with a readable message; the worktree is then kept.
class TaskFinisher {
  final RunCommand run;
  final Task task;
  final TaskWorktree worktree;
  final DispatcherConfig config;

  /// The tool name `start` recorded, for example `claude` or `kimi`.
  final String tool;

  /// The model of each stage `start` recorded.
  final Map<Role, RoleModel> models;
  final String projectRoot;

  const TaskFinisher({
    required this.run,
    required this.task,
    required this.worktree,
    required this.config,
    required this.tool,
    required this.models,
    required this.projectRoot,
  });

  /// The coordinating agent writes this file with the `## Summary`,
  /// `## Evidence`, `## Checks` and `## Points to review` sections.
  String get reportFile => '${worktree.runnerDirectory}/report.md';

  GitPublisher get _publisher => GitPublisher(
    workspace: worktree.directory,
    run: run,
    baseBranch: config.baseBranch,
    goldensDir: config.goldensDir,
  );

  /// How a commit names the tool and model of [role]: `Claude Sonnet 5.5`.
  String _author(Role role) => '${Tool.labelOf(tool)} ${models[role]?.displayName ?? ''}'.trim();

  String _trailer(Role role) => 'Co-Authored-By: ${_author(role)}';

  /// Commits everything the [role] stage changed with [message], attributed
  /// to the model of that stage. Does nothing when nothing changed.
  Future<void> commit({required Role role, required String message}) async {
    if (CommitMessage.problem(message, types: config.commitTypes) case final problem?) throw StateError(problem);
    if (await _publisher.commitAll(subject: message, trailer: _trailer(role)) case final error?) {
      throw StateError(error);
    }
  }

  /// The subject of the commit that closes the task. It is fixed, so it
  /// passes the [Guard] whatever the project's `commit_types` are.
  String get closingSubject => '${Guard.closingPrefix}${task.id.toLowerCase()} ${task.slug}';

  /// Moves the task to `done/` with its notes, commits, checks, pushes, opens
  /// the PR and removes the worktree. Returns the PR URL. It can run again
  /// after a failure: a task already closed in the worktree is not closed
  /// again, and a PR already open for the branch is reused.
  Future<String> finish() async {
    final status = await run('git', ['status', '--porcelain'], workingDirectory: worktree.directory);
    if (status.stdout.trim().isNotEmpty) {
      throw StateError('The worktree has uncommitted changes. Commit each stage with `dispatcher commit` first.');
    }
    final file = File(reportFile);
    if (!file.existsSync()) throw StateError('There is no report at $reportFile.');
    final report = file.readAsStringSync();
    if (report.section('Checks').isEmpty) throw StateError('The report has no "## Checks" section.');

    final origin = await run('git', ['remote', 'get-url', 'origin'], workingDirectory: worktree.directory);
    final slug = origin.stdout.githubSlug;
    if (slug == null) throw StateError('The origin URL "${origin.stdout.trim()}" is not a GitHub URL.');

    // Check before closing the task, so a problem leaves the worktree as it was.
    final leaks = DiffScanner.scan(
      '+++ b/${TaskWorktree.runnerFolder}/report.md\n${report.split('\n').map((line) => '+$line').join('\n')}',
      extra: config.privatePatterns,
    );
    if (leaks.isNotEmpty) {
      throw StateError('Nothing was changed: ${leaks.map((leak) => 'private data: $leak').join('; ')}.');
    }
    await _guard();

    var archived = _closedDirectory();
    if (archived == null) {
      archived = await TaskArchiver(
        workspace: worktree.directory,
        run: run,
        tasksDir: config.tasksDir,
      ).archive(task, notes: _notes(report));
      if (await _publisher.commitAll(subject: closingSubject, trailer: _trailer(Role.implementer)) case final error?) {
        throw StateError(error);
      }
    }
    await _guardAndPush();

    final url = await _openPullRequest(
      PrBody.build(
        task: task,
        summary: report.section('Summary'),
        checks: report.section('Checks'),
        pointsToReview: report.section('Points to review'),
        goldens: await _publisher.changedGoldens(),
        slug: slug,
        baseSha: await _publisher.baseSha(),
        headSha: await _publisher.headSha(),
        taskPath: '$archived/index.md',
      ),
    );
    await worktree.remove(run: run, projectRoot: projectRoot, branch: task.branch);
    return url;
  }

  /// Where an earlier [finish] moved the task, or null when it is still open.
  /// The archiver may have moved its story and epic too, so look for the task
  /// folder name below any `done/` folder of the backlog.
  String? _closedDirectory() {
    if (Directory('${worktree.directory}/${task.directory}').existsSync()) return null;
    final backlog = Directory('${worktree.directory}/${config.tasksDir}');
    if (!backlog.existsSync()) return null;
    final name = task.directory.split('/').last;
    for (final entity in backlog.listSync(recursive: true, followLinks: false)) {
      final path = entity.path.substring(worktree.directory.length + 1);
      if (entity is Directory && path.split('/').last == name && path.split('/').contains('done')) return path;
    }
    return null;
  }

  /// Opens the PR, or returns the URL of the one already open for the branch.
  Future<String> _openPullRequest(String body) async {
    final open = await run('gh', [
      'pr',
      'view',
      task.branch,
      '--json',
      'url,state',
      '--jq',
      'select(.state == "OPEN") | .url',
    ], workingDirectory: worktree.directory);
    if (open.ok && open.stdout.trim().isNotEmpty) return open.stdout.trim();

    final bodyFile = '${worktree.runnerDirectory}/pr-body.md';
    File(bodyFile).writeAsStringSync(body);
    final url = await _publisher.openPullRequest(
      branch: task.branch,
      title: '${task.type}: ${task.title.lowerFirst}',
      bodyFile: bodyFile,
    );
    if (url.startsWith('error:')) {
      throw StateError(
        'The branch is pushed but the PR could not be opened: $url Run `finish` again once it is fixed.',
      );
    }
    return url;
  }

  /// Writes [question] under `## Blocked` in the task's `notes.md`, commits
  /// everything as `wip:`, pushes and removes the worktree.
  Future<void> block(String question) async {
    File('${worktree.directory}/${task.directory}/notes.md').writeAsStringSync(
      '\n## Blocked\n\n${question.trim()}\n',
      mode: FileMode.append,
    );
    if (await _publisher.commitAll(
          subject: 'wip: ${task.id.toLowerCase()} ${task.slug} stopped',
          trailer: _trailer(Role.implementer),
        )
        case final error?) {
      throw StateError(error);
    }
    await _guardAndPush();
    await worktree.remove(run: run, projectRoot: projectRoot, branch: task.branch);
  }

  Future<void> _guardAndPush() async {
    await _guard();
    if (await _publisher.push(task.branch) case final error?) throw StateError(error);
  }

  Future<void> _guard() async {
    final problems = await Guard(
      run: run,
      directory: worktree.directory,
      baseBranch: config.baseBranch,
      commitTypes: config.commitTypes,
      emailSuffix: config.gitEmailSuffix,
      privatePatterns: config.privatePatterns,
    ).problems();
    if (problems.isNotEmpty) throw StateError('Nothing was pushed:\n${problems.map((p) => '- $p').join('\n')}');
  }

  String _notes(String report) {
    final models = [
      for (final role in Role.values) '${role.name}: ${_author(role)}',
    ].join('; ');
    String orNone(String text) => text.isEmpty ? 'None.' : text;
    return [
      '## Summary',
      '',
      orNone(report.section('Summary')),
      '',
      '## Evidence',
      '',
      orNone(report.section('Evidence')),
      '',
      '## Points to review',
      '',
      orNone(report.section('Points to review')),
      '',
      '## Run',
      '',
      models,
    ].join('\n');
  }
}
