<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo/lethe-logo-vertical-dark.svg">
    <img src="docs/logo/lethe-logo-vertical.svg" alt="lethe: a time to keep, and a time to cast away." width="300">
  </picture>
</p>

# lethe [![CI](https://github.com/kaibyaku-jp/lethe/actions/workflows/ci.yml/badge.svg)](https://github.com/kaibyaku-jp/lethe/actions/workflows/ci.yml)

A time to keep, and a time to cast away.

When someone deletes their account, every table that points at them needs a
decision: delete the rows, overwrite what is personal, or keep them for a
reason. lethe finds those tables in your Rails app, checks that each one has
a declared policy, and fails CI when a new table has none.

> **Status:** early, before its first release. Until 1.0, minor versions may
> change how things work; [CHANGELOG.md](CHANGELOG.md) says what changed.

Lethe is the river of forgetting in Greek myth: in Plato's *Republic*, souls
drink from it before they are born again.


## Features

### Finds What Points at a User

Foreign keys, `has_many` and `has_one`, `belongs_to` in other models,
join tables, polymorphic associations, Active Storage attachments and,
as a guess, columns named like `user_id` or `*_user_id`.

### Fails on What Nobody Decided

A table added last week with a `user_id` and no policy fails the check. So
does a policy for a table or column that no longer exists.

### Writes It Down for People

`lethe:export` writes what happens to each kind of data as a Markdown table,
in English or Japanese, for your privacy policy, app store review or support
team. CI can check that it is up to date, so every change shows up in review.

### Hands Off Your Data

lethe reads the schema and your models' associations. It never reads or
writes a row, and it adds nothing to your running application: only rake
tasks and a method for your tests.


## Supported Versions

* Ruby 3.4, 4.0

* Rails 7.2, 8.0, 8.1

* SQLite, MySQL and PostgreSQL


## Installation

Put this in your Gemfile:

```ruby
group :development, :test do
  gem "lethe"
end
```

Bundler loads it in development and test only. It adds the rake tasks and
nothing else to your application.


## Declaring Policies

Write the policies in `config/lethe.rb`:

```ruby
Lethe.define User do
  # The users row itself: destroy: true, or soft_delete: with a column.
  subject soft_delete: :deleted_at, scrub: {nickname: "Deleted user", email: nil}

  # Associations of User, by name.
  destroy :ratings, :favorites, :notifications
  scrub   :posts, set: {body: ""}, reason: "Quoted posts keep their row"
  scrub   :questions, where: {status: "answered"}, set: {body: ""}
  destroy :questions, where: {status: %w[pending declined]}
  keep    :orders, for: 7.years, reason: "Bookkeeping"

  # Anything without an association, as "table.column".
  destroy "follows.follower_id", "follows.following_id"
  keep    "muted_users.muted_user_id", reason: "Other people's settings"

  destroy_attachments :avatar

  # A guess that does not point at User.
  ignore "audit_logs.admin_user_id", reason: "Points at AdminUser"
end
```

| policy | means |
| --- | --- |
| `destroy` | The rows are deleted. |
| `scrub` | The rows stay, with the columns in `set:` overwritten. |
| `keep` | The rows stay as they are. Needs a `reason:`; `for:` says how long. |
| `ignore` | The column does not point at the subject. Needs a `reason:`. |
| `destroy_attachments` | The subject's Active Storage attachments are deleted. |
| `subject` | How the subject's own row goes. |

`where:` limits a policy to some rows, so the same table can have one policy
per condition. lethe does not check that the conditions cover every row.

Declare more subjects, such as `Organization`, the same way. Declarations
for the same subject add up.


## Checking

```sh
% bin/rails lethe:check
User: 41 references (association 36, attachment 3, column name 4, foreign key 31)

✓ 37 have a policy
✗ chat_messages.user_id             no policy (found by foreign key, association, column name)
? question_blocks.blocked_user_id   guessed from the column name; declare a policy, or `ignore` it with a reason if it does not point at User
! config/lethe.rb:14 :badges        User has no association :badges

2 problems, 1 to confirm.
```

| mark | means | fails the check |
| --- | --- | --- |
| `✓` | Has a policy. | no |
| `✗` | Certainly points at the subject, with no policy. | yes |
| `!` | A declaration is wrong or names something that is gone. | yes |
| `?` | Might point at the subject, from its name alone, with no policy. | with `STRICT=1` |

It exits with 0 when there are no problems, 1 when there are, and 2 when
`config/lethe.rb` cannot be loaded.

| option | meaning |
| --- | --- |
| `FORMAT=github` | GitHub Actions annotations; `FORMAT=json` for tools |
| `STRICT=1` | Fail on `?` too |
| `LOCALE=ja` | Messages in Japanese |

In a test instead:

```ruby
it "has a policy for every table that points at a user" do
  Rails.application.eager_load!
  Lethe.load_definitions(Rails.root.join("config/lethe.rb"))
  Lethe.check!
end
```


## Exporting

```sh
% bin/rails lethe:export LOCALE=ja
lethe: wrote docs/lethe.md
lethe: wrote docs/lethe.json
```

```markdown
| Data | When they leave | Kept for | Reason |
| --- | --- | --- | --- |
| The User itself | Kept as deleted (deleted_at), with nickname, email overwritten |  |  |
| Avatar (attachment) | Deleted |  |  |
| Order | Kept | 7 years | Bookkeeping |
```

Names come from your app's translations, such as `activerecord.models.order`.
Nothing is written while the check has problems. `CHECK=1` compares instead
of writing and fails when the files are out of date; run it in CI:

```sh
bin/rails lethe:check lethe:export CHECK=1 FORMAT=github
```


## Configuring lethe

In `config/initializers/lethe.rb`, or anywhere loaded before the tasks run:

```ruby
Lethe.configure do |config|
  config.definition_path = "config/lethe.rb"   # the default
  config.export_path = "docs/lethe"            # .md and .json are added
  config.skip_tables = %w[audit_logs]          # besides Rails' own
  config.guess_columns[User] = %w[follower_id following_id questioner_id]
end
```


## Questions, Feedback

Open an issue on GitHub. Report security problems privately as described in
[SECURITY.md](SECURITY.md).


## Contributing to lethe

Fork, fix, then send a pull request. [CONTRIBUTING.md](CONTRIBUTING.md) has the
details.

```sh
% nix develop          # or use Ruby 3.4+ without Nix
% bundle install
% bundle exec rake
```


## Copyright

Copyright (c) 2026- KAIBYAKU K.K. See [LICENSE](LICENSE) for further details.
