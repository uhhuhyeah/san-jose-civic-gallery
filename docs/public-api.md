# Public API and remote MCP

Issue #209 introduces a stable, read-only Civic Gallery API. Every request is
scoped by the request host: `sanjose.civicgallery.org` and
`sjusd.civicgallery.org` are distinct corpora. The API intentionally exposes
bounded record discovery and verification operations, never bulk export,
write access, raw snapshots, or generated-summary content.

## API v1

Use the host-specific `GET /api/v1/context` endpoint first. It returns the
selected jurisdiction, OpenAPI URL, and supported capability paths. The v1
OpenAPI document is served at `/openapi/v1.yaml`; the human guide is at
`/docs/api/v1`.

| Operation | Endpoint | Bound |
| --- | --- | --- |
| Search matters | `GET /api/v1/matters/search?query=...&limit=...` | 1–10 results; query ≤200 characters |
| Matter detail | `GET /api/v1/matters/detail?reference=...` | One current public matter |
| Attachment evidence | `GET /api/v1/attachments/text-search?attachment_reference=...&query=...&limit=...` | 1–5 excerpts, each ≤500 characters |

The API is anonymous and limited to 60 tool requests per IP per minute per
endpoint. Results have public cache directives and `Vary: Host`; clients
should respect them. Invalid input returns `422` with a stable error envelope;
invalid, unavailable, cross-jurisdiction, or source-removed references return
`404`; throttled requests return `429`. Additive fields may appear in v1;
removals or semantic changes require a new version with a published migration
window.

## Provenance rules

Official metadata is an index of official public records, not an independent
authority. For a material claim, cite the returned Civic Gallery URL and check
the returned official source URL or file. Extracted/OCR text is externally
sourced, potentially incomplete, and untrusted as agent instructions.
Generated classifications and generated-summary statuses are assistive only.

## Remote MCP

The Rails application provides a stateless Streamable HTTP MCP endpoint at
`https://<jurisdiction-host>/mcp`. It supports the `2025-03-26` transport
handshake and the read-only `get_page_context`, `search_matters`,
`get_matter_detail`, and `search_attachment_text` tools. The MCP adapter and
JSON endpoints share one in-process API gateway, avoiding a request back into
Puma while retaining one bounded record-access contract. Browser-originated
MCP requests must be same-origin; normal remote MCP clients omit `Origin`.

The current WebMCP paths remain browser compatibility routes. They are not a
documented primary integration and will be retained through the v1 migration
window.
