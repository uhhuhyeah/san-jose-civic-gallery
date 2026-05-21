# Repository Docs

This repository is intentionally documented in a compact way so contributors and coding agents can orient quickly without loading large strategy documents by default.

## Start Here

- `README.md`: project overview and local setup
- `CONTEXT.md`: compact implementation context
- `architecture.md`: current architecture direction and domain boundaries
- `multi-jurisdiction.md`: how a second jurisdiction (SJUSD via Simbli) was
  added, the architectural changes, and the tradeoffs and tech debt taken on
- `schema-guide.md`: source-system and app-schema contributor guide
- `document-backfill.md`: operator workflow for importing and extracting
  historical matter attachments
- `manual-attachment-upload.md`: operator playbook for hand-uploading
  attachment PDFs the importer cannot fetch (San Jose 403s, all SJUSD files)
- `attachment-revalidation.md`: operator workflow for validating
  imported attachment files against remote source metadata
- `event-window-sync.md`: bounded event sync and missing-event
  reconciliation workflow
- `generated-summaries.md`: operator workflow for creating generated
  attachment summaries from extracted text
- `background-queues.md`: Solid Queue worker responsibilities and why
  long-running work is isolated by queue
- `source-data-quality.md`: known limitations in the upstream source data,
  what they mean for Civic Gallery, and why we cannot fix them downstream

## Documentation Principles

- Keep repo-local docs practical and implementation-oriented
- Prefer short summaries over long strategy documents
- Promote durable technical decisions into dedicated docs only when they affect implementation
- Keep product claims conservative and traceable to source material
