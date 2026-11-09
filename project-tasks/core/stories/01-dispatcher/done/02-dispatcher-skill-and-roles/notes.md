# Notes: PD-01-02

Run by hand in a normal Claude Code session (Sonnet 5.5), as the task says.

## Decisions

- The skill, the three roles and the task format rule were copied from the source and made generic as the task's Contract lists. The source roles pointed to project style and commit rule files; those are now the config's `rules`, so each role reads: the config `rules`, `runner-rules.md`, the project overrides, the format rule, then the task and its `skills:`.
- `runner-rules.md` holds only the generic bullets. Per-file format, analyze and test commands live in this repo's `project-overrides.md` (`fvm dart format|analyze|test <path>`).
- The format rule's link to the dispatcher overrides now points to both `runner-rules.md` and the project overrides. Its links into `skill-planner` stay and resolve after PD-02-01.
- The moved task's relative links were adjusted for the extra `done/` level.

## Evidence

- Roles, reading order, four headings, no `fvm`/`flutter` command in shipped dispatcher files or the format rule, model table, existing `.agents` paths, repo config loads, symlink: `test/skills_test.dart`.
- Shipped files name no other project or home path: `test/independence_test.dart`.
- `fvm dart format --output=none --set-exit-if-changed lib bin test` exits 0, `fvm dart analyze` finds no issues, `fvm dart test` passes 134 tests.

## Not verified

- `fvm dart run planner_dispatcher:dispatcher next` showing `PD-02-01`: needs this PR merged and the `gh` CLI, which was not installed in the session. Run it after merge.
