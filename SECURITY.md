# Security Policy

## Supported versions

Only the latest released minor version of lethe receives security fixes.

## Reporting a vulnerability

Please do not open a public issue for security problems.
Report them privately through GitHub's "Report a vulnerability" button on the
[Security tab](https://github.com/kaibyaku-jp/lethe/security/advisories/new) of this repository.

We aim to acknowledge reports within 5 business days.

## What lethe touches

lethe reads table definitions, foreign keys and the associations of your
models. It never reads or writes rows. Its rake tasks write only the export
files at `Lethe.configuration.export_path`, and only when `lethe:export` runs
without `CHECK=1`. It loads `config/lethe.rb` as Ruby, so treat that file
like the rest of your application's code.
