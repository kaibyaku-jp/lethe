# Security Policy

## Supported versions

Only the latest released minor version of lethe receives security fixes.

## Reporting a vulnerability

Please do not open a public issue for security problems.
Report them privately through GitHub's "Report a vulnerability" button on the
[Security tab](https://github.com/kaibyaku-jp/lethe/security/advisories/new) of this repository.

We aim to acknowledge reports within 5 business days.

## What lethe touches

`lethe:check` and `lethe:export` read table definitions, foreign keys and
the associations of your models, never rows. `lethe:export` writes only the
files at `Lethe.configuration.export_path`, and not with `CHECK=1`.

`Lethe.erase!`, `Lethe.plan`, `Lethe.leftovers` and `lethe:sweep` read and
write rows, as your definitions declare, and only when your code or a task
calls them. `erase!` refuses to run while the check has problems, works in
one transaction, and records in `lethe_erasures` only class names, ids and
row counts.

lethe loads `config/lethe.rb` as Ruby, and runs the hooks and Procs in it,
so treat that file like the rest of your application's code.
