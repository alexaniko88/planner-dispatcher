---
id: PD-01-01
status: done
type: feat
complexity: high
depends-on: []
touches:
  - bin/dispatcher.dart
  - bin/sync.dart
  - lib/src/**
  - test/**
  - planner_dispatcher.yaml
  - pubspec.yaml
  - .github/workflows/ci.yml
  - analysis_options.yaml
skills: []
---

# Generic engine and config

Story: [Dispatcher](../../index.md)

Epic: [Standalone planner and dispatcher](../../../../index.md)

**Run this task by hand** in a normal AI session in this repo (the dispatcher cannot run here yet). Open a normal PR. In that PR, move this task folder to `done/` with `status: done` and a `notes.md`, as the format rule's done rule says (the dispatcher normally does this).

## Goal

Bring the dispatcher engine and its tests into this repo, with every project-specific value read from `planner_dispatcher.yaml`. After this task, `fvm dart run planner_dispatcher:dispatcher next` and `fvm dart run planner_dispatcher:sync` work in any project that has a valid config.

## Context

- Source to copy (public repo `https://github.com/alexaniko88/sport_timer`, branch `master`): `tool/dispatcher.dart`, `tool/dispatcher/**` (including `extensions/`), `tool/sync_master.dart`, `test/tool/dispatcher/**`. The engine uses only `dart:io` and `dart:convert`.
- Values hard-coded in the source that become config (file in the source):
  - base branch `master` (every `master` and `origin/master` in the engine): `dispatcher.dart` (`git fetch origin master`, `origin/master` ref, the "not a ready task on origin/master" text), `git_publisher.dart` (`baseSha`, `addedLinesDiff`, `changedGoldens`, `openPullRequest`), `run_workspace.dart` (clone), `launch_pipeline.dart` ("Review the diff of this branch against master."), `master_sync.dart` (`_trunk`, messages);
  - setup `fvm install`, `fvm flutter pub get`, `fvm flutter analyze --no-pub`: `run_workspace.dart` `_setUpFlutter`;
  - check `fvm dart tool/agent_check.dart --skip-build` and its PR text: `launch_pipeline.dart` `_check`, `_fixChecks`;
  - allowed Claude commands `_checkShell`: `tool_command.dart`;
  - goldens folder `test/snapshots/goldens`: `git_publisher.dart` `changedGoldens`;
  - run folder `sport-timer-runs`: `run_workspace.dart` `baseDirectory`;
  - noreply email check: `run_workspace.dart` `prepare`;
  - commit types and a company email pattern: `git_publisher.dart` `CommitMessage`, `DiffScanner`;
  - fixed models: `role_models.dart` `RoleModels.table`;
  - usage text `fvm dart tool/dispatcher.dart`: `dispatcher.dart`.
- The shared contracts (layout, config schema 1, default models, commands, role reading order) are in the [epic](../../../../index.md#shared-contracts).

## Contract

- New here: `lib/src/config.dart` with `class DispatcherConfig`, fields `String dart`, `String baseBranch`, `String runFolder`, `List<List<String>> setup`, `List<List<String>> check`, `List<List<String>> allowedCommands` (each inner list is program plus arguments), `List<String> rules`, `String? goldensDir`, `List<String> commitTypes`, `String? gitEmailSuffix`, `Map<String, RegExp> privatePatterns`, `Map<Tool, Map<Role, RoleModel>> models` (`effort`, `model` and `name` are non-empty strings; `effort` is not limited to a list), `static DispatcherConfig load({String path = 'planner_dispatcher.yaml'})` and `static DispatcherConfig parse(String yamlText)`. Both throw `ConfigError` (new here, `implements Exception`, with `key` and `problem`, `toString()` = `planner_dispatcher.yaml: <key>: <problem>`).
- New dependency: `yaml` under `dependencies:` (it is used by `lib/`), exact version: the newest 3.x that resolves.
- Formatting: add the source's formatter block to `analysis_options.yaml` (`formatter: page_width: 120, trailing_commas: preserve`), so the copied code keeps its layout.
- New signatures (all other source signatures stay): `CommitMessage.problem(String subject, {required List<String> types})`; `DiffScanner.scan(String diff, {Map<String, RegExp> extra = const {}})`; `ToolCommand.build(..., List<List<String>> allowedCommands = const [])`; `GitPublisher({required workspace, required run, required String baseBranch, String? goldensDir})`; `RunWorkspace.prepare(..., required String baseBranch, required List<List<String>> setup, String? emailSuffix, bool skipSetup = false)`; `RunWorkspace.baseDirectory(String runFolder)`; `MasterSync({required workspace, required run, required String baseBranch})`; `RoleModels.of({required tool, required role, Map<Tool, Map<Role, RoleModel>> configModels = const {}, Map<Role, String> overrides = const {}})`; `ModelCatalog.staleModels({required tool, required models, Map<Tool, Map<Role, RoleModel>> configModels = const {}})`; `LaunchPipeline` gets `required DispatcherConfig config` in place of `skipFlutterSetup` (plus `bool skipSetup = false` for tests). The `models` command prints the effective models (config layer applied).
- Moved and made generic: every class of the source keeps its name and behavior and lives in `lib/src/` (extensions in `lib/src/extensions/`), with its hard-coded value replaced by a constructor parameter or a `DispatcherConfig` field. `RoleModels.of` takes the config models as a middle layer (flag > config > default table). `RunWorkspace.baseDirectory` takes the run folder. Setup runs the `setup` commands in order instead of `_setUpFlutter`; a failing command throws (with `<command>` the full command line as written in the config) `StateError('"<command>" failed in a fresh clone of <base_branch>; fix <base_branch> before running tasks.\n<last 20 lines of stdout and stderr>')`. `skipFlutterSetup` becomes `skipSetup`. The check stage runs every `check` command in order and stops at the first failure (that output goes to the fix brief); after the one fix, all `check` commands run again from the first. The PR text is `All checks passed (` + each command in its own backticks, joined by `, ` + `).`, and `All checks passed (...), after one fix.` as in the source. `allowed_commands` replaces the source `_checkShell` list entirely: each entry `<command>` becomes `Bash(<command>:*)` for Claude; the read-only and file shell lists stay. `changedGoldens` returns an empty list without calling git when `goldens_dir` is unset. `CommitMessage.problem` checks report commit lines against `commit_types` (no `wip`; the ported case that accepts `wip:` now expects a rejection). `DiffScanner` keeps the four generic built-in rules and adds `private_patterns`; the company email rule is not copied. The engine does not use the `dart` or `rules` values (the skills and roles read them); usage text always shows the literal placeholder: `Usage: <dart> run planner_dispatcher:dispatcher next | models | launch <ID> --tool=<tool> | status` (and `<dart> run planner_dispatcher:sync` for sync). The email check message becomes `The git email "<email>" does not end with "<suffix>" (git_email_suffix).` The `models` command keeps the source output format; stale warnings check the effective models. Every comment and string in `lib/` and `bin/` must pass the independence test, so reword source comments that say `master`, `origin/master`, `fvm` or `flutter` ("the base branch", "the setup commands"). `MasterSync` takes the base branch; both `master` and `main` stay protected. The roles path in `StageRunner.prompt` stays `.agents/skills/skill-dispatcher/roles/<role>.md`.
- New here: `bin/dispatcher.dart` (the source `main`: with no arguments or an unknown command it prints usage and exits 64 without reading the config; otherwise it loads the config first, and on `ConfigError` it prints the error to stderr and exits 78) and `bin/sync.dart` (the source `sync_master.dart`, same config handling).
- New here: `planner_dispatcher.yaml` for this repo: `dart: fvm dart`, `base_branch: main`, `run_folder: planner-dispatcher-runs`, `setup: [fvm install --skip-pub-get, fvm dart pub get]`, `check: [fvm dart format --output=none --set-exit-if-changed lib bin test, fvm dart analyze, fvm dart test]`, `allowed_commands: [fvm dart format, fvm dart analyze, fvm dart test, fvm dart pub get]`, `rules: []` (this repo's runner rules are the project overrides, which every role reads anyway; the loader never checks that rule files exist), `commit_types: [feat, fix, refactor, chore, docs, style, perf, test, build]`, `git_email_suffix: "@users.noreply.github.com"`.
- Consumers: PD-01-02 (role files the brief points to), PD-03-01 (install reuses `ConfigError` style), PD-03-02 (README documents the commands).

## Behavior

- Everything the source does stays the same when the config holds the source's values (the Sport Timer values listed in Context).
- No other project's name, path or private pattern remains in `lib/` or `bin/`.
- Commands read the config from the current directory before any git or tool call (after the usage check).

## Decisions

- Keep Dart and the source behavior; only remove hard-coded project values (no rewrite, no new features).
- Commands are split on spaces without a shell, so a runner cannot inject shell syntax through the config.
- The company email pattern of the source is not copied anywhere; projects add their own `private_patterns`.

## Out of scope

- Role files, skills, install, release action, README usage (later tasks).
- Changing JSON output, exit codes or the stage pipeline order.

## Files and tests

- Create: `bin/dispatcher.dart`, `bin/sync.dart`, `lib/src/*.dart`, `lib/src/extensions/*.dart`, `planner_dispatcher.yaml`.
- Tests: port every source test file to the mirrored path under `test/` (for example `test/tool/dispatcher/launch_pipeline_test.dart` becomes `test/launch_pipeline_test.dart`, `test/tool/dispatcher/extensions/extensions_test.dart` becomes `test/extensions/extensions_test.dart`), passing config values where the source used constants. Keep every existing case; fixtures keep `master` as the configured base branch, and one launch test uses `main`. The baseline-analyze case becomes "a failing setup command throws with its output and cleans up".
- Nested error keys use dots and list indexes: `check[1]`, `models.claude.reviewer.effort`. A non-string list entry gives `must be a string`; an empty or whitespace-only command gives `must not be empty`. Commands are trimmed and split on runs of whitespace.
- New `test/config_test.dart`: valid full config; minimal valid config (optional keys defaulted); file not found; invalid YAML; unknown top-level key; each required key missing; wrong type; each listed empty or malformed value; unknown tool, unknown stage, incomplete or extra field under `models`; `private_patterns` with an invalid regex; command splitting; `toString` format.
- New `test/bin_test.dart`: `dispatcher` with no arguments exits 64 without a config; `dispatcher next` and `sync` in a temporary folder without a config exit 78 with the one-line error. Run with `Process.run(Platform.resolvedExecutable, ['--packages=<absolute path of this repo's .dart_tool/package_config.json>', <absolute path of bin/<name>.dart>, ...], workingDirectory: <temp folder>)` (the VM runs the script directly, no `dart run` and no implicit `pub get`), so CI needs no fvm.
- New `test/role_models_test.dart`: default table equals the epic table; config override replaces one stage only; flag beats config.
- New `test/independence_test.dart`: walks `lib/`, `bin/`, `.agents/`, `templates/` (each only when it exists) and `README.md`; fails when a file matches `\bsport` (case-insensitive, so "transport" passes), `agent_check` or `/Users/`. A second case walks only `lib/` and `bin/` and fails on `fvm`, `flutter`, `test/snapshots` or `origin/master` (case-insensitive), so no project value stays hard-coded.
- Change `.github/workflows/ci.yml`: add a step `dart test` after `dart analyze`.
- Change `pubspec.yaml`: add `yaml`.
- Run: `fvm dart format --output=none --set-exit-if-changed lib bin test`, `fvm dart analyze`, `fvm dart test`.

## Acceptance

- [ ] When `planner_dispatcher.yaml` is missing or a key is wrong, then `dispatcher` and `sync` exit 78 and print `planner_dispatcher.yaml: <key>: <problem>`. Check: `test/config_test.dart`, `test/bin_test.dart`.
- [ ] When the config gives base branch, setup, check, allowed commands, goldens folder, commit types, private patterns, email suffix, run folder and models, then the engine uses them and no project value is hard-coded. Check: ported tests in `fvm dart test` and the second case of `test/independence_test.dart`.
- [ ] When no model override is set, then each stage uses the default table; when one is set, only that stage changes; a flag beats the config. Check: `test/role_models_test.dart`.
- [ ] When a shipped file contains the word start `sport`, `agent_check` or `/Users/`, or `lib/`/`bin/` contains `fvm`, `flutter`, `test/snapshots` or `origin/master`, then the independence test fails. Check: `test/independence_test.dart`.
- [ ] When a PR is opened, then CI runs `dart analyze` and `dart test` and both pass. Check: `.github/workflows/ci.yml` and `fvm dart test`.
