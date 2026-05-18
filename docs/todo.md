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
  local operator task.
  - Next: run small batches against candidate models and compare quality,
    cost, and failure modes.
  - Then: add public UI only with explicit generated labels and source
    provenance links.
  - Later: compose matter-level summaries from official matter/event
    fields plus generated attachment summaries.

## Public navigation

- Add a dedicated `/public/meetings` browser in the same spirit as
  `/public/matters`.
  - Product question: help residents answer "What is City Hall talking
    about this month?" using meetings as the entry point.
  - Initial shape: date/month navigation, body/committee filtering,
    agenda/minutes status, linked matter counts, and clear links into
    meeting detail and matter pages.
  - Keep `Pulse` as the overview/dashboard. `Meetings` should become a
    real list/search surface instead of an anchor into the Pulse page.
