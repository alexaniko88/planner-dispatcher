import 'dart:io';

import 'command_runner.dart';
import 'config.dart';
import 'extensions/posix_path.dart';

/// Moves backlog folders with `git mv` and keeps every relative Markdown link
/// of the backlog pointing at the same files. A story whose tasks are all
/// done moves into `stories/done/`, an epic whose stories are all done into
/// `<tasks_dir>/done/`, and [reopen] moves them back.
class BacklogMover {
  final String workspace;
  final RunCommand run;

  /// The backlog folder (`tasks_dir`), relative to [workspace].
  final String tasksDir;

  const BacklogMover({required this.workspace, required this.run, this.tasksDir = DispatcherConfig.defaultTasksDir});

  static final _link = RegExp(r'\]\(([^)\s]+)\)');

  /// Moves the folder [from] to [to], both relative to [workspace].
  Future<void> move(String from, String to) async {
    if (FileSystemEntity.typeSync('$workspace/$to') != FileSystemEntityType.notFound) {
      throw StateError('$to already exists.');
    }
    Directory('$workspace/${_parent(to)}').createSync(recursive: true);
    final moved = await run('git', ['mv', from, to], workingDirectory: workspace);
    if (!moved.ok) throw StateError('git mv failed: ${moved.stderr}');
    _fixLinks(from: from, to: to);
  }

  /// Moves [story] into its `stories/done/` when it has done tasks and no
  /// open ones. Returns its new path, or null when it stays.
  Future<String?> closeStory(String story) async {
    if (_children(story, 'task-').isNotEmpty || _children('$story/done', 'task-').isEmpty) return null;
    final target = '${_parent(story)}/done/${_name(story)}';
    await move(story, target);
    return target;
  }

  /// Moves [epic] into `<tasks_dir>/done/` when it has done stories and no
  /// open ones. Returns its new path, or null when it stays.
  Future<String?> closeEpic(String epic) async {
    if (_children('$epic/stories', 'story-').isNotEmpty || _children('$epic/stories/done', 'story-').isEmpty) {
      return null;
    }
    final target = '$tasksDir/done/${_name(epic)}';
    await move(epic, target);
    return target;
  }

  /// Closes every open story and epic whose work is all done. Returns each
  /// move as old path -> new path.
  Future<Map<String, String>> closeFinished() async {
    final moves = <String, String>{};
    for (final epic in _children(tasksDir, 'epic-')) {
      for (final story in _children('$epic/stories', 'story-')) {
        if (await closeStory(story) case final target?) moves[story] = target;
      }
      if (await closeEpic(epic) case final target?) moves[epic] = target;
    }
    return moves;
  }

  /// Moves the epic or story at [path], and every closed epic above it, out
  /// of `done/`. Done tasks stay where they are. Returns the new path.
  Future<String> reopen(String path) async {
    if (!Directory('$workspace/$path').existsSync()) throw StateError('$path does not exist.');
    if (!path.startsWith('$tasksDir/')) throw StateError('$path is not in $tasksDir.');
    var current = path;
    while (true) {
      final parts = current.substring(tasksDir.length + 1).split('/');
      final index = [
        for (var at = 0; at < parts.length - 1; at++)
          if (parts[at] == 'done' && (parts[at + 1].startsWith('epic-') || parts[at + 1].startsWith('story-'))) at,
      ].firstOrNull;
      if (index == null) return current;
      final from = [tasksDir, ...parts.take(index + 2)].join('/');
      final to = [tasksDir, ...parts.take(index), parts[index + 1]].join('/');
      await move(from, to);
      current = to + current.substring(from.length);
    }
  }

  /// The child folders of [folder] whose name starts with [prefix], sorted.
  List<String> _children(String folder, String prefix) {
    final directory = Directory('$workspace/$folder');
    if (!directory.existsSync()) return const [];
    return [
      for (final entity in directory.listSync(followLinks: false))
        if (entity is Directory && _name(entity.path).startsWith(prefix)) '$folder/${_name(entity.path)}',
    ]..sort();
  }

  String _name(String path) => path.split('/').last;

  String _parent(String path) => path.substring(0, path.lastIndexOf('/'));

  /// Rewrites the relative links of every Markdown file in the backlog after
  /// [from] moved to [to], so each still points at the same file.
  void _fixLinks({required String from, required String to}) {
    final root = Directory('$workspace/$tasksDir');
    if (!root.existsSync()) return;
    for (final entity in root.listSync(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.md')) continue;
      final path = entity.path.substring(workspace.length + 1);
      final oldPath = path.startsWith('$to/') ? from + path.substring(to.length) : path;
      final before = entity.readAsStringSync();
      final after = _rewriteLinks(before, oldBase: _parent(oldPath), newBase: _parent(path), from: from, to: to);
      if (after != before) entity.writeAsStringSync(after);
    }
  }

  String _rewriteLinks(
    String text, {
    required String oldBase,
    required String newBase,
    required String from,
    required String to,
  }) {
    return text.replaceAllMapped(_link, (match) {
      final target = match.group(1) ?? '';
      if (RegExp(r'^[a-z][a-z0-9+.-]*:').hasMatch(target) || target.startsWith('#') || target.startsWith('/')) {
        return match.group(0) ?? '';
      }
      final anchorAt = target.indexOf('#');
      final path = anchorAt < 0 ? target : target.substring(0, anchorAt);
      final anchor = anchorAt < 0 ? '' : target.substring(anchorAt);
      if (path.isEmpty) return match.group(0) ?? '';
      final resolved = path.resolveFrom(oldBase);
      final mapped = resolved == from || resolved.startsWith('$from/')
          ? to + resolved.substring(from.length)
          : resolved;
      return '](${mapped.relativeTo(newBase)}$anchor)';
    });
  }
}
