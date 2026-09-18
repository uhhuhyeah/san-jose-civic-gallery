# WebMCP

Civic Gallery has an optional browser-native WebMCP enhancement on public HTML
pages. A compatible browser may discover the current page's
`civicgallery_get_page_context`, `search_matters`, and `get_matter_detail` tools through
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
