# Source Data Quality Notes

Civic Gallery is source-first: official Legistar records are authoritative,
and we surface what they actually contain rather than rewriting them. That
posture works in both directions. When the source has gaps or quirks,
we document them here rather than hiding them.

Each entry below describes one observed limitation, what it means for what
appears on Civic Gallery, and why it cannot be cleanly fixed downstream.

## Budget-document attachments on www.sanjoseca.gov return 403

**Observed (2026-05-19):** 14 matter attachments in the initial 12-month
backfill have a `hyperlink` pointing at `https://www.sanjoseca.gov/...`
paths under `/your-government/.../budget-documents/...`. All 14 attempts
to import the source file fail with HTTP 403 from `AkamaiGHost`.

**What is actually wrong:**

1. The URLs themselves are CivicPlus page URLs (HTML pages that list and
   link to the actual PDFs), not direct document URLs. Even with a 200
   response, downloading these would yield HTML rather than a budget PDF.
2. The www.sanjoseca.gov hostname sits behind Akamai. Akamai's Bot
   Manager rejects requests from our origin IP (a Hostinger VPS)
   regardless of the User-Agent we send. Verified with the SanJoseCivicGallery
   identifier, a generic Safari string, and a curl string. All three get 403.

**Effect on Civic Gallery:**

- These 14 attachments stay with `source_file_import_error` set and never
  produce extracted text or generated summaries.
- They appear in the "Reliability" rate on the Data Health page as
  not-imported, which is accurate: the source file is not retrievable
  through the URL the source system provided us.
- The matter rows and attachment metadata themselves are still present
  and linkable, because that data comes from Legistar's structured fields
  rather than from the file download.

**Why we cannot fix it downstream:**

- Changing User-Agent does not help. Akamai is not relying on UA.
- Routing through a residential proxy is not warranted: even if we got
  past the WAF, the URL is an HTML page, not a downloadable document.
- The fix would have to happen upstream in Legistar, where the attachment
  row should point at a direct document URL (Legistar's own
  `sanjose.legistar.com/View.ashx?...` or the city's
  `/home/showpublisheddocument/...` pattern) rather than a CMS page.

**What we do about it:**

- Keep `www.sanjoseca.gov` in `Documents::SafeHttpClient::DEFAULT_ALLOWED_HOSTS`.
  Currently zero benefit, but if future Legistar entries attach direct
  document URLs at that host they will import without another deploy.
- Accept the failed-import state as the correct surface for these
  attachments. Do not retry them with `RETRY_ERRORS=true` unless the
  source URL has actually changed.
- When a document like this is genuinely important (the 2026-2027 Capital
  Budget being a clear example), an operator can download the PDF in a
  browser and use the manual-upload helpers described below to bring it
  into Civic Gallery. The public attachment view renders a disclosure
  banner so readers know the file arrived by an operator override
  rather than the automated importer.

## Operator helpers for manual upload

These two commands cover the full workflow for handling exceptions like
the section above.

### Find what needs intervention

```bash
# Locally in development:
bin/rails attachments:needs_manual_upload

# Against production:
kamal app exec --reuse --roles=web 'bin/rails attachments:needs_manual_upload'
```

Lists every Civic::MatterAttachment that failed the automated importer
and has not been manually uploaded yet, grouped by host so you can see
patterns at a glance. Output includes the attachment id, matter file
number, attachment name, source hyperlink, and a one-line error
summary.

### Upload a PDF for one of them

```bash
bin/manual_upload <ATTACHMENT_ID> <LOCAL_PDF_PATH> [REASON]
```

This is a laptop-side wrapper that handles the laptop-to-VPS-to-container
file shuffle and runs `attachments:manual_upload` for you. Operator
identity defaults to your `git config user.email`. Reason defaults to a
generic disclosure if you do not provide one.

What it actually does, in order: scp the PDF to the VPS, docker cp it
into the running web container, run the rake task via kamal app exec,
remove the VPS temp file. The rake task itself stamps the manual import
columns, attaches the file to source_file, and enqueues text extraction.

## How to add to this doc

When a new source-data limitation turns up, add a new `##` section with
the same shape: Observed, What is actually wrong, Effect on Civic
Gallery, Why we cannot fix it downstream, What we do about it. Keep each
entry tight enough that a reader can scan the list to find the one they
care about.
