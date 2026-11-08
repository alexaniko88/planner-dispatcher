# Notes: PD-01-01

Run by hand in a normal Claude Code session (Opus 5.5), as the task says.

## Decisions

- The engine was copied file for file into `lib/src/` and `bin/`, then every project value was replaced by a `DispatcherConfig` field or a constructor parameter, with the signatures the task fixes.
- `MasterSync` keeps its name (the contract keeps class names); it now takes `baseBranch`. `master` and `main` stay protected next to the base branch, and the push guard refuses all three.
- A setup or check command list is run with a list pattern (`[program, ...args]`); the config loader guarantees no command is empty.
- The `models` command and its stale warnings use the effective models (flag, then config, then the default table).
- `bin/dispatcher.dart` prints usage and exits 64 for no or an unknown command before reading the config; every other path loads the config first and exits 78 on `ConfigError`.
- The CI job is renamed `analyze-and-test` now that it also runs `dart test`.

## Evidence

- Config errors exit 78 with the one-line text: `test/config_test.dart` (20 cases) and `test/bin_test.dart` (`dispatcher next` and `sync` without a config).
- The engine uses the config values: the ported tests in `test/` pass with a test config, plus new cases for a `main` base branch run, project private patterns, refusing a push to the base branch, no golden folder, no allowed commands and `wip` rejected.
- Models: `test/role_models_test.dart` (default table, one-stage override, flag beats config).
- Independence: `test/independence_test.dart` (shipped files have no `\bsport`, `agent_check` or home path; `lib/` and `bin/` have no `fvm`, `flutter`, `test/snapshots` or `origin/master`).
- CI: `.github/workflows/ci.yml` runs `dart analyze` and `dart test`.
- Local run: `fvm dart format --output=none --set-exit-if-changed lib bin test` exits 0, `fvm dart analyze` finds no issues, `fvm dart test` passes 120 tests.
- `fvm dart run planner_dispatcher:dispatcher next` in this repo reads its own `planner_dispatcher.yaml` and prints the task JSON.
