# STORY 1: Dispatcher

Epic: [Standalone planner and dispatcher](../../index.md)

## User outcome

As the maintainer of a Flutter or Dart project, I want the dispatcher engine, its skill and its runner roles to work from one config file, so that any project can run planned tasks without copying another project's code.

## Scope

The engine and its commands (`dispatcher`, `sync`), the config loader, the default and overridable stage models, the independence test, CI tests, then the dispatcher skill, the three runner roles, the generic runner rules, the task format rule and this repo's own runner rules. Install and the planner are later stories.

## Acceptance criteria

- Every project-specific value comes from `planner_dispatcher.yaml`, as the [epic contract](../../index.md#shared-contracts) defines.
- A bad or missing config stops every command with exit code 78 and a one-line reason.
- This repo can list and launch its own ready tasks after PD-01-02.

## Tasks

1. [PD-01-01: Generic engine and config](done/01-generic-engine/index.md). Run by hand.
2. [PD-01-02: Dispatcher skill and roles](done/02-dispatcher-skill-and-roles/index.md). Run by hand.

## Dependencies and open decisions

None open. PD-01-02 depends on PD-01-01.

## Shared contracts

The config schema, layout, commands, default models and role reading order are in the [epic](../../index.md#shared-contracts). PD-01-01 provides the engine and config; PD-01-02 provides the files the engine's stage brief points to. The engine has only test callers until PD-01-02 adds the role files; PD-01-02 owns the assembled check (`next` in this repo).

## Requirement coverage

| Requirement | Tasks | Checks |
| --- | --- | --- |
| R1 | PD-01-01 | `test/config_test.dart`, ported tests |
| R2 | PD-01-01 (engine), PD-01-02 (skill text) | `test/role_models_test.dart`, `test/skills_test.dart` |
| R3 | PD-01-01 (creates the test), PD-01-02 | `test/independence_test.dart` |
| R4 | PD-01-02 | `test/skills_test.dart`, `next` command |
| R8 | PD-01-01 | `.github/workflows/ci.yml` |
