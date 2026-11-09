/// The tools with built-in model suggestions. A task can run with any other
/// tool too; it then has no suggestion and the user types the models.
enum Tool {
  claude('Claude'),
  codex('Codex'),
  antigravity('Antigravity');

  final String label;

  const Tool(this.label);

  static Tool? fromName(String name) => Tool.values.asNameMap()[name];

  /// How a commit names [name]: the label of a known tool, else the name.
  static String labelOf(String name) => fromName(name)?.label ?? name;
}

/// The stages of one task run, each a subagent with its own model.
enum Role {
  implementer,
  tests,
  reviewer,
}

/// The model of one stage. [model] is the value the tool's subagent call
/// takes; [effort] is null when the call has no effort setting.
class RoleModel {
  final String model;
  final String? effort;
  final String displayName;

  const RoleModel({required this.model, required this.effort, required this.displayName});

  /// A model the user typed: `model` or `model:effort`.
  factory RoleModel.typed(String text) {
    final at = text.indexOf(':');
    final model = (at < 0 ? text : text.substring(0, at)).trim();
    final effort = at < 0 ? null : text.substring(at + 1).trim();
    return RoleModel(model: model, effort: effort == null || effort.isEmpty ? null : effort, displayName: model);
  }

  /// The parameters of the subagent call of the tool named [tool].
  Map<String, String> callParameters(String tool) => switch (Tool.fromName(tool)) {
    Tool.codex => {'model': model, 'reasoning_effort': ?effort, 'fork_turns': 'none'},
    Tool.antigravity => {'Model': model},
    _ => {'model': model, 'effort': ?effort},
  };

  Map<String, Object?> toJson() => {'model': model, 'effort': effort, 'name': displayName};

  static RoleModel? fromJson(Object? json) => switch (json) {
    {'model': final String model, 'name': final String name} => RoleModel(
      model: model,
      effort: json['effort'] is String ? json['effort'] as String : null,
      displayName: name,
    ),
    _ => null,
  };

  @override
  bool operator ==(Object other) =>
      other is RoleModel && other.model == model && other.effort == effort && other.displayName == displayName;

  @override
  int get hashCode => Object.hash(model, effort, displayName);
}

/// The suggested model of every stage, per tool.
class RoleModels {
  static const _sonnet = RoleModel(model: 'sonnet', effort: 'medium', displayName: 'Sonnet 5.5');
  static const _terra = RoleModel(model: 'gpt-6.1-terra', effort: 'medium', displayName: 'GPT-6.1 Terra');

  /// Antigravity's subagent call only picks `flash`; Argon is the model of the
  /// session itself, so its stages inherit it.
  static const flash = RoleModel(model: 'flash', effort: null, displayName: 'Gemini 3.8 Flash');
  static const argon = RoleModel(model: 'inherit', effort: null, displayName: 'Gemini 4 Argon');

  /// Antigravity tasks up to this complexity are simple enough for Flash.
  static const maxFlashComplexity = 4;

  static const Map<Tool, Map<Role, RoleModel>> table = {
    Tool.claude: {
      Role.implementer: _sonnet,
      Role.tests: _sonnet,
      Role.reviewer: RoleModel(model: 'opus', effort: 'medium', displayName: 'Opus 5.5'),
    },
    Tool.codex: {
      Role.implementer: _terra,
      Role.tests: _terra,
      Role.reviewer: RoleModel(model: 'gpt-6.1-sol', effort: 'medium', displayName: 'GPT-6.1 Sol'),
    },
    Tool.antigravity: {Role.implementer: argon, Role.tests: argon, Role.reviewer: argon},
  };

  /// The suggestion for each stage of a task of [complexity] run with the
  /// tool named [tool]: the project's [configModels] first, then the built-in
  /// [table]. A stage with neither is missing from the map.
  static Map<Role, RoleModel> suggest({
    required String tool,
    int? complexity,
    Map<String, Map<Role, RoleModel>> configModels = const {},
  }) {
    final builtIn = {...?table[Tool.fromName(tool)]};
    if (Tool.fromName(tool) == Tool.antigravity && complexity != null && complexity <= maxFlashComplexity) {
      builtIn[Role.implementer] = flash;
      builtIn[Role.tests] = flash;
    }
    return {
      for (final role in Role.values) role: ?(configModels[tool]?[role] ?? builtIn[role]),
    };
  }
}
