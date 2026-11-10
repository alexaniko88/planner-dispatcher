# planner-dispatcher

A planner and a dispatcher for AI coding tools, for Flutter and Dart projects.

- The **planner** turns an idea into small, concrete tasks under `docs/backlog/` (set by `tasks_dir`) that a runner can implement without asking anything.
- The **dispatcher** runs one ready task in the thread or CLI you open it in: an agent coordinates, and a subagent per stage (implementer, tests, reviewer) does the work in the task's own worktree, ending as one pull request. It suggests a model for each stage for Claude, Codex and Antigravity; you accept it or type others, and you type them for any other tool.
- The **dispatcher check** shows which tasks can start now, how complex each one is (1 to 10) and which ones overlap, so you can open one thread or CLI per task.

## Requirements

- Dart SDK 3.10 or newer, optionally through fvm.
- `git`.
- `gh`, signed in.
- An AI coding tool whose agent can start subagents, for example Claude Code, Codex or Antigravity.

## Setup

1. Add the library to `pubspec.yaml`, pinned to a release tag:

   ```yaml
   dev_dependencies:
     planner_dispatcher:
       git:
         url: https://github.com/alexaniko88/planner-dispatcher.git
         ref: v0.1.0
   ```

2. Run `<dart> pub get`, where `<dart>` is your Dart command (`dart` or `fvm dart`).
3. Run `<dart> run planner_dispatcher:install` from the project root.
4. Fill `planner_dispatcher.yaml` and the two project files `.agents/planner-dispatcher/project-overrides.md` and `.agents/planner-dispatcher/planner-notes.md`.
5. Run install again, so the Claude Code permissions match your `dart` and `check` commands.
6. Commit the result.

Install copies the library-owned files (`.agents/skills/skill-dispatcher/`, `.agents/skills/skill-dispatcher-check/`, `.agents/skills/skill-planner/`, `.agents/rules/backlog-format.md` and the three `.claude/skills/` links) and creates the three project files only when they are missing. It never overwrites a project file.

Install also adds to `.claude/settings.json` the permission rules a task run needs, so a run is not stopped by a permission dialog: `Bash(<dart> run planner_dispatcher:*)`, each `check` command and the read-only git commands (`git status`, `git diff`, `git log`, `git show`). It only adds missing rules and keeps the rest of the file; when the config or the file cannot be read, it changes nothing and prints why. Add your per-file format, analyze and test commands there if the `check` commands do not cover them. Codex and Antigravity have their own permission settings: allow the same commands there.

## How to work

1. `skill-planner`: plan the work into ready tasks, and merge its PR.
2. `skill-dispatcher-check`: see which tasks can start now and how complex they are.
3. For each task you pick, open a new thread or CLI with the tool you want and run `skill-dispatcher <ID>`. It suggests the model of each stage; accept it or type others. Then it works on its own and ends with a PR for you to review. It asks only when it cannot go on without you, and goes on with your answer.

## Config

`planner_dispatcher.yaml` is read from the project root. A bad config makes every command exit 78 with one line naming the key.

- `dart`: required. The command that runs Dart and the library commands, for example `fvm dart`.
- `base_branch`: required. Task worktrees start from `origin/<base_branch>`, pull requests target it and it is never pushed to.
- `setup`: required, may be empty. Commands run in order in a new task worktree; a failure stops the start and removes the worktree.
- `check`: required, at least one. Commands run in order after implementation; all must exit 0.
- `rules`: required, may be empty. Project files every role and the planner read first.
- `tasks_dir`: optional, default `docs/backlog`. The backlog folder, relative to the project root: the planner writes the epics, stories and tasks there and the dispatcher reads them from it. A project that already uses `project-tasks/` sets `tasks_dir: project-tasks`.
- `goldens_dir`: optional, default unset. Changed `.png` files there get before/after images in the pull request.
- `commit_types`: required. The commit types allowed in commit subjects.
- `git_email_suffix`: optional, default unset (any email). When set, `start` and the guard refuse another git email.
- `publish`: optional, default `auto`. With `auto`, the planner and the dispatcher commit, push their own branch and open the PR without asking; with `ask`, they ask once first. Either way they never push to the base branch, never merge and never force-push, and the guard runs before every push.
- `private_patterns`: optional, default none. A map of label to regex, added to the built-in private data scan.
- `models`: optional, default none. Per tool name and stage (`implementer`, `tests`, `reviewer`), the suggested model instead of the built-in one: `{model: ..., name: ..., effort: ...}`, where `effort` is optional and `name` is used in `Co-Authored-By`. Any tool name works, so a team can add suggestions for a tool with none built in. The old keys `run_folder` and `allowed_commands` are refused: remove them.

## Commands

Run each from the project root.

- `<dart> run planner_dispatcher:dispatcher check`: print every task that can start now, with its complexity (1 to 10) and the other ready tasks it overlaps with, and why the other ready tasks wait. It suggests no tool or model.
- `<dart> run planner_dispatcher:dispatcher start <ID> --tool=<tool> [--implementer=M[:EFFORT]] [--tests=M[:EFFORT]] [--reviewer=M[:EFFORT]]`: check the task can start, create its worktree in `.worktrees/<ID>` on the task branch from `origin/<base_branch>`, run `setup` there and push the branch so other threads see the task as busy. A stage takes the model passed for it, else the suggestion; a tool with no suggestion needs all three. It prints the task, the worktree and the subagent call parameters of each stage as JSON, and records the task, the tool and the models in `.runner/run.json`, so `commit`, `finish` and `block` read the task from there with no network. When the task branch is already on the remote and ends with a blocked run's `wip:` commit, it continues that branch; any other branch on the remote means another thread claimed the task, and it stops. A task with an open PR is refused. `.worktrees/` and `.runner/` are added to `.git/info/exclude`.
- `<dart> run planner_dispatcher:dispatcher checks <ID>`: run the `check` commands in order in the task worktree and stop at the first failure. It prints only `passed` and the `commands`, and for a failure the `failed` command and the last 40 lines of its output, so a long test run stays out of the agent's context. Exits 1 when one fails.
- `<dart> run planner_dispatcher:dispatcher commit <ID> --role=implementer|tests|reviewer --message="<subject>"`: commit everything in the task worktree with a subject that follows `commit_types`, and a `Co-Authored-By` line with the tool and the model of that stage.
- `<dart> run planner_dispatcher:dispatcher finish <ID>`: with the work committed and `.runner/report.md` written (`## Summary`, `## Evidence`, `## Checks`, `## Points to review`), move the task to `done/` with its notes, run the guard, push, open the PR and remove the worktree. It prints `RESULT {json}` with the PR link. It checks the report and the branch before it changes anything. On any error nothing more is pushed and the worktree stays; run it again once the cause is fixed: it does not close the task twice and reuses a PR already open for the branch. The closing commit `docs: close task <id> <slug>` passes the guard even when `commit_types` has no `docs`.
- `<dart> run planner_dispatcher:dispatcher block <ID> --question="<text>"` (or `--question-file=<path>`): write the question under `## Blocked` in the task's `notes.md`, commit everything as `wip:`, run the guard, push and remove the worktree.
- `<dart> run planner_dispatcher:dispatcher guard`: check the current branch before a push: not the base branch, `master` or `main`, the git email matches `git_email_suffix`, every commit subject follows `commit_types` (a `wip:` commit is allowed) and no added line holds private data (built-in rules and `private_patterns`). Exits 1 and lists every problem.
- `<dart> run planner_dispatcher:dispatcher models <ID> --tool=<tool>`: print the suggested model of each stage of the task for that tool, or `"suggested": false` when there is none. Claude: Sonnet 5.5, Sonnet 5.5, Opus 5.5. Codex: GPT-6.1 Terra, GPT-6.1 Terra, GPT-6.1 Sol. Antigravity: Gemini 3.8 Flash for the implementer and tests up to complexity 4, else Gemini 4 Argon, and Argon for the reviewer.
- `<dart> run planner_dispatcher:sync`: switch to the base branch, pull it and delete merged local branches.
- `<dart> run planner_dispatcher:install`: install or update the library files.
- `<dart> run planner_dispatcher:backlog close-finished`: move every story whose tasks are all done, and every epic whose stories are all done, into `done/`, fixing the links. The planner runs it on its branch.
- `<dart> run planner_dispatcher:backlog reopen <path>`: move a closed story or epic, and its closed epic, back out of `done/`. The planner runs it before adding a task to closed work.

## Updating

1. Change `ref` in `pubspec.yaml` to the new tag.
2. Run `<dart> pub get`.
3. Run `<dart> run planner_dispatcher:install`.
4. Review any `starter changed` lines: the starter for that project file changed, and the diff of `.agents/planner-dispatcher/.starters/` shows how. Merge what you want by hand.

## Releasing

Bump `version` in `pubspec.yaml` in a pull request. When it merges to `main`, a GitHub Action creates tag and release `v<version>` once.

## License

MIT, see [LICENSE](LICENSE).
