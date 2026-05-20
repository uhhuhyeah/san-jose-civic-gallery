# Simbli (eBoardSolutions) Ingestion Spike

Reference material from the SJUSD feasibility spike. This is **not application
code**; the real adapter will be Ruby (see
[docs/sjusd-ingestion-plan.md](../../sjusd-ingestion-plan.md)). These scripts and
captured payloads exist so the reverse-engineered Simbli interface is not lost
when scratch space is cleared. The original spike lived in `tmp/`, which is
gitignored.

Target source: San Jose Unified School District on Simbli, `S=36030421`.

## Contents

- `probe-sjusd-simbli.mjs`: full local Playwright probe (listing discovery,
  agenda capture, supporting-doc fetch, sample PDF download). Writes artifacts
  to `./out`.
- `vps-probe.mjs`: trimmed probe meant to run inside a Playwright container on
  the VPS; prints a JSON summary to stdout.
- `run-vps-probe.sh`: base64-encodes `vps-probe.mjs` and runs it on the VPS via
  `kamal server exec` in an `mcr.microsoft.com/playwright` container. Run from
  the repo root.
- `inspect-simbli-body-fields.mjs`: probe used to investigate whether Simbli
  exposes a governing-body/committee field (it does not; see Body Mapping).
- `package.json`: pins `playwright` (the spike used `1.52.0`).
- `payloads/`: representative captured responses, with ephemeral session tokens
  redacted (see Redaction).

## The Simbli Interface Contract

This is the fragile, undocumented part. Each step's URL shape:

1. **Meeting listing** (HTML):
   `GET /SB_Meetings/SB_MeetingListing.aspx?S=<school_id>`
   Meeting ids come from anchor `onclick="ViewMeeting("<school_id>","<mid>",...)"`
   (fallback: `MID=<mid>` in the href).

2. **Meeting page** (HTML, fires the agenda XHR):
   `GET /SB_Meetings/ViewMeeting.aspx?S=<school_id>&MID=<mid>`

3. **Agenda tree** (JSON XHR, captured by listening for the response):
   `GET /Services/api/MeetingView/GetItemsTreeDTO/?sct=<s>&endid=<s>&enmid=<s>&enuid=&v=`
   Response: `{ Items: [...] }`, a nested tree (each node has `Children`).
   Each item carries `ID`, `AgendaID`, `Title`, `HasAttachment`.
   The session params are read **from this captured URL** and reused in step 4.

4. **Supporting documents** (JSON, one call per `HasAttachment` item):
   `GET /Services/api/GetSupportingDocuments/?sct=<s>&endid=<s>&enentityid=<s>&enitemid=<item.ID>`
   Note `enentityid` takes the **same value** as `enmid` from step 3's URL.
   Response: `{ Attachment: [{ AttachmentID, ... }], HyperLink: [...] }`.

5. **Attachment download** (binary):
   `GET /Meetings/Attachment.aspx?S=<school_id>&AID=<AttachmentID>&MID=<mid>`

### Stable identity vs ephemeral session params

- **Stable** (safe to persist as identity): `S` (school_id), `MID` (meeting id),
  agenda item `ID`, `AID` (attachment id).
- **Ephemeral** (do NOT persist; re-derive every session): `sct`, `endid`,
  `enmid`/`enentityid`, `enuid`. These are encrypted, session-scoped tokens that
  expire with the browser session. They are redacted in `payloads/`.

Because the public interface requires the full `(S, MID, AID)` / `(S, MID, item
ID)` tuple, do not assume `AID` or item `ID` is globally unique. Ingestion keys
use composite source ids including `MID` (see the schema evolution plan).

## Anti-Bot Behavior (Incapsula)

Simbli sits behind Incapsula. Observed:

- Plain Ruby HTTP from the VPS receives the Incapsula interstitial, not data.
- A Playwright/Chromium container on the VPS loads **metadata** successfully.
- **Attachment PDF downloads are blocked from the VPS**: HTTP 403, `text/html`,
  Incapsula response. The same download succeeds **locally** (HTTP 200,
  `application/pdf`, first bytes `%PDF-`).

Operator note: expect SJUSD PDFs to need the same human-in-the-loop manual
upload flow already used for blocked San Jose City downloads. Metadata sync can
be automated from the VPS; PDF retrieval may not be.

A blocked fetch returns an interstitial that parses as empty, not as an error.
The real adapter must treat an Incapsula interstitial as a hard, recorded
failure, never as "no meetings found."

## Body Mapping

Simbli exposes no clean governing-body field. The listing has columns
Date/Time, Meeting Title, Minutes, Meeting Type; for ordinary rows Meeting Title
and Meeting Type are both values like `Regular Session Board Meeting`. The
`meetingDTO` page global carried only ids/tokens.

Decision: default `body_name` to `Board of Education`; store Simbli Meeting Title
as the event `title` and Meeting Type as a separate field; make a deliberate
choice for special rows (for example `Financing Corporation Annual Meeting`)
rather than letting them fall out of the Meeting Type column accidentally.

## Running

Local (writes JSON + screenshots to `./out`):

```
cd docs/spikes/simbli
npm install
SCHOOL_ID=36030421 node probe-sjusd-simbli.mjs        # optional: MID=<mid> HEADLESS=false
```

VPS (from the repo root, requires Kamal access to the server):

```
docs/spikes/simbli/run-vps-probe.sh
```

## Redaction

`payloads/*.json` are real captured responses with the ephemeral session tokens
(`sct`, `endid`, `enmid`, `enentityid`, `enuid`) replaced by `REDACTED_*`
placeholders. Agenda content is public board-meeting record metadata: expulsion
items are referenced by anonymized case number and personnel items name
contractor companies, so no student or employee PII is present. Attachment PDFs
themselves were not captured.
