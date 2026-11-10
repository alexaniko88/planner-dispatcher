import 'extensions/front_matter_text.dart';
import 'extensions/markdown_sections.dart';

/// One task folder of the backlog (`tasks_dir`), as described in
/// `.agents/rules/backlog-format.md`.
class Task {
  final String id;
  final String status;
  final String type;

  /// How hard the task is, from 1 (simplest) to 10 (hardest), or null when
  /// it is not set or not readable.
  final int? complexity;
  final List<String> dependsOn;
  final List<String> touches;
  final List<String> skills;
  final String directory;

  /// The backlog folder the [directory] starts with, for example `docs/backlog`.
  final String root;
  final String title;
  final String text;

  const Task({
    required this.id,
    required this.status,
    required this.type,
    required this.complexity,
    required this.dependsOn,
    required this.touches,
    required this.skills,
    required this.directory,
    this.root = '',
    required this.title,
    required this.text,
  });

  /// Whether the task, its story or its epic is in a `done/` folder. Only the
  /// part below [root] counts, so a backlog folder named `done` is no problem.
  bool get isDone {
    final below = root.isNotEmpty && directory.startsWith('$root/') ? directory.substring(root.length + 1) : directory;
    return below.split('/').contains('done');
  }

  bool get isReady => status == 'ready' && !isDone;

  /// Where the task folder lives once it is closed: `<parent>/done/<name>`.
  String get doneDirectory => '${directory.substring(0, directory.lastIndexOf('/'))}/done/${directory.split('/').last}';

  String get indexPath => '$directory/index.md';

  /// The folder name without its `task-NN-` prefix (or an older `NN-` one).
  String get slug => directory.split('/').last.replaceFirst(RegExp(r'^(task-)?\d+-'), '');

  /// How a person reads the task: `Save template (TPL-03-02)`.
  String get label => '$title ($id)';

  /// `<type>/<id-lowercase>-<slug>`, for example `feat/tpl-03-02-save-template`.
  String get branch => '$type/${id.toLowerCase()}-$slug';

  /// The acceptance checkboxes, one trimmed line each.
  List<String> get acceptance {
    return text
        .section('Acceptance')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('- ['))
        .toList();
  }

  /// What a task id may hold. The id names the worktree folder and the
  /// branch, so it never holds `/`, `.` or a leading `-`.
  static final idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]*$');

  static final _typePattern = RegExp(r'^[a-z]+$');

  /// Returns null when [path] is not a task `index.md` (an epic or story has
  /// no `id`), or when its id or type could not name a folder and a branch.
  static Task? tryParse({required String path, required String text, String root = ''}) {
    if (!path.endsWith('/index.md')) return null;
    final front = text.frontMatter;
    final id = _scalar(front['id']);
    if (id == null || !idPattern.hasMatch(id)) return null;
    final type = _scalar(front['type']) ?? 'feat';
    if (!_typePattern.hasMatch(type)) return null;
    return Task(
      id: id,
      status: _scalar(front['status']) ?? 'draft',
      type: type,
      complexity: _complexity(_scalar(front['complexity'])),
      dependsOn: _list(front['depends-on']),
      touches: _list(front['touches']),
      skills: _list(front['skills']),
      directory: path.substring(0, path.length - '/index.md'.length),
      root: root,
      title: text.firstHeading,
      text: text,
    );
  }

  /// A number from 1 to 10. The older `low`, `medium` and `high` read as 3, 6
  /// and 9 until the planner refines the task.
  static int? _complexity(String? value) {
    if (value == null) return null;
    final legacy = const {'low': 3, 'medium': 6, 'high': 9}[value];
    if (legacy != null) return legacy;
    final number = int.tryParse(value);
    return number != null && number >= 1 && number <= 10 ? number : null;
  }

  static String? _scalar(Object? value) => value is String && value.isNotEmpty ? value : null;

  static List<String> _list(Object? value) => switch (value) {
    final List<String> list => list,
    final String text when text.isNotEmpty => [text],
    _ => const [],
  };
}
