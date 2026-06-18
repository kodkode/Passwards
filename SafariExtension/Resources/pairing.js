// Pairing runs in a full tab (not the popup) because the popup is killed the
// moment Passwards takes focus to show its approval alert.

const steps = {
  start: document.getElementById("step-start"),
  code: document.getElementById("step-code"),
  done: document.getElementById("step-done"),
  error: document.getElementById("step-error"),
};

function show(name) {
  for (const [key, el] of Object.entries(steps)) el.hidden = key !== name;
}

chrome.runtime.onMessage.addListener((message) => {
  if (message.event === "pairing-code") {
    document.getElementById("code").textContent = message.code;
  }
});

async function start() {
  show("code");
  const result = await chrome.runtime.sendMessage({ cmd: "pair" });
  if (result?.ok) {
    show("done");
    setTimeout(() => window.close(), 4000);
  } else {
    document.getElementById("error-text").textContent =
      `Pairing failed: ${result?.error ?? "unknown error"}`;
    show("error");
  }
}

document.getElementById("start").addEventListener("click", start);
document.getElementById("retry").addEventListener("click", start);

// If we're already paired (e.g. tab reopened), skip straight to done.
chrome.runtime.sendMessage({ cmd: "state" }).then((state) => {
  if (state?.paired) show("done");
});
