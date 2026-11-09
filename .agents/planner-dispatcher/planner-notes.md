# Planner notes

Project facts the planner reads besides `planner_dispatcher.yaml` and its `rules` files.

## Branches and pull requests

- Branch prefixes: `feat/`, `fix/`, `improve/`. Planning branches are `feat/plan-<short-topic>`.
- The PR title starts with the same word as the branch prefix, for example `feat: ...`.
- Commit subject: `<type>: <description>` with a type from the config's `commit_types`, at most 72 characters. Planning commits use `docs`.
- Commits end with `Co-Authored-By: <tool> <model>`.

## UI sources

No UI

## Project skills

None

## Checks

The check runs format, analyze and all tests. It does not install into a real consumer project or run the GitHub workflows.

## Coverage checks

- A change to shipped files keeps them free of other project names.
