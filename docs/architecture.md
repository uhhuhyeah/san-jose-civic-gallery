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

## Product Integrity Rules

- Official source material is the center of gravity
- Generated text must not overwrite official records
- User-facing summaries should be conservative
- Provenance should be explicit anywhere interpretation is involved
