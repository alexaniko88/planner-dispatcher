---
abbr: PD
---

# EPIC: Standalone planner and dispatcher

## Goal

Give any Flutter or Dart project the planner and the dispatcher as one independent library: add a git `dev_dependency`, run one install command, fill one config file. The library does not depend on any other project and names no other project's files, rules, theme or paths in the files it ships.

The code starts as a copy of the planner and dispatcher that live today in the public Sport Timer repo (`https://github.com/alexaniko88/sport_timer`, `tool/dispatcher.dart`, `tool/dispatcher/`, `tool/sync_master.dart`, `test/tool/dispatcher/`, `.agents/skills/skill-planner/`, `.agents/skills/skill-dispatcher/`, `.agents/rules/project-tasks-format.md`). Tasks copy from there and make the copy generic in the same change. Read the source at its commit on `master`; it does not change while this epic runs.

## Agreed behavior and boundaries

- Flutter and Dart projects only. Other languages are out of scope for this version.
- The engine stays in Dart (no rewrite). Consumers need the Dart SDK.
- A consumer adds the library as a git `dev_dependency` pinned to a release tag, then runs `<dart> run planner_dispatcher:install`. `<dart>` is the configured Dart command (`fvm dart` or `dart`).
- Install copies the library-owned files byte for byte (nothing is filled in). Project facts come from `planner_dispatcher.yaml` and the project-owned files, which install creates once and never overwrites.
- Each AI tool keeps today's fixed stage models as defaults. A project can override any stage in its config.
- Releases: a GitHub Action creates tag `v<version>` when a version bump in `pubspec.yaml` merges to `main`.
- Independence: the files the library ships (`lib/`, `bin/`, `.agents/`, `templates/`, `README.md`) never mention the source project. Task files under `project-tasks/` may name the source paths they copy from.
- No secret, company email domain or local `/Users/` path is ever committed.

## Shared contracts

Paths and names below are planned (new) unless marked existing. Every task follows them; a needed change returns to planning.

### Repository layout

```text
bin/dispatcher.dart        next | models | launch | status        (PD-01-01)
bin/sync.dart              sync the base branch, delete merged    (PD-01-01)
bin/install.dart           install into a consumer project        (PD-03-01)
lib/src/**                 the engine; lib/src/extensions/ for extensions (PD-01-01)
lib/src/install/**         install logic                          (PD-03-01)
test/**                    mirrors lib/src and bin
.agents/skills/skill-dispatcher/**      shipped, library-owned    (PD-01-02)
.agents/skills/skill-planner/**         shipped, library-owned    (PD-02-01)
.agents/rules/project-tasks-format.md   shipped, library-owned    (PD-01-02)
templates/planner_dispatcher.yaml       starter config            (PD-03-01)
templates/project-overrides.md          starter runner rules      (PD-03-01)
templates/planner-notes.md              starter planner notes     (PD-03-01)
planner_dispatcher.yaml                 this repo's own config    (PD-01-01)
.agents/planner-dispatcher/project-overrides.md  this repo's own runner rules (PD-01-02)
.agents/planner-dispatcher/planner-notes.md      this repo's own planner notes (PD-02-01)
.claude/skills/skill-dispatcher -> ../../.agents/skills/skill-dispatcher  (PD-01-02)
.claude/skills/skill-planner -> ../../.agents/skills/skill-planner        (PD-02-01)
.github/workflows/ci.yml       existing; PD-01-01 adds `dart test`
.github/workflows/release.yml  (PD-03-02)
```

This repo uses the same shipped `.agents/` files it installs into consumers, so it runs its own backlog with them.

### Paths in a consumer project

- Library-owned, written by install, replaced on every install: `.agents/skills/skill-dispatcher/`, `.agents/skills/skill-planner/`, `.agents/rules/project-tasks-format.md`, and the two `.claude/skills/` symlinks above.
- Install bookkeeping, written only by install: `.agents/planner-dispatcher/.starters/` (the last seen copy of each starter template).
- Project-owned, created by install only when missing: `planner_dispatcher.yaml` (project root), `.agents/planner-dispatcher/project-overrides.md`, `.agents/planner-dispatcher/planner-notes.md`.
- Tasks always live in `project-tasks/` (not configurable).
- Every command runs from the project root and reads `planner_dispatcher.yaml` there.

### Config file `planner_dispatcher.yaml` (schema 1)

```yaml
dart: fvm dart                 # required. The command that runs Dart and the library commands.
base_branch: master            # required. Task clones start from origin/<base_branch>; PRs target it; never pushed to.
run_folder: my-app-runs        # required. Runs live in <system temp>/<run_folder>/<task id>.
setup:                         # required, may be empty. Run in order in a fresh clone; a failure ends the run as failed.
  - fvm install --skip-pub-get
  - fvm flutter pub get
  - fvm flutter analyze --no-pub
check:                         # required, at least one. Run in order after implementation; all must exit 0.
  - fvm dart tool/agent_check.dart --skip-build
allowed_commands:              # optional. Extra command prefixes the Claude implementer and tests stages may run.
  - fvm dart format
  - fvm flutter test
rules:                         # required, may be empty. Project files every role and the planner read first.
  - CLAUDE.md
goldens_dir: test/snapshots/goldens   # optional. Changed .png files there get before/after images in the PR.
commit_types: [feat, fix, refactor, chore, docs, style, perf, test, build]   # required.
git_email_suffix: "@users.noreply.github.com"   # optional. When set, launch refuses another git email.
private_patterns:              # optional. Label -> regex, added to the built-in scan.
  a company email: "@example\\.com"
models:                        # optional. Per tool and stage: model, effort, name (used in Co-Authored-By).
  claude:
    reviewer: {model: opus, effort: high, name: Opus 5.5}
```

- Commands in `setup`, `check` and `allowed_commands` are split on spaces into a program and arguments (no shell, no quoting).
- Validation stops every command (except a no-argument usage call) with exit code 78 and one line `planner_dispatcher.yaml: <key>: <problem>`. Errors: file not found (key `(file)`, problem `not found`); invalid YAML (key `(file)`, problem `invalid YAML: <parser message>`); unknown top-level key (`unknown key`); missing required key (`missing`); wrong type (`must be <type>`); empty `dart`, `base_branch`, `check` or `commit_types`; `base_branch` with a space; `run_folder` not matching `^[A-Za-z0-9._-]+$`; a `commit_types` entry not matching `^[a-z]+$`; a `private_patterns` value that is not a valid regex; under `models` an unknown tool (`claude`, `codex`, `antigravity`), an unknown stage (`implementer`, `tests`, `reviewer`), or a stage entry without all of `model`, `effort`, `name` or with another field.
- Optional keys left out: `allowed_commands` empty, `goldens_dir` unset (no golden section in the PR and no golden diff), `git_email_suffix` unset (any email), `private_patterns` empty, `models` empty.
- Built-in private-data scan (always on): a local home path (`/Users/<letter>`), a private key header, a GitHub token, an `sk-` secret key. `private_patterns` add to it.
- Commit subject rule for the commit lines the stages report: `<type>: <description>`, `type` from `commit_types`, description starting with a lowercase letter, digit or backtick, no final period, at most 100 characters. The script's own `docs: close task <id>` and `wip: <id> stopped` commits are not checked against it.

### Default stage models (today's table)

| Tool | Implementer | Tests | Reviewer |
| --- | --- | --- | --- |
| Claude | `sonnet`, medium, "Sonnet 5.5" | `sonnet`, medium, "Sonnet 5.5" | `opus`, medium, "Opus 5.5" |
| Codex | `gpt-6.1-terra`, medium, "GPT-6.1 Terra" | same | `gpt-6.1-sol`, medium, "GPT-6.1 Sol" |
| Antigravity | `gemini-4-argon-medium`, medium, "Gemini 4 Argon" | same | `gemini-4-argon-high`, high, "Gemini 4 Argon" |

Precedence for one stage: `--implementer/--tests/--reviewer` flag, then `models` in the config, then this table.

### Commands

- `<dart> run planner_dispatcher:dispatcher next [--skip=ID,ID]`, `models`, `launch <ID> --tool=claude|codex|antigravity [--implementer=M] [--tests=M] [--reviewer=M] [--allow=P,P]`, `status`. Same JSON output, `RESULT {json}` line and exit codes as the source.
- `<dart> run planner_dispatcher:sync`: the source `sync_master` behavior with `base_branch` in place of `master` (both `master` and `main` stay protected from deletion).
- `<dart> run planner_dispatcher:install` (PD-03-01).
- Usage text names these commands, never `tool/dispatcher.dart`.

### Stage brief and role files

The stage prompt stays `Read .agents/skills/skill-dispatcher/roles/<role>.md and follow it exactly. The task is <path>. ...`. Each role reads, in this order: every file in the config's `rules`, `.agents/skills/skill-dispatcher/references/runner-rules.md` (generic, shipped), `.agents/planner-dispatcher/project-overrides.md` (project-owned), `.agents/rules/project-tasks-format.md`, then the task and its parents, then every skill in the task's `skills:` (`.agents/skills/<name>/SKILL.md`).

Both `runner-rules.md` and the project overrides have the same four sections: `## Common`, `## Implementation`, `## Tests`, `## Review checks`. The implementer reads Common and Implementation of both, the tests role Common and Tests, the reviewer Common and Review checks. The project overrides also name the per-file commands (format, analyze, test one file by literal path).

### Planner notes

`.agents/planner-dispatcher/planner-notes.md` has exactly these sections: `## Branches and pull requests` (branch prefixes, PR title rule, commit subject rule and the type planning commits use, commit attribution rule), `## UI sources` (theme files and tokens, shared widgets, goldens, flow index and mockup frame size, or "No UI"), `## Project skills` (skills a task may list in `skills:`, or "None"), `## Checks` (what the configured `check` covers and what it does not), `## Coverage checks` (extra interview topics this project always needs, or "None").

## Stories

1. [Dispatcher](stories/01-dispatcher/index.md): the generic engine, its commands, and the dispatcher skill and roles.
2. [Planner](stories/02-planner/index.md): the generic planner skill.
3. [Distribution](stories/03-distribution/index.md): the install command, the release action and the README.

## Delivery order

1. PD-01-01 and then PD-01-02 are **run by hand** in a normal AI session in this repo (the dispatcher cannot run here until both are merged). Open each as a normal PR and review it.
2. After PD-01-02 merges, this repo runs its own backlog: `fvm dart run planner_dispatcher:dispatcher next`. PD-02-01 and PD-03-01 can then run; PD-03-02 comes last, and its merge creates `v0.1.0`.
3. A consumer adopts `v0.1.0` only after that tag exists.

## Requirement coverage

| Requirement | Tasks | Checks |
| --- | --- | --- |
| R1: Engine generic, driven by `planner_dispatcher.yaml` | PD-01-01 | `test/config_test.dart`, ported engine tests |
| R2: Default models with per-project override | PD-01-01, PD-01-02 | `test/role_models_test.dart`, `test/skills_test.dart` |
| R3: Shipped files never mention the source project or private data | PD-01-01 (test), PD-01-02, PD-02-01, PD-03-01, PD-03-02 | `test/independence_test.dart` in every task's `dart test` |
| R4: Dispatcher skill and roles generic; this repo dispatches itself | PD-01-02 | `test/skills_test.dart`, `next` in this repo |
| R5: Planner skill generic | PD-02-01 | `test/skills_test.dart` |
| R6: One-command install, safe re-run, project files never overwritten | PD-03-01 | `test/install/installer_test.dart` |
| R7: Tag on version bump, README usage | PD-03-02 | `test/release_tag_test.dart`, `test/readme_test.dart` |
| R8: CI runs analyze and tests on every PR | PD-01-01 | `.github/workflows/ci.yml` |
