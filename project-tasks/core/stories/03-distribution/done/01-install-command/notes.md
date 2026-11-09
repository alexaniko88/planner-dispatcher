# Notes: PD-03-01

Run by hand in a normal Claude Code session (Sonnet 5.5) directly on `main`, without a PR, as the user asked.

## Decisions

- `Installer` validates everything before it writes, so a failed install changes nothing.
- A `.DS_Store` file inside a shipped folder is not copied.
- The starter copies in `.starters/` are written for every template on every run, after the project file is judged created, kept or changed.

## Evidence

- `test/install/installer_test.dart` and `test/install/install_bin_test.dart` cover the task's cases.
- `fvm dart format --output=none --set-exit-if-changed lib bin test` exits 0, `fvm dart analyze` finds no issues, `fvm dart test` passes 161 tests.
