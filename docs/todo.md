# TODO

## Performance

- `Ingestion::SyncEventItemsForEvent` now deduplicates linked matter
  IDs and skips matter refresh fan-out when the local `Civic::Matter`
  was synced recently enough.
  - Current default: linked matters are considered fresh for 12 hours.
  - Follow-up: tune the freshness window once production sync cadence
    and Legistar update frequency are clearer.

- The matching DB-level N+1 in `Ingestion::SyncMatter.link_event_items!`
  is **fixed**. The query is now scoped by `(source_system, matter_id)`
  with a composite index, so each Matter sync does one bounded
  `UPDATE`.

## Ingestion completeness

- Event-level retraction reconciliation is not yet driven by sync.
  `civic_events.source_present` / `source_missing_at` columns exist
  but stay `true`, because `recent_events` is a sliding `$top` window
  and naive reconciliation would mark every older event as missing.

- Extracted text uses local `pdftotext` first and falls back to local
  `ocrmypdf` for scanned PDFs when embedded text is empty.

- Imported attachment files are refreshed when Legistar attachment
  metadata changes. A future reconciliation pass may still add stronger
  remote file validation, such as conditional requests or periodic
  checksum revalidation for files whose metadata has not changed.

## Operational Backfill

- Document backfill will be needed once the app goes live or ingests a
  larger historical window.
  - Likely shape: a resumable task that finds attachments without an
    imported source file, imports them in bounded batches, then enqueues
    extraction/OCR for imported PDFs without current successful text.
  - Requirements: rate limits, idempotency, progress logging, retry
    visibility, and controls for date/body/matter-file slices.
  - Keep this separate from request-time public UI work; backfill should
    run as an operator workflow over the existing ingestion services.
