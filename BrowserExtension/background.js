// 2Password background service worker.
//
// Speaks the app's wire protocol over native messaging: one-time X25519
// pairing (user approves a verification code in the app), then per-connection
// session keys (HKDF bound to the pairing secret) sealing every RPC with
// AES-256-GCM. Mirrors BrowserChannelCrypto.swift — labels and byte orders
// are the wire contract.

const HOST = "com.michael.twopassword";

const enc = new TextEncoder();
const b64 = {
  encode: (bytes) => btoa(String.fromCharCode(...new Uint8Array(bytes))),
  decode: (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0)),
};

// ---------------------------------------------------------------- crypto

async function hkdf(ikmBytes, saltBytes, infoBytes, lengthBytes) {
  const key = await crypto.subtle.importKey("raw", ikmBytes, "HKDF", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits(
    { name: "HKDF", hash: "SHA-256", salt: saltBytes, info: infoBytes },
    key,
    lengthBytes * 8
  );
  return new Uint8Array(bits);
}

async function x25519Generate() {
  return crypto.subtle.generateKey({ name: "X25519" }, true, ["deriveBits"]);
}

async function x25519SharedSecret(privateKey, peerPublicRaw) {
  const peer = await crypto.subtle.importKey("raw", peerPublicRaw, { name: "X25519" }, false, []);
  const bits = await crypto.subtle.deriveBits({ name: "X25519", public: peer }, privateKey, 256);
  return new Uint8Array(bits);
}

function concatBytes(...parts) {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const p of parts) { out.set(p, offset); offset += p.length; }
  return out;
}

// nonce = 4-byte BE direction + 8-byte BE counter; AAD repeats both.
function nonceFor(direction, seq) {
  const out = new Uint8Array(12);
  const view = new DataView(out.buffer);
  view.setUint32(0, direction);
  view.setBigUint64(4, BigInt(seq));
  return out;
}

async function sealRequest(keyBytes, seq, obj) {
  const key = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["encrypt"]);
  const nonce = nonceFor(1, seq); // extension → app
  const box = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce, additionalData: enc.encode(`2pw-enc-1-${seq}`) },
    key,
    enc.encode(JSON.stringify(obj))
  );
  return { type: "enc", seq, payload: b64.encode(concatBytes(nonce, new Uint8Array(box))) };
}

async function openResponse(keyBytes, expectedSeq, message) {
  if (message.type !== "enc" || message.seq !== expectedSeq) throw new Error("bad sequence");
  const combined = b64.decode(message.payload);
  const key = await crypto.subtle.importKey("raw", keyBytes, "AES-GCM", false, ["decrypt"]);
  const plain = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: combined.slice(0, 12), additionalData: enc.encode(`2pw-enc-2-${expectedSeq}`) },
    key,
    combined.slice(12)
  );
  return JSON.parse(new TextDecoder().decode(plain));
}

async function pairingFromShared(sharedSecret, extPub, appPub) {
  const secret = await hkdf(
    sharedSecret, enc.encode("2pw-browser-pairing-v1"), concatBytes(extPub, appPub), 32);
  const codeBytes = await hkdf(secret, new Uint8Array(0), enc.encode("2pw-verification-code"), 4);
  const code = String(new DataView(codeBytes.buffer).getUint32(0) % 1000000).padStart(6, "0");
  return { secret, code };
}

async function sessionKeysFromShared(sharedSecret, pairingSecret, extEphPub, appEphPub) {
  const material = await hkdf(
    sharedSecret, pairingSecret,
    concatBytes(enc.encode("2pw-browser-session-v1"), extEphPub, appEphPub), 64);
  return { send: material.slice(0, 32), receive: material.slice(32, 64) };
}

// ---------------------------------------------------------------- transport

let session = null; // {port, send, receive, sendSeq, recvSeq, pending: Map, queue: []}

function connectPort() {
  return chrome.runtime.connectNative(HOST);
}

function postRaw(port, message) {
  port.postMessage(message);
}

// One in-flight wire exchange at a time keeps the seq counters in lockstep.
function nextFromPort(port) {
  return new Promise((resolve, reject) => {
    const onMessage = (m) => { cleanup(); resolve(m); };
    const onDisconnect = () => { cleanup(); reject(new Error(chrome.runtime.lastError?.message || "disconnected")); };
    const cleanup = () => {
      port.onMessage.removeListener(onMessage);
      port.onDisconnect.removeListener(onDisconnect);
    };
    port.onMessage.addListener(onMessage);
    port.onDisconnect.addListener(onDisconnect);
  });
}

async function getStoredPairing() {
  const data = await chrome.storage.local.get(["staticKeyPair", "pairingSecret"]);
  return data.pairingSecret ? data : null;
}

// Pair with the app. onCode is called with the verification code so the
// popup can display it while the user approves in 2Password.
async function pair(onCode) {
  const keyPair = await x25519Generate();
  const extPub = new Uint8Array(await crypto.subtle.exportKey("raw", keyPair.publicKey));

  const port = connectPort();
  try {
    postRaw(port, { type: "pair-request", publicKey: b64.encode(extPub) });
    const response = await nextFromPort(port);
    if (response.type === "error") throw new Error(response.message);
    if (response.type !== "pair-response") throw new Error("unexpected " + response.type);

    const appPub = b64.decode(response.publicKey);
    const shared = await x25519SharedSecret(keyPair.privateKey, appPub);
    const { secret, code } = await pairingFromShared(shared, extPub, appPub);
    onCode?.(code);

    const verdict = await nextFromPort(port);
    if (verdict.type !== "pair-confirmed") throw new Error("pairing rejected");

    await chrome.storage.local.set({
      staticKeyPair: {
        privateJwk: await crypto.subtle.exportKey("jwk", keyPair.privateKey),
        publicRaw: b64.encode(extPub),
      },
      pairingSecret: b64.encode(secret),
    });
  } finally {
    port.disconnect();
  }
}

async function startSession() {
  const stored = await getStoredPairing();
  if (!stored) throw new Error("not-paired");

  const eph = await x25519Generate();
  const ephPub = new Uint8Array(await crypto.subtle.exportKey("raw", eph.publicKey));
  const port = connectPort();
  postRaw(port, {
    type: "session-start",
    publicKey: stored.staticKeyPair.publicRaw,
    ephemeralKey: b64.encode(ephPub),
  });
  const accept = await nextFromPort(port);
  if (accept.type === "error") {
    port.disconnect();
    if (accept.message === "not paired") {
      // The app forgot us (e.g. Keychain reset) — force a fresh pairing.
      await chrome.storage.local.remove(["staticKeyPair", "pairingSecret"]);
      throw new Error("not-paired");
    }
    throw new Error(accept.message);
  }
  if (accept.type !== "session-accept") { port.disconnect(); throw new Error("unexpected " + accept.type); }

  const appEphPub = b64.decode(accept.ephemeralKey);
  const shared = await x25519SharedSecret(eph.privateKey, appEphPub);
  const keys = await sessionKeysFromShared(shared, b64.decode(stored.pairingSecret), ephPub, appEphPub);

  session = { port, send: keys.send, receive: keys.receive, sendSeq: 0, recvSeq: 0, rpcID: 0, busy: Promise.resolve() };
  port.onDisconnect.addListener(() => { if (session?.port === port) session = null; });
  return session;
}

async function rpc(method, params = {}) {
  let s = session;
  if (!s) s = await startSession();
  // Serialize exchanges so seq counters match the app's expectations.
  const run = s.busy.then(async () => {
    const request = { id: ++s.rpcID, method, ...params };
    const reply = nextFromPort(s.port);
    postRaw(s.port, await sealRequest(s.send, s.sendSeq, request));
    s.sendSeq += 1;
    const opened = await openResponse(s.receive, s.recvSeq, await reply);
    s.recvSeq += 1;
    return opened;
  });
  s.busy = run.catch(() => {});
  try {
    return await run;
  } catch (error) {
    if (session === s) { try { s.port.disconnect(); } catch {} session = null; }
    throw error;
  }
}

// ---------------------------------------------------------------- routing

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  (async () => {
    try {
      // A page's content script can only act on its own tab's URL — it must
      // not be able to request credentials (or save logins) for other sites.
      if (sender.tab && ["query", "fill-credentials", "save-login", "pending-fill"].includes(message.cmd)) {
        message.url = sender.tab.url;
      }
      switch (message.cmd) {
        case "state": {
          const paired = !!(await getStoredPairing());
          if (!paired) return sendResponse({ paired: false });
          const status = await rpc("status");
          return sendResponse({ paired: true, locked: !!status.locked });
        }
        case "pair": {
          await pair((code) => {
            chrome.runtime.sendMessage({ event: "pairing-code", code }).catch(() => {});
          });
          return sendResponse({ ok: true });
        }
        case "query": {
          const result = await rpc("credentials.query", { url: message.url });
          return sendResponse(result);
        }
        case "fill-credentials": {
          const result = await rpc("credentials.fill", { url: message.url, itemID: message.itemID });
          return sendResponse(result);
        }
        case "pending-fill": {
          // Don't trigger pairing UI from a page load; only ask when paired.
          if (!(await getStoredPairing())) return sendResponse({});
          const result = await rpc("fill.pending", { url: message.url });
          return sendResponse(result);
        }
        case "save-login": {
          const result = await rpc("login.save", {
            url: message.url, username: message.username,
            password: message.password, title: message.title,
          });
          return sendResponse(result);
        }
        default:
          return sendResponse({ error: "unknown command" });
      }
    } catch (error) {
      sendResponse({ error: error.message });
    }
  })();
  return true; // keep sendResponse alive across awaits
});
