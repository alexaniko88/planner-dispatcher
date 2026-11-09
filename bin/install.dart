// Installs the planner and dispatcher files into the project in the current folder.
//
//   <dart> run planner_dispatcher:install
//
// It copies the library-owned files, links them for Claude and creates the
// project-owned files once. It can run again after an update. The rules are in
// lib/src/install/installer.dart and are unit tested.
import 'dart:io';
import 'dart:isolate';

import 'package:planner_dispatcher/src/install/installer.dart';

Future<void> main() async {
  final projectRoot = Directory.current.path;
  if (!File('$projectRoot/pubspec.yaml').existsSync()) {
    stderr.writeln('Run install from the project root (no pubspec.yaml here).');
    exit(64);
  }
  final library = await Isolate.resolvePackageUri(Uri.parse('package:planner_dispatcher/'));
  if (library == null) {
    stderr.writeln('Cannot find the planner_dispatcher package.');
    exit(1);
  }
  final packageRoot = Directory.fromUri(library.resolve('../')).path.replaceFirst(RegExp(r'/$'), '');
  try {
    final report = Installer(projectRoot: projectRoot, packageRoot: packageRoot).install();
    report.lines().forEach(stdout.writeln);
  } catch (error) {
    stderr.writeln(error);
    exit(1);
  }
}
