# STORY 3: Distribution

Epic: [Standalone planner and dispatcher](../../index.md)

## User outcome

As the maintainer of a Flutter or Dart project, I want to add the library with one dependency and one command, update it safely, and pin a released version, so that using it needs no manual copying.

## Scope

The install command with its starters, the release action that tags versions, and the README that explains use. The first release `v0.1.0` comes from PD-03-02's merge.

## Acceptance criteria

- Install creates everything a project needs, can run again safely, and never overwrites project-owned files.
- A merged version bump creates its tag once.
- The README documents every command and config key.

## Tasks

1. [PD-03-01: Install command](01-install-command/index.md).
2. [PD-03-02: Release action and README](02-release-and-readme/index.md).

## Dependencies and open decisions

None open. PD-03-01 depends on PD-02-01 (all shipped files exist). PD-03-02 depends on PD-03-01.

## Shared contracts

Consumer paths and the config schema are in the [epic](../../index.md#shared-contracts). Starter headings for the project overrides and the planner notes are in the epic (role reading order and [planner notes](../../index.md#planner-notes)).

## Requirement coverage

| Requirement | Tasks | Checks |
| --- | --- | --- |
| R3 | PD-03-01 (templates), PD-03-02 (README) | `test/independence_test.dart` |
| R6 | PD-03-01 | `test/install/installer_test.dart` |
| R7 | PD-03-02 | `test/release_tag_test.dart`, `test/readme_test.dart` |
