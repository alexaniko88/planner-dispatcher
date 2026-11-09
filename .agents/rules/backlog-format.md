---
paths:
  - "docs/backlog/**"
---

# Backlog format

Single source for how the backlog is laid out and how a task is written. Skills and roles link to this file and never copy it.

The backlog lives in `<tasks_dir>/`, where `<tasks_dir>` is the `tasks_dir` value of `planner_dispatcher.yaml` (default `docs/backlog`). It is a path relative to the project root.

## Layout

```text
<tasks_dir>/
├── planning/
│   └── <topic>/
│       └── planning.md
├── bugs/
│   ├── index.md
│   └── 01-<slug>/
├── improvements/
│   ├── index.md
│   └── 01-<slug>/
└── <epic-slug>/
    ├── index.md
    └── stories/
        └── 01-<story-slug>/
            ├── index.md
            ├── 01-<task-slug>/
            └── done/
                └── 02-<task-slug>/
```

- Lowercase kebab-case paths. Stories and tasks have a two-digit prefix that gives their order. Epics have none. Keep a number once it is used; never renumber.
- **A task is a folder** with `index.md`. It can also hold `mockup.html` (UI tasks) and `notes.md`.
- **Only tasks are archived.** A finished task moves into the `done/` folder of its parent (story, `bugs/` or `improvements/`). Epics and stories never move, so new work can always be added to them.
- Standalone bugs and improvements have no epic or story. Use them for a broken behavior (`bugs/`) or a change to something that already works (`improvements/`).
- Indexes link to their children and carry no status, counts or progress. State is deduced (see below).
- A story may own one approved `mockup.html` shared by its visual tasks. Tasks link to the relevant states instead of copying the design. A standalone visual task owns its mockup itself.

## Planning record

`<tasks_dir>/planning/<topic>/planning.md` holds one planning effort, including efforts that span stories. It is not a task: give it no task front matter or `index.md`, and never list it as a dispatcher dependency. This location lets interviewing begin before the user agrees to a backlog structure. Reuse its path when resuming the same effort.

It holds the request, evidence, decisions and open questions; its working format is in [the planner's question reference](../skills/skill-planner/references/questions.md). A mockup lives beside it until the split is agreed.

During the interview it is the working source of truth. It may be committed on the planning branch, so a paused effort can resume in a later session. Never link to it from backlog files. Do not track implementation progress in it.

**At handoff, delete it.** Once every task of the effort is `ready`, transfer the current requirements, decisions and exclusions into the epic/story/task files and verify nothing was lost. Then delete the record, its `planning/<topic>/` folder, and anything else that only served the planning (drafts, scratch files, links to them), in the same planning PR. Runners need only their task, parents and repository. While a task of the effort is still `draft`, keep the record so its open questions are not lost, and delete it in the session that makes the last task `ready`. A follow-up planning effort starts a new record.

## IDs

- Every epic `index.md` starts with a front matter line `abbr: <ABBR>` (for example `TPL`).
- Task id: `<ABBR>-<story>-<task>`, for example `TPL-03-02`. Standalone tasks: `BUG-01`, `IMP-02`.
- An id is unique, never reused and never changed. `depends-on` uses ids.

## Task `index.md`

Front matter:

```yaml
---
id: TPL-03-02
status: draft          # draft | ready; in done/ it is done
type: feat             # feat | fix | improve; sets the branch prefix
complexity: low        # low | medium | high; picks the suggested model
depends-on: [TPL-03-01]
touches:               # paths or globs the task changes
  - lib/src/store.dart
  - test/goldens/home.png
skills: []             # optional; project skills the roles read, e.g. [skill-charts]
---
```

After the front matter, the title and the story and epic link lines, these sections, in this order. Leave out a section marked "only when" that does not apply. Keep the task short and concrete: a runner implements it without asking anything, using only code, tests and the config's `check` commands.

1. `## Goal`: what the task delivers, in one or two sentences, with the requirement ids it serves.
2. `## Context`: the code entry points and goldens that matter, and where new code goes.
3. `## Contract` (only when the task provides or uses something from another task): each symbol or path marked `existing`, `new here` or `provided by <task-id>`, with its signature, inputs, outputs, failures and ownership. Link shared agreements in the parent instead of copying them. An unwired piece names its consumer task. New names are proposals fixed by this plan, not claims about existing code.
4. `## View spec` (visual tasks only): the widget or screen states, themes, strings, accessibility and navigation. An isolated widget covers its own states and callbacks; assembly covers wiring and the full screen.
5. `## Mockup` (visual tasks only): link to the approved `mockup.html` and the states this task implements.
6. `## Decisions` (only when there are choices a runner might otherwise reverse).
7. `## Out of scope`
8. `## Files and tests`: each created or changed file, each test file with its kind, and any planned fake or harness change. The test cases are the `Check`s in `## Acceptance`. Explain a behavioral widget test, or why no test is planned, only when that is the case.
9. `## Acceptance`: the task's behavior, one checkbox per behavior or edge case, on one line each: `- [ ] When <situation>, then <result>. Check: <check>.` Start with `Given <state>,` only when the starting state is not obvious. There is no separate behavior section: this list is the specification, the tests to write and the definition of done.

A `Check` is one of these, and nothing else:

- A test file and the test case, for example ``Check: `test/timer_list_test.dart` "delete removes the timer".``
- A golden file, only when `goldens_dir` is set.
- A command from the config's `check` list, written exactly as it appears there.

New and refined plans use these sections. Existing tasks keep their ids; before dispatching a task in an older layout, refine it rather than asking a runner to invent the missing parts.

## Shared agreements and requirements

The story lists its requirements once, as R1, R2…, each with the task ids that deliver it, and holds contracts its tasks share. The epic holds cross-story agreements. This is a scope map, not progress tracking.

`notes.md` is written by the worker: decisions it took, the evidence for each criterion, the PR link, and, when blocked, the exact question under `## Blocked`.

## When a task is `ready`

All of these are true:

- No open decision is left, and the task reads clearly to an agent that has not seen the planning conversation (cold read passed).
- Every criterion has a `Check` of an allowed kind.
- A visual widget/assembly task has its view spec and a linked mockup the user approved. ViewModel/state-only tasks omit them.
- `complexity`, `depends-on` and `touches` are filled in. `depends-on` ids exist.
- Its contract, consumer/assembly ownership and exact validation plan are settled, consistent with its dependencies and executable within runner boundaries. No required test infrastructure or technical decision is left for a runner to discover.
- The whole split has complete requirement coverage and compatible contracts. Each PR preserves a buildable, usable app with its completed prerequisites.

Anything else stays `draft`. Resolve unknowns in planning. A code/test prerequisite may unblock a draft, but findings-only investigations do not go to the implementation dispatcher. `ready` tasks may depend on unmerged fixed-contract tasks; they cannot be picked until those prerequisites are done. If an upstream contract changes, return affected pending tasks to `draft` and reconcile/cold-read them before restoring readiness.

## State is deduced

Nothing writes a progress status. From the repo:

| What exists | State |
| --- | --- |
| Task folder is under `done/` on the base branch | done |
| Open PR from the task branch | in review |
| Task branch on the remote, no PR | in progress, or blocked (a `wip:` commit and `## Blocked` in `notes.md`) |
| `status: ready`, every `depends-on` done, no overlap with a running task | can be picked |

The task branch is `<type>/<id-lowercase>-<slug>`, for example `feat/tpl-03-02-save-template`. The worker moves its own task folder to `done/` (with `status: done`) in its PR, so merging the PR means the task is done.

## Overlap

Two tasks overlap when their `touches` overlap. They never run at the same time.

- `touches` lists exact paths: code, tests and, when `goldens_dir` is set, golden files. Use a narrow glob only when necessary.
- List specific golden files, never the whole `goldens_dir`.
- Prefer exact code/test paths to feature-wide globs. If several tasks edit the snapshot harness, list that file in each; overlap is intentional serialization, not a semantic dependency.
- When a task adds strings, list the localization folder the project rules name. It counts as a path like any other, so two tasks that add strings overlap.
- Do not list generated index files the planner notes name, or the backlog indexes. A merge conflict there is small and the user resolves it.

## Writing rules

- Relative Markdown links between task files. Repository-relative paths in prose. No local usernames, absolute paths or secrets.
- Do not copy global coding, git or model policies into a task. The worker follows the repo rules.
- Do not invent file names or APIs as verified facts. Check the code first.
