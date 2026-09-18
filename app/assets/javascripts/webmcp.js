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
      await document.modelContext.registerTool({
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
      }, { signal: controller.signal });

      var abort = function () { controller.abort(); };
      window.addEventListener("pagehide", abort, { once: true });
      document.addEventListener("turbo:before-cache", abort, { once: true });
    } catch (_error) {
      controller.abort();
    }
  }

  register().catch(function () {});
})();
