import fs from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";

const SCHOOL_ID = process.env.SCHOOL_ID || "36030421";
const REQUESTED_MID = process.env.MID || null;
const FALLBACK_MID = "37079";
const OUT_DIR = path.resolve("out");
const LISTING_URL = `https://simbli.eboardsolutions.com/SB_Meetings/SB_MeetingListing.aspx?S=${SCHOOL_ID}`;
const meetingUrl = (mid) =>
  `https://simbli.eboardsolutions.com/SB_Meetings/ViewMeeting.aspx?S=${SCHOOL_ID}&MID=${mid}`;

const antiBotText = [
  "Incapsula incident",
  "Request unsuccessful",
  "Pardon Our Interruption",
  "Access Denied"
];

async function saveArtifact(name, content) {
  await fs.mkdir(OUT_DIR, { recursive: true });
  await fs.writeFile(path.join(OUT_DIR, name), content);
}

async function savePage(page, prefix) {
  await saveArtifact(`${prefix}.html`, await page.content());
  await page.screenshot({ path: path.join(OUT_DIR, `${prefix}.png`), fullPage: true });
}

async function pageStatus(page) {
  const body = await page.locator("body").innerText({ timeout: 3000 }).catch(() => "");
  const blocked = antiBotText.find((text) => body.includes(text));
  return {
    title: await page.title().catch(() => ""),
    url: page.url(),
    blocked: Boolean(blocked),
    blockedBy: blocked || null,
    bodySample: body.replace(/\s+/g, " ").slice(0, 300)
  };
}

async function waitForChallenge(page, seconds = 30) {
  const deadline = Date.now() + seconds * 1000;
  let status = await pageStatus(page);

  while (Date.now() < deadline && status.blocked) {
    await page.waitForTimeout(1000);
    status = await pageStatus(page);
  }

  return status;
}

async function discoverMeetings(page) {
  await page.goto(LISTING_URL, { waitUntil: "domcontentloaded", timeout: 60000 });
  const status = await waitForChallenge(page);

  await page
    .waitForSelector(
      'a[onclick*="ViewMeeting"], a[href*="ViewMeeting.aspx"], a[onclick*="MID="]',
      { timeout: 20000 }
    )
    .catch(() => {});

  const links = await page
    .locator("a")
    .evaluateAll((anchors) =>
      anchors.map((anchor) => ({
        text: anchor.textContent?.trim() || "",
        href: anchor.href || "",
        onclick: anchor.getAttribute("onclick") || ""
      }))
    )
    .catch(() => []);

  const meetings = [];
  const seen = new Set();

  for (const link of links) {
    const haystack = `${link.href} ${link.onclick}`;
    const viewMeetingArgs = link.onclick.match(/ViewMeeting\(([^)]*)\)/i)?.[1];
    const parsedArgs = viewMeetingArgs
      ?.split(",")
      .map((arg) => arg.trim().replace(/^["']|["']$/g, ""));
    const mid = parsedArgs?.[1] || haystack.match(/MID=(\d+)/i)?.[1];
    if (!mid || seen.has(mid)) continue;
    seen.add(mid);
    meetings.push({ mid, text: link.text, href: link.href, onclick: link.onclick });
  }

  await saveArtifact("listing-links.json", JSON.stringify({ status, meetings, links }, null, 2));
  if (status.blocked || meetings.length === 0) await savePage(page, "listing");

  return { status, meetings };
}

function flattenItems(items) {
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

async function probeMeeting(page, mid) {
  const apiResponses = [];
  const supportingDocumentResponses = [];

  page.on("response", async (response) => {
    const url = response.url();
    if (!url.includes("GetItemsTreeDTO") && !url.includes("GetSupportingDocuments")) return;

    const record = {
      url,
      status: response.status(),
      contentType: response.headers()["content-type"] || ""
    };

    try {
      record.body = await response.json();
    } catch {
      record.bodySample = (await response.text().catch(() => "")).slice(0, 1000);
    }

    if (url.includes("GetItemsTreeDTO")) apiResponses.push(record);
    if (url.includes("GetSupportingDocuments")) supportingDocumentResponses.push(record);
  });

  await page.goto(meetingUrl(mid), { waitUntil: "domcontentloaded", timeout: 60000 });
  let status = await waitForChallenge(page);

  await page
    .waitForResponse((response) => response.url().includes("GetItemsTreeDTO"), { timeout: 30000 })
    .catch(() => {});
  await page.waitForTimeout(5000);
  status = await pageStatus(page);

  const agendaItems = await page
    .locator("button.level-strip.node-title, span.item-title-vm, app-itemcontent, a.supportingDocText")
    .count()
    .catch(() => 0);

  const attachmentLinks = await page
    .locator('a[href*="Attachment.aspx"]')
    .evaluateAll((anchors) =>
      anchors.map((anchor) => ({
        text: anchor.textContent?.trim() || "",
        href: anchor.href
      }))
    )
    .catch(() => []);

  const itemSupportingDocs = [];
  const agendaApiUrl = apiResponses[0]?.url;
  const agendaItemsFromApi = flattenItems(apiResponses[0]?.body?.Items || []);
  if (agendaApiUrl) {
    const params = new URL(agendaApiUrl).searchParams;
    const fetchTargets = agendaItemsFromApi.filter((item) => item.HasAttachment).slice(0, 10);

    for (const item of fetchTargets) {
      const docs = await page.evaluate(
        async ({ sct, endid, enmid, enitemid }) => {
          const url = new URL("/Services/api/GetSupportingDocuments/", location.origin);
          url.searchParams.set("sct", sct);
          url.searchParams.set("endid", endid);
          url.searchParams.set("enentityid", enmid);
          url.searchParams.set("enitemid", enitemid);

          const response = await fetch(url.toString(), {
            credentials: "include",
            headers: { accept: "application/json, text/plain, */*" }
          });

          return {
            url: url.toString(),
            status: response.status,
            body: await response.json().catch(async () => ({ sample: (await response.text()).slice(0, 1000) }))
          };
        },
        {
          sct: params.get("sct"),
          endid: params.get("endid"),
          enmid: params.get("enmid"),
          enitemid: item.ID
        }
      );

      itemSupportingDocs.push({
        agendaId: item.AgendaID,
        itemId: item.ID,
        title: item.Title,
        docs
      });
    }
  }

  const firstAttachment = itemSupportingDocs
    .flatMap((entry) =>
      (entry.docs.body?.Attachment || []).map((attachment) => ({
        agendaId: entry.agendaId,
        itemTitle: entry.title,
        attachment
      }))
    )[0];
  const firstAttachmentFetch = firstAttachment
    ? await page.evaluate(
        async ({ schoolId, mid, aid }) => {
          const url = new URL("/Meetings/Attachment.aspx", location.origin);
          url.searchParams.set("S", schoolId);
          url.searchParams.set("AID", aid);
          url.searchParams.set("MID", mid);

          const response = await fetch(url.toString(), { credentials: "include" });
          const buffer = await response.arrayBuffer();
          const bytes = Array.from(new Uint8Array(buffer.slice(0, 8)));
          return {
            url: url.toString(),
            status: response.status,
            contentType: response.headers.get("content-type"),
            byteLength: buffer.byteLength,
            firstBytes: bytes,
            startsWithPdf: bytes.slice(0, 5).map((byte) => String.fromCharCode(byte)).join("") === "%PDF-"
          };
        },
        {
          schoolId: SCHOOL_ID,
          mid,
          aid: String(firstAttachment.attachment.AttachmentID)
        }
      )
    : null;

  const result = {
    mid,
    status,
    agendaItems,
    apiResponseCount: apiResponses.length,
    supportingDocumentResponseCount: supportingDocumentResponses.length,
    itemSupportingDocsCount: itemSupportingDocs.length,
    itemSupportingDocsWithAttachments: itemSupportingDocs.filter((entry) => entry.docs.body?.Attachment?.length).length,
    itemSupportingDocsWithHyperlinks: itemSupportingDocs.filter((entry) => entry.docs.body?.HyperLink?.length).length,
    firstAttachmentFetch,
    attachmentLinks
  };

  await saveArtifact(
    `meeting-${mid}.json`,
    JSON.stringify({ result, apiResponses, supportingDocumentResponses, itemSupportingDocs }, null, 2)
  );
  await savePage(page, `meeting-${mid}`);

  return result;
}

const browser = await chromium.launch({
  channel: process.env.PW_CHANNEL || "chrome",
  headless: process.env.HEADLESS !== "false",
  args: [
    "--disable-blink-features=AutomationControlled",
    "--disable-dev-shm-usage",
    "--no-sandbox"
  ]
});

try {
  const context = await browser.newContext({
    acceptDownloads: true,
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
  const discovery = await discoverMeetings(page);
  const mid = REQUESTED_MID || discovery.meetings[0]?.mid || FALLBACK_MID;
  const meeting = await probeMeeting(page, mid);

  const summary = {
    schoolId: SCHOOL_ID,
    listingUrl: LISTING_URL,
    listingBlocked: discovery.status.blocked,
    listingBlockedBy: discovery.status.blockedBy,
    discoveredMeetingCount: discovery.meetings.length,
    probedMid: mid,
    meetingBlocked: meeting.status.blocked,
    meetingBlockedBy: meeting.status.blockedBy,
    apiResponseCount: meeting.apiResponseCount,
    supportingDocumentResponseCount: meeting.supportingDocumentResponseCount,
    itemSupportingDocsCount: meeting.itemSupportingDocsCount,
    itemSupportingDocsWithAttachments: meeting.itemSupportingDocsWithAttachments,
    itemSupportingDocsWithHyperlinks: meeting.itemSupportingDocsWithHyperlinks,
    attachmentLinkCount: meeting.attachmentLinks.length,
    agendaDomSignalCount: meeting.agendaItems
  };

  await saveArtifact("summary.json", JSON.stringify(summary, null, 2));
  console.log(JSON.stringify(summary, null, 2));
} finally {
  await browser.close();
}
