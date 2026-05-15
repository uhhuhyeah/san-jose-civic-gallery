# Contributing

Thanks for contributing to San Jose Civic Pulse.

## Project Posture

This project is public-interest civic software. That means correctness, provenance, and clarity matter more than novelty.

Please optimize for:

- source-linked claims
- conservative summaries
- explicit provenance
- maintainable Rails code
- small, reviewable changes

Please do not optimize for:

- speculative interpretation presented as fact
- AI-generated output without verification
- clever abstractions that make provenance harder to follow

## Before You Open A Pull Request

1. Read `README.md` and `docs/architecture.md`.
2. Make sure your change fits the source-first design of the app.
3. Keep generated and official data concerns clearly separated.
4. Add or update tests when behavior changes.
5. Update documentation when the operational workflow or architecture changes.

## Development

Local development uses:

- host-run Rails app
- Dockerized local Postgres via `docker compose up -d db`

Typical loop:

```bash
bundle install
docker compose up -d db
bin/setup
bin/dev
```

### Migrations

Never edit a migration file after it has been recorded as run against
any environment. Migrations are identified by timestamp, not by
content, so once a row in `schema_migrations` exists for a given
timestamp Rails will skip the file forever — leaving any subsequent
edits unapplied. The dev DB and `schema.rb` then silently disagree,
which is how three of this project's migrations ended up out of sync
with the schema dump (now backfilled idempotently in
`20260515200000_add_source_system_scoping_and_provenance.rb`).

If you need to change schema, add a new migration. If you need to
change a migration that hasn't been merged yet, roll it back first
(`bin/rails db:rollback`) so the next migrate re-applies the edited
version.

### Tests

`test/test_helper.rb` calls `parallelize(workers: 1)`. That is
deliberate: process-based parallel testing forks workers that each
open their own libpq connection, and `pg` segfaults under that
pattern on macOS arm64. The suite is fast enough single-threaded
that the speedup isn't worth the platform-specific crash. Leave the
worker count at 1 unless you've actually verified parallel safety on
the platforms we test on.

## Pull Request Guidance

- Keep pull requests focused
- Explain user-facing behavior changes clearly
- Mention schema, job, or deployment implications
- Note any provenance or trust-model implications

## AI-Assisted Contributions

AI-assisted work is welcome, but contributors are responsible for the result.

If AI tools were used, review especially for:

- fabricated assumptions
- broken source links
- mixed official/generated concerns
- accidental complexity

## Questions

If a change affects trust, provenance, or public interpretation of civic records, prefer discussing the design before implementing a large patch.
