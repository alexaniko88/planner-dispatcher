import 'dart:io';

import 'backlog_mover.dart';
import 'command_runner.dart';
import 'config.dart';
import 'task.dart';

/// Closes a task in its own branch: marks it done, writes its notes and moves
/// its folder into the `done/` folder of its parent, fixing every link. When
/// it was the last open task of its story, the story moves to done too, and
/// the epic when that was its last open story.
class TaskArchiver {
  final String workspace;
  final RunCommand run;

  /// The backlog folder (`tasks_dir`), relative to [workspace].
  final String tasksDir;

  const TaskArchiver({required this.workspace, required this.run, this.tasksDir = DispatcherConfig.defaultTasksDir});

  /// Returns the new folder of the task, relative to the workspace.
  Future<String> archive(Task task, {required String notes}) async {
    final mover = BacklogMover(workspace: workspace, run: run, tasksDir: tasksDir);
    final oldDirectory = task.directory;
    await mover.move(oldDirectory, task.doneDirectory);
    var newDirectory = task.doneDirectory;

    final index = File('$workspace/$newDirectory/index.md');
    index.writeAsStringSync(_markDone(index.readAsStringSync()));
    final notesFile = File('$workspace/$newDirectory/notes.md');
    final existing = notesFile.existsSync() ? '${notesFile.readAsStringSync().trimRight()}\n\n' : '# Notes\n\n';
    notesFile.writeAsStringSync('$existing${notes.trim()}\n');

    final story = oldDirectory.substring(0, oldDirectory.lastIndexOf('/'));
    if (!story.split('/').last.startsWith('story-')) return newDirectory;
    final closedStory = await mover.closeStory(story);
    if (closedStory == null) return newDirectory;
    newDirectory = closedStory + newDirectory.substring(story.length);

    final epic = story.substring(0, story.lastIndexOf('/stories/'));
    final closedEpic = await mover.closeEpic(epic);
    if (closedEpic == null) return newDirectory;
    return closedEpic + newDirectory.substring(epic.length);
  }

  String _markDone(String text) {
    final withStatus = text.replaceFirst(RegExp(r'^status:.*$', multiLine: true), 'status: done');
    final start = withStatus.indexOf('\n## Acceptance');
    if (start < 0) return withStatus;
    final end = withStatus.indexOf('\n## ', start + 1);
    final section = withStatus.substring(start, end < 0 ? withStatus.length : end);
    final checked = section.replaceAll(RegExp(r'^- \[ \]', multiLine: true), '- [x]');
    return withStatus.replaceRange(start, start + section.length, checked);
  }
}
