# Changelog

All notable changes to this project are documented in this file. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

The first release.

### Added

- `Lethe.define` to declare, per subject such as `User`, what happens to the
  data that points at it: `destroy`, `scrub`, `keep`, `ignore`,
  `destroy_attachments`, and `subject` for its own row.
- Finding what points at a subject from foreign keys, associations, join
  tables, polymorphic associations, Active Storage attachments and, as a
  guess, column names.
- `bin/rails lethe:check`, with text, GitHub Actions and JSON output, and
  `STRICT=1` to fail on guesses.
- `bin/rails lethe:export`, which writes the policies as Markdown and JSON,
  and `CHECK=1` to fail when they are out of date.
- `Lethe.check!` for tests.
- Messages and exports in English and Japanese.
