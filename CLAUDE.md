# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

2Password — a native macOS clone of 1Password 8 (Swift 6 + SwiftUI), built for the owner's daily personal use with real passwords. **Design fidelity to 1Password 8 is a hard requirement**: when touching UI, match 1P8's layout/colors/behavior, and prefer what real 1P8 does (e.g. the sidebar uses macOS's native translucent material — do not replace it with custom backgrounds).

Screen Recording permission is granted: after UI changes, verify your own work by relaunching the app and capturing it (`screencapture -x /tmp/shot.png`, then Read the PNG; `screencapture -l <windowid>` for a single window). Look at the result before declaring a design change done.

## Commands

```bash
# Build the app
xcodebuild -project 2Password.xcodeproj -scheme 2Password -configuration Debug build

# All unit tests live in the SPM package (no signing needed)
cd Packages/TwoPasswordCore && swift test

# Single suite / single test
cd Packages/TwoPasswordCore && swift test --filter Watchtower
cd Packages/TwoPasswordCore && swift test --filter "TOTPTests/rfc6238Vectors"

# Relaunch after build — MUST fully kill first, or macOS re-activates the old
# instance and the user sees stale UI:
osascript -e 'quit app "2Password"'; until ! pgrep -f "2Password.app/Contents/MacOS"; do sleep 0.5; done
open ~/Library/Developer/Xcode/DerivedData/2Password-*/Build/Products/Debug/2Password.app

# To screenshot the app's own windows (debug builds only): set the bypass env
# var via launchd, then relaunch with `open` as above. NEVER exec the binary
# directly — that bypasses LaunchServices and the browser-extension host will
# spawn duplicate app instances.
launchctl setenv TWOPW_ALLOW_CAPTURE 1
```

## Naming gotcha

Product/bundle is `2Password` / `com.michael.twopassword`, but Swift modules can't start with a digit: the app module is **`TwoPassword`**, the package is **`TwoPasswordCore`**. The app target uses Xcode 16 filesystem-synchronized groups — new files under `2Password/` are picked up automatically, no pbxproj edits needed.

## Architecture

Two layers with a strict boundary:

- **`Packages/TwoPasswordCore`** (SPM, fully testable headless): Crypto, Models, Storage (GRDB), Sync (CKSyncEngine), Generator, TOTP, Watchtower, Importers. Deps: GRDB, ZIPFoundation. Crypto is CryptoKit + CommonCrypto only — no third-party code may touch key material.
- **`2Password/`** (app target, SwiftUI, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`): all UI + AppKit integration (Quick Access NSPanel, hotkeys via KeyboardShortcuts, clipboard, Touch ID prompts).

### Encryption layering (the core invariant)

```
password ─NFKD→ HKDF(salt,email) → PBKDF2-SHA256×650k ─┐
SecretKey (Keychain-only, never in DB/CloudKit) ─HKDF──┴─XOR→ AUK
AUK → encMasterKey → per-vault keys → per-item keys → blobs/files
```

Every DB column and CKRecord field that carries item/vault data is AES-256-GCM ciphertext with **AAD = record-type:ID** (`EncryptedBlob`). Plaintext columns are limited to IDs, timestamps, and sync state. `KeyStore` (actor) holds decrypted keys while unlocked; `AppState.lock()` clears it. If you add a stored field, decide explicitly which side of the boundary it's on.

### Item model: overview/details split

`ItemOverview` (title, urls, tags, category, strength bucket…) is decrypted for ALL items at unlock and cached in `VaultStore.summaries` — it drives list/search/sidebar/most Watchtower checks. `ItemDetails` (sections → fields) is decrypted per item on demand. Anything derived (subtitle, urls, hasOTP, strengthBucket) is recomputed in `VaultStore.reconcileOverview` on save — update it if you add derived state. All 22 category templates are data in `CategoryTemplates.swift`; storage is always the generic sections/fields model.

### State flow (app side)

`AppState` (phase machine: onboarding → locked ⇄ unlocked) owns database/keyStore/repos/sync and the shared `VaultStore` (`ensureVaultStore()` — shared by MainWindow AND Quick Access; don't create a second one). Editing happens on a **local `@State` copy** in `ItemEditView`, never via bindings into `store.editorDraft` (force-unwrap crash history). Every detail-changing save snapshots the old payload into `item_versions` (history with restore).

### CloudKit sync (code-complete, dormant)

`SyncEngine` (CKSyncEngine, single "Main" zone, LWW conflicts with the losing payload preserved into local history, tombstone table for deletions) only activates when the binary has the iCloud entitlement — checked at runtime via `SecTaskCopyValueForEntitlement` in `SyncController` (CloudKit APIs crash uncatchably without it). Activation requires the owner's Apple ID in Xcode: swap `2Password/2Password.entitlements` for `2Password/2Password+CloudKit.entitlements` contents, build once, deploy schema to Production (steps in README). Sync runs while locked (ciphertext only); local mutations propagate via `VaultStore.refresh()` → `sync.kick()`.

### SSH agent + CLI (implemented)

**SSH agent** (`TwoPasswordCore/SSH/`): a vault-backed OpenSSH agent. `SSHKey` parses unencrypted OpenSSH private keys — Ed25519 & ECDSA P-256/384/521 (CryptoKit) and RSA (`SSHRSA` via Security/`SecKey`, with `SSHBigInt` computing the CRT exponents PKCS#1 needs; honors rsa-sha2-256/512 flags). `SSHAgentProtocol`/`SSHAgentServer` serve REQUEST_IDENTITIES + SIGN_REQUEST over a 0600 Unix socket in the App Group container (`SSHAgentServer.defaultSocketPath()` → `agent.sock`). App side: `SSHAgentController` (`SSHAgentBackend`) serves `.sshKey` items only while unlocked (locking sheds them); **every signature is gated on Touch ID** (`LocalAuthorization`, per-key approval cache) — Settings → SSH Agent. Note `.sshKey` fields use a multi-line editor and the parser is whitespace-tolerant (a single-line field would strip a pasted key's newlines).

**CLI** (`CLIMode`, dispatched from `Boot.main` alongside `--browser-host` — run the app binary directly): `ssh-agent` (print SSH_AUTH_SOCK line), `ssh-keys` (list public keys via `SSHAgentClient`), plus `item list` / `item get <item> [field]` / `read op://[vault/]item/field`. The `item`/`read` commands hit a second control socket (`TwoPasswordCore/CLI/`: `CLIControlServer`/`CLIControlClient`/`CLIControlController`, `cli.sock`), opt-in via Settings → Advanced → Command-Line Access, unlocked-only, with every secret read Touch-ID-gated. Both blocking clients share `UnixSocketClient`. Interop verified against real `ssh-add`. (Passphrase-encrypted keys unsupported — decrypt-on-import is the intended path.)

### Deferred features

Passkeys and item sharing are deferred **by the owner's explicit decision** — don't build them unprompted. Protocol seams live in `TwoPasswordCore/ExtensionPoints.swift`; `FieldKind.unknown(String)` preserves unrecognized field kinds for forward compatibility.

## Testing conventions

Swift Testing (`@Test`/`#expect`), not XCTest. Crypto/TOTP changes must keep the published test vectors green (PBKDF2/HKDF/RFC 6238 in `CryptoTests`/`TOTPTests`). `TestEnvironment.make()` (StorageTests) builds an unlocked in-memory DB + vault for repository-level tests — reuse it. Importer tests run against inline fixtures; HIBP is tested with recorded responses, never live calls.
