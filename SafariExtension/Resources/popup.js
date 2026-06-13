// 2Password popup: suggestions for the current tab, search across all
// logins, fill / copy actions, and the first-run pairing flow.

const statusEl = document.getElementById("status");
const listEl = document.getElementById("list");
const searchEl = document.getElementById("search");
const footerEl = document.getElementById("footer-text");

let allItems = [];
let suggestions = [];
let activeTab = null;

function showStatus(html) {
  statusEl.hidden = false;
  statusEl.innerHTML = html;
  listEl.innerHTML = "";
}

function hideStatus() {
  statusEl.hidden = true;
}

async function send(message) {
  return chrome.runtime.sendMessage(message);
}

async function init() {
  [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });

  const state = await send({ cmd: "state" });
  if (state?.error) return showStatus(`Can't reach 2Password.<br>${state.error}`);
  if (!state.paired) return showPairing();
  if (state.locked) return showStatus("2Password is locked.<br>Unlock the app to use the extension.");

  const url = activeTab?.url ?? "";
  const isWebPage = /^https?:/.test(url);

  const [forTab, everything] = await Promise.all([
    isWebPage ? send({ cmd: "query", url }) : Promise.resolve({ matches: [] }),
    send({ cmd: "query" }),
  ]);
  if (everything?.error) return showStatus(everything.error);

  suggestions = forTab?.matches ?? [];
  allItems = everything?.matches ?? [];
  hideStatus();
  render();
  searchEl.focus();
}

function showPairing() {
  // Pairing happens in a dedicated tab: the popup dies as soon as the
  // 2Password app takes focus for its approval alert.
  showStatus(`Connect this browser to 2Password.<button id="connect">Connect…</button>`);
  statusEl.querySelector("#connect").addEventListener("click", () => {
    chrome.tabs.create({ url: chrome.runtime.getURL("pairing.html") });
    window.close();
  });
}

function render() {
  const filter = searchEl.value.trim().toLowerCase();
  listEl.innerHTML = "";

  const matching = filter
    ? allItems.filter((m) => (m.title + " " + m.username).toLowerCase().includes(filter))
    : null;

  if (!filter && suggestions.length) {
    addSection("Suggestions", suggestions, true);
    const suggestedIDs = new Set(suggestions.map((m) => m.itemID));
    const rest = allItems.filter((m) => !suggestedIDs.has(m.itemID));
    if (rest.length) addSection("All Logins", rest, false);
  } else {
    const rows = matching ?? allItems;
    addSection(filter ? "Results" : "All Logins", rows, false);
    if (!rows.length) listEl.innerHTML = `<div class="section-title">No matches</div>`;
  }
  footerEl.textContent = `${allItems.length} logins`;
}

function addSection(title, rows, fillable) {
  const heading = document.createElement("div");
  heading.className = "section-title";
  heading.textContent = title;
  listEl.appendChild(heading);
  const suggestedIDs = new Set(suggestions.map((m) => m.itemID));

  for (const match of rows) {
    const row = document.createElement("div");
    row.className = "item";
    const canFill = fillable || suggestedIDs.has(match.itemID);

    const glyph = document.createElement("div");
    glyph.className = "glyph";
    glyph.textContent = (match.title || "?").slice(0, 1).toUpperCase();

    const meta = document.createElement("div");
    meta.className = "meta";
    const titleEl = document.createElement("div");
    titleEl.className = "title";
    titleEl.textContent = match.title;
    const subEl = document.createElement("div");
    subEl.className = "sub";
    subEl.textContent = match.username;
    meta.append(titleEl, subEl);

    const actions = document.createElement("div");
    actions.className = "actions";
    if (canFill) {
      const fillBtn = document.createElement("button");
      fillBtn.className = "fill";
      fillBtn.textContent = "Fill";
      fillBtn.addEventListener("click", () => fill(match));
      actions.appendChild(fillBtn);
    }
    const copyBtn = document.createElement("button");
    copyBtn.textContent = "Copy";
    copyBtn.addEventListener("click", async () => {
      const creds = await send({ cmd: "fill-credentials", itemID: match.itemID });
      if (creds?.password != null) {
        await navigator.clipboard.writeText(creds.password);
        copyBtn.textContent = "Copied";
        setTimeout(() => (copyBtn.textContent = "Copy"), 1200);
      }
    });
    actions.appendChild(copyBtn);

    row.append(glyph, meta, actions);
    listEl.appendChild(row);
  }
}

async function fill(match) {
  const creds = await send({ cmd: "fill-credentials", url: activeTab.url, itemID: match.itemID });
  if (creds?.error) return;
  await chrome.tabs.sendMessage(activeTab.id, {
    cmd: "fill-form", username: creds.username, password: creds.password,
  });
  window.close();
}

searchEl.addEventListener("input", render);
init();
