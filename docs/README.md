# Repository Docs

This repository is intentionally documented in a compact way so contributors and coding agents can orient quickly without loading large strategy documents by default.

## Start Here

- `README.md`: project overview and local setup
- `CONTEXT.md`: compact implementation context
- `architecture.md`: current architecture direction and domain boundaries
- `schema-guide.md`: source-system and app-schema contributor guide
- `document-backfill.md`: operator workflow for importing and extracting
  historical matter attachments
- `attachment-revalidation.md`: operator workflow for validating
  imported attachment files against remote source metadata
- `event-window-sync.md`: bounded event sync and missing-event
  reconciliation workflow
- `generated-summaries.md`: operator workflow for creating generated
  attachment summaries from extracted text

## Documentation Principles

- Keep repo-local docs practical and implementation-oriented
- Prefer short summaries over long strategy documents
- Promote durable technical decisions into dedicated docs only when they affect implementation
- Keep product claims conservative and traceable to source material
