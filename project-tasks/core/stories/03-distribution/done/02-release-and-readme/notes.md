# Notes: PD-03-02

Run by hand in a normal Claude Code session (Sonnet 5.5) directly on `main`, without a PR, as the user asked.

## Decisions

- `README.md` documents the four optional keys the starter config leaves commented out (`goldens_dir`, `git_email_suffix`, `private_patterns`, `models`) as well as the keys the `yaml` package reads from it; `test/readme_test.dart` checks both.
- The release workflow cannot be run by tests. It tags only through the `ls-remote` guard.

## Evidence

- `fvm dart run tool/release_tag.dart` prints `v0.1.0`.
- `fvm dart format` and `fvm dart analyze` are clean; `fvm dart test` passes 170 tests.

## Not verified

- The release tag `v0.1.0` is only created when this commit reaches `main` on GitHub; the workflow has not run.
