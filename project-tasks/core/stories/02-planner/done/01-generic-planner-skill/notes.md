# Notes: PD-02-01

Run by hand in a normal Claude Code session (Sonnet 5.5) directly on `main`, without a PR, as the user asked.

## Decisions

- The planner skill, its five references and two roles were copied from the source and made generic with the replacements the task's Contract lists. Project-dependent steps are conditions the planner checks at run time (`No UI`, unset `goldens_dir`, integration tests).
- Role and reference links to the runner boundaries point to `runner-rules.md` and `.agents/planner-dispatcher/project-overrides.md`.
- This repo's planner notes and the `.claude/skills/skill-planner` symlink were added as the Contract says.

## Evidence

- Group `planner` in `test/skills_test.dart`: read-only roles, model names, links, `.agents` paths, mentions of the config and notes, forbidden words, the five notes headings, the symlink.
- `fvm dart format --output=none --set-exit-if-changed lib bin test` exits 0, `fvm dart analyze` finds no issues, `fvm dart test` passes 144 tests.
