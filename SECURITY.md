# Security Policy

## Reporting A Vulnerability

Please do not open a public GitHub issue for security-sensitive problems.

Until a dedicated private reporting channel is set up, contact the maintainer directly and include:

- a short description of the issue
- affected area or files
- reproduction steps if available
- impact assessment if known

Examples of security-sensitive issues include:

- secret exposure
- authentication or authorization flaws
- command execution risks
- unsafe handling of uploaded or downloaded files
- SSRF or unsafe outbound fetch behavior

## Scope Notes

This project fetches public civic source material and may process external files. Please report any issue that could allow:

- unsafe file processing
- unsafe storage access
- unintended disclosure of credentials
- abuse of background job execution

## Existing Outbound-Fetch Controls

Attachment downloads run through `Documents::SafeDownloader`, which is
the only outbound-fetch path for arbitrary URLs supplied by Legistar.
It enforces:

- HTTPS-only (env override available for local dev only)
- a host allowlist re-checked on every redirect
  (default `sanjose.legistar.com`, configurable via
  `LEGISTAR_ATTACHMENT_ALLOWED_HOSTS`)
- bounded open and read timeouts
- a redirect cap (three)
- a configurable body-size ceiling
  (default 100 MB via `LEGISTAR_ATTACHMENT_MAX_BYTES`)
- streaming to a tempfile rather than buffering full responses in memory

Reports of bypasses for any of those controls — or for SSRF affecting
other outbound paths in the codebase — are in scope.

The Legistar API client (`Legistar::Client`) has its own timeouts and a
`User-Agent` that identifies the app to Legistar operators.

## Response Posture

Security reports will be triaged privately first. Public disclosure should wait until the issue is understood and a fix or mitigation is available.
