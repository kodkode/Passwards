# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Passwards — a native macOS clone of 1Password 8 (Swift 6 + SwiftUI), built for the owner's daily personal use with real passwords. **Design fidelity to 1Password 8 is a hard requirement**: when touching UI, match 1P8's layout/colors/behavior, and prefer what real 1P8 does (e.g. the sidebar uses macOS's native translucent material — do not replace it with custom backgrounds).

Screen Recording permission is granted: after UI changes, verify your own work by relaunching the app and capturing it (`screencapture -x /tmp/shot.png`, then Read the PNG; `screencapture -l <windowid>` for a single window). Look at the result before declaring a design change done.

## Commands

```bash
# Build the app
xcodebuild -project Passwards.xcodeproj -scheme Passwards -configuration Debug -allowProvisioningUpdates build

# All unit tests live in the SPM package (no signing needed)
cd Packages/PasswardsCore && swift test

# Single suite / single test
cd Packages/PasswardsCore && swift test --filter Watchtower
cd Packages/PasswardsCore && swift test --filter "TOTPTests/rfc6238Vectors"

# Relaunch after build — MUST fully kill first, or macOS re-activates the old
# instance and the user sees stale UI:
osascript -e 'quit app "Passwards"'; until ! pgrep -f "Passwards.app/Contents/MacOS"; do sleep 0.5; done
open ~/Library/Developer/Xcode/DerivedData/Passwards-*/Build/Products/Debug/Passwards.app

# To screenshot the app's own windows (debug builds only): set the bypass env
# var via launchd, then relaunch with `open` as above. NEVER exec the binary
# directly — that bypasses LaunchServices and the browser-extension host will
# spawn duplicate app instances.
launchctl setenv TWOPW_ALLOW_CAPTURE 1
```

## Naming gotcha

Product/bundle is `Passwards` / `com.michael.passwards`; the app module is **`Passwards`** and the package is **`PasswardsCore`**. The app target uses Xcode 16 filesystem-synchronized groups — new files under `Passwards/` are picked up automatically, no pbxproj edits needed.

**Legacy identifiers kept on purpose** (the app was renamed from "2Password" — renaming these too would orphan live data): the on-disk vault is still `…/Application Support/2Password/2password.sqlite` (+ `Attachments/`), the IPC sockets are still `.2password-*.sock`, and the CloudKit container is still `iCloud.com.michael.twopassword`. These stayed at the old names so the existing vault and any cloud data remain reachable after the rename. Everything user-visible plus the bundle id are `Passwards` / `com.michael.passwards`. Building the renamed bundle id the first time needs `-allowProvisioningUpdates` (Xcode registers its iCloud/Push profile).

## Architecture

Two layers with a strict boundary:

- **`Packages/PasswardsCore`** (SPM, fully testable headless): Crypto, Models, Storage (GRDB), Sync (CKSyncEngine), Generator, TOTP, Watchtower (+ `PublicSuffixList`), Importers, BrowserBridge, SSH agent, CLI control. Deps: GRDB, ZIPFoundation. Crypto is CryptoKit + CommonCrypto only — no third-party code may touch key material.
- **`Passwards/`** (app target, SwiftUI, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`): all UI + AppKit integration (Quick Access NSPanel, hotkeys via KeyboardShortcuts, clipboard, Touch ID prompts).

### Encryption layering (the core invariant)

```
password ─NFKD→ HKDF(salt,email) → PBKDF2-SHA256×650k ─┐
SecretKey (Keychain-only, never in DB/CloudKit) ─HKDF──┴─XOR→ AUK
AUK → encMasterKey → per-vault keys → per-item keys → blobs/files
```

Every DB column and CKRecord field that carries item/vault data is AES-256-GCM ciphertext with **AAD = record-type:ID** (`EncryptedBlob`). Plaintext columns are limited to IDs, timestamps, and sync state. `KeyStore` (actor) holds decrypted keys while unlocked; `AppState.lock()` clears it — and also sheds the decrypted `VaultStore` caches (summaries + any in-progress edit draft) and any secret left on the clipboard. If you add a stored field, decide explicitly which side of the boundary it's on.

**Touch ID unlock** (`BiometricUnlock`) wraps the master key (ECIES) to a **non-exportable Secure Enclave key** kept in the Keychain; locking sheds the decrypted key, unlock decrypts via the SE — it's cryptographically enforced, not a bypassable `evaluatePolicy` boolean. The SE key is **per-device and never syncs**, so each new Mac re-enrolls (Settings → Security toggle, while unlocked). **The app entitlements MUST include `keychain-access-groups` = `$(AppIdentifierPrefix)com.michael.passwards`** (same as the default app group, so existing items stay readable) — without it, creating the SE key fails with `OSStatus -34018` (errSecMissingEntitlement) and enrollment silently fails. The lock screen auto-prompts Touch ID on app **launch/activation** (an `AppState` `didBecomeActive` observer), not on lock-screen appearance, so manually locking doesn't immediately re-prompt.

### Item model: overview/details split

`ItemOverview` (title, urls, tags, category, strength bucket…) is decrypted for ALL items at unlock and cached in `VaultStore.summaries` — it drives list/search/sidebar/most Watchtower checks. `ItemDetails` (sections → fields) is decrypted per item on demand. Anything derived (subtitle, urls, hasOTP, strengthBucket) is recomputed in `VaultStore.reconcileOverview` on save — update it if you add derived state. All 22 category templates are data in `CategoryTemplates.swift`; storage is always the generic sections/fields model. New `ItemOverview` fields must be **optional / have safe defaults** so old encrypted blobs and synced records still decode (e.g. the custom item-icon `iconSymbol`/`iconColor` are `String?` — backward-compatible, no migration). `ItemIconView` (+ the editor/detail headers) render precedence: custom icon → favicon → category tile.

### State flow (app side)

`AppState` (phase machine: onboarding → locked ⇄ unlocked) owns database/keyStore/repos/sync and the shared `VaultStore` (`ensureVaultStore()` — shared by MainWindow AND Quick Access; don't create a second one). Editing happens on a **local `@State` copy** in `ItemEditView`, never via bindings into `store.editorDraft` (force-unwrap crash history). Every detail-changing save snapshots the old payload into `item_versions` (history with restore).

### CloudKit sync (ACTIVE — verified across two Macs)

`SyncEngine` (CKSyncEngine, single "Main" zone, LWW conflicts with the losing payload preserved into local history, tombstone table for deletions) is **live**: the committed build signs with `Passwards/Passwards+CloudKit.entitlements` (`CODE_SIGN_ENTITLEMENTS`), `com.michael.passwards` is provisioned for iCloud + Push, and sync was verified working across the owner's two Macs (same iCloud account, **Development** CloudKit environment — record types auto-create on first write; deploying schema to **Production** is only needed for a non-dev/distributed build). `SyncController` still gates it at runtime via `SecTaskCopyValueForEntitlement` (CloudKit APIs crash uncatchably without the entitlement). A new device uses Onboarding → **"Sign in to an existing account"**: it pulls the account record from CloudKit, then you enter the account password + Secret Key (the Secret Key never syncs). Sync runs while locked (ciphertext only); local mutations propagate via `VaultStore.refresh()` → `sync.kick()`. The iCloud container is still `iCloud.com.michael.twopassword` (kept across the rename so existing cloud data stays reachable).

### Account recovery + encrypted backup (both opt-in)

**Recovery code** (`AccountCrypto.enableRecovery/recover`, `Crypto/RecoveryCode.swift`): opt-in forgotten-password recovery. A ~147-bit code (created while unlocked, **gated on re-entering the current password**) seals the **master key + Secret Key** into `recoveryBlob` (AAD `recovery:<accountID>`, derived `HKDF(code, accountID)`), stored in the account row and synced. Recovery reconstructs both keys and sets a new password; the code is **reusable and survives password changes** (`changePassword` forwards the recovery fields). The account row gained `recoveryEnabled`/`recoveryBlob`/`encRecoveryCode` via migration **`v4-recovery-code`** (nullable/defaulted → backward-compatible) plus additive CKRecord fields older clients tolerate. Turning recovery **off overwrites the blob with random bytes** (not NULL) because a freshly-built CKRecord can overwrite but can't delete a server field — so the stale CloudKit copy can't be reopened. Same-Mac recovery reads the **local** blob (works with no iCloud); a new Mac pulls it from CloudKit. UI: Settings → Security, onboarding, lock screen. **Security trade (owner-accepted): an encrypted copy of the Secret Key now lives in iCloud sealed under the code — guard the code like the Secret Key.**

**Encrypted backup** (`PasswardsCore/Backup/`: `BackupArchive` + `BackupStore`): a single `.pwbackup` file = a readable header (the `AccountRecord` — KDF params, `encMasterKey`, recovery fields) + the whole vault (all rows + attachment ciphertext files) sealed under the master key (AAD `backup:<accountID>`). Opening **reuses `AccountCrypto.unlock`/`recover`** against the header → master key → open payload; no new crypto. Create while unlocked (File menu / Settings → Advanced). **Restore replaces the entire local vault** — `BackupStore.restore` clears all rows + attachment files then re-inserts with `syncState="pending"` and `ckSystemFields=nil` so it re-syncs cleanly, and resets Touch ID (the SE wrap may no longer match). Offered in **onboarding** (fresh Mac, no iCloud needed) and **Settings → Advanced**; unlock with password+Secret Key or a recovery code (the recovery-code path also sets a new password). This is the off-device backstop for non-iCloud users. App glue: `AppState.makeBackupData()`/`restoreBackup(...)`, `Passwards/Backup/` (`Backup.swift` panels, `RestoreBackupSheet`).

### In-app Help (+ website Help)

The macOS **Help menu → "Passwards Help"** opens a window (`Passwards/Help/HelpView.swift`) that renders **`Passwards/Help/PasswardsHelp.md`** as a grouped multi-article library via a small built-in Markdown renderer (articles split on `#` headings, grouped by `<!-- GROUP: name -->` marker comments). **That one bundled `.md` is the single source for BOTH the in-app Help and the website Help section** — edit it once. The synchronized group auto-bundles it as a resource (no pbxproj edit). New feature articles should be written/verified against the actual code.

### Browser extension + bridge (implemented)

`BrowserExtension/` is the single source of truth for the extension (Chrome/Brave/Edge load it unpacked); `scripts/sync-safari-extension.sh` copies it verbatim into `SafariExtension/Resources/` (only the manifest differs — edit `BrowserExtension/` then re-run the script, never edit the Safari copy). The same app binary is the native-messaging host in `--browser-host` mode (`BrowserHostMode`): a dumb byte pipe between the extension's stdio and the bridge socket. `PasswardsCore/BrowserBridge/`: `BrowserChannelCrypto` (one-time X25519 pairing the user approves via a 6-digit code → per-connection ephemeral session keys → AES-256-GCM, nonce = direction+counter, strict per-direction sequence for replay protection), `BrowserWire` (native-messaging framing + `BrowserRequest`/`BrowserResponse`), `BrowserBridgeServer` (actor, 0600 socket in the App Group container, state keyed by `cid`). App side: `BrowserBridgeController` serves credentials **only while unlocked**, pairings in the Keychain; which item is released is matched on the page's registrable domain (eTLD+1) via `WatchtowerAuditor.registrableDomain` → `PublicSuffixList` (bundled Mozilla PSL; `scripts/update-psl.sh` refreshes it) — never a last-two-labels guess. "Open & Fill" stages a one-shot same-domain auto-submit fill. Settings → Browser installs/repairs the per-browser native-messaging manifest (`BrowserIntegration`).

### SSH agent + CLI (implemented)

**SSH agent** (`PasswardsCore/SSH/`): a vault-backed OpenSSH agent. `SSHKey` parses unencrypted OpenSSH private keys — Ed25519 & ECDSA P-256/384/521 (CryptoKit) and RSA (`SSHRSA` via Security/`SecKey`, with `SSHBigInt` computing the CRT exponents PKCS#1 needs; honors rsa-sha2-256/512 flags). `SSHAgentProtocol`/`SSHAgentServer` serve REQUEST_IDENTITIES + SIGN_REQUEST over a 0600 Unix socket in the App Group container (`SSHAgentServer.defaultSocketPath()` → `agent.sock`). App side: `SSHAgentController` (`SSHAgentBackend`) serves `.sshKey` items only while unlocked (locking sheds them); **every signature is gated on Touch ID** (`LocalAuthorization`, per-key approval cache) — Settings → SSH Agent. Note `.sshKey` fields use a multi-line editor and the parser is whitespace-tolerant (a single-line field would strip a pasted key's newlines).

**CLI** (`CLIMode`, dispatched from `Boot.main` alongside `--browser-host` — run the app binary directly): `ssh-agent` (print SSH_AUTH_SOCK line), `ssh-keys` (list public keys via `SSHAgentClient`), plus `item list` / `item get <item> [field]` / `read op://[vault/]item/field`. The `item`/`read` commands hit a second control socket (`PasswardsCore/CLI/`: `CLIControlServer`/`CLIControlClient`/`CLIControlController`, `cli.sock`), opt-in via Settings → Advanced → Command-Line Access, unlocked-only, with every secret read Touch-ID-gated. Both blocking clients share `UnixSocketClient`. Interop verified against real `ssh-add`. (Passphrase-encrypted keys unsupported — decrypt-on-import is the intended path.)

### Deferred features

Passkeys and item sharing are deferred **by the owner's explicit decision** — don't build them unprompted. Protocol seams live in `PasswardsCore/ExtensionPoints.swift`; `FieldKind.unknown(String)` preserves unrecognized field kinds for forward compatibility.

## Testing conventions

Swift Testing (`@Test`/`#expect`), not XCTest. Crypto/TOTP changes must keep the published test vectors green (PBKDF2/HKDF/RFC 6238 in `CryptoTests`/`TOTPTests`). `TestEnvironment.make()` (StorageTests) builds an unlocked in-memory DB + vault for repository-level tests — reuse it. Importer tests run against inline fixtures; HIBP is tested with recorded responses, never live calls.

## Dev references

- **`docs/agent-teams.md`** — master reference for orchestrating **agent teams** (one lead + peer teammates that share a task list and message via `SendMessage`): when to use teams vs subagents vs the `Workflow` tool, spawning/steering, the real tools/settings/limits, and Passwards-specific fit (parallel security review, cross-layer core/app features, disjoint-file ownership across the strict layer boundary). Agent teams are **enabled for this repo** via `.claude/settings.local.json` (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`); restart Claude Code for it to take effect.
