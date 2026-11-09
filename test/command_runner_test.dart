import 'dart:io';

import 'package:test/test.dart';

import 'package:planner_dispatcher/src/command_runner.dart';

void main() {
  test('a missing command throws', () async {
    const missing = 'dispatcher_nonexistent_executable_987654321';
    expect(() => runSystemCommand(missing, []), throwsA(isA<ProcessException>()));
  });

  test('resolves a user executable only when PATH does not contain it', () async {
    final root = await Directory.systemTemp.createTemp('dispatcher_test');
    addTearDown(() => root.delete(recursive: true));
    final bin = await Directory('${root.path}/.local/bin').create(recursive: true);
    final executable = File('${bin.path}/example');
    await executable.writeAsString('#!/bin/sh\n');
    await Process.run('chmod', ['755', executable.path]);
    final environment = {'HOME': root.path, 'PATH': '/nonexistent'};
    expect(resolveExecutable('example', environment: environment), executable.path);
    environment['PATH'] = bin.path;
    expect(resolveExecutable('example', environment: environment), 'example');
    expect(resolveExecutable('/explicit/example', environment: environment), '/explicit/example');
    expect(resolveExecutable('missing', environment: environment), 'missing');
  });
}
