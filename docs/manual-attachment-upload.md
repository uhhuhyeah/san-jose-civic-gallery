# Manual Attachment Upload (operator playbook)

Some attachment PDFs cannot be downloaded by the automated importer, so a human
has to fetch them in a browser and attach them by hand. Two situations:

- **San Jose (Legistar):** occasional HTTP 403 on a PDF behind Akamai/CivicPlus.
  The exception, not the rule.
- **SJUSD (Simbli):** the PDF host (Incapsula) returns 403 to the server for
  every attachment, so **all** SJUSD files are manual. Recover the ones you care
  about; you do not have to clear the whole list.

Both use the **same** two helper scripts. You do not type `scp` / `docker cp` /
`kamal` commands by hand: the scripts do the server-side shuffle for you. Work
from a spreadsheet (a CSV), not file by file.

## Prerequisites

- Run from the **laptop** that deploys this app (it has `kamal` configured and
  SSH access to the VPS). The scripts read the host from `config/deploy.yml`.
- `OPERATOR` defaults to your `git config user.email`. Override with
  `OPERATOR=...` if needed.

## The workflow (three steps)

### 1. Pull the worklist

`bin/needs_manual_upload` runs the query in production and writes a local CSV
(default `./needs_manual_upload.csv`):

```bash
# San Jose: everything whose automated import failed
bin/needs_manual_upload

# San Jose: only the HTTP 403s
STATUS=403 bin/needs_manual_upload

# SJUSD: every attachment with no stored file yet
JURISDICTION=sjusd bin/needs_manual_upload

# SJUSD, narrowed to one calendar year of meetings (the whole set is ~1,100 rows)
JURISDICTION=sjusd YEAR=2026 bin/needs_manual_upload ./sjusd-2026.csv
```

The SJUSD list is large (every attachment is fileless by design), so narrow it
by **meeting date**. `YEAR=2026` is the shortcut; `FROM_DATE` / `TO_DATE`
(`YYYY-MM-DD`, either one optional) give an open-ended range. These filter on the
date of the meeting the attachment's matter appeared on, which is the only
reliable date for SJUSD (synthetic matters carry no agenda date).

The CSV has these columns: `attachment_id`, `jurisdiction`, `source_system`,
`matter_file`, `attachment_name`, `error_status`, `error_message`, `hyperlink`,
`pdf_path`, `reason`. The last two (`pdf_path`, `reason`) come out blank, that is
where you write.

### 2. Fill in the CSV

Open it in a spreadsheet. For each row you want to handle:

1. Open the row's `hyperlink` in a browser and save the PDF (a browser works
   where the server gets a 403, that is the whole point).
2. Put the **local path** to that downloaded PDF in the `pdf_path` column.
3. Optionally write a `reason` (defaults to a generic disclosure if blank).

Leave `pdf_path` **blank** for any row you are skipping. Save the file.

### 3. Upload the batch

```bash
bin/manual_upload --csv ./needs_manual_upload.csv
```

This walks every row with a non-blank `pdf_path`, copies the PDF to the VPS and
into the running web container, attaches it, and cleans up the temp file, for
each row. It prints a running `[n/total]` and a final
`Uploaded / Skipped / Failed` summary. Rows with a blank `pdf_path`, a missing
file, or a non-PDF are skipped (and reported), not fatal.

That is it. Re-run step 1 to confirm the rows you handled have dropped off the
worklist.

## One-off (a single file, no CSV)

For a single ad-hoc upload:

```bash
bin/manual_upload <ATTACHMENT_ID> <LOCAL_PDF_PATH> ["reason"]

# example
bin/manual_upload 12345 ~/Downloads/budget.pdf "Akamai blocks the source URL"
```

It prints a `bin/rails runner` one-liner at the end to verify the attachment.

## Good to know

- **Safe to re-run.** Uploading overwrites the attached blob, so re-running a row
  is harmless. The daily re-sync only rewrites attachment *metadata*; it never
  touches a manually uploaded file, and the manual-upload stamp keeps the
  attachment off the worklist for good. The worklist also excludes anything
  already uploaded, so you will not see duplicates.
- **PDF only.** Both scripts check the content type and skip/refuse non-PDFs. If
  a source link hands you an HTML viewer page, find the real PDF first.
- **`STATUS` vs `JURISDICTION`.** `STATUS` filters the San Jose worklist by
  `error_status` (e.g. `403`, or `ERR` for the non-HTTP bucket). It does not
  apply to `JURISDICTION=sjusd`, because those PDFs were never attempted, so
  there is no recorded error to filter on. `JURISDICTION` takes precedence.
- **After upload**, text extraction is enqueued automatically, and the AI summary
  (if text extracts) follows on the normal recurring schedule. Nothing else to
  run.
- **What the scripts do under the hood** (so you can debug a failure): they read
  `servers.web.hosts` from `config/deploy.yml`, `scp` the PDF to `root@<host>`,
  `docker cp` it into the running web container, run
  `bin/rails attachments:manual_upload` via `kamal app exec --reuse --roles=web`,
  and remove the temp file. The underlying rake tasks are
  `attachments:needs_manual_upload` and `attachments:manual_upload`.

## Related

- `docs/document-backfill.md`: re-running automated import/extraction for files
  that *can* be fetched.
- `docs/multi-jurisdiction.md`: why SJUSD attachments are manual in the first
  place (the Incapsula constraint).
