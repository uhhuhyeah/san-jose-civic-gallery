# WebMCP

Civic Gallery has an optional browser-native WebMCP enhancement on public HTML
pages. A compatible browser may discover the current page's
`civicgallery_get_page_context` and `search_matters` tools through
`document.modelContext`; an unsupported browser simply skips registration and
renders the normal site. WebMCP requires a browser-supported secure context
such as HTTPS.

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

## Manual verification

1. Open HTTPS public pages on San José and SJUSD hosts in a browser with native
   WebMCP support.
2. Discover and invoke `civicgallery_get_page_context`; verify the page URL,
   host jurisdiction, source system, discovery links, and capability list.
3. Invoke `search_matters` with a keyword query and a document-text query;
   verify host scoping, result bounds, match provenance, Civic Gallery links,
   and zero-result behavior.
4. Open the same pages in an unsupported browser and verify normal navigation,
   search, keyboard, and screen-reader behavior with no visible dependency.
5. Verify `/up`, `/jobs`, and development pages contain neither the context
   JSON nor a registered tool.
