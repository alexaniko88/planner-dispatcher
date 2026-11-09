import 'dart:io';

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
  final List<String> created;
  final List<String> kept;
  final List<String> starterChanged;

  const InstallReport({
    required this.written,
    required this.created,
    required this.kept,
    required this.starterChanged,
  });

  /// The output lines, each group sorted by path.
  List<String> lines() {
    List<String> group(String prefix, List<String> paths) => [
      for (final path in [...paths]..sort()) '$prefix$path',
    ];
    return [
      ...group('wrote ', written),
      ...group('created ', created),
      ...group('kept ', kept),
      ...group('starter changed: ', starterChanged),
    ];
  }
}

/// Copies the library-owned files into a project and creates its project-owned files once.
class Installer {
  final String projectRoot;
  final String packageRoot;

  const Installer({required this.projectRoot, required this.packageRoot});

  static const _skills = ['skill-dispatcher', 'skill-planner'];
  static const _formatRule = '.agents/rules/backlog-format.md';

  /// The format rule's name before it was renamed; install removes it.
  static const _oldFormatRule = '.agents/rules/project-tasks-format.md';
  static const _tempSuffix = '.install-tmp';
  static const _startersFolder = '.agents/planner-dispatcher/.starters';

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
    '.agents/planner-dispatcher',
  ];

  static List<String> get _libraryFolders => [for (final name in _skills) '.agents/skills/$name'];

  InstallReport install() {
    _validate();
    final libraryPaths = [..._libraryFolders, _formatRule];
    for (final path in libraryPaths) {
      _delete('${_project(path)}$_tempSuffix');
    }

    final written = <String>[];
    for (final path in _libraryFolders) {
      _replaceFolder(_package(path), _project(path));
      written.add(path);
    }
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

    return InstallReport(written: written, created: created, kept: kept, starterChanged: starterChanged);
  }

  void _validate() {
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
    for (final path in _libraryFolders) {
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
