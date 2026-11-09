import 'dart:io';

import 'package:yaml/yaml.dart';

import 'role_models.dart';

/// A problem in `planner_dispatcher.yaml`. [key] is the dotted path of the
/// value (`check[1]`, `models.claude.reviewer.effort`), or `(file)` when the
/// file itself cannot be read.
class ConfigError implements Exception {
  final String key;
  final String problem;

  const ConfigError(this.key, this.problem);

  @override
  String toString() => 'planner_dispatcher.yaml: $key: $problem';
}

/// The project values the dispatcher reads from `planner_dispatcher.yaml`
/// (schema 1). Commands are stored as a program followed by its arguments.
class DispatcherConfig {
  final String dart;
  final String baseBranch;
  final String runFolder;
  final List<List<String>> setup;
  final List<List<String>> check;
  final List<List<String>> allowedCommands;
  final List<String> rules;
  final String tasksDir;
  final String? goldensDir;
  final List<String> commitTypes;
  final String? gitEmailSuffix;
  final Map<String, RegExp> privatePatterns;
  final Map<Tool, Map<Role, RoleModel>> models;

  const DispatcherConfig({
    required this.dart,
    required this.baseBranch,
    required this.runFolder,
    required this.setup,
    required this.check,
    required this.rules,
    required this.commitTypes,
    this.tasksDir = defaultTasksDir,
    this.allowedCommands = const [],
    this.goldensDir,
    this.gitEmailSuffix,
    this.privatePatterns = const {},
    this.models = const {},
  });

  static const fileName = 'planner_dispatcher.yaml';

  /// Where the backlog lives when `tasks_dir` is not set.
  static const defaultTasksDir = 'docs/backlog';

  static const _keys = {
    'dart',
    'base_branch',
    'run_folder',
    'setup',
    'check',
    'allowed_commands',
    'rules',
    'tasks_dir',
    'goldens_dir',
    'commit_types',
    'git_email_suffix',
    'private_patterns',
    'models',
  };

  static final _runFolder = RegExp(r'^[A-Za-z0-9._-]+$');
  static final _commitType = RegExp(r'^[a-z]+$');
  static final _tasksDir = RegExp(r'^[A-Za-z0-9._-]+(/[A-Za-z0-9._-]+)*$');
  static const _modelFields = {'model', 'effort', 'name'};

  /// Reads and checks the config file at [path]. Throws [ConfigError].
  static DispatcherConfig load({String path = fileName}) {
    final file = File(path);
    if (!file.existsSync()) throw const ConfigError('(file)', 'not found');
    return parse(file.readAsStringSync());
  }

  /// Checks [yamlText] against schema 1. Throws [ConfigError].
  static DispatcherConfig parse(String yamlText) {
    final Object? root;
    try {
      root = loadYaml(yamlText);
    } on YamlException catch (error) {
      throw ConfigError('(file)', 'invalid YAML: ${error.message}');
    }
    if (root is! Map) throw const ConfigError('(file)', 'must be a map');
    for (final key in root.keys) {
      if (!_keys.contains(key)) throw ConfigError('$key', 'unknown key');
    }

    final baseBranch = _string(root, 'base_branch');
    if (baseBranch.contains(' ')) throw const ConfigError('base_branch', 'must not contain spaces');
    final runFolder = _string(root, 'run_folder');
    if (!_runFolder.hasMatch(runFolder)) {
      throw ConfigError('run_folder', 'must match ${_runFolder.pattern}');
    }
    final tasksDir = root.containsKey('tasks_dir') ? _string(root, 'tasks_dir') : defaultTasksDir;
    if (!_tasksDir.hasMatch(tasksDir) || tasksDir.split('/').any((part) => part == '.' || part == '..')) {
      throw const ConfigError('tasks_dir', 'must be a relative folder path without . or ..');
    }
    final check = _commands(root, 'check');
    if (check.isEmpty) throw const ConfigError('check', 'must not be empty');
    final commitTypes = _strings(root, 'commit_types');
    if (commitTypes.isEmpty) throw const ConfigError('commit_types', 'must not be empty');
    for (final (index, type) in commitTypes.indexed) {
      if (!_commitType.hasMatch(type)) {
        throw ConfigError('commit_types[$index]', 'must match ${_commitType.pattern}');
      }
    }

    return DispatcherConfig(
      dart: _string(root, 'dart'),
      baseBranch: baseBranch,
      runFolder: runFolder,
      setup: _commands(root, 'setup'),
      check: check,
      allowedCommands: root.containsKey('allowed_commands') ? _commands(root, 'allowed_commands') : const [],
      rules: _strings(root, 'rules'),
      tasksDir: tasksDir,
      goldensDir: root.containsKey('goldens_dir') ? _string(root, 'goldens_dir') : null,
      commitTypes: commitTypes,
      gitEmailSuffix: root.containsKey('git_email_suffix') ? _string(root, 'git_email_suffix') : null,
      privatePatterns: _patterns(root),
      models: _models(root),
    );
  }

  /// Splits one configured command into its program and arguments. There is
  /// no shell, so quoting and shell syntax have no meaning.
  static List<String> splitCommand(String command) => command.trim().split(RegExp(r'\s+'));

  static Object? _required(Map<dynamic, dynamic> map, String key, {String? path}) {
    if (!map.containsKey(key)) throw ConfigError(path ?? key, 'missing');
    return map[key];
  }

  static String _string(Map<dynamic, dynamic> map, String key, {String? path}) {
    final value = _required(map, key, path: path);
    if (value is! String) throw ConfigError(path ?? key, 'must be a string');
    if (value.trim().isEmpty) throw ConfigError(path ?? key, 'must not be empty');
    return value;
  }

  static List<String> _strings(Map<dynamic, dynamic> map, String key) {
    final value = _required(map, key);
    if (value is! List) throw ConfigError(key, 'must be a list');
    return [
      for (final (index, entry) in value.indexed)
        if (entry is String) entry else throw ConfigError('$key[$index]', 'must be a string'),
    ];
  }

  static List<List<String>> _commands(Map<dynamic, dynamic> map, String key) {
    return [
      for (final (index, command) in _strings(map, key).indexed)
        if (command.trim().isEmpty) throw ConfigError('$key[$index]', 'must not be empty') else splitCommand(command),
    ];
  }

  static Map<String, RegExp> _patterns(Map<dynamic, dynamic> root) {
    final value = root['private_patterns'];
    if (value == null) return const {};
    if (value is! Map) throw const ConfigError('private_patterns', 'must be a map');
    final patterns = <String, RegExp>{};
    for (final MapEntry(:key, value: pattern) in value.entries) {
      final path = 'private_patterns.$key';
      if (pattern is! String) throw ConfigError(path, 'must be a string');
      try {
        patterns['$key'] = RegExp(pattern);
      } on FormatException catch (error) {
        throw ConfigError(path, 'invalid regex: ${error.message}');
      }
    }
    return patterns;
  }

  static Map<Tool, Map<Role, RoleModel>> _models(Map<dynamic, dynamic> root) {
    final value = root['models'];
    if (value == null) return const {};
    if (value is! Map) throw const ConfigError('models', 'must be a map');
    final models = <Tool, Map<Role, RoleModel>>{};
    for (final MapEntry(key: toolName, value: stages) in value.entries) {
      final tool = Tool.fromName('$toolName');
      if (tool == null) throw ConfigError('models.$toolName', 'unknown tool');
      if (stages is! Map) throw ConfigError('models.$toolName', 'must be a map');
      final roles = <Role, RoleModel>{};
      for (final MapEntry(key: stageName, value: entry) in stages.entries) {
        final path = 'models.$toolName.$stageName';
        final role = Role.values.asNameMap()['$stageName'];
        if (role == null) throw ConfigError(path, 'unknown stage');
        if (entry is! Map) throw ConfigError(path, 'must be a map');
        for (final field in entry.keys) {
          if (!_modelFields.contains(field)) throw ConfigError('$path.$field', 'unknown key');
        }
        roles[role] = RoleModel(
          model: _string(entry, 'model', path: '$path.model'),
          effort: _string(entry, 'effort', path: '$path.effort'),
          displayName: _string(entry, 'name', path: '$path.name'),
        );
      }
      models[tool] = roles;
    }
    return models;
  }
}
