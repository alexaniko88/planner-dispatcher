import 'dart:convert';
import 'dart:io';

import '../config.dart';
import 'claude_permissions.dart';

/// Raised when an install cannot run safely. Nothing has been changed when it is thrown.
class InstallError implements Exception {
  final String message;

  const InstallError(this.message);

  @override
  String toString() => message;
}

/// What an install did. Paths are project-relative, `/`-separated, with no trailing slash.
class InstallReport {
  final List<String> written;
  final List<String> removed;
  final List<String> created;
  final List<String> kept;
  final List<String> starterChanged;

  /// One line when the installed stacks were left as they are, with the reason.
  final String stacksKept;

  /// One line about the Claude Code permissions: what was added, or why not.
  final String permissions;

  const InstallReport({
    required this.written,
    this.removed = const [],
    required this.created,
    required this.kept,
    required this.starterChanged,
    this.stacksKept = '',
    this.permissions = '',
  });

  /// The output lines, each group sorted by path.
  List<String> lines() {
    List<String> group(String prefix, List<String> paths) => [
      for (final path in [...paths]..sort()) '$prefix$path',
    ];
    return [
      ...group('wrote ', written),
      ...group('removed ', removed),
      ...group('created ', created),
      ...group('kept ', kept),
      ...group('starter changed: ', starterChanged),
      if (stacksKept.isNotEmpty) stacksKept,
      if (permissions.isNotEmpty) permissions,
    ];
  }
}

/// Copies the library-owned files into a project and creates its project-owned files once.
class Installer {
  final String projectRoot;
  final String packageRoot;

  const Installer({required this.projectRoot, required this.packageRoot});

  static const _skills = ['skill-dispatcher', 'skill-dispatcher-check', 'skill-planner'];
  static const _formatRule = '.agents/rules/backlog-format.md';

  /// The format rule's name before it was renamed; install removes it.
  static const _oldFormatRule = '.agents/rules/project-tasks-format.md';
  static const _tempSuffix = '.install-tmp';
  static const _startersFolder = '.agents/planner-dispatcher/.starters';

  /// Where the rule packs of the configured stacks go in the project.
  static const _stacksFolder = '.agents/rules/stacks';

  /// The one file every `stacks/<name>/` folder of the package must have.
  static const _stackRules = 'rules.md';

  /// Template file name -> the project-owned file made from it.
  static const _starters = {
    'planner_dispatcher.yaml': 'planner_dispatcher.yaml',
    'project-overrides.md': '.agents/planner-dispatcher/project-overrides.md',
    'planner-notes.md': '.agents/planner-dispatcher/planner-notes.md',
  };

  static const _folders = [
    '.claude',
    '.claude/skills',
    '.agents',
    '.agents/skills',
    '.agents/rules',
    _stacksFolder,
    '.agents/planner-dispatcher',
  ];

  static List<String> get _libraryFolders => [for (final name in _skills) '.agents/skills/$name'];

  InstallReport install() {
    final (:stacks, :keptReason) = _configuredStacks();
    _validate(stacks ?? const []);
    final stackPaths = [for (final name in stacks ?? const <String>[]) '$_stacksFolder/$name'];
    for (final path in [..._libraryFolders, _formatRule]) {
      _delete('${_project(path)}$_tempSuffix');
    }
    _deleteStackTemps();

    final written = <String>[];
    for (final path in _libraryFolders) {
      _replaceFolder(_package(path), _project(path));
      written.add(path);
    }
    for (final path in stackPaths) {
      _replaceFolder(_package(path.substring('.agents/rules/'.length)), _project(path));
      written.add(path);
    }
    final removed = stacks == null ? const <String>[] : _removeOtherStacks(stackPaths);
    _replaceFile(_package(_formatRule), _project(_formatRule));
    written.add(_formatRule);
    _delete(_project(_oldFormatRule));

    for (final name in _skills) {
      final link = '.claude/skills/$name';
      if (_isLink(_project(link))) continue;
      Directory(_project('.claude/skills')).createSync(recursive: true);
      Link(_project(link)).createSync(_linkTarget(name));
      written.add(link);
    }

    final created = <String>[];
    final kept = <String>[];
    final starterChanged = <String>[];
    for (final MapEntry(key: template, value: path) in _starters.entries) {
      final current = File(_package('templates/$template')).readAsBytesSync();
      final copy = File(_project('$_startersFolder/$template'));
      final projectFile = File(_project(path));
      if (!projectFile.existsSync()) {
        _writeBytes(projectFile.path, current);
        created.add(path);
      } else if (copy.existsSync() && !_sameBytes(copy.readAsBytesSync(), current)) {
        starterChanged.add(path);
      } else {
        kept.add(path);
      }
      _writeBytes(copy.path, current);
    }

    return InstallReport(
      written: written,
      removed: removed,
      created: created,
      kept: kept,
      starterChanged: starterChanged,
      stacksKept: keptReason == null ? '' : 'stacks kept as installed: $keptReason',
      permissions: _addPermissions(),
    );
  }

  /// The stacks of the project's config. [stacks] is null when the installed
  /// stacks must stay as they are: when there is no config yet (then nothing
  /// says which stacks the project wants), or when it cannot be read, with
  /// [keptReason] saying why. A wrong `stacks` value stops the install.
  ({List<String>? stacks, String? keptReason}) _configuredStacks() {
    final path = _project(DispatcherConfig.fileName);
    if (!File(path).existsSync()) return (stacks: null, keptReason: null);
    try {
      return (stacks: DispatcherConfig.load(path: path).stacks, keptReason: null);
    } on ConfigError catch (error) {
      if (error.key == 'stacks' || error.key.startsWith('stacks[')) throw InstallError('$error');
      return (stacks: null, keptReason: '$error');
    }
  }

  /// Deletes the leftovers of an install that stopped while it copied a stack.
  void _deleteStackTemps() {
    final folder = Directory(_project(_stacksFolder));
    if (!folder.existsSync()) return;
    for (final entity in folder.listSync(followLinks: false)) {
      if (entity.path.endsWith(_tempSuffix)) _delete(entity.path);
    }
  }

  /// Deletes the installed folders of the stacks the package ships and the
  /// config no longer names. A folder the package does not ship belongs to
  /// the project and stays.
  List<String> _removeOtherStacks(List<String> kept) {
    final folder = Directory(_project(_stacksFolder));
    if (!folder.existsSync()) return const [];
    final shipped = _shippedStacks();
    final removed = <String>[];
    for (final entity in folder.listSync(followLinks: false)) {
      final name = entity.path.split('/').last;
      final path = '$_stacksFolder/$name';
      if (entity is File || kept.contains(path) || !shipped.contains(name)) continue;
      _delete(entity.path);
      removed.add(path);
    }
    if (folder.listSync().isEmpty) folder.deleteSync();
    return removed;
  }

  /// The names of the stacks the package ships, exactly as the folders are
  /// spelled, so a case-insensitive disk does not match another spelling.
  Set<String> _shippedStacks() {
    final folder = Directory(_package('stacks'));
    if (!folder.existsSync()) return const {};
    return {
      for (final entity in folder.listSync(followLinks: false))
        if (entity is Directory && File('${entity.path}/$_stackRules').existsSync()) entity.path.split('/').last,
    };
  }

  static const _settings = '.claude/settings.json';

  /// Adds the permission rules of [ClaudePermissions] to the project's Claude
  /// settings, from the project's config. It only adds rules and keeps the
  /// rest of the file; it changes nothing when the config or the file cannot
  /// be read.
  String _addPermissions() {
    final DispatcherConfig config;
    try {
      config = DispatcherConfig.load(path: _project(DispatcherConfig.fileName));
    } on ConfigError catch (error) {
      return 'permissions skipped: $error. Fix it and run install again.';
    }
    final file = File(_project(_settings));
    try {
      final merged = ClaudePermissions.merge(
        file.existsSync() ? file.readAsStringSync() : null,
        ClaudePermissions.rules(config),
      );
      if (merged.added.isEmpty) return 'permissions kept $_settings';
      _writeBytes(file.path, utf8.encode(merged.text));
      return 'permissions added ${merged.added.length} rules to $_settings';
    } on FormatException catch (error) {
      return 'permissions skipped: $_settings: ${error.message}';
    }
  }

  void _validate(List<String> stacks) {
    if (Directory(projectRoot).resolveSymbolicLinksSync() == Directory(packageRoot).resolveSymbolicLinksSync()) {
      throw const InstallError('Refusing to install into the package itself.');
    }
    for (final name in _skills) {
      final path = _project('.claude/skills/$name');
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      if (type != FileSystemEntityType.link || Link(path).targetSync() != _linkTarget(name)) {
        throw InstallError('.claude/skills/$name exists and is not the link to ${_linkTarget(name)}');
      }
    }
    for (final path in _folders) {
      final type = FileSystemEntity.typeSync(_project(path));
      if (type != FileSystemEntityType.notFound && type != FileSystemEntityType.directory) {
        throw InstallError('$path must be a folder');
      }
    }
    final shipped = [..._libraryFolders, _formatRule, for (final name in _starters.keys) 'templates/$name'];
    for (final path in shipped) {
      if (FileSystemEntity.typeSync(_package(path)) == FileSystemEntityType.notFound) {
        throw InstallError('package is incomplete: $path');
      }
    }
    for (final name in stacks) {
      if (!File(_package('stacks/$name/$_stackRules')).existsSync()) {
        throw InstallError('unknown stack $name: the package has no stacks/$name/$_stackRules');
      }
    }
    for (final path in [..._libraryFolders, for (final name in stacks) 'stacks/$name']) {
      for (final entity in Directory(_package(path)).listSync(recursive: true, followLinks: false)) {
        if (entity is Link) throw InstallError('shipped files must not contain links: ${_relative(entity.path)}');
      }
    }
  }

  String _linkTarget(String name) => '../../.agents/skills/$name';

  String _project(String path) => '$projectRoot/$path';

  String _package(String path) => '$packageRoot/$path';

  String _relative(String path) => path.substring(packageRoot.length + 1);

  bool _isLink(String path) => FileSystemEntity.isLinkSync(path);

  bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }

  /// Deletes whatever is at [path]: a folder, a file or a link.
  void _delete(String path) {
    switch (FileSystemEntity.typeSync(path, followLinks: false)) {
      case FileSystemEntityType.directory:
        Directory(path).deleteSync(recursive: true);
      case FileSystemEntityType.link:
        Link(path).deleteSync();
      case FileSystemEntityType.notFound:
        break;
      default:
        File(path).deleteSync();
    }
  }

  void _replaceFolder(String from, String to) {
    final temp = '$to$_tempSuffix';
    for (final entity in Directory(from).listSync(recursive: true, followLinks: false)) {
      if (entity is! File || entity.uri.pathSegments.last == '.DS_Store') continue;
      _writeBytes('$temp/${entity.path.substring(from.length + 1)}', entity.readAsBytesSync(), atomic: false);
    }
    Directory(temp).createSync(recursive: true);
    _delete(to);
    Directory(temp).renameSync(to);
  }

  void _replaceFile(String from, String to) => _writeBytes(to, File(from).readAsBytesSync());

  /// Writes [bytes] to [path], through a temp file and a rename unless [atomic] is false.
  void _writeBytes(String path, List<int> bytes, {bool atomic = true}) {
    File(path).parent.createSync(recursive: true);
    if (!atomic) {
      File(path).writeAsBytesSync(bytes);
      return;
    }
    final temp = '$path$_tempSuffix';
    File(temp).writeAsBytesSync(bytes);
    _delete(path);
    File(temp).renameSync(path);
  }
}
