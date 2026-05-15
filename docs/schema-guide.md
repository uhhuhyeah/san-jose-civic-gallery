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
```

In the app, those concerns are intentionally split:

- `Civic::*` holds normalized official civic records
- `Ingestion::*` holds raw source snapshots and ingestion mechanics
- `Documents::*` holds extracted document artifacts
- `Generated::*` is reserved for future AI-generated outputs

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

- `legistar_event_id`
- `event_date`
- `body_name`
- `title`
- `in_site_url`
- agenda/minutes status fields

Key relationship:

- has many `Civic::EventItem`

### `civic_event_items` / `Civic::EventItem`

Normalized official agenda items within a meeting.

Key fields:

- `legistar_event_item_id`
- `civic_event_id`
- `civic_matter_id` optional
- `agenda_sequence`
- `agenda_number`
- `title`
- `matter_file`
- `matter_name`
- action/result-adjacent fields

Key relationships:

- belongs to `Civic::Event`
- optionally belongs to `Civic::Matter`

Important note:

`EventItem` is the bridge between a specific meeting and a broader legislative matter.

### `civic_matters` / `Civic::Matter`

Normalized official matter records.

Key fields:

- `legistar_matter_id`
- `matter_file`
- `title`
- `name`
- `matter_type_name`
- `matter_status_name`
- `requester`

Key relationships:

- has many `Civic::EventItem`
- has many `Civic::MatterAttachment`

Important note:

`matter_file` is usually the human-meaningful identifier contributors will recognize first.

### `civic_matter_attachments` / `Civic::MatterAttachment`

Normalized official matter attachment metadata.

Key fields:

- `legistar_matter_attachment_id`
- `civic_matter_id`
- `name`
- `hyperlink`
- `file_name`
- `sort_order`

Import-related fields:

- `source_file_imported_at`
- `source_file_checksum_sha256`
- `source_file_byte_size`
- `source_file_import_error`

Key relationships:

- belongs to `Civic::Matter`
- has one Active Storage attachment: `source_file`
- has one `Documents::ExtractedText`

Important note:

This row is attachment metadata. The actual downloaded file lives in Active Storage.

### `document_extracted_texts` / `Documents::ExtractedText`

Locally extracted text from imported files.

Key fields:

- `civic_matter_attachment_id`
- `extractor_name`
- `extractor_version`
- `status`
- `character_count`
- `content`
- `error_message`

Key relationship:

- belongs to `Civic::MatterAttachment`

Important note:

This is extracted data, not official source data. Keep it distinct from the civic tables.

### `ingestion_source_snapshots` / `Ingestion::SourceSnapshot`

Raw source payload preservation for provenance and debugging.

Key fields:

- `source_system`
- `resource_type`
- `source_id`
- `request_url`
- `http_status`
- `response_sha256`
- `payload`

Important note:

This table is the evidence trail. If normalization logic is wrong, these records let us re-check what the source actually returned.

## Relationship Summary

Core relationships:

- one `Civic::Event` has many `Civic::EventItem`
- one `Civic::Matter` has many `Civic::EventItem`
- one `Civic::Matter` has many `Civic::MatterAttachment`
- one `Civic::MatterAttachment` has one imported `source_file`
- one `Civic::MatterAttachment` has one `Documents::ExtractedText`

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

Reserved for `Generated::*`

Meaning:

- AI-produced or heuristic interpretation
- useful, but never the official record

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

## Known Limitations

- Matter sync currently does N+1 fetches from event items
- attachment import is not yet automatically triggered during metadata sync
- extracted text currently assumes a PDF and local `pdftotext`
- scanned-PDF OCR fallback does not exist yet

## Contributor Tips

- When in doubt, start from `legistar_*` IDs and `matter_file`
- Use `Ingestion::SourceSnapshot` when debugging mapper behavior
- Keep new extracted fields out of `Civic::*` unless they are truly official
- Prefer adding a new table or namespace over blurring trust boundaries
