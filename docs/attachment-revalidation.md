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
```

Options are environment variables:

- `RUN=true`: enqueue jobs. Omit for dry-run mode.
- `LIMIT`: maximum candidates to process. Default: `100`.
- `REVALIDATE_AFTER_DAYS`: only include files whose last validation is
  older than this many days. Default: `30`.

When a remote file returns `304 Not Modified` or matching metadata, the
local record is marked validated. When remote metadata differs, the file
is re-imported through `Documents::ImportMatterAttachmentFile`, which
refreshes the checksum and validation metadata.
