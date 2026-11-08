---
id: PD-01-02
status: ready
type: feat
complexity: medium
depends-on: [PD-01-01]
touches:
  - .agents/skills/skill-dispatcher/**
  - .agents/rules/project-tasks-format.md
  - .agents/planner-dispatcher/project-overrides.md
  - .claude/skills/skill-dispatcher
  - test/skills_test.dart
skills: []
---

# Dispatcher skill and roles

Story: [Dispatcher](../index.md)

Epic: [Standalone planner and dispatcher](../../../index.md)

**Run this task by hand** in a normal AI session in this repo, after PD-01-01 is merged. Open a normal PR. In that PR, move this task folder to `done/` with `status: done` and a `notes.md`, as the format rule's done rule says.

## Goal

Add the generic dispatcher skill, the three runner roles, the shared runner rules and the task format rule, plus this repo's own runner rules. After this task the engine's stage brief points to real files, and this repo dispatches its own tasks.

## Context

- Source to copy (public repo `https://github.com/alexaniko88/sport_timer`, branch `master`): `.agents/skills/skill-dispatcher/SKILL.md`, `roles/implementer.md`, `roles/tests.md`, `roles/reviewer.md`, `references/project-overrides.md`, `.agents/rules/project-tasks-format.md`; the role guards in `test/architecture/ai_setup_test.dart` (group `dispatcher`).
- Engine from PD-01-01: `Role`, `Tool`, `RoleModels.table` in `lib/src/role_models.dart`; `DispatcherConfig` in `lib/src/config.dart`; stage brief in `lib/src/stage_runner.dart`.
- Contracts: layout, consumer paths, role reading order and default models in the [epic](../../../index.md#shared-contracts).

## Contract

- New here, shipped and library-owned:
  - `.agents/skills/skill-dispatcher/SKILL.md`: the source skill with every command written as `<dart> run planner_dispatcher:dispatcher ...` and `<dart> run planner_dispatcher:sync`, and one line saying `<dart>` is the `dart` value of `planner_dispatcher.yaml` (example: `dart`; never write `fvm` here). The model table points to `lib/src/role_models.dart` instead of `tool/dispatcher/role_models.dart`. "Rules for the runners" points to `references/runner-rules.md` and `.agents/planner-dispatcher/project-overrides.md`. Same loop, limits (3 runners), standing authorization and result handling as the source, with `master` replaced by "the configured `base_branch`". The pointer to the orchestrator skill for free-form requests is dropped (no such skill ships); front matter keeps `model: claude-sonnet-5-5` and `effort: medium`. The "refine with `skill-planner`" sentence stays (plain name, no path). The noreply email line becomes "the configured `git_email_suffix`, when set". The model table is the epic default table plus one line saying a project may override it under `models`.
  - `roles/implementer.md`, `roles/tests.md`, `roles/reviewer.md`: the source roles with the "Read first" list replaced by the epic reading order and sections (no `dart-style.md` or `git-commits.md`; those are project rules listed in the config). Format, analyze and test steps become "run the per-file format, analyze and test commands the project overrides name, by literal path"; ARB, `gen-l10n`, golden, layer and `fvm` details move out (they are project facts). Diffs use `origin/<base_branch>`. The implementer and tests commit lines stay `<type>: <description>`: type from the config's `commit_types` (the tests role uses `test` when listed, otherwise the closest listed type), lowercase, imperative, no final period, at most 72 characters (the engine's 100 is only the hard limit). The implementer keeps reading every skill in the task's `skills:`. The reviewer's checks and severity examples become "the project rules and the Review checks sections" (no layer test, style file or app topics named); its JSON example finding uses `lib/src/store.dart` and "The missing-file case has no test." The implementer note becomes "the task's `type` is a branch prefix, not a commit type; the script rejects `improve`". Front matter keeps `name` and `access` (reviewer `read-only` and says `Never edit`).
  - `references/runner-rules.md`, sections `## Common`, `## Implementation`, `## Tests`, `## Review checks`: the generic bullets of the source `project-overrides.md` and roles (Common: scope, fixed task contract, unwired building blocks, git, minimal tools limited to the project overrides' per-file commands and the config's `check` commands (Claude enforces this through `allowed_commands`; Codex and Antigravity get it as an instruction only, as the source's permission-limits bullet says) plus read-only `git status/diff/log/show`, `rg`, `grep`, `ls`, `cat`, `head`, `tail`, `wc`, `sort`, `diff`, `mkdir`, no runtime or manual validation, permission limits, one simple command per check, edit with edit tools; Implementation: plan one file or concern per step, comments explain why in one or two sentences, put new files where the project rules say; Tests: tests only for changed code, run by literal path, reuse existing infrastructure, the task names fakes and harness changes; Review: unapproved contract change or unmet acceptance check is critical, out-of-scope helpers or test infrastructure is general). No project-specific architecture, theme, strings or tools.
  - `.agents/rules/project-tasks-format.md`: the source rule, generic. "on `master`" becomes "on the base branch"; golden examples refer to "the configured `goldens_dir`"; `lib/l10n/**` becomes "a generated or shared strings folder"; the `test/snapshots/README.md` exemption becomes "generated index files the planner notes name"; the `skills:` example becomes `[skill-charts]`; the `touches` example becomes `lib/src/store.dart` and `test/goldens/home.png`; "never `test/snapshots/**`" becomes "never the whole `goldens_dir`"; "the dispatcher overrides" becomes `../skills/skill-dispatcher/references/runner-rules.md` and `.agents/planner-dispatcher/project-overrides.md`; `TPL` id examples stay; the visual task sections stay (they apply only when a project has a view); links into the planner (`../skills/skill-planner/...`) stay as they are (they resolve after PD-02-01).
- New here, this repo only: `.agents/planner-dispatcher/project-overrides.md` with sections `## Common`, `## Implementation`, `## Tests`, `## Review checks` for this Dart package. Common: per-file commands `fvm dart format <path>`, `fvm dart analyze <path>`, `fvm dart test <path>`; shipped files (`lib/`, `bin/`, `.agents/`, `templates/`, `README.md`) never name another project. Implementation: code in `lib/src/`, extensions in `lib/src/extensions/` one per file, fields then constructor then methods, no new dependency unless the task names it. Tests: `lib/src/<path>.dart` is tested in `test/<path>_test.dart`, hand-written fakes, no mocking package. Review checks: a file in the wrong folder, a shipped file naming another project or a fixed build command, a mocking package, changed logic without a test.
- New here: symlink `.claude/skills/skill-dispatcher` -> `../../.agents/skills/skill-dispatcher`.
- Consumers: the engine (stage brief), PD-02-01 (planner links to the roles and runner rules), PD-03-01 (install copies these folders).

## Behavior

- Every role reads exactly the epic reading order, and nothing names a file that does not exist in this repo or in a consumer after install.
- The skill, roles and runner rules never name another project or a project build or test command (`fvm`, `flutter`); project commands come from the config or the project overrides. `git`, `gh` and the read-only shell commands are fine.

## Decisions

- Generic runner rules are shipped and replaced on install; project rules live in the project-owned overrides file, so an update never wipes them.
- The format rule ships with the dispatcher because the roles need it.

## Out of scope

- Planner skill (PD-02-01), install (PD-03-01), starters in `templates/` (PD-03-01).
- Changing the engine.

## Files and tests

- Create the files listed in Contract and the symlink.
- New `test/skills_test.dart`, group `dispatcher` (port of the source `ai_setup_test.dart` group): each `Role` has `roles/<name>.md` with matching `name` and an `access` of `read-only` or `edit`; no role file without a `Role`; reviewer is `read-only` and contains `Never edit`; `SKILL.md` names every `displayName` of `RoleModels.table`; every `.agents/...md` path mentioned in the dispatcher files exists; inside each role's `## Read first` section, the first occurrences of `planner_dispatcher.yaml`, `runner-rules.md`, `.agents/planner-dispatcher/project-overrides.md` and `project-tasks-format.md` come in that order; `runner-rules.md` and this repo's overrides have exactly the four headings; no file under `.agents/skills/skill-dispatcher/` and not `.agents/rules/project-tasks-format.md` matches `(?i)\bfvm\b|\bflutter (analyze|test|pub|run|gen-l10n|build)\b` (prose such as "Flutter or Dart projects" passes); the path check covers only `.agents/skills/skill-dispatcher/**`; this repo's `planner_dispatcher.yaml` loads with `DispatcherConfig.load()` and each of its `rules` files exists (none today, since `rules: []`; the case guards later additions). Put small helpers (front matter value, file list) at the bottom of the test file; PD-02-01 reuses them.
- Run: `fvm dart format --output=none --set-exit-if-changed lib bin test`, `fvm dart analyze`, `fvm dart test`; then, once merged, `fvm dart run planner_dispatcher:dispatcher next` in this repo.

## Acceptance

- [ ] When a runner stage starts, then its role reads the config's rules, `runner-rules.md`, the project overrides and the format rule, in that order, and the sections of its stage. Check: `test/skills_test.dart`.
- [ ] When a dispatcher file is read, then it names no `fvm` or `flutter` command. Check: `test/skills_test.dart`.
- [ ] When the skill lists stage models, then they match the default table. Check: `test/skills_test.dart`.
- [ ] When this repo's config is loaded, then it is valid and every listed rule file exists. Check: `test/skills_test.dart`.
- [ ] When `fvm dart run planner_dispatcher:dispatcher next` runs in this repo after merge, then it exits 0 and prints JSON with `next`, `alsoReady` and `waiting`, and `next.id` is `PD-02-01`. Check: the command.
- [ ] When a shipped dispatcher file contains the word start `sport`, `agent_check` or a `/Users/` path, then a test fails. Check: `test/independence_test.dart`.
