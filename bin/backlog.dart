// Moves backlog folders in the local checkout, fixing every link. The
// planner uses it on its planning branch.
//
//   <dart> run planner_dispatcher:backlog close-finished
//   <dart> run planner_dispatcher:backlog reopen <path>
//
// close-finished moves each story whose tasks are all done into its
// stories/done/, and each epic whose stories are all done into
// <tasks_dir>/done/. reopen moves a closed story or epic, and every closed
// epic above it, back out of done/. The rules are in
// lib/src/backlog_mover.dart and are unit tested.
import 'dart:io';

import 'package:planner_dispatcher/src/backlog_mover.dart';
import 'package:planner_dispatcher/src/command_runner.dart';
import 'package:planner_dispatcher/src/config.dart';

Future<void> main(List<String> args) async {
  final DispatcherConfig config;
  try {
    config = DispatcherConfig.load();
  } on ConfigError catch (error) {
    stderr.writeln(error);
    exit(78);
  }
  final mover = BacklogMover(workspace: Directory.current.path, run: runSystemCommand, tasksDir: config.tasksDir);
  try {
    switch (args) {
      case ['close-finished']:
        final moves = await mover.closeFinished();
        if (moves.isEmpty) stdout.writeln('Nothing to close.');
        for (final MapEntry(key: from, value: to) in moves.entries) {
          stdout.writeln('Closed $from -> $to');
        }
      case ['reopen', final path]:
        final target = await mover.reopen(path.endsWith('/') ? path.substring(0, path.length - 1) : path);
        stdout.writeln(target == path ? '$path is already open.' : 'Reopened $path -> $target');
      default:
        stderr.writeln('Usage: <dart> run planner_dispatcher:backlog close-finished | reopen <path>');
        exit(64);
    }
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exit(1);
  }
}
