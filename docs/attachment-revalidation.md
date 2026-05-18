# Attachment Revalidation

Attachment revalidation checks imported source files against the remote
attachment URL without downloading the full file when the remote server
supports validators.

The probe uses `HEAD`, follows safe redirects, and records:

- final URL
- ETag
- Last-Modified
- Content-Length
- validation time
- validation error, when a probe fails

Run a dry run first:

```bash
bin/rails documents:revalidate_attachments
```

Enqueue revalidation jobs with:

```bash
RUN=true bin/rails documents:revalidate_attachments
```

Useful options:

```bash
LIMIT=25 bin/rails documents:revalidate_attachments
REVALIDATE_AFTER_DAYS=7 bin/rails documents:revalidate_attachments
RUN=true LIMIT=25 REVALIDATE_AFTER_DAYS=7 bin/rails documents:revalidate_attachments
RETRY_ERRORS=true bin/rails documents:revalidate_attachments
```

Options are environment variables:

- `RUN=true`: enqueue jobs. Omit for dry-run mode.
- `LIMIT`: maximum candidates to process. Default: `100`.
- `REVALIDATE_AFTER_DAYS`: only include files whose last validation is
  older than this many days. Default: `30`. Must be a non-negative
  integer; the task aborts on invalid input.
- `RETRY_ERRORS=true`: also re-enqueue attachments whose previous
  revalidation failed (`source_file_validation_error` is set). Omit to
  skip them.

## Behavior

The probe always targets the canonical `hyperlink` and lets redirects
re-resolve to the current CDN/final URL. The previously stored
`source_file_final_url` is metadata only and is not reused as a probe
target, since CDN-signed URLs can expire between runs.

When a remote file returns `304 Not Modified` or matching metadata, the
local record is marked validated. When remote metadata differs, the file
is re-imported through `Documents::ImportMatterAttachmentFile`, which
refreshes the checksum and validation metadata.

After a re-import:

- prior `extracted_texts` rows for the attachment are marked
  `superseded` so search stops returning stale content from the
  previous file version
- a fresh `ExtractMatterAttachmentTextJob` is enqueued when the new
  file is still extractable as a PDF
- a warning is logged when a previously extractable file is replaced
  by a non-PDF; no extraction is enqueued, but the superseded rows
  prevent stale results

When the remote server provides no comparable validators (no ETag,
Last-Modified, or Content-Length on either side), the file is treated
as unchanged and marked validated without a download. To force a
re-import in that case, clear `source_file_validated_at` for the
affected rows.

Failed revalidations record the error on
`civic_matter_attachments.source_file_validation_error` and are
excluded from subsequent runs by default. Re-include them with
`RETRY_ERRORS=true` after fixing the underlying problem (URL change,
allowlist, etc.).

Avoid running `RUN=true` concurrently with itself — the underlying
services are idempotent, but concurrent runs waste worker time on
duplicate jobs.
