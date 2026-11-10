import 'dart:convert';
import 'dart:io';

import 'package:planner_dispatcher/src/config.dart';
import 'package:planner_dispatcher/src/install/installer.dart';
import 'package:test/test.dart';

const _libraryPaths = [
  '.agents/skills/skill-dispatcher',
  '.agents/skills/skill-dispatcher-check',
  '.agents/skills/skill-planner',
  '.agents/rules/backlog-format.md',
];
const _skills = ['skill-dispatcher', 'skill-dispatcher-check', 'skill-planner'];
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

  test('a fresh install writes the library files, the skill links and the three project files', () {
    final report = installer().install();

    expect(report.written, [..._libraryPaths, for (final name in _skills) '.claude/skills/$name']);
    expect(report.created, unorderedEquals(_projectFiles));
    expect(report.kept, isEmpty);
    expect(report.starterChanged, isEmpty);
    for (final name in _skills) {
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
      removed: ['j', 'i'],
      created: ['d', 'c'],
      kept: ['f', 'e'],
      starterChanged: ['h', 'g'],
      stacksKept: 'stacks kept as installed: x',
      permissions: 'permissions kept y',
    );

    expect(report.lines(), [
      'wrote a',
      'wrote b',
      'removed i',
      'removed j',
      'created c',
      'created d',
      'kept e',
      'kept f',
      'starter changed: g',
      'starter changed: h',
      'stacks kept as installed: x',
      'permissions kept y',
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

  group('Claude permissions', () {
    List<Object?> allow() =>
        ((jsonDecode(File('$project/.claude/settings.json').readAsStringSync()) as Map)['permissions'] as Map)['allow']
            as List<Object?>;

    test('a fresh install allows the library and check commands from the new config', () {
      final report = installer().install();

      expect(report.permissions, 'permissions added 7 rules to .claude/settings.json');
      expect(allow(), containsAll(['Bash(fvm dart run planner_dispatcher:*)', 'Bash(fvm flutter test:*)']));
    });

    test('a second install adds nothing and keeps the rules the project added', () {
      installer().install();
      final file = File('$project/.claude/settings.json');
      final settings = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
      ((settings['permissions'] as Map)['allow'] as List).add('Bash(make:*)');
      file.writeAsStringSync(jsonEncode(settings));

      expect(installer().install().permissions, 'permissions kept .claude/settings.json');
      expect(allow(), contains('Bash(make:*)'));
    });

    test('a broken config or settings file changes nothing and says why', () {
      File('$project/planner_dispatcher.yaml').writeAsStringSync('dart: [broken\n');
      expect(installer().install().permissions, startsWith('permissions skipped: planner_dispatcher.yaml: (file)'));
      expect(File('$project/.claude/settings.json').existsSync(), isFalse);

      File('$project/planner_dispatcher.yaml').deleteSync();
      installer().install();
      File('$project/.claude/settings.json').writeAsStringSync('{broken');
      expect(installer().install().permissions, startsWith('permissions skipped: .claude/settings.json:'));
      expect(File('$project/.claude/settings.json').readAsStringSync(), '{broken');
    });
  });

  group('stacks', () {
    /// A copied package with a `stacks/<name>/` folder for each of [names].
    String packageWithStacks(List<String> names) {
      final package = copyPackage();
      for (final name in names) {
        File('$package/stacks/$name/rules.md')
          ..createSync(recursive: true)
          ..writeAsStringSync('# $name rules\n');
        File('$package/stacks/$name/extra/notes.md')
          ..createSync(recursive: true)
          ..writeAsStringSync('$name notes\n');
      }
      return package;
    }

    /// Writes the starter config with a `stacks` line.
    void configure(String stacksLine) {
      final starter = File('$_repoRoot/templates/planner_dispatcher.yaml').readAsStringSync();
      File('$project/planner_dispatcher.yaml').writeAsStringSync('$starter$stacksLine\n');
    }

    test('a configured stack is copied byte for byte and reported', () {
      final package = packageWithStacks(['demo', 'other']);
      configure('stacks: [demo]');

      final report = installer(package: package).install();

      expect(report.written, contains('.agents/rules/stacks/demo'));
      expect(File('$project/.agents/rules/stacks/demo/rules.md').readAsStringSync(), '# demo rules\n');
      expect(File('$project/.agents/rules/stacks/demo/extra/notes.md').readAsStringSync(), 'demo notes\n');
      expect(Directory('$project/.agents/rules/stacks/other').existsSync(), isFalse);
    });

    test('a stack the config no longer names is removed and reported', () {
      final package = packageWithStacks(['demo', 'other']);
      configure('stacks: [demo, other]');
      installer(package: package).install();

      configure('stacks: [other]');
      final report = installer(package: package).install();

      expect(report.removed, ['.agents/rules/stacks/demo']);
      expect(Directory('$project/.agents/rules/stacks/demo').existsSync(), isFalse);
      expect(Directory('$project/.agents/rules/stacks/other').existsSync(), isTrue);

      configure('stacks: []');
      expect(installer(package: package).install().removed, ['.agents/rules/stacks/other']);
      expect(Directory('$project/.agents/rules/stacks').existsSync(), isFalse);
    });

    test('an unknown stack raises InstallError and changes nothing', () {
      final package = packageWithStacks(['demo']);
      configure('stacks: [missing]');

      expect(
        () => installer(package: package).install(),
        throwsA(
          isA<InstallError>().having(
            (e) => e.message,
            'message',
            'unknown stack missing: the package has no stacks/missing/rules.md',
          ),
        ),
      );
      expect(Directory('$project/.agents').existsSync(), isFalse);
    });

    test('a broken config keeps the installed stacks and says why', () {
      final package = packageWithStacks(['demo']);
      configure('stacks: [demo]');
      installer(package: package).install();

      File('$project/planner_dispatcher.yaml').writeAsStringSync('dart: [broken\n');
      final report = installer(package: package).install();

      expect(report.removed, isEmpty);
      expect(report.written, isNot(contains('.agents/rules/stacks/demo')));
      expect(report.stacksKept, startsWith('stacks kept as installed: planner_dispatcher.yaml: (file)'));
      expect(File('$project/.agents/rules/stacks/demo/rules.md').existsSync(), isTrue);
    });

    test('a deleted config keeps the installed stacks', () {
      final package = packageWithStacks(['demo']);
      configure('stacks: [demo]');
      installer(package: package).install();

      File('$project/planner_dispatcher.yaml').deleteSync();
      final report = installer(package: package).install();

      expect(report.removed, isEmpty);
      expect(report.stacksKept, isEmpty);
      expect(report.created, contains('planner_dispatcher.yaml'));
      expect(File('$project/.agents/rules/stacks/demo/rules.md').existsSync(), isTrue);
    });

    test('a malformed stacks value raises InstallError and changes nothing', () {
      final package = packageWithStacks(['demo']);
      configure('stacks: [Demo]');

      expect(
        () => installer(package: package).install(),
        throwsA(
          isA<InstallError>().having(
            (e) => e.message,
            'message',
            r'planner_dispatcher.yaml: stacks[0]: must match ^[a-z0-9]+(-[a-z0-9]+)*$',
          ),
        ),
      );
      expect(Directory('$project/.agents').existsSync(), isFalse);
    });

    test('a folder the package does not ship stays, and a stopped copy is cleaned up', () {
      final package = packageWithStacks(['demo']);
      File('$project/.agents/rules/stacks/mine/rules.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('# mine\n');
      Directory('$project/.agents/rules/stacks/demo.install-tmp').createSync(recursive: true);
      configure('stacks: []');

      final report = installer(package: package).install();

      expect(report.removed, isEmpty);
      expect(File('$project/.agents/rules/stacks/mine/rules.md').existsSync(), isTrue);
      expect(Directory('$project/.agents/rules/stacks/demo.install-tmp').existsSync(), isFalse);
    });

    test('a project folder spelled like a shipped stack in another case stays', () {
      final package = packageWithStacks(['demo']);
      File('$project/.agents/rules/stacks/Demo/own.md')
        ..createSync(recursive: true)
        ..writeAsStringSync('own\n');
      configure('stacks: []');

      expect(installer(package: package).install().removed, isEmpty);
      expect(File('$project/.agents/rules/stacks/Demo/own.md').existsSync(), isTrue);
      expect(Directory('$project/.agents/rules/stacks/demo.install-tmp').existsSync(), isFalse);
    });

    test('a stack folder with a link raises InstallError', () {
      final package = packageWithStacks(['demo']);
      Link('$package/stacks/demo/link.md').createSync('rules.md');
      configure('stacks: [demo]');

      expect(
        () => installer(package: package).install(),
        throwsA(
          isA<InstallError>().having(
            (e) => e.message,
            'message',
            'shipped files must not contain links: stacks/demo/link.md',
          ),
        ),
      );
    });
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
