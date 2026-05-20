import { chromium } from "playwright";

const SCHOOL_ID = "36030421";
const MID = "57394";
const LISTING_URL = `https://simbli.eboardsolutions.com/SB_Meetings/SB_MeetingListing.aspx?S=${SCHOOL_ID}`;
const MEETING_URL = `https://simbli.eboardsolutions.com/SB_Meetings/ViewMeeting.aspx?S=${SCHOOL_ID}&MID=${MID}`;
const BLOCK_TEXT = ["Incapsula incident", "Request unsuccessful", "Pardon Our Interruption", "Access Denied"];

function flatten(items) {
  const flattened = [];
  const walk = (nodes) => {
    for (const node of nodes || []) {
      flattened.push(node);
      walk(node.Children);
    }
  };
  walk(items);
  return flattened;
}

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
  headless: true,
  args: ["--disable-blink-features=AutomationControlled", "--no-sandbox"]
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

  const meetingLinks = await page.locator("a").evaluateAll((anchors) => {
    const meetings = [];
    const seen = new Set();

    for (const anchor of anchors) {
      const onclick = anchor.getAttribute("onclick") || "";
      const args = onclick
        .match(/ViewMeeting\(([^)]*)\)/i)?.[1]
        ?.split(",")
        .map((arg) => arg.trim().replace(/^["']|["']$/g, ""));
      const mid = args?.[1];
      if (!mid || seen.has(mid)) continue;
      seen.add(mid);
      meetings.push({ mid, text: anchor.textContent?.trim() || "" });
    }

    return meetings;
  });

  const apiResponses = [];
  page.on("response", async (response) => {
    if (!response.url().includes("GetItemsTreeDTO")) return;
    apiResponses.push({
      url: response.url(),
      status: response.status(),
      body: await response.json().catch(() => null)
    });
  });

  await page.goto(MEETING_URL, { waitUntil: "domcontentloaded", timeout: 60000 });
  const meetingBlockedBy = await waitForChallenge(page);
  await page.waitForResponse((response) => response.url().includes("GetItemsTreeDTO"), { timeout: 30000 }).catch(() => {});
  await page.waitForTimeout(3000);

  const agendaItems = flatten(apiResponses[0]?.body?.Items || []);
  const firstAttachmentItem = agendaItems.find((item) => item.HasAttachment);
  let supportingDocs = null;
  let pdfFetch = null;
  let pdfGoto = null;

  if (apiResponses[0]?.url && firstAttachmentItem) {
    const params = new URL(apiResponses[0].url).searchParams;
    supportingDocs = await page.evaluate(
      async ({ sct, endid, enmid, enitemid }) => {
        const url = new URL("/Services/api/GetSupportingDocuments/", location.origin);
        url.searchParams.set("sct", sct);
        url.searchParams.set("endid", endid);
        url.searchParams.set("enentityid", enmid);
        url.searchParams.set("enitemid", enitemid);
        const response = await fetch(url.toString(), { credentials: "include" });
        return { status: response.status, body: await response.json() };
      },
      {
        sct: params.get("sct"),
        endid: params.get("endid"),
        enmid: params.get("enmid"),
        enitemid: firstAttachmentItem.ID
      }
    );

    const attachment = supportingDocs.body.Attachment?.[0];
    if (attachment) {
      pdfFetch = await page.evaluate(
        async ({ schoolId, mid, aid }) => {
          const url = new URL("/Meetings/Attachment.aspx", location.origin);
          url.searchParams.set("S", schoolId);
          url.searchParams.set("AID", aid);
          url.searchParams.set("MID", mid);
          const response = await fetch(url.toString(), { credentials: "include" });
          const buffer = await response.arrayBuffer();
          const bytes = Array.from(new Uint8Array(buffer.slice(0, 5)));
          const textSample = new TextDecoder().decode(buffer.slice(0, 500)).replace(/\s+/g, " ");
          return {
            url: url.toString(),
            status: response.status,
            contentType: response.headers.get("content-type"),
            byteLength: buffer.byteLength,
            startsWithPdf: bytes.map((byte) => String.fromCharCode(byte)).join("") === "%PDF-",
            textSample
          };
        },
        { schoolId: SCHOOL_ID, mid: MID, aid: String(attachment.AttachmentID) }
      );

      const response = await page.goto(pdfFetch.url, { waitUntil: "domcontentloaded", timeout: 60000 }).catch((error) => ({
        status: () => null,
        headers: () => ({ error: error.message })
      }));
      const bodySample = await page.locator("body").innerText({ timeout: 3000 }).catch(() => "");
      pdfGoto = {
        status: response?.status?.() || null,
        contentType: response?.headers?.()["content-type"] || null,
        bodySample: bodySample.replace(/\s+/g, " ").slice(0, 500)
      };
    }
  }

  console.log(JSON.stringify({
    listingBlocked: Boolean(listingBlockedBy),
    listingBlockedBy,
    discoveredMeetingCount: meetingLinks.length,
    meetingBlocked: Boolean(meetingBlockedBy),
    meetingBlockedBy,
    apiResponseCount: apiResponses.length,
    agendaItemCount: agendaItems.length,
    attachmentItemCount: agendaItems.filter((item) => item.HasAttachment).length,
    supportingDocStatus: supportingDocs?.status || null,
    supportingAttachmentCount: supportingDocs?.body?.Attachment?.length || 0,
    pdfFetch,
    pdfGoto
  }, null, 2));
} finally {
  await browser.close();
}
