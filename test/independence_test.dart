import 'dart:io';

import 'package:test/test.dart';

/// Every file under the folders that exist, plus [files] that exist.
List<File> _files(List<String> folders, {List<String> files = const []}) {
  return [
    for (final folder in folders)
      if (Directory(folder).existsSync())
        ...Directory(folder).listSync(recursive: true, followLinks: false).whereType<File>(),
    for (final file in files)
      if (File(file).existsSync()) File(file),
  ];
}

/// The files that contain [pattern], with the first matching line.
List<String> _matches(List<File> files, RegExp pattern) {
  return [
    for (final file in files)
      for (final (index, line) in file.readAsLinesSync().indexed)
        if (pattern.hasMatch(line)) '${file.path}:${index + 1}: ${line.trim()}',
  ];
}

void main() {
  test('shipped files never name another project or a local home path', () {
    final shipped = _files(['lib', 'bin', '.agents', 'templates'], files: ['README.md']);
    // Built from parts so this test does not describe a private path itself.
    final forbidden = RegExp(
      r'\bsport|agent_check|/Us'
      'ers/',
      caseSensitive: false,
    );

    expect(_matches(shipped, forbidden), isEmpty);
  });

  test('the engine hard-codes no project command, golden folder or base branch', () {
    final engine = _files(['lib', 'bin']);
    final forbidden = RegExp(r'fvm|flutter|test/snapshots|origin/master', caseSensitive: false);

    expect(_matches(engine, forbidden), isEmpty);
  });
}
