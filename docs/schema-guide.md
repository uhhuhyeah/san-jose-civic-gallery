# Schema Guide

This guide is for contributors working on the current ingestion spine.

It explains:

- the main San Jose Legistar source concepts
- the current application-side schema and model boundaries
- the most important relationships
- the intended meaning of "official", "extracted", and "generated"

## Mental Model

The pipeline currently looks like this:

```text
Legistar Event
  -> EventItems
    -> Matter
      -> MatterAttachments
        -> imported file
          -> extracted text

Every civic row above also points back at the
Ingestion::SourceSnapshot that produced it.
```

In the app, those concerns are intentionally split:

- `Civic::*` holds normalized official civic records
- `Ingestion::*` holds raw source snapshots and ingestion mechanics
- `Documents::*` holds extracted document artifacts
- `Generated::*` is reserved for future AI-generated outputs

Every civic row carries a `source_system` (currently `legistar.sanjose`)
so the schema is ready for additional sources without ID collisions.

## Source Concepts

These are the main San Jose / Legistar concepts currently modeled.

### Event

A meeting.

Examples:

- a City Council meeting
- a budget study session
- a committee meeting

Important source fields:

- `EventId`
- `EventDate`
- `EventBodyName`
- `EventTitle`
- `EventInSiteURL`
- agenda/minutes status fields

### EventItem

An agenda line item within a meeting.

Examples:

- public comment section
- a consent agenda item
- a substantive policy item

Important source fields:

- `EventItemId`
- `EventItemEventId`
- `EventItemAgendaSequence`
- `EventItemAgendaNumber`
- `EventItemTitle`
- `EventItemMatterId`
- action and vote-adjacent fields when present

### Matter

A legislative file or matter referenced by an event item.

This is often the durable civic object you actually care about across meetings.

Examples:

- `26-575`
- `26-587`
- `26-602`

Important source fields:

- `MatterId`
- `MatterFile`
- `MatterTitle`
- `MatterTypeName`
- `MatterStatusName`
- `MatterBodyName`

### MatterAttachment

A document attached to a matter.

Examples:

- memorandum
- agreement
- presentation
- resolution attachment

Important source fields:

- `MatterAttachmentId`
- `MatterAttachmentName`
- `MatterAttachmentHyperlink`
- `MatterAttachmentFileName`
- sort/display flags

## Application Schema

### `civic_events` / `Civic::Event`

Normalized official meeting records.

Key fields:

- `source_system` (e.g. `legistar.sanjose`)
- `legistar_event_id` (unique per `source_system`)
- `event_date`
- `body_name`
- `title`
- `in_site_url`
- `source_present` / `source_missing_at` (columns exist; not yet driven by sync — see note below)
- `last_source_snapshot_id` (FK to the `Ingestion::SourceSnapshot` that produced this row)
- agenda/minutes status fields

Key relationships:

- has many `Civic::EventItem`
- belongs to `Ingestion::SourceSnapshot` via `last_source_snapshot_id`

Important note:

The default recent sync only fetches a sliding `$top` window of recent
events and does not mark older events missing. Use bounded event window
sync for retraction reconciliation: it fetches an explicit body/date
window and only marks local events missing inside that same window.

### `civic_event_items` / `Civic::EventItem`

Normalized official agenda items within a meeting.

Key fields:

- `source_system`
- `legistar_event_item_id` (unique per `source_system`)
- `civic_event_id`
- `civic_matter_id` optional — populated when the linked `Civic::Matter` exists locally
- `matter_id` — the upstream Legistar matter id, indexed jointly with `source_system` so `SyncMatter` can back-link items in O(log n)
- `source_present`
- `source_missing_at`
- `last_source_snapshot_id` (FK to `Ingestion::SourceSnapshot`)
- `agenda_sequence`
- `agenda_number`
- `title`
- `matter_file`
- `matter_name`
- action/result-adjacent fields

Key relationships:

- belongs to `Civic::Event`
- optionally belongs to `Civic::Matter`
- belongs to `Ingestion::SourceSnapshot` via `last_source_snapshot_id`

Important note:

`EventItem` is the bridge between a specific meeting and a broader legislative matter.
Rows are retained for provenance, but normal application reads should treat `source_present = true` as the current source-backed set. Items can land before their linked matter is synced; the matter sync job back-fills `civic_matter_id` once the matter record exists.

### `civic_matters` / `Civic::Matter`

Normalized official matter records.

Key fields:

- `source_system`
- `legistar_matter_id` (unique per `source_system`)
- `matter_file`
- `title`
- `name`
- `matter_type_name`
- `matter_status_name`
- `requester`
- `last_source_snapshot_id` (FK to `Ingestion::SourceSnapshot`)

Key relationships:

- has many `Civic::EventItem`
- has many `Civic::MatterAttachment`
- belongs to `Ingestion::SourceSnapshot` via `last_source_snapshot_id`

Important note:

`matter_file` is usually the human-meaningful identifier contributors will recognize first.

### `civic_matter_attachments` / `Civic::MatterAttachment`

Normalized official matter attachment metadata.

Key fields:

- `source_system`
- `legistar_matter_attachment_id` (unique per `source_system`)
- `civic_matter_id`
- `name`
- `hyperlink`
- `file_name`
- `sort_order`
- `source_present`
- `source_missing_at`
- `last_source_snapshot_id` (FK to `Ingestion::SourceSnapshot`)

Import-related fields:

- `source_file_imported_at`
- `source_file_checksum_sha256`
- `source_file_byte_size`
- `source_file_import_error`

Key relationships:

- belongs to `Civic::Matter`
- has one Active Storage attachment: `source_file`
- has many `Documents::ExtractedText` (append-only history; `latest_extracted_text` is the convenience reader)
- belongs to `Ingestion::SourceSnapshot` via `last_source_snapshot_id`

Important note:

This row is attachment metadata. The actual downloaded file lives in Active Storage. Outbound fetches of the `hyperlink` go through `Documents::SafeDownloader`, which enforces an HTTPS-only host allowlist, timeouts, a redirect cap, and a body-size ceiling.

Like event items, attachments can be marked missing from the latest upstream payload without deleting the historical row.

### `document_extracted_texts` / `Documents::ExtractedText`

Locally extracted text from imported files.

Key fields:

- `civic_matter_attachment_id`
- `extractor_name`
- `extractor_version`
- `source_file_checksum_sha256`
- `status`
- `character_count`
- `content`
- `error_message`

Key relationship:

- belongs to `Civic::MatterAttachment`

Important note:

This table is append-only. Each extraction attempt produces a new artifact row so extractor changes and retries can be audited over time. `pdftotext` rows come from embedded PDF text; `ocrmypdf` rows come from scanned-PDF OCR fallback. This is extracted data, not official source data — keep it distinct from the civic tables.

### `generated_artifacts` / `Generated::Artifact`

AI-produced or heuristic generated content.

Key fields:

- `target_type` / `target_id` — the official or app record being
  described, initially `Civic::MatterAttachment`
- `source_artifact_type` / `source_artifact_id` — the extracted artifact
  used as input, initially `Documents::ExtractedText`
- `kind` — generated artifact type, for example `attachment_summary`
- `status`
- `model_identifier`
- `prompt_version`
- `input_sha256`
- `content` (jsonb)
- `input_metadata` (jsonb)
- `generated_at`
- `error_message`

Important note:

Generated artifacts are separate from both official civic records and
extracted document artifacts. They are idempotent by target, kind, model
identifier, prompt version, and input digest so a changed model, prompt,
or source input can produce a new auditable artifact without overwriting
prior results.

### `ingestion_source_snapshots` / `Ingestion::SourceSnapshot`

Raw source payload preservation for provenance and debugging. **One row per distinct payload version** for a given identity, not one row per fetch.

Identity fields:

- `source_system`
- `resource_type`
- `source_id`

Payload + provenance:

- `request_url`
- `http_status`
- `response_sha256` — SHA-256 of the individual source payload after
  canonical key ordering; drives the dedup decision
- `payload` (jsonb)

Fetch history fields:

- `fetched_at` — when this version was *first* observed (immutable)
- `last_fetched_at` — when this version was *most recently* observed
- `fetch_count` — how many times we've fetched this exact `response_sha256`

Important note:

`Ingestion::RecordSourceSnapshot` relies on a unique database index over
`source_system`, `resource_type`, `source_id`, and `response_sha256`.
If the incoming payload version already exists, it atomically bumps
`last_fetched_at` and `fetch_count` on that row. Only a genuinely new
payload version inserts a new row.

That keeps the evidence trail intact (every distinct payload version is still preserved) while bounding growth under recurring sync schedules. If normalization logic is ever wrong, these records still let us re-check what the source actually returned and when.

Collection endpoints such as `Events/:id/EventItems` and
`Matters/:id/Attachments` are split into individual source payloads
before persistence. A changed sibling item or a different collection
order should not change the digest for an unchanged row.

## Relationship Summary

Core relationships:

- one `Civic::Event` has many `Civic::EventItem`
- one `Civic::Matter` has many `Civic::EventItem`
- one `Civic::Matter` has many `Civic::MatterAttachment`
- one `Civic::MatterAttachment` has one imported `source_file`
- one `Civic::MatterAttachment` has many `Documents::ExtractedText` (append-only)
- every civic row references its `Ingestion::SourceSnapshot` via `last_source_snapshot_id`

Important consequence:

An event item is meeting-specific.

A matter is cross-meeting.

An attachment belongs to a matter, not directly to an event.

## Official vs Extracted vs Generated

### Official

Stored in `Civic::*`

Meaning:

- values directly represented in the source system
- normalized for application use
- still treated as official records

Examples:

- event date
- agenda item title
- matter file number
- attachment hyperlink

### Extracted

Stored in `Documents::*`

Meaning:

- values derived from official documents by local extraction
- still traceable to a source file
- not to be treated as official fields

Examples:

- plain text extracted from a PDF
- future extracted fiscal amounts or addresses

### Generated

Stored in `Generated::*`

Meaning:

- AI-produced or heuristic interpretation
- useful, but never the official record
- traceable to the source artifact and model configuration that produced
  it

Examples:

- summaries
- topics
- related-item suggestions

## Current Ingestion Flow

Today’s flow is:

1. sync recent events
2. sync event items for each event
3. sync linked matters for items with `EventItemMatterId`
4. sync matter attachments for each linked matter
5. import attachment files into Active Storage
6. extract text from imported PDFs with `pdftotext`
7. fall back to local OCR with `ocrmypdf` when embedded text is empty

Deferred jobs pass `source_system` through the pipeline. A matter sync
enqueued from a San Jose event item therefore writes San Jose matter
rows even if another source is configured later.

Attachment files are imported when first seen and re-imported when the
attachment metadata payload changes. This catches upstream file refreshes
that preserve the same hyperlink and filename but expose a new source
modified timestamp or other metadata.

### Eventual consistency between event items and matters

Stages 2 and 3 are decoupled via the job queue. An `EventItem` is persisted
with `civic_matter_id: nil` whenever its upstream `EventItemMatterId` has
not been synced into `Civic::Matter` yet; `Ingestion::SyncMatter` back-fills
the FK once the matter job runs.

When an event item references a matter that already exists locally,
`Ingestion::SyncEventItemsForEvent` links the item immediately and only
fans out a matter refresh if the local matter is missing or older than
the configured freshness window. The default window is 12 hours; passing
`matter_refresh_after: nil` preserves always-refresh behavior for
manual or diagnostic runs.

This means the public event page can render between stages 2 and 3 with
items that have `matter_id` (the upstream legistar id) but no
`civic_matter` row. The view renders a "Linked matter sync pending" hint
in that window rather than silently hiding attachments.

## Known Limitations

- `Ingestion::SyncEventItemsForEvent` still issues one upstream `Matter`
  HTTP fetch per linked event item (HTTP-level N+1). The downstream
  `SyncMatter.link_event_items!` DB query is now indexed and is no
  longer a separate N+1.
- Event-level retraction reconciliation is not yet wired up — the
  columns exist on `civic_events` but sync doesn't drive them, since
  `recent_events` is a sliding window.
- Extracted text uses local CLI tools (`pdftotext`, then `ocrmypdf` for
  scanned-PDF fallback). Production hosts need those binaries installed.

## Contributor Tips

- When in doubt, start from `legistar_*` IDs and `matter_file`
- Use `Ingestion::SourceSnapshot` when debugging mapper behavior
- Keep new extracted fields out of `Civic::*` unless they are truly official
- Prefer adding a new table or namespace over blurring trust boundaries
