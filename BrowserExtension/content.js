// 2Password content script: fills login forms on request from the popup and
// offers to save credentials when a login form is submitted.

(() => {
  if (window.top !== window) return; // top frame only, v1

  // ------------------------------------------------------------- detection

  function visible(el) {
    const rect = el.getBoundingClientRect();
    return rect.width > 0 && rect.height > 0;
  }

  function findLoginFields() {
    const passwords = [...document.querySelectorAll('input[type="password"]')].filter(visible);
    if (passwords.length === 0) return null;
    const password = passwords[0];

    // Username: the closest prior text-ish input, preferring the same form.
    const scope = password.form ?? document;
    const candidates = [...scope.querySelectorAll(
      'input[type="text"], input[type="email"], input:not([type])'
    )].filter(visible);
    let username = null;
    for (const input of candidates) {
      const position = password.compareDocumentPosition(input);
      if (position & Node.DOCUMENT_POSITION_PRECEDING) username = input;
    }
    return { username, password, form: password.form };
  }

  // ------------------------------------------------------------------ fill

  function setValue(input, value) {
    // React/Vue listen for synthetic events; set via the native setter.
    const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set;
    setter.call(input, value);
    input.dispatchEvent(new Event("input", { bubbles: true }));
    input.dispatchEvent(new Event("change", { bubbles: true }));
  }

  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.cmd !== "fill-form") return;
    const fields = findLoginFields();
    if (!fields) return sendResponse({ filled: false, reason: "no password field found" });
    if (fields.username && message.username) setValue(fields.username, message.username);
    setValue(fields.password, message.password);
    sendResponse({ filled: true });
  });

  // ----------------------------------------------------------- open & fill

  // The app may have staged a one-shot fill for this domain ("Open & Fill"
  // clicked in 2Password). Login forms often render late, so retry briefly.
  async function checkPendingFill() {
    let creds;
    try {
      creds = await chrome.runtime.sendMessage({ cmd: "pending-fill" });
    } catch { return; }
    if (!creds?.password) return;

    const deadline = Date.now() + 8000;
    while (Date.now() < deadline) {
      const fields = findLoginFields();
      if (fields) {
        if (fields.username && creds.username) setValue(fields.username, creds.username);
        setValue(fields.password, creds.password);
        if (creds.submit) {
          await new Promise((r) => setTimeout(r, 150)); // let framework state settle
          submitLogin(fields);
        }
        return;
      }
      await new Promise((r) => setTimeout(r, 250));
    }
  }

  function submitLogin(fields) {
    const scope = fields.form ?? document;
    const button = scope.querySelector(
      'button[type="submit"], input[type="submit"]'
    ) ?? [...scope.querySelectorAll("button")].find((b) =>
      /log\s*in|sign\s*in|submit|continue/i.test(b.textContent));
    if (button) {
      button.click();
    } else if (fields.form) {
      fields.form.requestSubmit();
    } else {
      // Last resort: Enter in the password field.
      for (const type of ["keydown", "keyup"]) {
        fields.password.dispatchEvent(new KeyboardEvent(type, {
          key: "Enter", code: "Enter", keyCode: 13, bubbles: true,
        }));
      }
    }
  }

  checkPendingFill();

  // ------------------------------------------------------------ save offer

  let lastCapture = null;

  function capture() {
    const fields = findLoginFields();
    if (!fields || !fields.password.value) return;
    lastCapture = {
      url: location.href,
      title: document.title,
      username: fields.username?.value ?? "",
      password: fields.password.value,
    };
  }

  document.addEventListener("submit", capture, true);
  document.addEventListener("click", (event) => {
    if (event.target.closest('button, input[type="submit"], [role="button"]')) capture();
  }, true);

  // After navigation-style submits the page unloads; for SPA logins the
  // password field disappears instead — offer to save at that point.
  const observer = new MutationObserver(() => {
    if (!lastCapture) return;
    if (!document.querySelector('input[type="password"]')) {
      const captured = lastCapture;
      lastCapture = null;
      maybeOfferSave(captured);
    }
  });
  observer.observe(document.documentElement, { childList: true, subtree: true });

  window.addEventListener("pagehide", () => {
    if (!lastCapture) return;
    // Stash for the next page load on this site.
    sessionStorage.setItem("__2pw_pending_save", JSON.stringify(lastCapture));
    lastCapture = null;
  });

  const pendingRaw = sessionStorage.getItem("__2pw_pending_save");
  if (pendingRaw) {
    sessionStorage.removeItem("__2pw_pending_save");
    try { maybeOfferSave(JSON.parse(pendingRaw)); } catch {}
  }

  async function maybeOfferSave(captured) {
    let state;
    try {
      state = await chrome.runtime.sendMessage({ cmd: "state" });
    } catch { return; }
    if (!state?.paired || state.locked) return;

    const query = await chrome.runtime.sendMessage({ cmd: "query", url: captured.url });
    const existing = (query?.matches ?? []).find((m) => m.username === captured.username);
    if (existing) {
      // Only offer an update if the password actually changed.
      const current = await chrome.runtime.sendMessage({
        cmd: "fill-credentials", url: captured.url, itemID: existing.itemID,
      });
      if (!current || current.password === captured.password) return;
      showBanner(`Update password for “${existing.title}” in 2Password?`, "Update", async () => {
        await chrome.runtime.sendMessage({ cmd: "save-login", ...captured });
      });
    } else {
      showBanner("Save this login in 2Password?", "Save", async () => {
        await chrome.runtime.sendMessage({ cmd: "save-login", ...captured });
      });
    }
  }

  // ---------------------------------------------------------------- banner

  function showBanner(text, actionTitle, onAction) {
    document.getElementById("__2pw-banner")?.remove();
    const host = document.createElement("div");
    host.id = "__2pw-banner";
    const shadow = host.attachShadow({ mode: "closed" });
    shadow.innerHTML = `
      <style>
        .banner {
          position: fixed; top: 16px; right: 16px; z-index: 2147483647;
          display: flex; align-items: center; gap: 12px;
          background: #1c1c1f; color: #f2f2f4;
          border: 1px solid #3a3a3f; border-radius: 10px;
          box-shadow: 0 8px 30px rgba(0,0,0,.35);
          padding: 12px 14px; font: 13px -apple-system, sans-serif;
        }
        button {
          font: inherit; border-radius: 6px; padding: 5px 12px; cursor: pointer;
          border: none; background: #2e6ee8; color: white;
        }
        .dismiss { background: transparent; color: #9a9aa2; padding: 5px 6px; }
      </style>
      <div class="banner">
        <span>${text.replace(/</g, "&lt;")}</span>
        <button class="action">${actionTitle}</button>
        <button class="dismiss">✕</button>
      </div>`;
    shadow.querySelector(".action").addEventListener("click", async () => {
      await onAction();
      host.remove();
    });
    shadow.querySelector(".dismiss").addEventListener("click", () => host.remove());
    document.documentElement.appendChild(host);
    setTimeout(() => host.remove(), 20000);
  }
})();
