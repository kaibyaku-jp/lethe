# Releasing

The gem is released by `.github/workflows/release.yml` when a `v*` tag is
pushed.

## One-time setup

1. On RubyGems.org, add a trusted publisher for `lethe`. Before the first
   release, use a **pending trusted publisher** under your account settings,
   since the gem does not exist yet.
   - Repository owner: `kaibyaku-jp`
   - Repository name: `lethe`
   - Workflow filename: `release.yml`
   - Environment: `release`
2. In the GitHub repository settings, create the `release` environment and
   limit it to `v*` tags. Add required reviewers once the repository is public.
3. After the first release, add a second owner to the gem and make sure MFA
   is required for all owners.

## Each release

1. Update `Lethe::VERSION` in `lib/lethe/version.rb` and run `bundle install`
   so `Gemfile.lock` follows.
2. Move the `Unreleased` entries in `CHANGELOG.md` under the new version and
   date.
3. Open a pull request with those changes and merge it once CI passes.
4. Tag the merge commit on `main` and push the tag:

   ```sh
   git switch main && git pull
   git tag v0.1.0
   git push origin v0.1.0
   ```

The workflow checks that the tag matches `Lethe::VERSION`, runs the specs and
lint, builds the gem, pushes it and creates the GitHub release with the built
gem attached.
