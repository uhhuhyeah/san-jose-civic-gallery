# TODO

## Performance

- `Ingestion::SyncEventItemsForEvent` still issues one upstream
  `Matter` HTTP fetch per linked event item.
  - Current behavior: for each `EventItem` with `EventItemMatterId`,
    the sync performs a separate Legistar API call.
  - Why it is acceptable for now: the current slice is focused on
    correctness and provenance, not throughput.
  - Likely follow-up: skip Matter fetches when the local record is
    fresh enough, batch downstream attachment/history work, or
    separate Matter refresh into its own queue.

- The matching DB-level N+1 in `Ingestion::SyncMatter.link_event_items!`
  is **fixed**. The query is now scoped by `(source_system, matter_id)`
  with a composite index, so each Matter sync does one bounded
  `UPDATE`.

## Ingestion completeness

- Event-level retraction reconciliation is not yet driven by sync.
  `civic_events.source_present` / `source_missing_at` columns exist
  but stay `true`, because `recent_events` is a sliding `$top` window
  and naive reconciliation would mark every older event as missing.

- Extracted text currently assumes a PDF with embedded text. Scanned
  PDFs and an OCR fallback are not yet handled.
