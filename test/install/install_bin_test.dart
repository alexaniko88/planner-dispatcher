import 'dart:io';

import 'package:test/test.dart';

final _root = Directory.current.path;

ProcessResult _run(String workingDirectory) {
  return Process.runSync(
    Platform.resolvedExecutable,
    ['--packages=$_root/.dart_tool/package_config.json', '$_root/bin/install.dart'],
    workingDirectory: workingDirectory,
  );
}

void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('install_bin_test');
    addTearDown(() => folder.deleteSync(recursive: true));
  });

  test('install without a pubspec exits 64 with the message', () {
    final result = _run(folder.path);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Run install from the project root (no pubspec.yaml here).'));
  });

  test('install in a project writes the files and exits 0', () {
    File('${folder.path}/pubspec.yaml').writeAsStringSync('name: fixture\n');

    final result = _run(folder.path);

    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect((result.stdout as String).split('\n').first, startsWith('wrote '));
  });
}
