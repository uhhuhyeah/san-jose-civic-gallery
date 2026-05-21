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

## Discovery

- Google Search Console is set up under a single **Domain property for
  the apex `civicgallery.org`**, which covers both the `sanjose.` and
  `sjusd.` subdomains. Verified via the **Domain name provider (DNS TXT)**
  method (`google-site-verification=` record on the apex).
  - Do **not** delete that TXT record in Cloudflare DNS, or verification
    is lost.
  - Both host-scoped sitemaps are submitted under this apex property (a
    Domain property accepts sitemaps from any subdomain under it):
    - `https://sanjose.civicgallery.org/sitemap.xml`
    - `https://sjusd.civicgallery.org/sitemap.xml`
  - Reporting is combined across both subdomains under the apex property.
    If per-jurisdiction reporting is wanted later, add URL-prefix
    properties for each subdomain (`https://sanjose.civicgallery.org/`
    and `https://sjusd.civicgallery.org/`); they auto-verify under the
    verified apex domain with no further DNS work.
  - Cleanup: any stray `sanjose.civicgallery.org` Domain property or
    standalone `https://sanjose.civicgallery.org/` URL-prefix property
    created during setup are redundant with the apex property and can be
    removed to avoid "which property?" confusion.
