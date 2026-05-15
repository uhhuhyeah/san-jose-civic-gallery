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

## Response Posture

Security reports will be triaged privately first. Public disclosure should wait until the issue is understood and a fix or mitigation is available.
