# STORY 2: Planner

Epic: [Standalone planner and dispatcher](../../index.md)

## User outcome

As the maintainer of a Flutter or Dart project, I want the planner skill to read my project's facts from my own files, so that it plans tasks for my project without naming another one.

## Scope

The planner skill, its references and its two roles, generic; the planner notes format; this repo's own planner notes. Install of these files is PD-03-01.

## Acceptance criteria

- The planner takes project facts only from `planner_dispatcher.yaml`, the config's `rules` files and `.agents/planner-dispatcher/planner-notes.md`.
- Every link in the planner files resolves.

## Tasks

1. [PD-02-01: Generic planner skill](01-generic-planner-skill/index.md).

## Dependencies and open decisions

None open. Depends on PD-01-02 (runner rules, roles, format rule, `test/skills_test.dart`).

## Shared contracts

Consumer paths and the role reading order are in the [epic](../../index.md#shared-contracts). The planner notes headings are fixed in the [epic](../../index.md#planner-notes) and reused by the PD-03-01 starter.

## Requirement coverage

| Requirement | Tasks | Checks |
| --- | --- | --- |
| R3 | PD-02-01 | `test/independence_test.dart` |
| R5 | PD-02-01 | `test/skills_test.dart` |
