import 'dart:convert';

import '../config.dart';

/// The Claude Code permission rules a task run needs, so the coordinator and
/// its subagents are not stopped by a permission dialog: the library commands,
/// the project's `check` commands and the read-only git commands.
class ClaudePermissions {
  static const _readOnlyGit = ['git status', 'git diff', 'git log', 'git show'];

  static List<String> rules(DispatcherConfig config) => [
    'Bash(${config.dart} run planner_dispatcher:*)',
    for (final command in config.check) 'Bash(${command.join(' ')}:*)',
    for (final command in _readOnlyGit) 'Bash($command:*)',
  ];

  /// Adds the missing [rules] to `permissions.allow` of the settings in
  /// [existing] (null when there is no file yet), keeping everything else.
  /// Returns the new text and the rules it added. Throws a [FormatException]
  /// when [existing] is not a JSON object with an object `permissions` and a
  /// list `allow`.
  static ({String text, List<String> added}) merge(String? existing, List<String> rules) {
    final Object? decoded = existing == null || existing.trim().isEmpty ? <String, Object?>{} : jsonDecode(existing);
    if (decoded is! Map<String, Object?>) throw const FormatException('the settings are not a JSON object');
    final permissions = decoded['permissions'] ?? <String, Object?>{};
    if (permissions is! Map<String, Object?>) throw const FormatException('"permissions" is not an object');
    final allow = permissions['allow'] ?? <Object?>[];
    if (allow is! List<Object?>) throw const FormatException('"permissions.allow" is not a list');

    final added = [
      for (final rule in rules)
        if (!allow.contains(rule)) rule,
    ];
    final settings = {
      ...decoded,
      'permissions': {
        ...permissions,
        'allow': [...allow, ...added],
      },
    };
    return (text: '${const JsonEncoder.withIndent('  ').convert(settings)}\n', added: added);
  }
}
