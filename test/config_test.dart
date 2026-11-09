import 'dart:io';

import 'package:planner_dispatcher/src/config.dart';
import 'package:planner_dispatcher/src/role_models.dart';
import 'package:test/test.dart';

const _minimal = '''
dart: dart
base_branch: main
run_folder: app-runs
setup: []
check:
  - dart test
rules: []
commit_types: [feat, fix]
''';

const _full = '''
dart: fvm dart
base_branch: master
run_folder: app-runs
setup:
  - fvm install --skip-pub-get
  - fvm flutter pub get
check:
  - fvm flutter analyze --no-pub
  - fvm flutter test
allowed_commands:
  - fvm dart format
rules:
  - CLAUDE.md
tasks_dir: planning/tasks
goldens_dir: test/goldens
commit_types: [feat, fix, docs]
git_email_suffix: "@users.noreply.github.com"
private_patterns:
  a company email: "@example\\\\.com"
models:
  claude:
    reviewer: {model: opus, effort: high, name: Opus 5.5}
''';

/// [_minimal] with one top-level line replaced, added or removed.
String _with(String key, String? line) {
  final lines = _minimal.trim().split('\n');
  final index = lines.indexWhere((candidate) => candidate.startsWith('$key:'));
  if (index >= 0) {
    var end = index + 1;
    while (end < lines.length && lines[end].startsWith(' ')) {
      end++;
    }
    lines.removeRange(index, end);
    if (line != null) lines.insert(index, line);
  } else if (line != null) {
    lines.add(line);
  }
  return '${lines.join('\n')}\n';
}

Matcher _error(String key, String problem) {
  return isA<ConfigError>()
      .having((error) => error.key, 'key', key)
      .having((error) => error.problem, 'problem', problem);
}

void main() {
  test('a full config gives every value', () {
    final config = DispatcherConfig.parse(_full);

    expect(config.dart, 'fvm dart');
    expect(config.baseBranch, 'master');
    expect(config.runFolder, 'app-runs');
    expect(config.setup, [
      ['fvm', 'install', '--skip-pub-get'],
      ['fvm', 'flutter', 'pub', 'get'],
    ]);
    expect(config.check, [
      ['fvm', 'flutter', 'analyze', '--no-pub'],
      ['fvm', 'flutter', 'test'],
    ]);
    expect(config.allowedCommands, [
      ['fvm', 'dart', 'format'],
    ]);
    expect(config.rules, ['CLAUDE.md']);
    expect(config.tasksDir, 'planning/tasks');
    expect(config.goldensDir, 'test/goldens');
    expect(config.commitTypes, ['feat', 'fix', 'docs']);
    expect(config.gitEmailSuffix, '@users.noreply.github.com');
    expect(config.privatePatterns.keys, ['a company email']);
    expect(config.privatePatterns['a company email']!.hasMatch('me@example.com'), isTrue);
    final reviewer = config.models[Tool.claude]![Role.reviewer]!;
    expect((reviewer.model, reviewer.effort, reviewer.displayName), ('opus', 'high', 'Opus 5.5'));
  });

  test('a minimal config leaves the optional values empty', () {
    final config = DispatcherConfig.parse(_minimal);

    expect(config.setup, isEmpty);
    expect(config.allowedCommands, isEmpty);
    expect(config.rules, isEmpty);
    expect(config.tasksDir, 'docs/backlog');
    expect(config.goldensDir, isNull);
    expect(config.gitEmailSuffix, isNull);
    expect(config.privatePatterns, isEmpty);
    expect(config.models, isEmpty);
  });

  test('a missing file is reported as (file): not found', () {
    final folder = Directory.systemTemp.createTempSync('config_test');
    addTearDown(() => folder.deleteSync(recursive: true));

    expect(
      () => DispatcherConfig.load(path: '${folder.path}/planner_dispatcher.yaml'),
      throwsA(_error('(file)', 'not found')),
    );
  });

  test('a file is loaded from its path', () {
    final folder = Directory.systemTemp.createTempSync('config_test');
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File('${folder.path}/planner_dispatcher.yaml')..writeAsStringSync(_minimal);

    expect(DispatcherConfig.load(path: file.path).baseBranch, 'main');
  });

  test('invalid YAML is reported with the parser message', () {
    expect(
      () => DispatcherConfig.parse('dart: [unclosed\n'),
      throwsA(
        isA<ConfigError>()
            .having((error) => error.key, 'key', '(file)')
            .having((error) => error.problem, 'problem', startsWith('invalid YAML: ')),
      ),
    );
  });

  test('a file that is not a map is refused', () {
    expect(() => DispatcherConfig.parse(''), throwsA(_error('(file)', 'must be a map')));
    expect(() => DispatcherConfig.parse('- a\n'), throwsA(_error('(file)', 'must be a map')));
  });

  test('an unknown top-level key is refused', () {
    expect(
      () => DispatcherConfig.parse(_with('backlog', 'backlog: tasks')),
      throwsA(_error('backlog', 'unknown key')),
    );
  });

  for (final key in ['dart', 'base_branch', 'run_folder', 'setup', 'check', 'rules', 'commit_types']) {
    test('a missing $key is refused', () {
      expect(() => DispatcherConfig.parse(_with(key, null)), throwsA(_error(key, 'missing')));
    });
  }

  test('a wrong type is refused', () {
    expect(() => DispatcherConfig.parse(_with('dart', 'dart: 3')), throwsA(_error('dart', 'must be a string')));
    expect(
      () => DispatcherConfig.parse(_with('check', 'check: dart test')),
      throwsA(_error('check', 'must be a list')),
    );
    expect(
      () => DispatcherConfig.parse(_with('private_patterns', 'private_patterns: [a]')),
      throwsA(_error('private_patterns', 'must be a map')),
    );
    expect(() => DispatcherConfig.parse(_with('models', 'models: [a]')), throwsA(_error('models', 'must be a map')));
  });

  test('empty or malformed values are refused', () {
    expect(() => DispatcherConfig.parse(_with('dart', 'dart: " "')), throwsA(_error('dart', 'must not be empty')));
    expect(
      () => DispatcherConfig.parse(_with('base_branch', 'base_branch: "my branch"')),
      throwsA(_error('base_branch', 'must not contain spaces')),
    );
    expect(
      () => DispatcherConfig.parse(_with('run_folder', 'run_folder: a/b')),
      throwsA(_error('run_folder', r'must match ^[A-Za-z0-9._-]+$')),
    );
    expect(() => DispatcherConfig.parse(_with('check', 'check: []')), throwsA(_error('check', 'must not be empty')));
    expect(
      () => DispatcherConfig.parse(_with('commit_types', 'commit_types: []')),
      throwsA(_error('commit_types', 'must not be empty')),
    );
    expect(
      () => DispatcherConfig.parse(_with('commit_types', 'commit_types: [feat, Fix]')),
      throwsA(_error('commit_types[1]', r'must match ^[a-z]+$')),
    );
    expect(
      () => DispatcherConfig.parse(_with('check', 'check: [dart test, 3]')),
      throwsA(_error('check[1]', 'must be a string')),
    );
    expect(
      () => DispatcherConfig.parse(_with('check', 'check: [dart test, "  "]')),
      throwsA(_error('check[1]', 'must not be empty')),
    );
  });

  test('a tasks_dir that is not a relative folder path is refused', () {
    for (final value in ['/abs', 'docs/', '../tasks', 'docs/./backlog', 'my tasks', '" "']) {
      expect(
        () => DispatcherConfig.parse(_with('tasks_dir', 'tasks_dir: $value')),
        throwsA(isA<ConfigError>().having((error) => error.key, 'key', 'tasks_dir')),
        reason: value,
      );
    }
  });

  test('a private pattern that is not a valid regex is refused', () {
    expect(
      () => DispatcherConfig.parse(_with('private_patterns', 'private_patterns: {broken: "("}')),
      throwsA(
        isA<ConfigError>()
            .having((error) => error.key, 'key', 'private_patterns.broken')
            .having((error) => error.problem, 'problem', startsWith('invalid regex: ')),
      ),
    );
  });

  test('a models entry must name a known tool and stage with exactly model, effort and name', () {
    String models(String body) => _with('models', 'models:\n$body');

    expect(
      () => DispatcherConfig.parse(models('  cursor:\n    reviewer: {model: a, effort: b, name: c}')),
      throwsA(_error('models.cursor', 'unknown tool')),
    );
    expect(
      () => DispatcherConfig.parse(models('  claude:\n    planner: {model: a, effort: b, name: c}')),
      throwsA(_error('models.claude.planner', 'unknown stage')),
    );
    expect(
      () => DispatcherConfig.parse(models('  claude:\n    reviewer: {model: a, name: c}')),
      throwsA(_error('models.claude.reviewer.effort', 'missing')),
    );
    expect(
      () => DispatcherConfig.parse(models('  claude:\n    reviewer: {model: a, effort: b, name: c, extra: d}')),
      throwsA(_error('models.claude.reviewer.extra', 'unknown key')),
    );
    expect(
      () => DispatcherConfig.parse(models('  claude:\n    reviewer: {model: "", effort: b, name: c}')),
      throwsA(_error('models.claude.reviewer.model', 'must not be empty')),
    );
  });

  test('commands are trimmed and split on runs of whitespace', () {
    expect(DispatcherConfig.splitCommand('  fvm   flutter\ttest  '), ['fvm', 'flutter', 'test']);
  });

  test('the error text names the file, the key and the problem', () {
    expect(
      '${const ConfigError('check[1]', 'must be a string')}',
      'planner_dispatcher.yaml: check[1]: must be a string',
    );
  });
}
