// Production Simbli fetch primitive. Driven by Ruby's Simbli::Client (which
// shells out to `node fetch.mjs meeting <mid>`). Loads a single meeting in one
// browser session and emits JSON on stdout:
//
//   { ok, blocked, blockedBy, agenda, supportingDocuments: { "<AgendaID>": {...} } }
//
// Identity note: supporting documents are fetched with the item's encrypted
// `ID` (what the API requires) but keyed in the output by the stable numeric
// `AgendaID`, so Ruby can look them up by the same id it persists.
//
// This reuses the anti-bot approach validated in docs/spikes/simbli. It only
// reads metadata; attachment PDFs are downloaded (or recovered manually)
// elsewhere.
import { chromium } from "playwright";

const SCHOOL_ID = process.env.SCHOOL_ID || "36030421";
const [, , command, mid] = process.argv;
const ANTIBOT = ["Incapsula incident", "Request unsuccessful", "Pardon Our Interruption", "Access Denied"];

function emit(obj) {
  process.stdout.write(JSON.stringify(obj));
}

function flatten(items) {
  const out = [];
  const walk = (nodes) => {
    for (const node of nodes || []) {
      out.push(node);
      walk(node.Children);
    }
  };
  walk(items);
  return out;
}

async function blockedBy(page) {
  const body = await page.locator("body").innerText({ timeout: 3000 }).catch(() => "");
  return ANTIBOT.find((text) => body.includes(text)) || null;
}

async function waitForChallenge(page, seconds = 30) {
  const deadline = Date.now() + seconds * 1000;
  let blocked = await blockedBy(page);
  while (blocked && Date.now() < deadline) {
    await page.waitForTimeout(1000);
    blocked = await blockedBy(page);
  }
  return blocked;
}

async function fetchMeeting(page, meetingId) {
  const apiResponses = [];
  page.on("response", async (response) => {
    if (!response.url().includes("GetItemsTreeDTO")) return;
    try {
      apiResponses.push({ url: response.url(), body: await response.json() });
    } catch {
      // non-JSON (e.g. interstitial) is ignored; handled via block detection
    }
  });

  const url = `https://simbli.eboardsolutions.com/SB_Meetings/ViewMeeting.aspx?S=${SCHOOL_ID}&MID=${meetingId}`;
  await page.goto(url, { waitUntil: "domcontentloaded", timeout: 60000 });

  const blocked = await waitForChallenge(page);
  if (blocked) return { ok: false, blocked: true, blockedBy: blocked };

  await page.waitForResponse((response) => response.url().includes("GetItemsTreeDTO"), { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(3000);

  const api = apiResponses[0];
  if (!api) return { ok: false, blocked: false, error: "GetItemsTreeDTO response not captured" };

  const params = new URL(api.url).searchParams;
  const attachmentItems = flatten(api.body.Items || []).filter((item) => item.HasAttachment);
  const supportingDocuments = {};

  for (const item of attachmentItems) {
    const docs = await page.evaluate(
      async ({ sct, endid, enmid, enitemid }) => {
        const u = new URL("/Services/api/GetSupportingDocuments/", location.origin);
        u.searchParams.set("sct", sct);
        u.searchParams.set("endid", endid);
        u.searchParams.set("enentityid", enmid);
        u.searchParams.set("enitemid", enitemid);
        const response = await fetch(u.toString(), { credentials: "include", headers: { accept: "application/json, text/plain, */*" } });
        return { status: response.status, body: await response.json().catch(() => null) };
      },
      { sct: params.get("sct"), endid: params.get("endid"), enmid: params.get("enmid"), enitemid: item.ID }
    );

    if (docs && docs.body) supportingDocuments[String(item.AgendaID)] = docs.body;
  }

  return { ok: true, blocked: false, agenda: api.body, supportingDocuments };
}

if (command !== "meeting" || !mid) {
  emit({ ok: false, blocked: false, error: "usage: fetch.mjs meeting <mid>" });
  process.exit(0);
}

const browser = await chromium.launch({
  channel: process.env.PW_CHANNEL || undefined,
  headless: true,
  args: ["--disable-blink-features=AutomationControlled", "--disable-dev-shm-usage", "--no-sandbox"]
});

try {
  const context = await browser.newContext({
    locale: "en-US",
    timezoneId: "America/Los_Angeles",
    userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
  });
  await context.addInitScript(() => {
    Object.defineProperty(navigator, "webdriver", { get: () => false });
    Object.defineProperty(navigator, "languages", { get: () => ["en-US", "en"] });
  });

  const page = await context.newPage();
  emit(await fetchMeeting(page, mid));
} catch (err) {
  emit({ ok: false, blocked: false, error: String((err && err.message) || err) });
} finally {
  await browser.close();
}
