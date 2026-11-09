import 'package:planner_dispatcher/src/role_models.dart';
import 'package:test/test.dart';

String _row(Map<Role, RoleModel> models) => [
  for (final role in Role.values) '${models[role]?.model}/${models[role]?.effort}/${models[role]?.displayName}',
].join(' | ');

void main() {
  test('Claude and Codex suggest the agreed models for any complexity', () {
    for (final complexity in [1, 9, null]) {
      expect(
        _row(RoleModels.suggest(tool: 'claude', complexity: complexity)),
        'sonnet/medium/Sonnet 5.5 | sonnet/medium/Sonnet 5.5 | opus/medium/Opus 5.5',
      );
      expect(
        _row(RoleModels.suggest(tool: 'codex', complexity: complexity)),
        'gpt-6.1-terra/medium/GPT-6.1 Terra | gpt-6.1-terra/medium/GPT-6.1 Terra | gpt-6.1-sol/medium/GPT-6.1 Sol',
      );
    }
  });

  test('Antigravity suggests Flash for simple work and Argon for the rest and every review', () {
    const flash = 'flash/null/Gemini 3.8 Flash';
    const argon = 'inherit/null/Gemini 4 Argon';

    expect(_row(RoleModels.suggest(tool: 'antigravity', complexity: 4)), '$flash | $flash | $argon');
    expect(_row(RoleModels.suggest(tool: 'antigravity', complexity: 5)), '$argon | $argon | $argon');
    expect(_row(RoleModels.suggest(tool: 'antigravity')), '$argon | $argon | $argon');
  });

  test('another tool has no suggestion unless the project sets one', () {
    const kimi = RoleModel(model: 'kimi-k3', effort: null, displayName: 'Kimi K3');

    expect(RoleModels.suggest(tool: 'kimi'), isEmpty);
    expect(
      RoleModels.suggest(
        tool: 'kimi',
        configModels: {
          'kimi': {Role.implementer: kimi},
        },
      ),
      {Role.implementer: kimi},
    );
  });

  test('a project model replaces only its own stage', () {
    const custom = RoleModel(model: 'opus', effort: 'high', displayName: 'Opus 5.5');
    final models = RoleModels.suggest(
      tool: 'claude',
      configModels: {
        'claude': {Role.reviewer: custom},
      },
    );

    expect(models[Role.reviewer], custom);
    expect(models[Role.implementer]?.model, 'sonnet');
  });

  test('a typed model may carry an effort after a colon', () {
    expect(RoleModel.typed('opus:high'), const RoleModel(model: 'opus', effort: 'high', displayName: 'opus'));
    expect(RoleModel.typed(' qwen-4 '), const RoleModel(model: 'qwen-4', effort: null, displayName: 'qwen-4'));
  });

  test('each tool gets the parameters of its own subagent call', () {
    const terra = RoleModel(model: 'gpt-6.1-terra', effort: 'medium', displayName: 'GPT-6.1 Terra');

    expect(terra.callParameters('codex'), {
      'model': 'gpt-6.1-terra',
      'reasoning_effort': 'medium',
      'fork_turns': 'none',
    });
    expect(RoleModels.flash.callParameters('antigravity'), {'Model': 'flash'});
    expect(RoleModel.typed('opus:high').callParameters('claude'), {'model': 'opus', 'effort': 'high'});
    expect(RoleModel.typed('kimi-k3').callParameters('kimi'), {'model': 'kimi-k3'});
  });

  test('a commit names a known tool by its label and another by its name', () {
    expect(Tool.labelOf('claude'), 'Claude');
    expect(Tool.labelOf('kimi'), 'kimi');
  });
}
