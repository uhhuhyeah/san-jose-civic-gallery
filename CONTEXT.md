# App Context

This directory is the Rails 8 application for San Jose Civic Pulse.

## First-Read Guidance

For most implementation tasks, start here rather than loading large strategy documents.

Then open:

1. `README.md`
2. relevant files in `config/`
3. `docs/README.md`
4. focused implementation files

## App Priorities

- Keep one Rails monolith
- Prefer Rails defaults before adding infrastructure
- Preserve clear boundaries between official, extracted, and generated data
- Keep ingestion idempotent and provenance-preserving
- Use Hotwire for the primary UI

## Current Infra Assumptions

- Postgres is the canonical database
- Solid Queue handles background jobs
- Solid Cache handles caching
- Active Storage uses Cloudflare R2 in non-local environments
- Kamal deploys the app to a Hostinger VPS
- Production Postgres lives off the app box

## Directory Intent

As the app grows, keep practical implementation docs in this repository so the codebase stays understandable on its own.
