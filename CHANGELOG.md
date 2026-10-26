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
- `Lethe.erase!` to carry the policies out in one transaction, refusing
  while the check has problems; `destroy ..., cascade: true`, Procs in
  `set:`, and `before_erase` / `after_erase` hooks.
- `Lethe.plan` to see the steps without changing anything, and
  `Lethe.leftovers` to prove in tests that nothing else was left behind.
- `bin/rails lethe:sweep` to delete kept rows once `keep ..., for:` has
  passed, and `bin/rails generate lethe:install` for the table it needs.
- The check also fails on a polymorphic "table.column" without its type,
  `cascade: true` without a model, and rows kept with a foreign key to a
  subject row that is deleted.
- Enum names in `where:` and `set:`, read through the application's model;
  a name the enum does not have fails the check.
- A definition for an STI subclass is used for its records, and its kept
  rows are swept by its own retention.
- Messages and exports in English and Japanese.
