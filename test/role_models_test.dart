import 'package:planner_dispatcher/src/role_models.dart';
import 'package:test/test.dart';

void main() {
  test('the default table is the agreed one', () {
    String row(Tool tool) => [
      for (final role in Role.values)
        '${RoleModels.table[tool]![role]!.model}/${RoleModels.table[tool]![role]!.effort}'
            '/${RoleModels.table[tool]![role]!.displayName}',
    ].join(' | ');

    expect(row(Tool.claude), 'sonnet/medium/Sonnet 5.5 | sonnet/medium/Sonnet 5.5 | opus/medium/Opus 5.5');
    expect(
      row(Tool.codex),
      'gpt-6.1-terra/medium/GPT-6.1 Terra | gpt-6.1-terra/medium/GPT-6.1 Terra | gpt-6.1-sol/medium/GPT-6.1 Sol',
    );
    expect(
      row(Tool.antigravity),
      'gemini-4-argon-medium/medium/Gemini 4 Argon | gemini-4-argon-medium/medium/Gemini 4 Argon'
      ' | gemini-4-argon-high/high/Gemini 4 Argon',
    );
  });

  test('a config override replaces only its own stage', () {
    const custom = RoleModel(model: 'opus', effort: 'high', displayName: 'Opus 5.5');
    const config = {
      Tool.claude: {Role.reviewer: custom},
    };

    expect(RoleModels.of(tool: Tool.claude, role: Role.reviewer, configModels: config), custom);
    expect(RoleModels.of(tool: Tool.claude, role: Role.implementer, configModels: config).model, 'sonnet');
    expect(RoleModels.of(tool: Tool.codex, role: Role.reviewer, configModels: config).model, 'gpt-6.1-sol');
  });

  test('a command line flag beats the config', () {
    const config = {
      Tool.claude: {Role.reviewer: RoleModel(model: 'opus', effort: 'high', displayName: 'Opus 5.5')},
    };

    final model = RoleModels.of(
      tool: Tool.claude,
      role: Role.reviewer,
      configModels: config,
      overrides: {Role.reviewer: 'haiku'},
    );

    expect((model.model, model.effort), ('haiku', 'medium'));
  });
}
