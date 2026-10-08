// Google Analytics (GA4) bootstrap. Lives in a file rather than an inline
// <script> so it runs under the strict script-src CSP. The measurement ID comes
// from the including tag's data-measurement-id attribute.
(function () {
  "use strict";

  var script = document.currentScript;
  var measurementId = script && script.dataset.measurementId;
  if (!measurementId) return;

  window.dataLayer = window.dataLayer || [];
  function gtag() {
    window.dataLayer.push(arguments);
  }
  window.gtag = gtag;
  gtag("js", new Date());
  gtag("config", measurementId);

  var loader = document.createElement("script");
  loader.async = true;
  loader.src = "https://www.googletagmanager.com/gtag/js?id=" + encodeURIComponent(measurementId);
  document.head.appendChild(loader);
})();
