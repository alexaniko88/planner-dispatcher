import 'dart:io';

import 'package:planner_dispatcher/src/config.dart';
import 'package:planner_dispatcher/src/install/installer.dart';
import 'package:test/test.dart';

const _libraryPaths = [
  '.agents/skills/skill-dispatcher',
  '.agents/skills/skill-planner',
  '.agents/rules/backlog-format.md',
];
const _projectFiles = [
  'planner_dispatcher.yaml',
  '.agents/planner-dispatcher/project-overrides.md',
  '.agents/planner-dispatcher/planner-notes.md',
];
const _templates = ['planner_dispatcher.yaml', 'project-overrides.md', 'planner-notes.md'];

final _repoRoot = Directory.current.path;

void main() {
  late Directory temp;
  late String project;

  Installer installer({String? package}) => Installer(projectRoot: project, packageRoot: package ?? _repoRoot);

  setUp(() {
    temp = Directory.systemTemp.createTempSync('installer_test');
    project = '${temp.path}/project';
    Directory(project).createSync();
    File('$project/pubspec.yaml').writeAsStringSync('name: fixture\n');
    addTearDown(() => temp.deleteSync(recursive: true));
  });

  /// A package root holding copies of only the shipped files.
  String copyPackage() {
    final root = '${temp.path}/package';
    for (final path in _libraryPaths) {
      final source = '$_repoRoot/$path';
      if (FileSystemEntity.isDirectorySync(source)) {
        for (final file in Directory(source).listSync(recursive: true).whereType<File>()) {
          _copy(file, '$root/${file.path.substring(_repoRoot.length + 1)}');
        }
      } else {
        _copy(File(source), '$root/$path');
      }
    }
    for (final name in _templates) {
      _copy(File('$_repoRoot/templates/$name'), '$root/templates/$name');
    }
    return root;
  }

  test('a fresh install writes the library files, both links and the three project files', () {
    final report = installer().install();

    expect(report.written, [..._libraryPaths, '.claude/skills/skill-dispatcher', '.claude/skills/skill-planner']);
    expect(report.created, unorderedEquals(_projectFiles));
    expect(report.kept, isEmpty);
    expect(report.starterChanged, isEmpty);
    for (final name in ['skill-dispatcher', 'skill-planner']) {
      final link = Link('$project/.claude/skills/$name');
      expect(link.targetSync(), '../../.agents/skills/$name');
      expect(
        Directory(link.path).resolveSymbolicLinksSync(),
        Directory('$project/.agents/skills/$name').resolveSymbolicLinksSync(),
      );
    }
    for (final path in _projectFiles) {
      expect(File('$project/$path').existsSync(), isTrue, reason: path);
    }
  });

  test('library files equal the package files byte for byte', () {
    installer().install();

    for (final path in _libraryPaths) {
      final source = '$_repoRoot/$path';
      final files = FileSystemEntity.isDirectorySync(source)
          ? Directory(
              source,
            ).listSync(recursive: true).whereType<File>().where((f) => !f.path.endsWith('.DS_Store')).toList()
          : [File(source)];
      for (final file in files) {
        final target = File('$project/${file.path.substring(_repoRoot.length + 1)}');
        expect(target.readAsBytesSync(), file.readAsBytesSync(), reason: target.path);
      }
    }
  });

  test('a second run writes library files again, keeps project files and leaves edits alone', () {
    installer().install();
    File('$project/planner_dispatcher.yaml').writeAsStringSync('edited\n');

    final report = installer().install();

    expect(report.written, _libraryPaths);
    expect(report.created, isEmpty);
    expect(report.kept, unorderedEquals(_projectFiles));
    expect(File('$project/planner_dispatcher.yaml').readAsStringSync(), 'edited\n');
  });

  test('a shipped file that is gone disappears on the next run', () {
    final package = copyPackage();
    File('$package/.agents/skills/skill-planner/references/extra.md')
      ..createSync()
      ..writeAsStringSync('x');
    installer(package: package).install();
    expect(File('$project/.agents/skills/skill-planner/references/extra.md').existsSync(), isTrue);

    File('$package/.agents/skills/skill-planner/references/extra.md').deleteSync();
    installer(package: package).install();

    expect(File('$project/.agents/skills/skill-planner/references/extra.md').existsSync(), isFalse);
  });

  test('a package without a template raises InstallError', () {
    final package = copyPackage();
    File('$package/templates/planner-notes.md').deleteSync();

    expect(
      () => installer(package: package).install(),
      throwsA(
        isA<InstallError>().having((e) => e.message, 'message', 'package is incomplete: templates/planner-notes.md'),
      ),
    );
  });

  test('installing into the package itself raises InstallError', () {
    expect(
      () => Installer(projectRoot: _repoRoot, packageRoot: _repoRoot).install(),
      throwsA(isA<InstallError>().having((e) => e.message, 'message', 'Refusing to install into the package itself.')),
    );
  });

  test('lines come in the agreed order, each group sorted', () {
    const report = InstallReport(
      written: ['b', 'a'],
      created: ['d', 'c'],
      kept: ['f', 'e'],
      starterChanged: ['h', 'g'],
    );

    expect(report.lines(), [
      'wrote a',
      'wrote b',
      'created c',
      'created d',
      'kept e',
      'kept f',
      'starter changed: g',
      'starter changed: h',
    ]);
  });

  test('a shipped folder with a link raises InstallError', () {
    final package = copyPackage();
    Link('$package/.agents/skills/skill-planner/link').createSync('SKILL.md');

    expect(
      () => installer(package: package).install(),
      throwsA(
        isA<InstallError>().having((e) => e.message, 'message', startsWith('shipped files must not contain links:')),
      ),
    );
  });

  test('a correct dangling link is accepted', () {
    Directory('$project/.claude/skills').createSync(recursive: true);
    Link('$project/.claude/skills/skill-planner').createSync('../../.agents/skills/skill-planner');
    Directory('$project/.agents/skills/skill-planner').createSync(recursive: true);
    Directory('$project/.agents/skills/skill-planner').deleteSync();

    final report = installer().install();

    expect(report.written, isNot(contains('.claude/skills/skill-planner')));
    expect(report.written, contains('.claude/skills/skill-dispatcher'));
  });

  test('a leftover install-tmp is removed and the install completes', () {
    Directory('$project/.agents/skills/skill-planner.install-tmp').createSync(recursive: true);
    File('$project/.agents/skills/skill-planner.install-tmp/half.md').writeAsStringSync('half');
    Directory('$project/.agents/rules').createSync(recursive: true);
    File('$project/.agents/rules/backlog-format.md.install-tmp').writeAsStringSync('half');

    installer().install();

    expect(Directory('$project/.agents/skills/skill-planner.install-tmp').existsSync(), isFalse);
    expect(File('$project/.agents/rules/backlog-format.md.install-tmp').existsSync(), isFalse);
    expect(File('$project/.agents/skills/skill-planner/SKILL.md').existsSync(), isTrue);
  });

  test('install removes the format rule under its old name', () {
    File('$project/.agents/rules/project-tasks-format.md')
      ..createSync(recursive: true)
      ..writeAsStringSync('old');

    installer().install();

    expect(File('$project/.agents/rules/project-tasks-format.md').existsSync(), isFalse);
    expect(File('$project/.agents/rules/backlog-format.md').existsSync(), isTrue);
  });

  test('a real folder at a link path raises InstallError and changes nothing', () {
    Directory('$project/.claude/skills/skill-planner').createSync(recursive: true);

    expect(() => installer().install(), throwsA(isA<InstallError>()));

    expect(Directory('$project/.agents').existsSync(), isFalse);
    expect(Directory('$project/.claude/skills/skill-dispatcher').existsSync(), isFalse);
  });

  test('a wrong link raises InstallError', () {
    Directory('$project/.claude/skills').createSync(recursive: true);
    Link('$project/.claude/skills/skill-planner').createSync('../elsewhere');

    expect(() => installer().install(), throwsA(isA<InstallError>()));
  });

  test('a file where a folder belongs raises InstallError', () {
    File('$project/.agents').writeAsStringSync('x');

    expect(
      () => installer().install(),
      throwsA(isA<InstallError>().having((e) => e.message, 'message', '.agents must be a folder')),
    );
  });

  test('a changed template is reported and the starter copy is updated', () {
    final package = copyPackage();
    installer(package: package).install();
    File('$package/templates/planner-notes.md').writeAsStringSync('# New starter\n');

    final report = installer(package: package).install();

    expect(report.starterChanged, ['.agents/planner-dispatcher/planner-notes.md']);
    expect(report.kept, isNot(contains('.agents/planner-dispatcher/planner-notes.md')));
    expect(
      File('$project/.agents/planner-dispatcher/.starters/planner-notes.md').readAsStringSync(),
      '# New starter\n',
    );
    expect(File('$project/.agents/planner-dispatcher/planner-notes.md').readAsStringSync(), isNot('# New starter\n'));
  });

  test('the starter config parses as a schema 1 config', () {
    final config = DispatcherConfig.parse(File('$_repoRoot/templates/planner_dispatcher.yaml').readAsStringSync());

    expect(config.dart, 'fvm dart');
    expect(config.baseBranch, 'main');
  });
}

void _copy(File from, String to) {
  File(to).parent.createSync(recursive: true);
  from.copySync(to);
}
