import 'dart:io';

import 'package:planner_dispatcher/src/config.dart';
import 'package:planner_dispatcher/src/role_models.dart';
import 'package:test/test.dart';

const _dispatcherFolder = '.agents/skills/skill-dispatcher';
const _plannerFolder = '.agents/skills/skill-planner';
const _formatRule = '.agents/rules/backlog-format.md';
const _accessModes = {'read-only', 'edit'};
const _plannerNotesHeadings = [
  '## Branches and pull requests',
  '## UI sources',
  '## Project skills',
  '## Checks',
  '## Coverage checks',
];
const _headings = ['## Common', '## Implementation', '## Tests', '## Review checks'];

/// What a role reads, in this order, the first time each one is named.
const _readOrder = [
  'planner_dispatcher.yaml',
  'runner-rules.md',
  '.agents/planner-dispatcher/project-overrides.md',
  'backlog-format.md',
];

// A project build or test command must not appear in shipped dispatcher files.
final _projectCommand = RegExp(r'\bfvm\b|\bflutter (analyze|test|pub|run|gen-l10n|build)\b', caseSensitive: false);

final _plannerForbidden = RegExp(
  r'\bfvm\b|\bflutter (analyze|test|pub|run|gen-l10n|build)\b|\bmaster\b',
  caseSensitive: false,
);

final _referencedPath = RegExp(r'\.agents/(?:rules|skills)/[A-Za-z0-9_./\-]+\.md');

void main() {
  group('dispatcher', () {
    for (final role in Role.values) {
      test('${role.name} has a role file that the runner can read', () {
        final markdown = File('$_dispatcherFolder/roles/${role.name}.md').readAsStringSync();

        expect(_frontMatterValue(markdown, 'name'), role.name);
        expect(_accessModes, contains(_frontMatterValue(markdown, 'access')));
      });

      test('${role.name} reads the config, runner rules, project overrides and format rule in order', () {
        final markdown = File('$_dispatcherFolder/roles/${role.name}.md').readAsStringSync();
        final section = _section(markdown, '## Read first');

        expect(section, isNotNull, reason: '${role.name}.md has no "## Read first" section');
        final positions = [for (final name in _readOrder) section!.indexOf(name)];
        expect(positions, everyElement(isNonNegative), reason: '${role.name}.md must name all of $_readOrder');
        expect(positions, orderedEquals([...positions]..sort()), reason: '${role.name}.md reads them out of order');
      });
    }

    test('the reviewer role is read-only and says so', () {
      final markdown = File('$_dispatcherFolder/roles/reviewer.md').readAsStringSync();

      expect(_frontMatterValue(markdown, 'access'), 'read-only');
      expect(markdown, contains('Never edit'));
    });

    test('there is no role file without a Role value', () {
      final names = _files('$_dispatcherFolder/roles').map(_baseName).toList()..sort();

      expect(names, (Role.values.map((role) => '${role.name}.md').toList()..sort()));
    });

    test('SKILL.md names every default model of the table', () {
      final text = File('$_dispatcherFolder/SKILL.md').readAsStringSync();

      for (final models in RoleModels.table.values) {
        for (final model in models.values) {
          expect(text, contains(model.displayName), reason: 'SKILL.md does not mention ${model.displayName}');
        }
      }
    });

    test('every file the dispatcher files tell to read exists', () {
      for (final file in _files(_dispatcherFolder, recursive: true)) {
        final text = File(file).readAsStringSync();
        for (final match in _referencedPath.allMatches(text)) {
          final path = match.group(0) ?? '';
          expect(File(path).existsSync(), isTrue, reason: '$file mentions $path, which does not exist');
        }
      }
    });

    test('runner-rules.md and the project overrides have exactly the four sections', () {
      for (final path in [
        '$_dispatcherFolder/references/runner-rules.md',
        '.agents/planner-dispatcher/project-overrides.md',
      ]) {
        expect(_headingsOf(File(path).readAsStringSync()), _headings, reason: path);
      }
    });

    test('no dispatcher file or the format rule names a project build command', () {
      final files = [..._files(_dispatcherFolder, recursive: true), _formatRule];

      for (final file in files) {
        final lines = File(file).readAsLinesSync();
        for (final (index, line) in lines.indexed) {
          expect(_projectCommand.hasMatch(line), isFalse, reason: '$file:${index + 1}: $line');
        }
      }
    });

    test('this repo config is valid and every rule file it lists exists', () {
      final config = DispatcherConfig.load();

      for (final rule in config.rules) {
        expect(File(rule).existsSync(), isTrue, reason: 'rules lists $rule, which does not exist');
      }
    });

    test('the Claude skill folder links to the shipped skill', () {
      const link = '.claude/skills/skill-dispatcher';

      expect(FileSystemEntity.isLinkSync(link), isTrue);
      expect(
        Directory(link).resolveSymbolicLinksSync(),
        Directory(_dispatcherFolder).absolute.resolveSymbolicLinksSync(),
      );
    });
  });

  group('planner', () {
    for (final role in ['cold-reader', 'interview-reviewer']) {
      test('$role is read-only and says it never edits', () {
        final markdown = File('$_plannerFolder/roles/$role.md').readAsStringSync();

        expect(_frontMatterValue(markdown, 'access'), 'read-only');
        expect(markdown, anyOf(contains('Never edit'), contains('Do not edit')));
      });
    }

    test('SKILL.md names the planner model of every tool', () {
      final text = File('$_plannerFolder/SKILL.md').readAsStringSync();

      for (final model in ['Opus 5.5', 'GPT-6.1 Sol', 'Gemini 4 Argon']) {
        expect(text, contains(model));
      }
    });

    test('every references or roles link in SKILL.md exists', () {
      final text = File('$_plannerFolder/SKILL.md').readAsStringSync();
      final links = RegExp(r'\]\(((?:references|roles)/[^)#]+)').allMatches(text).map((match) => match.group(1)!);

      expect(links, isNotEmpty);
      for (final link in links) {
        expect(File('$_plannerFolder/$link').existsSync(), isTrue, reason: 'SKILL.md links $link');
      }
    });

    test('every relative link in the planner files and the format rule resolves', () {
      for (final file in [..._files(_plannerFolder, recursive: true), _formatRule]) {
        for (final link in _relativeLinks(File(file).readAsStringSync())) {
          final target = _resolve(file, link);
          expect(
            File(target).existsSync() || Directory(target).existsSync(),
            isTrue,
            reason: '$file links $link, which does not exist',
          );
        }
      }
    });

    test('every .agents path a planner file mentions exists', () {
      for (final file in _files(_plannerFolder, recursive: true)) {
        for (final match in _referencedPath.allMatches(File(file).readAsStringSync())) {
          final path = match.group(0) ?? '';
          expect(File(path).existsSync(), isTrue, reason: '$file mentions $path, which does not exist');
        }
      }
    });

    test('the entry files mention the config and the planner notes', () {
      for (final path in ['SKILL.md', 'roles/cold-reader.md', 'roles/interview-reviewer.md']) {
        final text = File('$_plannerFolder/$path').readAsStringSync();

        expect(text, contains('planner_dispatcher.yaml'), reason: path);
        expect(text, contains('planner-notes.md'), reason: path);
      }
    });

    test('no planner file names a project build command or the master branch', () {
      for (final file in _files(_plannerFolder, recursive: true)) {
        final lines = File(file).readAsLinesSync();
        for (final (index, line) in lines.indexed) {
          expect(_plannerForbidden.hasMatch(line), isFalse, reason: '$file:${index + 1}: $line');
        }
      }
    });

    test('this repo planner notes have exactly the five agreed headings', () {
      final markdown = File('.agents/planner-dispatcher/planner-notes.md').readAsStringSync();

      expect(_headingsOf(markdown), _plannerNotesHeadings);
    });

    test('the Claude skill folder links to the shipped planner skill', () {
      const link = '.claude/skills/skill-planner';

      expect(FileSystemEntity.isLinkSync(link), isTrue);
      expect(
        Directory(link).resolveSymbolicLinksSync(),
        Directory(_plannerFolder).absolute.resolveSymbolicLinksSync(),
      );
    });
  });
}

/// Relative Markdown link targets outside code fences, without anchors, `<` placeholders and URLs.
List<String> _relativeLinks(String source) {
  final links = <String>[];
  var inFence = false;
  for (final line in source.split('\n')) {
    if (line.trimLeft().startsWith('```')) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    for (final match in RegExp(r'\]\(([^)\s]+)\)').allMatches(line)) {
      final target = match.group(1)!.split('#').first;
      if (target.isEmpty || target.contains('<') || target.contains('://')) continue;
      links.add(target);
    }
  }
  return links;
}

/// The path of [link] relative to the folder of [file], with `..` segments applied.
String _resolve(String file, String link) {
  final parts = file.split('/')..removeLast();
  for (final part in link.split('/')) {
    if (part == '..') {
      parts.removeLast();
    } else if (part != '.' && part.isNotEmpty) {
      parts.add(part);
    }
  }
  return parts.join('/');
}

/// Files directly in [folder], or all files below it, without hidden ones like `.DS_Store`.
List<String> _files(String folder, {bool recursive = false}) {
  return Directory(folder)
      .listSync(recursive: recursive, followLinks: false)
      .whereType<File>()
      .map((file) => file.path)
      .where((path) => !_baseName(path).startsWith('.'))
      .toList();
}

String _baseName(String path) => path.split('/').last;

/// The value of [key] in the YAML front matter of a Markdown file.
String? _frontMatterValue(String source, String key) {
  final block = RegExp(r'^---\r?\n(.*?)\r?\n---', dotAll: true).firstMatch(source)?.group(1);
  if (block == null) return null;
  return RegExp('^$key: (.*)\$', multiLine: true).firstMatch(block)?.group(1)?.trim();
}

/// The text under [heading] up to the next `## ` heading.
String? _section(String source, String heading) {
  return RegExp(
    '^${RegExp.escape(heading)}\\r?\\n(.*?)(?=^## |\\z)',
    multiLine: true,
    dotAll: true,
  ).firstMatch(source)?.group(1);
}

/// Every `## ` heading of [source], outside code fences.
List<String> _headingsOf(String source) {
  return [
    for (final line in source.split('\n'))
      if (line.startsWith('## ')) line.trimRight(),
  ];
}
