// Moves the local repo to an up to date base branch and deletes the local
// branches whose pull request is already merged.
//
//   <dart> run planner_dispatcher:sync
//
// It stops with no change when there are uncommitted changes. It deletes a
// branch only when GitHub shows a merged pull request into the base branch
// with the same last commit, and never touches remote branches. The rules are
// in lib/src/master_sync.dart and are unit tested.
import 'dart:io';

import 'package:planner_dispatcher/src/command_runner.dart';
import 'package:planner_dispatcher/src/config.dart';
import 'package:planner_dispatcher/src/master_sync.dart';

Future<void> main() async {
  final DispatcherConfig config;
  try {
    config = DispatcherConfig.load();
  } on ConfigError catch (error) {
    stderr.writeln(error);
    exit(78);
  }
  final base = config.baseBranch;
  final sync = MasterSync(workspace: Directory.current.path, run: runSystemCommand, baseBranch: base);
  try {
    final report = await sync.sync();
    if (report.switchedFrom case final branch?) stdout.writeln('Switched from $branch to $base. It was kept.');
    stdout.writeln('On $base, up to date.');
    stdout.writeln(
      report.deleted.isEmpty ? 'No merged branches to delete.' : 'Deleted: ${report.deleted.join(', ')}',
    );
    for (final MapEntry(key: branch, value: reason) in report.kept.entries) {
      stdout.writeln('Kept $branch: $reason');
    }
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exit(1);
  }
}
