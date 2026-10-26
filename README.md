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
a declared policy, fails CI when a new table has none, and carries the
policies out when the account goes.

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

### Erases as Declared

`Lethe.erase!(user)` deletes, overwrites and keeps exactly what the
policies say, in one transaction, and refuses to run while the check has
problems. `Lethe.leftovers(user)` proves in a test that nothing else was
left behind.

### Reads the Schema to Check

`lethe:check` and `lethe:export` read the schema and your models'
associations only, never a row. Only `erase!`, `plan`, `leftovers` and
`lethe:sweep` touch data, and only when your code calls them.


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

To erase accounts with it in production, put it outside the group instead.
It adds the rake tasks and the methods below, and nothing else: no
callbacks, middleware or patches to Rails.

To keep rows for a while (`keep ..., for:`), lethe records each erasure in a
table of its own. Create it, with a `config/lethe.rb` to start from:

```sh
% bin/rails generate lethe:install
% bin/rails db:migrate
```


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
  scrub   :orders, set: {phone: nil, address: nil}, for: 7.years, reason: "Bookkeeping"

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
| `scrub` | The rows stay, with the columns in `set:` overwritten; `for:` says how long. |
| `keep` | The rows stay as they are. Needs a `reason:`; `for:` says how long. |
| `ignore` | The column does not point at the subject. Needs a `reason:`. |
| `destroy_attachments` | The subject's Active Storage attachments are deleted. |
| `subject` | How the subject's own row goes. |

`where:` limits a policy to some rows, so the same table can have one policy
per condition. lethe does not check that the conditions cover every row.
Enum names work in `where:` and `set:` as they do with your model, and a
name the enum does not have fails the check.

An STI subclass, such as `Admin < User`, can have a definition of its own.
It is used instead of the base class's for records of that class, so it
must declare everything.

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
  Lethe.check!
end
```

Inside a Rails app, lethe loads `config/lethe.rb` the first time it is
needed, and loads every model once where `eager_load` is off, so that
development and test see the same associations as CI.


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
| Order | Kept, with phone, address overwritten | 7 years | Bookkeeping |
```

Names come from your app's translations, such as `activerecord.models.order`.
Nothing is written while the check has problems. `CHECK=1` compares instead
of writing and fails when the files are out of date; run it in CI:

```sh
bin/rails lethe:check lethe:export CHECK=1 FORMAT=github
```


## Erasing

```ruby
class AccountsController < ApplicationController
  def destroy
    Lethe.erase!(current_user)
    reset_session
    head :no_content
  end
end
```

`erase!` checks the subject's definition first and raises `Lethe::Unclean`
without touching anything when it has problems. Then, in one transaction,
it runs the `before_erase` hooks, deletes rows (those with foreign keys to
other deleted tables first), overwrites columns, marks or deletes the
subject's own row, runs the `after_erase` hooks and records the erasure. If
anything fails, all of it is rolled back. Attachments are detached in the
transaction and their files purged after it commits.

| erasing | how |
| --- | --- |
| `destroy` | `delete_all` on the table, with no callbacks; `cascade: true` uses the model's `destroy_all`, so `dependent:` associations and attachments go too |
| `scrub` | `update_all`; a Proc in `set:` is called for each row, given the row if it takes an argument |
| `keep` | Nothing now; `lethe:sweep` deletes the rows once `for:` has passed (as does `scrub ..., for:`) |
| polymorphic | The type always becomes part of the condition, so erasing User 5 never touches Post 5's rows |

```ruby
Lethe.define User do
  subject soft_delete: :deleted_at,
    scrub: {screen_name: ->(user) { "deleted_#{user.id}_#{SecureRandom.hex(8)}" }}
  destroy :episodes, cascade: true
  destroy "ratings.target_id", where: {target_type: "User"}

  before_erase { |user| Follow.decrement_counters_for(user) }
  after_erase { |user| DeleteFirebaseAccountJob.perform_later(user.firebase_uid) }
end
```

Hooks run inside the transaction. Anything that cannot be rolled back,
such as a call to another service, belongs in a job enqueued from
`after_erase`.

`Lethe.plan(user)` lists the steps and how many rows each touches, without
changing anything. `erase!` returns the rows per table and policy, and
sends an `erase.lethe` notification with the subject's class, id and those
counts, never anything personal. Files that could not be purged after the
commit are logged and listed as `purge_failures` (blob ids) rather than
raised, since the erasure itself has already committed.

Running `erase!` again is safe: what is gone stays gone, and a soft
delete keeps the time of the first erasure.

### Proving It in Tests

```ruby
it "leaves nothing of a user behind but what we keep" do
  user = create(:user, :with_everything)
  Lethe.erase!(user)

  expect(Lethe.leftovers(user)).to be_empty
end
```

`leftovers` lists rows that should be gone, columns that should have been
overwritten (values from a Proc are not compared), attachments, and the
subject's row.

### Sweeping

Run this daily, from cron or a recurring job:

```sh
% bin/rails lethe:sweep
lethe: swept 3 from User :inquiries
```

It deletes the rows of each `keep ..., for:` and `scrub ..., for:` whose
time has passed since their subject was first erased, one subject at a time
in a transaction. If other rows still point at them through a foreign key,
it stops there; add `cascade: true` to delete through the model and its
`dependent:` associations instead.


## Configuring lethe

In `config/initializers/lethe.rb`, or anywhere loaded before the tasks run:

```ruby
Lethe.configure do |config|
  config.definition_path = "config/lethe.rb"   # the default
  config.export_path = "docs/lethe"            # .md and .json are added
  config.skip_tables = %w[audit_logs]          # besides Rails' own
  config.guess_columns[User] = %w[follower_id following_id questioner_id]
  config.purge = :later                        # or :now, for erased attachments' files
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
