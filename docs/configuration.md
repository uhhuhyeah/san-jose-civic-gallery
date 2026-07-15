# Configuration

All runtime knobs are read from environment variables. Defaults are
sane for local development against San Jose Legistar; production
deployments may override any of them.

## Database

| Variable | Default | Notes |
| --- | --- | --- |
| `DB_HOST` | `127.0.0.1` | Postgres host |
| `DB_PORT` | `55432` | Postgres port |
| `DB_USER` | `postgres` | |
| `DB_PASSWORD` | `postgres` | |
| `DB_NAME` | `san_jose_civic_gallery_development` | |
| `TEST_DB_NAME` | (Rails default) | Overrides test database name |

## Active Storage (R2 in non-local environments)

| Variable | Notes |
| --- | --- |
| `AWS_ACCESS_KEY_ID` | R2 access key |
| `AWS_SECRET_ACCESS_KEY` | R2 secret |
| `AWS_REGION` | Defaults to `auto` for R2 |
| `AWS_BUCKET` | R2 bucket name |
| `AWS_ENDPOINT_URL_S3` | R2 endpoint |

Local development uses the on-disk `local` service in `config/storage.yml`.

## Error monitoring (Sentry)

| Variable | Notes |
| --- | --- |
| `SENTRY_DSN` | Sentry project DSN. In production this is supplied through Kamal secrets. Leave unset to disable event delivery in local development. |

## Legistar API client (`Legistar::Client`)

| Variable | Default | Notes |
| --- | --- | --- |
| `LEGISTAR_API_BASE_URL` | `https://webapi.legistar.com/v1/sanjose` | Base URL for Legistar API calls. Read per request so tests can override without re-evaluating constants. |
| `LEGISTAR_SOURCE_SYSTEM` | `legistar.sanjose` | Stamped on every civic row and snapshot this client persists. Adding another Legistar tenant means standing up another client with a different source-system value. |
| `LEGISTAR_USER_AGENT` | `SanJoseCivicGallery/1.0 (+mail@davidamcclain.com)` | Sent on every API request. Identifies the app to Legistar operators. |
| `LEGISTAR_OPEN_TIMEOUT` | `5` (seconds) | Connect timeout. |
| `LEGISTAR_READ_TIMEOUT` | `30` (seconds) | Read timeout. |

## Attachment downloader (`Documents::SafeDownloader`)

Used by `Documents::ImportMatterAttachmentFile` to fetch attachment
bytes from Legistar's file server. All defaults are deliberately
conservative for an outbound-fetch trust boundary.

| Variable | Default | Notes |
| --- | --- | --- |
| `LEGISTAR_ATTACHMENT_ALLOWED_HOSTS` | `sanjose.legistar.com,legistar.granicus.com` | Comma-separated allowlist. The host is re-checked on every redirect. |
| `LEGISTAR_ATTACHMENT_ALLOW_HTTP` | unset | Set to `"true"` to allow plain HTTP. HTTPS only by default. |
| `LEGISTAR_ATTACHMENT_MAX_BYTES` | `104857600` (100 MB) | Hard cap on response body size. Both the `Content-Length` header and the running byte count are checked. |
| `LEGISTAR_ATTACHMENT_OPEN_TIMEOUT` | `5` (seconds) | Connect timeout. |
| `LEGISTAR_ATTACHMENT_READ_TIMEOUT` | `30` (seconds) | Read timeout. |

A redirect cap of three is enforced in code (not env-configurable).

## Document extraction

Imported PDFs are first processed with the local `pdftotext` CLI. When
that returns no embedded text, the extraction pipeline falls back to
local OCR with `ocrmypdf --skip-text`, so mixed PDFs with some existing
text pages do not abort OCR for scanned pages. Both run synchronously inside the
`slow_extract` Solid Queue worker (see `config/queue.yml`) so long
OCR jobs cannot starve the default queue.

When a re-import produces a file whose SHA-256 already has a successful
prior extraction (`status: "ok"`) or a definitive OCR result
(`extractor_name: "ocrmypdf"` with `status: "empty"`), the pipeline
returns that prior row instead of re-running either tool.

| Variable | Default | Notes |
| --- | --- | --- |
| `OCR_PDF_COMMAND` | `ocrmypdf` | Command name or absolute path used for scanned-PDF OCR. The command must support `--sidecar` and `--version`. |
| `OCR_PDF_LANGUAGES` | `eng` | Passed to `ocrmypdf --language`. For San Jose civic records, `eng+spa+vie` is the recommended production value and requires the matching `tesseract-ocr-*` language packs (already installed in the production `Dockerfile`). |
| `OCR_PDF_TIMEOUT_SECONDS` | `600` | Wall-clock timeout for a single OCR run. On timeout the orchestrator sends `SIGTERM`, then `SIGKILL` after 5 seconds. |
| `PDFTOTEXT_TIMEOUT_SECONDS` | `120` | Wall-clock timeout for a single `pdftotext` run. |
