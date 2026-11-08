import 'dart:io';

import 'package:test/test.dart';

final _root = Directory.current.path;

/// Runs a script of `bin/` directly with this package's package config, so no
/// `pub get` runs and CI needs no fvm.
ProcessResult _run(String script, List<String> args, {required String workingDirectory}) {
  return Process.runSync(
    Platform.resolvedExecutable,
    ['--packages=$_root/.dart_tool/package_config.json', '$_root/bin/$script.dart', ...args],
    workingDirectory: workingDirectory,
  );
}

void main() {
  late Directory folder;

  setUp(() {
    folder = Directory.systemTemp.createTempSync('bin_test');
    addTearDown(() => folder.deleteSync(recursive: true));
  });

  test('dispatcher without arguments prints usage and exits 64 without a config', () {
    final result = _run('dispatcher', [], workingDirectory: folder.path);

    expect(result.exitCode, 64);
    expect(result.stderr, contains('Usage: <dart> run planner_dispatcher:dispatcher'));
  });

  test('dispatcher next without a config exits 78 with the one-line error', () {
    final result = _run('dispatcher', ['next'], workingDirectory: folder.path);

    expect(result.exitCode, 78);
    expect('${result.stderr}'.trim(), 'planner_dispatcher.yaml: (file): not found');
  });

  test('sync without a config exits 78 with the one-line error', () {
    final result = _run('sync', [], workingDirectory: folder.path);

    expect(result.exitCode, 78);
    expect('${result.stderr}'.trim(), 'planner_dispatcher.yaml: (file): not found');
  });
}
