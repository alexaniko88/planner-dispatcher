import 'dart:io';

import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('every stack lint set is a sorted list of distinct linter rules with no other key', () {
    final files = Directory('lib/analysis').listSync().whereType<File>().toList();

    expect(files, isNotEmpty);
    for (final file in files) {
      final root = loadYaml(file.readAsStringSync());
      expect(root, isA<Map>(), reason: file.path);
      expect((root as Map).keys, ['linter'], reason: file.path);
      final linter = root['linter'];
      expect(linter, isA<Map>(), reason: file.path);
      expect((linter as Map).keys, ['rules'], reason: file.path);
      final rules = linter['rules'];
      expect(rules, isA<List>(), reason: file.path);
      final names = [for (final rule in rules as List) rule as String];
      expect(
        names,
        [
          ...{...names},
        ]..sort(),
        reason: '${file.path} must be sorted, with no duplicates',
      );
    }
  });

  test('every stack lint set belongs to a stack pack', () {
    for (final file in Directory('lib/analysis').listSync().whereType<File>()) {
      final name = file.uri.pathSegments.last.replaceFirst(RegExp(r'\.yaml$'), '');
      expect(File('stacks/$name/rules.md').existsSync(), isTrue, reason: file.path);
    }
  });
}
