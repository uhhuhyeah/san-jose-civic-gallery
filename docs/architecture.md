# Architecture Summary

San Jose Civic Gallery is being built as a single Rails 8 application with a clear separation between official records, extracted artifacts, and generated artifacts.

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
`Ingestion::SourceSnapshot` is keyed the same way. Background jobs carry
`source_system` forward instead of falling back to a global default, so
deferred child syncs remain in the same source namespace as their parent
records. The schema is multi-source-capable today, but only
`legistar.sanjose` is wired in; adding another tenant or a non-Legistar
source still needs explicit client/source configuration, not a core
civic schema redesign.

## Source Payload Versions

Each normalized civic row stores a digest of the individual upstream
payload that produced that row. Collection API responses are not reused
as row-level digests, because one changed sibling item should not make
every item in the collection look like a new payload version.

`Ingestion::SourceSnapshot` stores one row per distinct payload version,
uniquely keyed by `source_system`, `resource_type`, `source_id`, and
`response_sha256`. Repeated observations atomically increment
`fetch_count` and update `last_fetched_at`, preserving the first-seen
timestamp while bounding recurring sync growth.

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

Imported attachment files are refreshed when the attachment metadata
payload changes, including cases where Legistar reports a new modified
timestamp while keeping the same hyperlink and filename. Local PDF text
extraction streams Active Storage blobs into a tempfile before invoking
`pdftotext`; when embedded text is empty, scanned-PDF fallback runs the
local `ocrmypdf` CLI and stores the sidecar text as another extracted
artifact.

Imported attachment files can also be revalidated by probing the remote
file with `HEAD`. When ETag, Last-Modified, or Content-Length indicate a
change, the app re-imports the file through the same safe downloader and
refreshes checksum metadata.

Generated attachment summaries are stored as separate `Generated::Artifact`
rows. Each artifact records its target, source extracted-text artifact,
model identifier, prompt version, input digest, generated content, and
status. This lets the app compare providers or models without changing
official or extracted records.

The Legistar API client (`Legistar::Client`) has its own bounded
timeouts and a `User-Agent` header that identifies the app and a
contact email, so Legistar can route concerns to the maintainer.

## Product Integrity Rules

- Official source material is the center of gravity
- Generated text must not overwrite official records
- User-facing summaries should be conservative
- Provenance should be explicit anywhere interpretation is involved
