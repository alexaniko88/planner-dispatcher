import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final readme = File('README.md').readAsStringSync();

  test('README names every command in full', () {
    for (final command in [
      'planner_dispatcher:dispatcher next',
      'planner_dispatcher:dispatcher models',
      'planner_dispatcher:dispatcher launch',
      'planner_dispatcher:dispatcher status',
      'planner_dispatcher:sync',
      'planner_dispatcher:install',
      'planner_dispatcher:backlog close-finished',
      'planner_dispatcher:backlog reopen',
    ]) {
      expect(readme, contains(command));
    }
  });

  test('README documents every key of the starter config', () {
    final starter = loadYaml(File('templates/planner_dispatcher.yaml').readAsStringSync()) as YamlMap;

    for (final key in starter.keys) {
      expect(readme, contains('`$key`'), reason: key.toString());
    }
  });

  test('README documents the optional keys that the starter leaves commented out', () {
    for (final key in ['tasks_dir', 'goldens_dir', 'git_email_suffix', 'private_patterns', 'models']) {
      expect(readme, contains('`$key`'), reason: key);
    }
  });

  test('README shows the pinned git dependency', () {
    expect(readme, contains('ref: v'));
  });
}
