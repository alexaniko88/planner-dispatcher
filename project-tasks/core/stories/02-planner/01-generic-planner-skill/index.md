---
id: PD-02-01
status: ready
type: feat
complexity: medium
depends-on: [PD-01-02]
touches:
  - .agents/skills/skill-planner/**
  - .agents/planner-dispatcher/planner-notes.md
  - .claude/skills/skill-planner
  - test/skills_test.dart
skills: []
---

# Generic planner skill

Story: [Planner](../index.md)

Epic: [Standalone planner and dispatcher](../../../index.md)

## Goal

Add the planner skill, its references and its two roles in a generic form, plus this repo's own planner notes. The planner then plans for any project from that project's config, rules and notes.

## Context

- Source to copy (public repo `https://github.com/alexaniko88/sport_timer`, branch `master`): `.agents/skills/skill-planner/SKILL.md`, `references/{questions,ui-questions,mockup,task-splitting,templates}.md`, `roles/{cold-reader,interview-reviewer}.md`; the planner guards in `test/architecture/ai_setup_test.dart` (group `planner`).
- Project-specific parts of the source to replace:
  - `SKILL.md`: `fvm dart tool/sync_master.dart`; `.agents/rules/git-commits.md`; `test/snapshots/goldens/` and `test/snapshots/README.md`; `skill-fl-chart` example; `../skill-dispatcher/references/project-overrides.md`; `lib/l10n/**`.
  - `references/mockup.md` and `references/ui-questions.md`: named theme files, shared widgets, `CLAUDE.md` sections, golden size and paths.
  - `references/task-splitting.md`: `tool/agent_check.dart --skip-build`; `CLAUDE.md` UI rule.
  - `references/templates.md`: `domain`/`data`/`presentation` layer text and `CLAUDE.md`.
  - `roles/cold-reader.md`, `roles/interview-reviewer.md`: `CLAUDE.md`, `.agents/rules/dart-style.md`, `.agents/skills/skill-dispatcher/references/project-overrides.md`; the "Strings" check (English or Spanish).
  - `references/questions.md`: the "Timer/background/audio" and "Statistics" coverage examples.
  - Everywhere: "dispatcher overrides" and `project-overrides.md` of the dispatcher skill; "master"; "device integration tests" and "snapshot harness" wording.
- From PD-01-02: `.agents/skills/skill-dispatcher/references/runner-rules.md`, roles, `.agents/rules/project-tasks-format.md`, `test/skills_test.dart`.

## Contract

- New here, shipped and library-owned: the planner files above, with these replacements:
  - sync: `<dart> run planner_dispatcher:sync`, where `<dart>` is the config's `dart`;
  - project rules and architecture: "the files in the config's `rules`";
  - branches, PR titles, UI sources, goldens, project skills: "`.agents/planner-dispatcher/planner-notes.md`";
  - runner boundaries: `../skill-dispatcher/references/runner-rules.md` and `.agents/planner-dispatcher/project-overrides.md`;
  - checks: "the config's `check` commands";
  - golden paths: "the config's `goldens_dir`". Write project-dependent steps as conditions the planner checks at run time, not deletions: "When the first line of the planner notes' `## UI sources` is `No UI`, skip steps 4 and 5"; "When `goldens_dir` is unset, skip golden and snapshot steps"; "When the project rules or planner notes mention integration tests, plan them outside dispatcher tasks; otherwise ignore them";
  - `mockup.md`: tokens, shared widgets and frame size come from `## UI sources` (default frame 390 by 844 when the notes give none); the language switch shows every language the project rules require;
  - "master": "the configured `base_branch`"; the sync step says it switches to the base branch;
  - the planning branch stays `git switch -c feat/plan-<short-topic>` unless the planner notes give another prefix; commit messages follow the config's `rules` and the attribution rule in the planner notes; the email check uses the config's `git_email_suffix` when set; the PR title follows the planner notes;
  - strings: "user-facing text in every language the project rules require (English only when they name none)";
  - `task-splitting.md`: "ViewModel/state block" becomes "State/logic block"; "the existing snapshot harness" becomes "the project's golden test named in the planner notes"; "under `CLAUDE.md`" becomes "under the project rules"; `templates.md`: the layer and `extensions/` text becomes "where the project rules put new code". Generic UI words (snackbar, haptic feedback) and the generic words "ViewModel" and "timer" in examples stay (Flutter and Dart projects only); in `templates.md`, the inline text `` `[Bugs](../index.md)` or `[Improvements](../index.md)` `` becomes "a link to the parent category `index.md` (`Bugs` or `Improvements`)" so it is no longer a Markdown link;
  - integration tests: `task-splitting.md` says "When the project rules or planner notes mention integration tests, plan them outside dispatcher tasks and never use them as acceptance checks"; `SKILL.md` step 8 says "Do not add an integration-test skill to ordinary implementation tasks";
  - app-specific coverage examples: removed; the planner adds the planner notes' `## Coverage checks`;
  - runner boundaries everywhere: `../skill-dispatcher/references/runner-rules.md` plus `.agents/planner-dispatcher/project-overrides.md`.
  The interview flow, question rules, mockup rules, cold read, model table and hand-off steps stay as in the source.
- Planner notes format: the five sections in the [epic](../../../index.md#planner-notes).
- New here, this repo only: `.agents/planner-dispatcher/planner-notes.md` filled for this package (branch prefixes `feat/`, `fix/`, `improve/`; PR title starts with the same word; commit subject `<type>: <description>` with a type from the config's `commit_types`, at most 72 characters, planning commits use `docs`; commits end with `Co-Authored-By: <tool> <model>`; UI sources: No UI; project skills: None; checks: the check runs format, analyze and all tests, and does not install into a real consumer project or run the GitHub workflows; coverage checks: "a change to shipped files keeps them free of other project names").
- New here: symlink `.claude/skills/skill-planner` -> `../../.agents/skills/skill-planner`.
- Consumer: PD-03-01 (install copies these files; its planner-notes starter uses the five headings).

## Behavior

- No planner file names another project, a fixed tool command, or a file that does not exist after install.

## Decisions

- Project facts the planner needs that are not commands live in one project-owned notes file, so install never overwrites them.

## Out of scope

- Changing how the planner interviews, splits or cold-reads.
- Install and starters (PD-03-01).

## Files and tests

- Create the files in Contract and the symlink.
- Extend `test/skills_test.dart` (reuse its helpers) with group `planner`: `cold-reader.md` and `interview-reviewer.md` have `access: read-only` and contain `Never edit` or `Do not edit`, as the source does; `SKILL.md` names `Opus 5.5`, `GPT-6.1 Sol` and `Gemini 4 Argon`; every `references/` or `roles/` link in `SKILL.md` exists; every relative Markdown link outside fenced code blocks and without `<` in the planner files and in `.agents/rules/project-tasks-format.md` resolves to an existing file or folder (anchors are stripped and not checked); every `.agents/...md` path mentioned in any planner file exists in this repo; `SKILL.md`, `cold-reader.md` and `interview-reviewer.md` mention `planner_dispatcher.yaml` and `planner-notes.md`; no file under `.agents/skills/skill-planner/` matches `(?i)\bfvm\b|\bflutter (analyze|test|pub|run|gen-l10n|build)\b|\bmaster\b` (this repo's planner notes are not scanned); this repo's planner notes have exactly the five `##` headings in the epic order (an `#` title is allowed).
- `test/independence_test.dart` already walks `.agents/`; no change.
- Run: `fvm dart format --output=none --set-exit-if-changed lib bin test`, `fvm dart analyze`, `fvm dart test`.

## Acceptance

- [ ] When the planner needs project facts, then it reads the config, the config's `rules` and the planner notes, and names no project command (its default `feat/plan-` planning branch is allowed). Check: `test/skills_test.dart` (mentions and forbidden words) and `test/independence_test.dart`.
- [ ] When a planner file or the format rule links to a file, then the file exists. Check: `test/skills_test.dart`.
- [ ] When this repo's planner notes are read, then they have exactly the five agreed headings. Check: `test/skills_test.dart`.
