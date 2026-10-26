# Contributing

Thank you for helping with lethe. Bug reports, ideas and pull requests are
all welcome.

## Setting up

The repository has a Nix flake with the Ruby and Bundler used in development:

```sh
nix develop   # or `direnv allow` if you use direnv
bundle install
```

Without Nix, use Ruby 3.4 or later.

## Running the checks

```sh
bundle exec rake          # all specs and lint (standard)
bundle exec rake package  # build the gem into pkg/
bundle exec rspec spec/lethe/checker_spec.rb  # one spec file
```

The specs run on SQLite in memory. To run them on another database, as CI
does, point Bundler at its Gemfile and set `DATABASE_URL`:

```sh
BUNDLE_GEMFILE=gemfiles/postgresql.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/postgresql.gemfile DATABASE_URL=postgres://localhost/lethe_test \
  bundle exec rspec spec/lethe spec/lethe_spec.rb
```

`gemfiles/rails_7_2.gemfile` and `gemfiles/rails_8_0.gemfile` run the specs on
older Rails in the same way.

## Layout

| path | what |
| --- | --- |
| `lib/lethe/definition.rb` | `Lethe.define` and its methods |
| `lib/lethe/discovery.rb` | finding what points at a subject |
| `lib/lethe/checker.rb` | comparing the two |
| `lib/lethe/formatters.rb`, `exporter.rb` | output |
| `lib/lethe/plan.rb`, `eraser.rb`, `leftovers.rb`, `sweeper.rb` | erasing |
| `lib/lethe/runner.rb`, `tasks/lethe.rake` | the rake tasks |
| `lib/generators/lethe/install` | `bin/rails generate lethe:install` |
| `spec/fixtures/sns_app` | a small Rails app with real attachments, for the integration specs |

## Ground rules

- `check` and `export` read the schema and associations only, never a row.
- `erase!` never runs while the check has problems, and never leaves half
  an erasure: everything in the database happens in one transaction.
- It adds nothing to the running application: no monkey patches, no
  callbacks, no middleware. Nothing runs unless the application calls lethe.
- Every reference it finds must end up in the report. A spec checks this.

## Pull requests

- Keep each commit to one change, with its specs in the same commit.
- Write commit messages that say what changed and why.
- Run `bundle exec rake` before pushing.
- Add an entry under `Unreleased` in `CHANGELOG.md` for user-facing changes.

Please report security issues privately as described in
[SECURITY.md](SECURITY.md), not in public issues.

## Branches and releases

lethe works on one branch, `main`. Every change is a short-lived branch
merged into `main` through a pull request. Releases are tags on `main`; see
[RELEASING.md](RELEASING.md).
