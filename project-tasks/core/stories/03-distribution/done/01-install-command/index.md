---
id: PD-03-01
status: done
type: feat
complexity: medium
depends-on: [PD-02-01]
touches:
  - bin/install.dart
  - lib/src/install/**
  - test/install/install_bin_test.dart
  - templates/**
  - test/install/**
skills: []
---

# Install command

Story: [Distribution](../../index.md)

Epic: [Standalone planner and dispatcher](../../../../index.md)

## Goal

Add `<dart> run planner_dispatcher:install`, which copies the library-owned files into a consumer project, creates the `.claude/skills` links and creates the project-owned starter files once. It can run again after a version bump and never touches the project's own files.

## Context

- Consumer paths (library-owned and project-owned) are in the [epic](../../../index.md#shared-contracts).
- Shipped files exist after PD-02-01: `.agents/skills/skill-dispatcher/`, `.agents/skills/skill-planner/`, `.agents/rules/project-tasks-format.md`.
- Config schema 1 and `DispatcherConfig.parse` (for checking the starter) from PD-01-01 in `lib/src/config.dart`.
- Starter headings: overrides `## Common`, `## Implementation`, `## Tests`, `## Review checks`; planner notes as in the [epic](../../../index.md#planner-notes) (five sections).

## Contract

- New here: `lib/src/install/installer.dart`: `class Installer` with fields `projectRoot` and `packageRoot` (constructor parameters) and `InstallReport install()`. Paths in the report are project-relative, `/`-separated, with no trailing slash and no `./`. `class InstallReport` lists `written` (one entry per library-owned path: the two skill folders, the format rule, plus each link path created), `created`, `kept`, `starterChanged` (project-relative paths; a project file with a changed starter is only in `starterChanged`, not in `kept`), and `List<String> lines()` returning the output lines in the order below. `class InstallError implements Exception` with a message. All three classes live in `installer.dart`.
- New here: `bin/install.dart` (thin: no logic beyond what follows): finds the package root with `Isolate.resolvePackageUri(Uri.parse('package:planner_dispatcher/'))` (the parent of the resolved `lib/`; when it returns null, exit 1 with `Cannot find the planner_dispatcher package.`), uses the current directory as project root, prints `report.lines()` where the lines are, in this order, each group sorted by path: `wrote <path>`, `created <path>`, `kept <path>`, `starter changed: <path>`; exits 0. On `InstallError` or any other exception it prints the message to stderr and exits 1; with no `pubspec.yaml` in the current directory exits 64 with `Run install from the project root (no pubspec.yaml here).`
- New here: `templates/planner_dispatcher.yaml` (a valid schema-1 file for a Flutter app using fvm, with a comment per key: `dart: fvm dart`, `base_branch: main`, `run_folder: planner-dispatcher-runs`, setup `fvm install --skip-pub-get` and `fvm flutter pub get`, check `fvm flutter analyze --no-pub` and `fvm flutter test`, `allowed_commands` `fvm dart format`, `fvm flutter analyze`, `fvm flutter test`, `fvm flutter pub get`, `rules: [CLAUDE.md]`, `commit_types` the nine epic types; `goldens_dir`, `git_email_suffix`, `private_patterns` and a `models` example present but commented out), `templates/project-overrides.md` (the four headings, each with a one-line hint; `## Common` also prefills the Flutter per-file commands `fvm dart format <path>`, `fvm flutter analyze --no-pub <path>`, `fvm flutter test <path>`) and `templates/planner-notes.md` (the five headings, each with a one-line hint).

## Behavior

1. Before writing anything, fail with `InstallError` and change nothing when:
   - `.claude/skills/skill-dispatcher` or `.claude/skills/skill-planner` exists and is not a symlink whose target text is exactly `../../.agents/skills/<name>` (a correct but dangling link counts as correct);
   - the project root is the package root (`Refusing to install into the package itself.`);
   - `.claude`, `.claude/skills`, `.agents`, `.agents/skills`, `.agents/rules` or `.agents/planner-dispatcher` exists and is not a folder (`<path> must be a folder`);
   - a shipped path is missing from the package root (`package is incomplete: <path>`); shipped paths are the three library-owned paths and the three files in `templates/`;
   - a shipped folder contains a symlink (`shipped files must not contain links: <path>`).
2. Delete any `*.install-tmp` file or folder left by an earlier failed run at the library-owned paths.
3. Each library-owned folder is copied to `<path>.install-tmp`, then the old folder is deleted and the temp folder renamed; each library-owned file is written to `<path>.install-tmp` and renamed. Files are copied byte for byte (contents only; permissions are not copied); files no longer shipped disappear. Whatever was at a library-owned path before (folder, file or link) is replaced. Reported as `written`.
4. Create missing `.claude/skills/` symlinks with relative targets, creating `.claude/skills/` when missing. Reported as `written` when created; an existing correct link is not reported.
5. For each project-owned file: create it from its template when missing (`created`), otherwise leave it as it is (`kept`).
6. Keep the last seen template of each starter at `.agents/planner-dispatcher/.starters/<template file name>` (install bookkeeping, not reported, written with temp-then-rename). When that copy is missing, write it. When it exists and differs from the current template, report the project file as `starterChanged` and replace the copy with the current template (the project's git diff of `.starters/` shows what changed). A project file created in this run is never `starterChanged`; when a deleted project file is created again, its `.starters/` copy is replaced silently.
7. Never touch any other file (no `pubspec.yaml`, `.gitignore` or tasks).

## Decisions

- Byte-for-byte copies, no filling in: the skills read project values from the config at run time.
- Starter changes are reported, never merged into the project's files.

## Out of scope

- Editing `pubspec.yaml` or creating tasks.
- Removing a previous non-library copy of the skills in a consumer (the consumer's migration does that).

## Files and tests

- Create: `bin/install.dart`, `lib/src/install/installer.dart`, `templates/planner_dispatcher.yaml`, `templates/project-overrides.md`, `templates/planner-notes.md`.
- New `test/install/installer_test.dart`, using a temporary fixture project (a folder with a `pubspec.yaml`) and this repo's root as package root: fresh install creates every library-owned path, both symlinks and the three project files; files equal the package files byte for byte; second run reports library files `written` and project files `kept` and leaves an edited project file unchanged; a removed shipped file disappears on re-run (use a temporary package root holding copies of only `.agents/skills/skill-dispatcher/`, `.agents/skills/skill-planner/`, `.agents/rules/project-tasks-format.md` and `templates/`); a package root without `templates/planner-notes.md` raises `InstallError`; installing with project root equal to package root raises `InstallError`; `lines()` order and sorting; a shipped folder with a link raises `InstallError`; a correct dangling `.claude/skills` link is accepted; a leftover `*.install-tmp` is removed and the install completes; a conflicting real `.claude/skills/skill-planner` folder raises `InstallError` and changes nothing; a changed template is reported as `starterChanged` and the `.starters/` copy is updated; the starter config parses with `DispatcherConfig.parse`.
- `test/independence_test.dart` already walks `templates/`; no change.
- New `test/install/install_bin_test.dart`: `Process.run(Platform.resolvedExecutable, ['--packages=<absolute path of this repo's .dart_tool/package_config.json>', <absolute path of bin/install.dart>], workingDirectory: <temp folder>)` (no `dart run`, so no implicit `pub get`; `Isolate.resolvePackageUri` then resolves through that package config). Without `pubspec.yaml` it exits 64 with the message; with a `pubspec.yaml` containing `name: fixture`, it exits 0 and the first line starts with `wrote `.
- Run: `fvm dart format --output=none --set-exit-if-changed lib bin test`, `fvm dart analyze`, `fvm dart test`.

## Acceptance

- [ ] When install runs in a project with none of the files, then it writes the library-owned files and links and creates the three project files. Check: `test/install/installer_test.dart`.
- [ ] When install runs again, then it rewrites only library-owned files, keeps project files unchanged and reports a changed starter. Check: `test/install/installer_test.dart`.
- [ ] When an earlier install stopped partway, then the next install removes the leftovers and finishes with complete library files. Check: `test/install/installer_test.dart`.
- [ ] When a `.claude/skills` path is a real folder or a wrong link, then install fails and changes nothing. Check: `test/install/installer_test.dart`.
- [ ] When the starter config is parsed, then it is a valid schema-1 config. Check: `test/install/installer_test.dart`.
