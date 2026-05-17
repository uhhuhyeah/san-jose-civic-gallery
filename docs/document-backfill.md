# Document Backfill

Document backfill is an operator workflow for filling gaps after a
larger ingest or before launch. It reuses the normal document pipeline:

1. enqueue imports for current matter attachments with a source link but
   no attached source file
2. enqueue text extraction/OCR for imported PDFs without successful
   extracted text

The task is idempotent and batch-oriented. Run a dry run first:

```bash
bin/rails documents:backfill
```

Enqueue jobs with:

```bash
RUN=true bin/rails documents:backfill
```

Useful filters:

```bash
LIMIT=25 bin/rails documents:backfill
MATTER_FILE=26-575 bin/rails documents:backfill
FROM_DATE=2026-05-01 TO_DATE=2026-05-31 bin/rails documents:backfill
RUN=true LIMIT=25 FROM_DATE=2026-05-01 bin/rails documents:backfill
RETRY_ERRORS=true bin/rails documents:backfill
```

Options are environment variables:

- `RUN=true`: enqueue jobs. Omit for dry-run mode.
- `LIMIT`: maximum total candidates to process. Default: `100`.
- `MATTER_FILE`: restrict to one matter file, such as `26-575`.
- `FROM_DATE` / `TO_DATE`: restrict by `Civic::Matter#agenda_date`
  using `YYYY-MM-DD`.
- `RETRY_ERRORS=true`: also re-enqueue imports that previously failed
  (`source_file_import_error` is set). Omit to skip them.

Backfill enqueues `Documents::ImportMatterAttachmentFileJob` for missing
source files. That job enqueues extraction for PDFs after import. For
PDFs already imported but lacking successful extracted text, backfill
enqueues `Documents::ExtractMatterAttachmentTextJob` directly.

By default, attachments with a prior import error are skipped to avoid
re-queueing known-bad URLs every run. Use `RETRY_ERRORS=true` after a
fix to the source URL or downloader before retrying.

Avoid running `RUN=true` concurrently with itself or another backfill
window — the underlying services are idempotent (extraction reuses by
checksum, import overwrites the attached blob), but concurrent runs
waste worker time on duplicate jobs.

Production hosts need the local extraction binaries documented in
`docs/configuration.md`: `pdftotext` and `ocrmypdf`.
