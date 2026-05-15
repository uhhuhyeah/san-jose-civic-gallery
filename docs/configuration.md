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
| `DB_NAME` | `san_jose_civic_pulse_development` | |
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

## Legistar API client (`Legistar::Client`)

| Variable | Default | Notes |
| --- | --- | --- |
| `LEGISTAR_API_BASE_URL` | `https://webapi.legistar.com/v1/sanjose` | Base URL for Legistar API calls. Read per request so tests can override without re-evaluating constants. |
| `LEGISTAR_SOURCE_SYSTEM` | `legistar.sanjose` | Stamped on every civic row and snapshot this client persists. Adding another Legistar tenant means standing up another client with a different source-system value. |
| `LEGISTAR_USER_AGENT` | `SanJoseCivicPulse/1.0 (+mail@davidamcclain.com)` | Sent on every API request. Identifies the app to Legistar operators. |
| `LEGISTAR_OPEN_TIMEOUT` | `5` (seconds) | Connect timeout. |
| `LEGISTAR_READ_TIMEOUT` | `30` (seconds) | Read timeout. |

## Attachment downloader (`Documents::SafeDownloader`)

Used by `Documents::ImportMatterAttachmentFile` to fetch attachment
bytes from Legistar's file server. All defaults are deliberately
conservative for an outbound-fetch trust boundary.

| Variable | Default | Notes |
| --- | --- | --- |
| `LEGISTAR_ATTACHMENT_ALLOWED_HOSTS` | `sanjose.legistar.com` | Comma-separated allowlist. The host is re-checked on every redirect. |
| `LEGISTAR_ATTACHMENT_ALLOW_HTTP` | unset | Set to `"true"` to allow plain HTTP. HTTPS only by default. |
| `LEGISTAR_ATTACHMENT_MAX_BYTES` | `104857600` (100 MB) | Hard cap on response body size. Both the `Content-Length` header and the running byte count are checked. |
| `LEGISTAR_ATTACHMENT_OPEN_TIMEOUT` | `5` (seconds) | Connect timeout. |
| `LEGISTAR_ATTACHMENT_READ_TIMEOUT` | `30` (seconds) | Read timeout. |

A redirect cap of three is enforced in code (not env-configurable).
