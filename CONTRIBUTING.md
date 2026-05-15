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
