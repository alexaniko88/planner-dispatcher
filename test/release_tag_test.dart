import 'dart:io';

import 'package:planner_dispatcher/src/release_tag.dart';
import 'package:test/test.dart';

void main() {
  test('a plain version gives its tag', () {
    expect(releaseTag('name: x\nversion: 0.1.0\n'), 'v0.1.0');
  });

  test('quoted, commented and CRLF forms work', () {
    expect(releaseTag('version: "1.2.3"\n'), 'v1.2.3');
    expect(releaseTag("version: '1.2.3'\n"), 'v1.2.3');
    expect(releaseTag('version: 1.2.3 # next\n'), 'v1.2.3');
    expect(releaseTag('name: x\r\nversion: 1.2.3\r\nrepository: y\r\n'), 'v1.2.3');
  });

  test('an indented version line is ignored', () {
    expect(releaseTag('dependencies:\n  version: 9.9.9\nversion: 1.0.0\n'), 'v1.0.0');
    expect(() => releaseTag('  version: 1.0.0\n'), throwsFormatException);
  });

  test('a pre-release, a build suffix, a missing line and an empty file throw', () {
    expect(() => releaseTag('version: 1.0.0-beta.1\n'), throwsFormatException);
    expect(() => releaseTag('version: 1.0.0+2\n'), throwsFormatException);
    expect(() => releaseTag('name: x\n'), throwsFormatException);
    expect(() => releaseTag(''), throwsFormatException);
  });

  test('the real pubspec.yaml gives a tag', () {
    expect(releaseTag(File('pubspec.yaml').readAsStringSync()), matches(RegExp(r'^v\d+\.\d+\.\d+$')));
  });
}
