# Repository Guidelines

## Project Structure & Module Organization

This is a Rails 8 application for source-first San Jose civic records. Core app code lives in `app/`: public controllers under `app/controllers/public`, domain models under `app/models/civic`, ingestion records under `app/models/ingestion`, and service objects under `app/services/{ingestion,documents,legistar}`. Background jobs live in `app/jobs`. Views are in `app/views/public`. Assets are minimal and live in `app/assets` and `public`.

Tests mirror app structure under `test/`, especially `test/services`, `test/models`, `test/controllers`, `test/jobs`, and `test/system`. Migrations and schema live in `db/`. Project context is in `CONTEXT.md` and `docs/`.

## Build, Test, and Development Commands

- `bundle install`: install Ruby dependencies.
- `docker compose up -d db`: start the local Postgres dependency.
- `bin/setup`: install dependencies, prepare the database, clear logs/temp files, and start the server unless `--skip-server` is passed.
- `bin/dev`: run the Rails development server.
- `bin/rails db:migrate`: apply new migrations.
- `bin/rails test`: run unit, model, controller, job, and service tests.
- `bin/rails test:system`: run browser-level system tests.
- `bin/rubocop`: run Rails Omakase Ruby style checks.
- `bin/ci`: run setup, style, security audits, tests, and seed checks.

## Coding Style & Naming Conventions

Follow standard Rails conventions and the configured `rubocop-rails-omakase` style. Use two-space indentation for Ruby. Name service objects as verb-oriented classes, for example `Ingestion::SyncMatterAttachments`, and place them in matching namespace paths. Keep official source data, normalized records, and generated/derived content clearly separated.

## Testing Guidelines

Use Rails Minitest. Place tests in the matching `test/...` directory and name files with `_test.rb`, such as `test/services/ingestion/sync_matter_test.rb`. Add focused tests for behavior changes, ingestion edge cases, document extraction, provenance handling, and schema-backed logic. `test/test_helper.rb` intentionally keeps parallel workers at `1`; do not change that without verifying platform safety.

## Commit & Pull Request Guidelines

Recent commits use short, imperative summaries such as `Import scope fixes` and `Fix test assertion`. Keep commits focused and avoid mixing schema, UI, ingestion, and docs changes unless they are one coherent change.

Pull requests should explain user-facing behavior, link relevant issues, mention migrations/jobs/deployment implications, and call out trust or provenance effects. Include screenshots for UI changes and update docs when workflows change.

## Agent-Specific Instructions

Start with `CONTEXT.md`, `README.md`, and relevant `docs/` files before broad changes. Preserve the source-first posture: official public records are authoritative, generated summaries are assistive, and claims should remain traceable to source material. Never edit a migration that may already have run; add a new migration instead.
