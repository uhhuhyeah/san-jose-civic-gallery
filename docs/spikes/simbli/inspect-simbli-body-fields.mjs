import { chromium } from "playwright";

const SCHOOL_ID = "36030421";
const MID = process.env.MID || "57394";
const LISTING_URL = `https://simbli.eboardsolutions.com/SB_Meetings/SB_MeetingListing.aspx?S=${SCHOOL_ID}`;
const MEETING_URL = `https://simbli.eboardsolutions.com/SB_Meetings/ViewMeeting.aspx?S=${SCHOOL_ID}&MID=${MID}`;
const BLOCK_TEXT = ["Incapsula incident", "Request unsuccessful", "Pardon Our Interruption", "Access Denied"];

async function blockedBy(page) {
  const body = await page.locator("body").innerText({ timeout: 3000 }).catch(() => "");
  return BLOCK_TEXT.find((text) => body.includes(text)) || null;
}

async function waitForChallenge(page) {
  const deadline = Date.now() + 30000;
  let blocked = await blockedBy(page);
  while (blocked && Date.now() < deadline) {
    await page.waitForTimeout(1000);
    blocked = await blockedBy(page);
  }
  return blocked;
}

const browser = await chromium.launch({
  channel: process.env.PW_CHANNEL || "chrome",
  headless: process.env.HEADLESS !== "false",
  args: ["--disable-blink-features=AutomationControlled", "--disable-dev-shm-usage", "--no-sandbox"]
});

try {
  const context = await browser.newContext({
    locale: "en-US",
    timezoneId: "America/Los_Angeles",
    userAgent:
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
  });
  await context.addInitScript(() => {
    Object.defineProperty(navigator, "webdriver", { get: () => false });
    Object.defineProperty(navigator, "languages", { get: () => ["en-US", "en"] });
  });

  const page = await context.newPage();
  await page.goto(LISTING_URL, { waitUntil: "domcontentloaded", timeout: 60000 });
  const listingBlockedBy = await waitForChallenge(page);
  await page.waitForSelector('a[onclick*="ViewMeeting"]', { timeout: 20000 }).catch(() => {});

  const listing = await page.evaluate(() => {
    const normalize = (text) => (text || "").replace(/\s+/g, " ").trim();
    const tables = [...document.querySelectorAll("table")].map((table, tableIndex) => {
      const headers = [...table.querySelectorAll("th")].map((th) => normalize(th.innerText));
      const rows = [...table.querySelectorAll("tr")].map((row) => ({
        cells: [...row.querySelectorAll("th,td")].map((cell) => normalize(cell.innerText)),
        onclicks: [...row.querySelectorAll("[onclick]")].map((node) => node.getAttribute("onclick"))
      })).filter((row) => row.cells.some(Boolean) || row.onclicks.length);
      return { tableIndex, headers, rows: rows.slice(0, 20) };
    }).filter((table) => table.rows.length);

    const meetingLinks = [...document.querySelectorAll('a[onclick*="ViewMeeting"]')].slice(0, 25).map((anchor) => ({
      text: normalize(anchor.innerText),
      rowText: normalize(anchor.closest("tr")?.innerText || ""),
      onclick: anchor.getAttribute("onclick")
    }));

    return {
      title: document.title.trim(),
      bodySample: normalize(document.body.innerText).slice(0, 1200),
      tables,
      meetingLinks
    };
  });

  await page.goto(MEETING_URL, { waitUntil: "domcontentloaded", timeout: 60000 });
  const meetingBlockedBy = await waitForChallenge(page);
  await page.waitForSelector("body", { timeout: 10000 });
  await page.waitForTimeout(3000);

  const meeting = await page.evaluate(() => {
    const normalize = (text) => (text || "").replace(/\s+/g, " ").trim();
    const labelledControls = [...document.querySelectorAll("[aria-labelledby], [aria-label], [title]")]
      .map((node) => ({
        tag: node.tagName.toLowerCase(),
        id: node.id || null,
        label: node.getAttribute("aria-label") || node.getAttribute("title") || null,
        ariaLabelledBy: node.getAttribute("aria-labelledby") || null,
        text: normalize(node.innerText || node.textContent).slice(0, 300)
      }))
      .filter((entry) => /Meeting|Board|Session|Type|Organization|Committee|Council|Corporation/i.test(JSON.stringify(entry)))
      .slice(0, 80);

    const dropdowns = [...document.querySelectorAll(".breadcrumb-mid [role='combobox'], .breadcrumb-mid button, [id*='MeetingDDL']")]
      .map((node) => ({
        tag: node.tagName.toLowerCase(),
        id: node.id || null,
        title: node.getAttribute("title") || null,
        text: normalize(node.innerText || node.textContent).slice(0, 500),
        ariaLabelledBy: node.getAttribute("aria-labelledby") || null
      }))
      .filter((entry) => entry.text || entry.title || entry.id)
      .slice(0, 80);

    const options = [...document.querySelectorAll("[role='option'], option, .dropdown-item")]
      .map((node) => ({
        id: node.id || null,
        selected: node.getAttribute("aria-selected") || node.selected || false,
        text: normalize(node.innerText || node.textContent)
      }))
      .filter((entry) => /Meeting|Session|Corporation|Organization|Board|Committee/i.test(entry.text))
      .slice(0, 120);

    const globals = {};
    for (const name of ["meetingDTO", "minuteAccess", "matchType", "isTemplate", "viewMode"]) {
      try {
        const value = window[name];
        globals[name] = typeof value === "object" ? JSON.parse(JSON.stringify(value)) : value;
      } catch (error) {
        globals[name] = `ERROR: ${error.message}`;
      }
    }

    return {
      title: document.title.trim(),
      bodySample: normalize(document.body.innerText).slice(0, 1200),
      labelledControls,
      dropdowns,
      options,
      globals
    };
  });

  console.log(JSON.stringify({
    listingBlockedBy,
    meetingBlockedBy,
    listing,
    meeting
  }, null, 2));
} finally {
  await browser.close();
}
