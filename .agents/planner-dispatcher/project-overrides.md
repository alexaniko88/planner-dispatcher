# Project overrides for the runners

The rules of this Dart package, by stage. Each role reads "Common" and its own section, after the generic `.agents/skills/skill-dispatcher/references/runner-rules.md`.

## Common

- **Per-file commands.** Format with `fvm dart format <path>`, analyze with `fvm dart analyze <path>` and test with `fvm dart test <path>`, always with a literal path.
- **Independence.** The shipped files (`lib/`, `bin/`, `.agents/`, `templates/`, `stacks/`, `README.md`) never name another project, a fixed build command or a local home path.

## Implementation

- Code goes in `lib/src/`; the command entry points are in `bin/`.
- An extension goes in `lib/src/extensions/`, one per file.
- Order members as fields, then the constructor, then methods.
- Add no new dependency unless the task names it.

## Tests

- `lib/src/<path>.dart` is tested in `test/<path>_test.dart`.
- Use hand-written fakes and no mocking package.

## Review checks

- A file in the wrong folder (general).
- A shipped file that names another project or a fixed build command (critical).
- A mocking package (general).
- Changed logic without a test (general).
