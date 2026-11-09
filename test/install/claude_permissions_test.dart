import 'dart:convert';

import 'package:planner_dispatcher/src/config.dart';
import 'package:planner_dispatcher/src/install/claude_permissions.dart';
import 'package:test/test.dart';

const _config = DispatcherConfig(
  dart: 'fvm dart',
  baseBranch: 'main',
  setup: [],
  check: [
    ['fvm', 'flutter', 'analyze', '--no-pub'],
    ['fvm', 'flutter', 'test'],
  ],
  rules: [],
  commitTypes: ['feat'],
);

void main() {
  test('allows the library commands, the check commands and read-only git', () {
    expect(ClaudePermissions.rules(_config), [
      'Bash(fvm dart run planner_dispatcher:*)',
      'Bash(fvm flutter analyze --no-pub:*)',
      'Bash(fvm flutter test:*)',
      'Bash(git status:*)',
      'Bash(git diff:*)',
      'Bash(git log:*)',
      'Bash(git show:*)',
    ]);
  });

  test('creates the settings when there are none', () {
    final merged = ClaudePermissions.merge(null, ['Bash(a:*)']);

    expect(jsonDecode(merged.text), {
      'permissions': {
        'allow': ['Bash(a:*)'],
      },
    });
    expect(merged.added, ['Bash(a:*)']);
  });

  test('adds only the missing rules and keeps every other setting', () {
    const existing = '{"model": "opus", "permissions": {"allow": ["Bash(a:*)", "Read"], "deny": ["Bash(rm:*)"]}}';

    final merged = ClaudePermissions.merge(existing, ['Bash(a:*)', 'Bash(b:*)']);

    expect(jsonDecode(merged.text), {
      'model': 'opus',
      'permissions': {
        'allow': ['Bash(a:*)', 'Read', 'Bash(b:*)'],
        'deny': ['Bash(rm:*)'],
      },
    });
    expect(merged.added, ['Bash(b:*)']);
  });

  test('refuses settings it cannot read safely', () {
    for (final text in ['[1]', '{"permissions": []}', '{"permissions": {"allow": "x"}}', '{broken']) {
      expect(() => ClaudePermissions.merge(text, ['Bash(a:*)']), throwsFormatException, reason: text);
    }
  });
}
