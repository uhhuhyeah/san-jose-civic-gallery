(function () {
  "use strict";

  if (window.__civicGalleryWebMcpRegistration) return;
  window.__civicGalleryWebMcpRegistration = true;

  function freeze(value) {
    if (!value || typeof value !== "object" || Object.isFrozen(value)) return value;
    Object.getOwnPropertyNames(value).forEach(function (property) {
      freeze(value[property]);
    });
    return Object.freeze(value);
  }

  function contextFromPage() {
    var element = document.getElementById("civicgallery-webmcp-context");
    if (!element) return null;

    try {
      return freeze(JSON.parse(element.textContent));
    } catch (_error) {
      return null;
    }
  }

  async function register() {
    var pageContext = contextFromPage();
    if (!pageContext) return;
    if (!document.modelContext || typeof document.modelContext.registerTool !== "function") return;

    var controller = new AbortController();
    try {
      var pageContextTool = {
        name: "civicgallery_get_page_context",
        description: "Get the current Civic Gallery public-page and jurisdiction context, available Civic Gallery agent capabilities, discovery links, and source provenance rules. This operation is read-only and never searches records.",
        inputSchema: {
          type: "object",
          properties: {},
          additionalProperties: false
        },
        annotations: {
          readOnlyHint: true,
          untrustedContentHint: false
        },
        execute: async function () {
          return pageContext;
        }
      };

      var matterSearchTool = {
        name: "search_matters",
        description: "Search public matters in the current Civic Gallery jurisdiction by keyword or natural-language query. Results are bounded and identify whether each match came from official record metadata or extracted document text. This operation is read-only and never uses semantic or embedding search.",
        inputSchema: {
          type: "object",
          properties: {
            query: {
              type: "string",
              minLength: 1,
              maxLength: 200,
              description: "Keywords or a natural-language search query for public matters."
            },
            limit: {
              type: "integer",
              minimum: 1,
              maximum: 10,
              description: "Maximum number of matters to return. Defaults to 10."
            }
          },
          required: [ "query" ],
          additionalProperties: false
        },
        annotations: {
          readOnlyHint: true,
          untrustedContentHint: false
        },
        execute: async function (input) {
          var searchUrl = sameOriginSearchUrl(pageContext);
          if (!searchUrl) throw new Error("Matter search is unavailable on this page.");

          var query = input && typeof input.query === "string" ? input.query.trim() : "";
          if (!query) throw new Error("query is required");
          if (query.length > 200) throw new Error("query must be 200 characters or fewer");

          searchUrl.searchParams.set("query", query);
          if (input && input.limit !== undefined) searchUrl.searchParams.set("limit", String(input.limit));

          var response = await fetch(searchUrl.toString(), {
            credentials: "same-origin",
            headers: { Accept: "application/json" }
          });
          var payload = await response.json();
          if (!response.ok) throw new Error(payload.error || "Matter search failed.");

          return payload;
        }
      };

      var matterDetailTool = {
        name: "get_matter_detail",
        description: "Retrieve verification-oriented public detail for one matter in the current Civic Gallery jurisdiction. Pass either the opaque matter_reference returned by search_matters or an exact same-origin Civic Gallery matter URL. This read-only operation returns record metadata, linked meeting context, official links, and document availability status; it never returns attachment text or generated summary content.",
        inputSchema: {
          type: "object",
          properties: {
            reference: {
              type: "string",
              minLength: 1,
              maxLength: 2000,
              description: "A matter_reference from search_matters or an exact same-origin Civic Gallery public matter URL."
            }
          },
          required: [ "reference" ],
          additionalProperties: false
        },
        annotations: {
          readOnlyHint: true,
          untrustedContentHint: false
        },
        execute: async function (input) {
          var detailUrl = sameOriginDetailUrl(pageContext);
          if (!detailUrl) throw new Error("Matter detail is unavailable on this page.");

          var reference = input && typeof input.reference === "string" ? input.reference.trim() : "";
          if (!reference) throw new Error("reference is required");
          if (reference.length > 2000) throw new Error("reference must be 2000 characters or fewer");

          detailUrl.searchParams.set("reference", reference);
          var response = await fetch(detailUrl.toString(), {
            credentials: "same-origin",
            headers: { Accept: "application/json" }
          });
          var payload = await response.json();
          if (!response.ok) throw new Error(payload.error || "Matter detail lookup failed.");

          return payload;
        }
      };

      // Native WebMCP may keep a registration promise pending until all tools
      // for the document have been submitted. Submit the whole capability set
      // together so a first tool cannot prevent later tools from registering.
      await Promise.all([
        document.modelContext.registerTool(pageContextTool, { signal: controller.signal }),
        document.modelContext.registerTool(matterSearchTool, { signal: controller.signal }),
        document.modelContext.registerTool(matterDetailTool, { signal: controller.signal })
      ]);

      var abort = function () { controller.abort(); };
      window.addEventListener("pagehide", abort, { once: true });
      document.addEventListener("turbo:before-cache", abort, { once: true });
    } catch (_error) {
      controller.abort();
    }
  }

  function sameOriginSearchUrl(pageContext) {
    return sameOriginEndpointUrl(pageContext, "matter_search_url");
  }

  function sameOriginDetailUrl(pageContext) {
    return sameOriginEndpointUrl(pageContext, "matter_detail_url");
  }

  function sameOriginEndpointUrl(pageContext, endpoint) {
    var value = pageContext && pageContext.endpoints && pageContext.endpoints[endpoint];
    if (!value) return null;

    try {
      var url = new URL(value, window.location.origin);
      return url.origin === window.location.origin ? url : null;
    } catch (_error) {
      return null;
    }
  }

  register().catch(function () {});
})();
