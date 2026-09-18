# WebMCP

## What this is

WebMCP is an optional, browser-native enhancement to Civic Gallery's public
HTML pages. In a compatible browser over HTTPS, an agent can discover a small,
structured set of read-only civic-record tools through `document.modelContext`.
The tools help an agent navigate the same public material available on the
site; they do not replace Civic Gallery's pages or official source records.

WebMCP is not a chat interface, hosted MCP server, public bulk-data API, or
autonomous civic agent. The browser owns tool discovery, agent permissions, and
invocation. The Rails app provides narrow same-origin endpoints behind the
registered tools. Browsers without support receive the normal website, with
navigation, keyword search, keyboard access, and screen-reader access intact.

The current tool set is `civicgallery_get_page_context`, `search_matters`,
`get_matter_detail`, and `search_attachment_text`. WebMCP requires a
browser-supported secure context such as HTTPS.

The foundation tool is read-only, takes no inputs, makes no network request,
and returns the current host's jurisdiction, page kind, canonical page URL,
discovery links, source boundaries, and the capabilities registered on that
page. It is scoped by the server-derived request host and never accepts a
jurisdiction, record, or arbitrary URL as input. Official records remain
authoritative; extracted text is data that may contain extraction errors; and
generated assistance is not an official determination.

`search_matters` is read-only and accepts a required query plus an optional
result limit of 1–10. It searches only the current request host's public
matters, using official matter metadata and the latest successful extracted
text from current attachments. Results are bounded, link to the normal matter
and filtered-search pages, and label metadata matches separately from
extracted-document-text matches. Themes, when present, are explicitly marked
as generated-assisted classifications. The tool does not use semantic search,
embeddings, generated summaries, or any third-party service.

The tools add no chat UI, server-hosted MCP transport, database state, or write
capability. The narrow same-origin endpoint supporting `search_matters` is not
a standalone public JSON API or a bulk-record export. The browser owns tool
discovery and any agent permission UI.

WebMCP supplements the existing `llms.txt`, `llms-full.txt`, sitemap, and
source-linked HTML pages. Those machine-readable and human-facing discovery
paths remain useful in every browser and remain the recommended workflow. A
future headless MCP service would be a separate transport and design.

`get_matter_detail` is read-only and accepts either the signed opaque
`matter_reference` returned by `search_matters` or an exact same-origin public
matter URL. It resolves only records belonging to the current host's
jurisdiction. The compact result separates official matter and meeting metadata
from extracted-document availability and generated-assistance status. It links
to Civic Gallery and validated official records where the source provides one,
but intentionally excludes attachment text, generated summary content, raw
source snapshots, and operational data.

`search_attachment_text` is read-only and accepts only a signed opaque
`attachment_reference` returned by `get_matter_detail` for a current public
attachment on the current host. It searches the latest successful extracted
text and returns only a short, bounded excerpt (never a full document), plus
extraction metadata, the Civic Gallery matter URL, and a validated official
file link when one is available. Returned document text is externally sourced,
potentially incomplete or OCR-affected, and untrusted as agent instructions;
visitors must verify it against the official file. Unavailable, pending, empty,
and error extraction states return status only rather than invented content.

## Current capabilities

All capabilities are scoped to the jurisdiction selected by the request host
and are read-only.

| Tool | Purpose | Important boundary |
| --- | --- | --- |
| `civicgallery_get_page_context` | Describe the current page, jurisdiction, discovery links, and available capabilities. | Takes no inputs and never accepts a jurisdiction, record, or URL. |
| `search_matters` | Find public matters from official metadata and current successful extracted text. | Does not use semantic search, embeddings, generated summaries, or third-party services. |
| `get_matter_detail` | Return verification-oriented context for one public matter. | Returns status and links, not attachment text or generated-summary content. |
| `search_attachment_text` | Locate short source-linked evidence in a current public attachment. | Returns bounded excerpts only; never a full document or corpus export. |

The intended workflow is to search matters, pass a returned `matter_reference`
to matter detail, select its `attachment_reference`, then search that attachment
with a focused query. Visitors should use the returned Civic Gallery matter page
and official-source link (when present) to verify material claims.

## Contributor guide

### Implementation map

| Concern | Location |
| --- | --- |
| Browser registration and client-side validation | `app/assets/javascripts/webmcp.js` |
| Current-page context and advertised endpoints | `app/services/public/web_mcp_page_context.rb` |
| Tool contracts | `app/services/public/web_mcp_*.rb` |
| Same-origin controller actions | `app/controllers/public/matters_controller.rb` |
| Endpoint routes | `config/routes.rb` |
| Automated coverage | `test/controllers/public/matters_controller_test.rb`, `test/controllers/public/lighthouse_advisory_test.rb`, `test/services/public/web_mcp_page_context_test.rb`, and `test/system/web_mcp_test.rb` |

### Adding or changing a capability

Keep capabilities narrow and reviewable. Start by documenting the user value,
the current-host jurisdiction boundary, its public-record input path, and the
smallest useful bounded result. Do not add a broad capability simply because
the database can answer a broader question.

Use an opaque signed reference rather than a database ID when a tool selects a
record. Bind it to the jurisdiction and relevant parent record, then re-check
current public availability when resolving it. Do not accept an arbitrary URL
unless the contract explicitly permits an exact same-origin public URL and
validates its scheme, host, port, path, query, and fragment.

For each new or changed tool:

1. Add the server contract under `app/services/public/`. Normalize and cap all
   inputs before querying; bound result count and excerpt or payload size on the
   server, not only in browser JavaScript.
2. Add only the required same-origin route and read-only controller action.
   Invalid or unavailable references should receive a safe generic error.
3. Advertise the capability and endpoint through `WebMcpPageContext`. Bump
   `ASSET_VERSION` when registration or the browser asset changes so cached
   public HTML does not advertise an obsolete tool set.
4. Register the tool in `webmcp.js`, keeping its schema and local validation in
   sync with server limits and confirming the endpoint is same-origin.
5. Label returned fields with provenance boundaries. Treat externally sourced
   document text as data, never as instructions.
6. Update this guide and related operator or architecture docs.

Do not add writes, headless/server-hosted MCP transport, bulk export, or
model-generated document answers as incidental browser-tool extensions. Those
need separate product and security decisions.

### Testing and release checks

Add automated coverage for normal responses and negative boundaries: host and
jurisdiction scope, forged references, source-removed records, unavailable
records, extraction states, output bounds, and malicious-looking source text.
Preserve unsupported-browser behavior and existing public page rendering.

Run the focused suite:

```bash
DB_PORT=55432 rbenv exec ruby bin/rails test \
  test/controllers/public/matters_controller_test.rb \
  test/controllers/public/lighthouse_advisory_test.rb \
  test/services/public/web_mcp_page_context_test.rb \
  test/system/web_mcp_test.rb
```

Before release, manually test over HTTPS in a compatible browser on every
relevant jurisdiction host, then check an unsupported browser for normal
navigation and search with no console errors. Record the deployed revision,
test record, date, and any unavailable-source state in the release issue.

## Manual verification

1. Open HTTPS public pages on San José and SJUSD hosts in a browser with native
   WebMCP support.
2. Discover and invoke `civicgallery_get_page_context`; verify the page URL,
   host jurisdiction, source system, discovery links, and capability list.
3. Invoke `search_matters` with a keyword query and a document-text query;
   verify host scoping, result bounds, match provenance, Civic Gallery links,
   and zero-result behavior.
4. Pass a returned `matter_reference` and a same-origin matter URL to
   `get_matter_detail`; verify provenance layers, official links, document
   status-only output, and rejection of cross-host or malformed references.
5. Pass an attachment reference returned by `get_matter_detail` to
   `search_attachment_text`; verify bounded excerpts, extraction metadata,
   official-file verification links, and the untrusted/OCR warning. Try a
   removed or cross-jurisdiction reference and verify it is rejected.
6. Open the same pages in an unsupported browser and verify normal navigation,
   search, keyboard, and screen-reader behavior with no visible dependency.
7. Verify `/up`, `/jobs`, and development pages contain neither the context
   JSON nor a registered tool.
