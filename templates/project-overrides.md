# Project overrides for the runners

The rules of this project, by stage. Each role reads "Common" and its own section, after the generic `.agents/skills/skill-dispatcher/references/runner-rules.md`.

## Common

Facts every stage needs, such as the layers and the style rules of this project.

- **Per-file commands.** Format with `fvm dart format <path>`, analyze with `fvm flutter analyze --no-pub <path>` and test with `fvm flutter test <path>`, always with a literal path.

## Implementation

Where new code goes and how it is written in this project.

## Tests

Where tests go, how they are named and which fakes to use.

## Review checks

What the reviewer flags in this project, each with a severity.
