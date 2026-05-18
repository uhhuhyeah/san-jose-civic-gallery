# Event Window Sync

Use event window sync when you need to reconcile a bounded source window
instead of polling the latest `$top` events.

The default recent sync intentionally does **not** mark older local
events missing. It only sees a sliding window and cannot prove that
older records disappeared from Legistar.

Event window sync is different: it fetches all events for one body and
date range, pages with `$top` / `$skip`, persists current source rows,
and marks previously seen local events in that same window as missing
when they are absent from the fresh source response.

Run it with an explicit half-open date range:

```bash
START_DATE=2026-05-01 END_DATE=2026-06-01 bin/rails ingestion:sync_events_window
```

Useful options:

```bash
BODY_NAME="City Council" START_DATE=2026-05-01 END_DATE=2026-06-01 bin/rails ingestion:sync_events_window
PAGE_SIZE=50 START_DATE=2026-05-01 END_DATE=2026-06-01 bin/rails ingestion:sync_events_window
SYNC_EVENT_ITEMS=off START_DATE=2026-05-01 END_DATE=2026-06-01 bin/rails ingestion:sync_events_window
```

Options are environment variables:

- `START_DATE`: inclusive start date, required, `YYYY-MM-DD`.
- `END_DATE`: exclusive end date, required, `YYYY-MM-DD`.
- `BODY_NAME`: Legistar event body name. Default: `City Council`.
- `PAGE_SIZE`: page size for `$top` / `$skip`. Default: `100`.
- `SYNC_EVENT_ITEMS`: `deferred`, `inline`, or `off`. Default:
  `deferred`.

Use half-open ranges so adjacent runs do not overlap:

```text
2026-05-01 <= EventDate < 2026-06-01
2026-06-01 <= EventDate < 2026-07-01
```

## Caveats

**Events that move dates between windows can briefly appear missing.**
Reconciliation uses the locally stored `event_date` to decide which
window an event belongs to. If Legistar moves an event from May 5 to
June 5:

- The May window run fetches Legistar's current May contents, does not
  see the moved event, and marks it `source_present: false` against its
  old (May) local date.
- The June window run sees it in source, calls `PersistEvent` (which
  updates `event_date` to June 5 and sets `source_present: true`), and
  the row is restored.

To minimize the window of incorrect state, run adjacent date windows
back-to-back rather than interleaving days. The bounded sync is
idempotent, so re-running a window that already restored an event is
safe.

**Server pagination is bounded.** The service raises after
`MAX_PAGES = 200` requests as a safety net against an upstream that
ignores `$skip` and returns full pages indefinitely. At the default
`PAGE_SIZE = 100`, this caps a single run at 20,000 events.
