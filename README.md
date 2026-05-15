# San Jose Civic Pulse Rails App

San Jose Civic Pulse is a source-first civic information app for making San Jose City Hall materials easier to discover, understand, and verify.

This repository contains the Rails 8 application. It is being built as public-interest, open-source software with a strong emphasis on provenance, source-linking, and conservative AI-assisted summaries.

Start with [CONTEXT.md](./CONTEXT.md) for the app-focused orientation and [docs/README.md](./docs/README.md) for repository documentation.

## Status

Early scaffold. Not production-ready and not yet useful as a public-facing product.

## Stack

- Rails 8
- Postgres
- Hotwire
- Solid Queue
- Solid Cache
- Active Storage
- Kamal

## Local Setup

1. Install Ruby and Docker locally.
2. Run `bundle install`.
3. Start Postgres with `docker compose up -d db`.
4. Run `bin/setup`.
5. Start the app with `bin/dev`.

The app runs on your host machine in development. Docker is used for the local Postgres dependency, not for the default Rails development loop.

## Local Development Loop

Use this as the normal day-to-day workflow:

```bash
docker compose up -d db
bin/dev
```

In this app, `bin/dev` currently runs the Rails server directly.

Local database defaults:

- host: `127.0.0.1`
- port: `55432`
- user: `postgres`
- password: `postgres`
- database: `san_jose_civic_pulse_development`

Override them with `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`, and `TEST_DB_NAME` if needed.

A full inventory of runtime environment variables — including the
Legistar API client, attachment downloader, and Active Storage R2
settings — lives in [docs/configuration.md](./docs/configuration.md).

## Production Direction

- App deploys to a Hostinger VPS via Kamal
- Production Postgres runs off the app host
- Durable blob storage uses Cloudflare R2

## Open Source Posture

- Official public records are the primary source of truth
- Generated summaries and labels are assistive, not authoritative, and should be labeled as such
- User-facing claims should be traceable to official source material
- Contributions should preserve provenance rather than optimize for cleverness

See [CONTRIBUTING.md](./CONTRIBUTING.md) and [SECURITY.md](./SECURITY.md) before opening issues or pull requests.

## First Ingestion Slice

The app includes a minimal first slice for:

- ingesting recent Legistar events
- storing raw source snapshots
- normalizing events into `Civic::Event`
- reconciling event items and matter attachments against the latest source payloads
- importing attachment files and extracting PDF text through background jobs
- rendering ingested events on the public site

You can run the sync manually from the Rails runner:

```bash
rbenv exec ruby bin/rails runner "Ingestion::SyncRecentEvents.call"
```

That command now persists recent events and fans out downstream sync stages through jobs. For a single blocking run during local development, use:

```bash
rbenv exec ruby bin/rails runner "Ingestion::SyncRecentEvents.call(sync_event_items: :inline)"
```

## Tests

Run the Rails unit, controller, model, and service tests with:

```bash
rbenv exec ruby bin/rails test
```

Run browser-level public flow tests with:

```bash
rbenv exec ruby bin/rails test:system
```
