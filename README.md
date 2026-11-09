# planner-dispatcher

A planner and a dispatcher for AI coding tools, for Flutter and Dart projects.

- The **planner** turns an idea into small, concrete tasks under `docs/backlog/` (set by `tasks_dir`) that a runner can implement without asking anything.
- The **dispatcher** runs ready tasks with Claude, Codex or Antigravity: one clean clone per task, an implementer, a tests stage, the project checks and a review, ending as one pull request.

## Requirements

- Dart SDK 3.10 or newer, optionally through fvm.
- `git`.
- `gh`, signed in.
- At least one of `claude`, `codex` or `agy`.

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
5. Commit the result.

Install copies the library-owned files (`.agents/skills/skill-dispatcher/`, `.agents/skills/skill-planner/`, `.agents/rules/backlog-format.md` and the two `.claude/skills/` links) and creates the three project files only when they are missing. It never overwrites a project file.

## Config

`planner_dispatcher.yaml` is read from the project root. A bad config makes every command exit 78 with one line naming the key.

- `dart`: required. The command that runs Dart and the library commands, for example `fvm dart`.
- `base_branch`: required. Task clones start from `origin/<base_branch>`, pull requests target it and it is never pushed to.
- `run_folder`: required. Runs live in the system temp folder under `<run_folder>/<task id>`.
- `setup`: required, may be empty. Commands run in order in a fresh clone; a failure ends the run as failed.
- `check`: required, at least one. Commands run in order after implementation; all must exit 0.
- `allowed_commands`: optional, default none. Extra command prefixes the Claude implementer and tests stages may run.
- `rules`: required, may be empty. Project files every role and the planner read first.
- `tasks_dir`: optional, default `docs/backlog`. The backlog folder, relative to the project root: the planner writes the epics, stories and tasks there and the dispatcher reads them from it. A project that already uses `project-tasks/` sets `tasks_dir: project-tasks`.
- `goldens_dir`: optional, default unset. Changed `.png` files there get before/after images in the pull request.
- `commit_types`: required. The commit types allowed in commit subjects.
- `git_email_suffix`: optional, default unset (any email). When set, launch refuses another git email.
- `private_patterns`: optional, default none. A map of label to regex, added to the built-in private data scan.
- `models`: optional, default none. Per tool (`claude`, `codex`, `antigravity`) and stage (`implementer`, `tests`, `reviewer`) an entry `{model: ..., effort: ..., name: ...}`; `name` is used in `Co-Authored-By`.

## Commands

Run each from the project root.

- `<dart> run planner_dispatcher:dispatcher next [--skip=ID,ID]`: print the next ready task.
- `<dart> run planner_dispatcher:dispatcher models`: print the models of each tool and stage.
- `<dart> run planner_dispatcher:dispatcher launch <ID> --tool=claude|codex|antigravity [--implementer=M] [--tests=M] [--reviewer=M] [--allow=P,P]`: run one task and open its pull request.
- `<dart> run planner_dispatcher:dispatcher status`: print the state of the runs.
- `<dart> run planner_dispatcher:sync`: switch to the base branch, pull it and delete merged local branches.
- `<dart> run planner_dispatcher:install`: install or update the library files.

## Updating

1. Change `ref` in `pubspec.yaml` to the new tag.
2. Run `<dart> pub get`.
3. Run `<dart> run planner_dispatcher:install`.
4. Review any `starter changed` lines: the starter for that project file changed, and the diff of `.agents/planner-dispatcher/.starters/` shows how. Merge what you want by hand.

## Releasing

Bump `version` in `pubspec.yaml` in a pull request. When it merges to `main`, a GitHub Action creates tag and release `v<version>` once.

## License

MIT, see [LICENSE](LICENSE).
