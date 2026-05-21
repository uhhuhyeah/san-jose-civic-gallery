# Lighthouse Advisory

Status: Draft advisory
Date: 2026-05-19
Reviewed URL: https://sanjose.civicgallery.org/
Shared report: https://pagespeed.web.dev/analysis/https-sanjose-civicgallery-org/hojqbeeogy

## Executive Summary

The PageSpeed/Lighthouse report is strong. The homepage scored 100 for
Performance on both mobile and desktop in the shared report. The remaining
issues are not heavy-asset problems; they are mostly document hygiene and cache
policy issues:

- Accessibility score: 89
- Best Practices score: 100
- Performance score: 100
- SEO score: 82

The most important fixes:

1. Add `lang="en"` to the root `<html>` element.
2. Add a useful meta description to the layout, with per-page overrides.
3. Fix low-contrast gold pill labels.
4. Decide whether Cloudflare's managed `Content-Signal` robots.txt directive is
   worth the Lighthouse SEO penalty.
5. Stop emitting anonymous session cookies on public read-only GET pages, then
   add public cache headers for selected pages.

The last item is not hurting the Lighthouse performance score today, but it is
the biggest operational performance issue: Cloudflare is proxying the site, but
HTML is currently marked private and `cf-cache-status` is `DYNAMIC`, so traffic
spikes still reach Rails.

## Measurement Notes

I reviewed the supplied PageSpeed report and extracted its embedded Lighthouse
13.0.1 results.

The public PageSpeed Insights API could not be used directly from this
environment because Google returned a quota error for the unauthenticated API
project:

```text
429 RESOURCE_EXHAUSTED: Quota exceeded for quota metric 'Queries'
```

I also inspected live response headers with `curl` against:

- `https://sanjose.civicgallery.org/`
- `https://sanjose.civicgallery.org/data`
- `https://sanjose.civicgallery.org/public/meetings`
- `https://sanjose.civicgallery.org/assets/application-38ca4e2e.css`
- `https://sanjose.civicgallery.org/icon.svg`
- `https://sanjose.civicgallery.org/robots.txt`

## Lighthouse Findings

### Mobile

Report timestamp: `2026-05-19T15:54:09.727Z`

| Category | Score |
| --- | ---: |
| Performance | 100 |
| Accessibility | 89 |
| Best Practices | 100 |
| SEO | 82 |

| Metric | Value |
| --- | ---: |
| First Contentful Paint | 0.8 s |
| Largest Contentful Paint | 1.5 s |
| Speed Index | 1.8 s |
| Total Blocking Time | 0 ms |
| Cumulative Layout Shift | 0 |
| Initial server response | Root document took 0 ms |

### Desktop

Report timestamp: `2026-05-19T15:54:08.397Z`

| Category | Score |
| --- | ---: |
| Performance | 100 |
| Accessibility | 89 |
| Best Practices | 100 |
| SEO | 82 |

| Metric | Value |
| --- | ---: |
| First Contentful Paint | 0.2 s |
| Largest Contentful Paint | 0.4 s |
| Speed Index | 0.8 s |
| Total Blocking Time | 0 ms |
| Cumulative Layout Shift | 0 |
| Initial server response | Root document took 0 ms |

### Flagged Audits

| Area | Finding | Details |
| --- | --- | --- |
| Accessibility | Missing document language | `<html>` has no `lang` attribute. |
| Accessibility | Insufficient contrast | Gold pill labels reported at 3.44:1 contrast. |
| SEO | Missing meta description | The document has no meta description. |
| SEO | Invalid `robots.txt` | Lighthouse reports `Content-Signal: search=yes,ai-train=no` as an unknown directive. |
| Performance | Cache lifetime opportunity | Estimated 5 KiB savings from Cloudflare's beacon script. |

## Live Header Findings

### Public HTML Is Not Edge-Cacheable

Homepage response headers observed on 2026-05-19:

```text
cache-control: max-age=0, private, must-revalidate
set-cookie: _san_jose_civic_gallery_session=...
cf-cache-status: DYNAMIC
x-runtime: 0.546318
```

`/public/meetings` was similar:

```text
cache-control: max-age=0, private, must-revalidate
set-cookie: _san_jose_civic_gallery_session=...
cf-cache-status: DYNAMIC
x-runtime: 1.722046
```

`/data` is marked public by `fresh_when`, but still emits a session cookie and
is not cached by Cloudflare:

```text
cache-control: public
set-cookie: _san_jose_civic_gallery_session=...
cf-cache-status: DYNAMIC
x-runtime: 2.434490
```

This confirms the earlier caching concern: Cloudflare is in front, but public
HTML requests are still reaching Rails.

### Static Assets Are Good

The fingerprinted CSS asset is cached correctly:

```text
cache-control: public, max-age=31556952
cf-cache-status: HIT
```

The SVG icon is also cached correctly:

```text
cache-control: public, max-age=31556952
cf-cache-status: HIT
```

Do not spend time on asset caching right now.

## Recommendations

### 1. Add `lang="en"` To The HTML Element

Priority: High
Effort: Very small
Expected impact: Accessibility score improvement

Current layout:

```erb
<html>
```

Recommended:

```erb
<html lang="en">
```

This is a straightforward fix in `app/views/layouts/application.html.erb`.

Reference:

- MDN notes that a valid `lang` on `<html>` helps screen readers determine the
  language to announce.

## 2. Add Meta Descriptions

Priority: High
Effort: Small
Expected impact: SEO score improvement and better search snippets

Current layout has a title but no description. Add a default meta description
and allow page-level overrides via `content_for`.

Suggested default:

```text
San Jose Civic Gallery helps residents browse San Jose City Hall agendas,
matters, attachments, minutes, extracted document text, and official source
links.
```

Implementation shape:

```erb
<meta name="description" content="<%= content_for(:description) || default_description %>">
```

Then set route-specific descriptions for:

- homepage
- matters index
- meetings index
- glossary
- data health

Reference:

- Chrome Lighthouse flags missing meta descriptions because search engines may
  use them in search result snippets.

## 3. Fix Gold Pill Contrast

Priority: High
Effort: Small
Expected impact: Accessibility score improvement

Lighthouse found insufficient contrast for gold pill labels:

```css
foreground: #b7791f
background: #fff8eb
contrast: 3.44:1
```

Affected examples in the report included labels such as:

- `Agenda Ready`
- `Review Draft Agenda`
- `Rules Committee Reviews, Recommendations, and Approvals`

Recommendation:

- Darken `--gold` enough to pass WCAG AA contrast for normal text on `#fff8eb`.
- Keep the warm background if desired, but make the text darker.

For example, test a replacement around:

```css
--gold: #75520b;
```

Then re-run Lighthouse. The exact target should be validated with an automated
contrast check or Lighthouse.

## 4. Decide What To Do With Cloudflare Managed `robots.txt`

Priority: Medium
Effort: Small operational decision
Expected impact: SEO score improvement if changed

The app serves a valid host-scoped `/robots.txt`, but the live response may
still be augmented by Cloudflare Managed Content:

```text
User-agent: *
Content-Signal: search=yes,ai-train=no
Allow: /
```

Lighthouse reports:

```text
robots.txt is not valid
Unknown directive: Content-Signal
```

This appears to come from Cloudflare's managed AI crawl-control feature, not the
Rails app. The standard bot-specific `User-agent` / `Disallow` rules that
Cloudflare adds are valid; the `Content-Signal` line is what Lighthouse rejects.

Recommendation:

- If SEO score cleanliness matters more than that specific machine-readable
  content signal, disable the Cloudflare managed `Content-Signal` injection and
  keep only standard directives such as `User-agent`, `Allow`, `Disallow`, and
  `Sitemap`.
- If the AI crawl-control signal is intentional and valuable, accept the
  Lighthouse SEO penalty and document the tradeoff.

Reference:

- Chrome's Lighthouse robots.txt audit lists `Unknown directive` as a common
  invalid robots.txt error.

## 5. Make Public GET Pages Truly Anonymous

Priority: High for traffic resilience
Effort: Medium
Expected impact: Cloudflare can cache public HTML; fewer Rails hits during
traffic spikes

The app emits `_san_jose_civic_gallery_session` cookies on public read-only
pages. That makes responses private and prevents Cloudflare from caching them as
anonymous HTML.

Likely cause:

- The application layout emits `csrf_meta_tags`.
- Public pages currently use only GET forms, so they do not need CSRF meta tags.
- Generating the CSRF token can initialize a session.

Recommendation:

1. Add a public read-only layout or helper that omits `csrf_meta_tags` for
   anonymous public GET pages.
2. Confirm that GET-only public pages no longer emit `Set-Cookie`.
3. Add route-specific `fresh_when`, `expires_in`, or explicit headers.
4. Then enable narrow Cloudflare Cache Rules for safe anonymous routes.

Initial target routes:

- `/`
- `/data`
- `/glossary`
- `/public/events/:id`
- `/public/matters/:id`

Use the existing `docs/caching-plan.md` as the broader implementation plan.

## 6. Add Public Cache Headers Before Cloudflare HTML Rules

Priority: High for traffic resilience
Effort: Medium

Do not start with a broad Cloudflare "cache everything" rule. First make Rails
send intentional headers for pages that are safe to cache.

Suggested shape:

```text
Cache-Control: public, max-age=60, s-maxage=7200, stale-while-revalidate=60
ETag: ...
```

Cloudflare Free plan has a minimum Edge Cache TTL of 2 hours for cache rules, so
this should be applied only to pages where that staleness is acceptable or where
manual purge is operationally clear.

## 7. Do Not Chase The Cloudflare Beacon Cache Warning

Priority: Low
Effort: None unless policy changes

The only Lighthouse performance opportunity was:

```text
Use efficient cache lifetimes
Estimated savings: 5 KiB
Resource: static.cloudflareinsights.com/beacon.min.js
```

The page still scores 100 for Performance. This warning is about Cloudflare's
own Browser Insights/RUM script cache lifetime, not the Rails app. Leave it
alone unless you decide to disable Cloudflare Browser Insights for privacy,
simplicity, or no-JS minimalism.

## 8. Consider Route-Specific Titles

Priority: Medium
Effort: Small
Expected impact: SEO polish

The layout defaults every page to:

```text
San Jose Civic Gallery
```

The views can already use `content_for(:title)`. Add page-specific titles such
as:

- `Matters | San Jose Civic Gallery`
- `Meetings | San Jose Civic Gallery`
- `Glossary | San Jose Civic Gallery`
- `Data Health | San Jose Civic Gallery`

This was not the main Lighthouse failure, but it improves search-result clarity
and browser-tab context.

## Suggested Implementation Order

1. Add `<html lang="en">`.
2. Add default and per-page meta descriptions.
3. Darken the gold pill text color and re-run Lighthouse.
4. Decide whether to disable Cloudflare's `Content-Signal` robots.txt injection.
5. Add route-specific titles.
6. Prevent session cookies on public read-only GET pages.
7. Add public cache headers and conditional GETs to selected routes.
8. Enable narrow Cloudflare Cache Rules for safe public pages.
9. Re-run PageSpeed/Lighthouse on mobile and desktop.
10. Add a small header smoke test for representative public routes:
    no `Set-Cookie`, expected `Cache-Control`, and stable `ETag` where relevant.

## References

- PageSpeed report reviewed:
  https://pagespeed.web.dev/analysis/https-sanjose-civicgallery-org/hojqbeeogy
- PageSpeed Insights API overview:
  https://developers.google.com/speed/docs/insights/v5/get-started
- Lighthouse meta description audit:
  https://developer.chrome.com/docs/lighthouse/seo/meta-description
- Lighthouse robots.txt audit:
  https://developer.chrome.com/docs/lighthouse/seo/invalid-robots-txt
- MDN `lang` global attribute:
  https://developer.mozilla.org/docs/Web/HTML/Reference/Global_attributes/lang
- Existing project caching plan:
  ./caching-plan.md
