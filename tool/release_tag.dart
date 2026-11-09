// Prints the release tag for the version in pubspec.yaml, for the release workflow.
import 'dart:io';

import 'package:planner_dispatcher/src/release_tag.dart';

void main() {
  try {
    stdout.writeln(releaseTag(File('pubspec.yaml').readAsStringSync()));
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exit(1);
  }
}
