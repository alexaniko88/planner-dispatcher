---
id: PD-03-02
status: ready
type: feat
complexity: low
depends-on: [PD-03-01]
touches:
  - .github/workflows/release.yml
  - tool/release_tag.dart
  - lib/src/release_tag.dart
  - test/release_tag_test.dart
  - test/readme_test.dart
  - README.md
  - pubspec.yaml
skills: []
---

# Release action and README

Story: [Distribution](../index.md)

Epic: [Standalone planner and dispatcher](../../../index.md)

## Goal

Tag a release automatically when a version bump merges to `main`, document how a project uses the library, and set the version to `0.1.0` so this task's merge creates the first release.

## Context

- Commands, config schema and consumer paths are in the [epic](../../../index.md#shared-contracts); the starter config is `templates/planner_dispatcher.yaml` (PD-03-01).
- Existing CI: `.github/workflows/ci.yml` (checkout `actions/checkout@v7.0.1`, `dart-lang/setup-dart@v1.7.1` with SDK `3.13.5`).
- Current `pubspec.yaml` version is `0.0.0`.

## Contract

- New here: `lib/src/release_tag.dart` with `String releaseTag(String pubspecText)`: takes the first unindented line matching `version:` (CRLF allowed), strips a trailing `#` comment, whitespace and one pair of single or double quotes; returns `v<value>` when the value matches `^\d+\.\d+\.\d+$`; throws `FormatException` otherwise (missing line, pre-release or build suffix, empty file).
- New here: `tool/release_tag.dart`: reads `pubspec.yaml`, prints `releaseTag(...)`, exits 1 with the error on `FormatException`.
- New here: `.github/workflows/release.yml`: on `push` to `main`; `permissions: contents: write`; checkout, setup-dart (same versions as CI), `dart pub get`, `tag=$(dart run tool/release_tag.dart)`; if `git ls-remote --tags origin "refs/tags/$tag"` prints anything, stop with a note; otherwise `gh release create "$tag" --target "$GITHUB_SHA" --title "$tag" --generate-notes` with `GH_TOKEN: ${{ github.token }}`.
- Changed: `pubspec.yaml` `version: 0.1.0`.
- Changed: `README.md` (no other project's name): what the planner and dispatcher do; requirements (Dart SDK 3.10 or newer, optionally through fvm; `git`; `gh` signed in; at least one of `claude`, `codex`, `agy`); setup (the `dev_dependencies` git snippet with `url: https://github.com/alexaniko88/planner-dispatcher.git` and `ref: v0.1.0`, then `<dart> pub get`, then `<dart> run planner_dispatcher:install`, then fill `planner_dispatcher.yaml` and the two project files, then commit); every top-level config key in backticks with one line (required or optional, default when optional, the `models` entry shape), and that a bad config exits 78; every command (`planner_dispatcher:dispatcher next|models|launch|status`, `planner_dispatcher:sync`, `planner_dispatcher:install`); updating (change `ref`, `pub get`, run install, review `starter changed` lines); how to release (bump `version` in a PR).

## Behavior

- A push to `main` with a new version creates exactly one tag and release; a push with an already tagged version does nothing.

## Decisions

- Tags come from the merged version bump, created by the action, not by hand.

## Out of scope

- Publishing to pub.dev; changelog files.

## Files and tests

- Create: `lib/src/release_tag.dart`, `tool/release_tag.dart`, `.github/workflows/release.yml`; change `README.md`, `pubspec.yaml`.
- New `test/release_tag_test.dart`: `version: 0.1.0` gives `v0.1.0`; quoted, commented and CRLF forms work; an indented `version:` is ignored; a pre-release suffix, a build suffix, a missing line and an empty file throw `FormatException`; the real `pubspec.yaml` gives a tag matching `^v\d+\.\d+\.\d+$` (not pinned, so later bumps keep it green).
- New `test/readme_test.dart`: `README.md` contains the full forms `planner_dispatcher:dispatcher next`, `planner_dispatcher:dispatcher models`, `planner_dispatcher:dispatcher launch`, `planner_dispatcher:dispatcher status`, `planner_dispatcher:sync`, `planner_dispatcher:install`; each top-level key of `templates/planner_dispatcher.yaml` (read with the `yaml` package) in backticks; `ref: v`.
- The workflow itself is not run by tests; its logic beyond the tag script is the `ls-remote` guard.
- Run: `fvm dart format --output=none --set-exit-if-changed lib bin test tool`, `fvm dart analyze`, `fvm dart test`.

## Acceptance

- [ ] When `pubspec.yaml` has `version: X.Y.Z`, then the tag script prints `vX.Y.Z`; otherwise it fails. Check: `test/release_tag_test.dart`.
- [ ] When a version bump merges to `main`, then the action creates tag and release `v<version>` once, and skips an existing tag. Check: `.github/workflows/release.yml` (review) and `test/release_tag_test.dart`.
- [ ] When someone reads the README, then it explains adding the dependency, install, config, every command and updating. Check: `test/readme_test.dart`.
- [ ] When this task is done, then `pubspec.yaml` has version `0.1.0`. Check: `fvm dart run tool/release_tag.dart` prints `v0.1.0`.
