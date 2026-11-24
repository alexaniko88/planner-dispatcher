import 'dart:convert';
import 'dart:io';

/// The result of a finished command.
class CommandResult {
  final int exitCode;
  final String stdout;
  final String stderr;

  const CommandResult({required this.exitCode, required this.stdout, required this.stderr});

  bool get ok => exitCode == 0;
}

/// Runs one command. Tests pass a fake; the tool uses [runSystemCommand].
typedef RunCommand =
    Future<CommandResult> Function(
      String executable,
      List<String> args, {
      String? workingDirectory,
    });

Future<CommandResult> runSystemCommand(
  String executable,
  List<String> args, {
  String? workingDirectory,
}) async {
  // Read the raw bytes: git can print binary files (such as images) in a diff,
  // and a strict UTF-8 decode would throw on them. Bad bytes become U+FFFD.
  final result = await Process.run(
    resolveExecutable(executable),
    args,
    workingDirectory: workingDirectory,
    stdoutEncoding: null,
    stderrEncoding: null,
  );
  return CommandResult(
    exitCode: result.exitCode,
    stdout: utf8.decode(result.stdout as List<int>, allowMalformed: true),
    stderr: utf8.decode(result.stderr as List<int>, allowMalformed: true),
  );
}

/// Finds user-installed tools when a non-interactive shell has a reduced PATH.
String resolveExecutable(String executable, {Map<String, String>? environment}) {
  final env = environment ?? Platform.environment;
  if (executable.contains('/') || executable.contains(r'\')) return executable;
  bool usable(String path) {
    final stat = File(path).statSync();
    return stat.type == FileSystemEntityType.file && (Platform.isWindows || stat.mode & 73 != 0);
  }

  for (final directory in (env['PATH'] ?? '').split(Platform.isWindows ? ';' : ':')) {
    if (directory.isNotEmpty && usable('$directory/$executable')) return executable;
  }
  final home = env['HOME'];
  if (home != null) {
    final candidate = '$home/.local/bin/$executable';
    if (usable(candidate)) return candidate;
  }
  return executable;
}
