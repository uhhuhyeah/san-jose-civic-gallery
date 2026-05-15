# Architecture Summary

San Jose Civic Pulse is being built as a single Rails 8 application with a clear separation between official records, extracted artifacts, and generated artifacts.

## Current Direction

- one Rails monolith
- Hotwire UI
- Postgres as canonical database
- Solid Queue for background jobs
- Solid Cache for caching
- Active Storage with Cloudflare R2 in non-local environments
- Kamal deployment to a Hostinger VPS
- production Postgres hosted separately from the app VPS

## Data Boundaries

Keep these concerns separate in both code and data modeling:

- official civic records
- raw source snapshots
- document downloads and extracted text
- generated summaries, labels, and related-item signals
- operational job and reconciliation state

## Module Direction

Planned namespaces:

- `Civic`
- `Ingestion`
- `Documents`
- `Generated`

## Source-System Dimension

Every civic row carries a `source_system` identifier (currently
`legistar.sanjose`). Uniqueness on the upstream IDs (`legistar_event_id`,
`legistar_matter_id`, etc.) is scoped by `source_system`, and
`Ingestion::SourceSnapshot` is keyed the same way. The schema is
multi-source-capable today even though only one source is wired in;
adding another Legistar tenant or a non-Legistar source is a config
change, not a schema migration.

## Outbound-Fetch Trust Boundary

All outbound HTTP fetches of attachment files go through
`Documents::SafeDownloader`. It enforces:

- HTTPS-only by default (env-overridable for local dev)
- a host allowlist re-checked on every redirect (default
  `sanjose.legistar.com`)
- open and read timeouts
- a redirect cap
- a body-size ceiling
- streaming SHA-256 computation chunk by chunk to a `Tempfile`, so
  even large attachments never sit fully in memory

The Legistar API client (`Legistar::Client`) has its own bounded
timeouts and a `User-Agent` header that identifies the app and a
contact email, so Legistar can route concerns to the maintainer.

## Product Integrity Rules

- Official source material is the center of gravity
- Generated text must not overwrite official records
- User-facing summaries should be conservative
- Provenance should be explicit anywhere interpretation is involved
