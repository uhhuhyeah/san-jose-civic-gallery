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

- Extracted text uses local `pdftotext` first and falls back to local
  `ocrmypdf` for scanned PDFs when embedded text is empty.

- Imported attachment files are refreshed when Legistar attachment
  metadata changes and can be periodically revalidated against remote
  file metadata with `documents:revalidate_attachments`.

## Generated summaries

- Attachment summaries now have a generated-artifact foundation and a
  local operator task, public UI states, local model evaluation, and a
  first production-path QA pass.
  - Next: run a broader local batch once more attachments have imported
    source files and extracted text.
  - Later: compose matter-level summaries from official matter/event
    fields plus generated attachment summaries.

## Public navigation

- The dedicated `/public/meetings` browser is in place for month-based
  meeting discovery.
  - Follow-up: add richer "what changed since last sync" signals once
    production ingestion cadence is known.
