# Passwards

A native macOS clone of 1Password 8 — Swift + SwiftUI, real cryptography, built for daily personal use.

![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue) ![Swift 6](https://img.shields.io/badge/Swift-6-orange)

## What's implemented

- **Real crypto, modeled on 1Password's security design (2SKD)**
  - Account password + locally generated **Secret Key** (`A3-XXXXXX-…`), shown once and stored only in the macOS Keychain + the **Emergency Kit PDF**
  - NFKD-normalized password → HKDF salt expansion (bound to email) → **PBKDF2-HMAC-SHA256 × 650,000** → XOR with HKDF(Secret Key) → Account Unlock Key
  - **AES-256-GCM** everywhere, with AAD binding ciphertexts to their record IDs; master key → per-vault keys → per-item keys
  - **Touch ID** unlock via a Secure Enclave key (invalidated on biometric re-enrollment, graceful password fallback)
  - Auto-lock (idle / sleep / screensaver / "require password after N hours"), ⇧⌘L, clipboard auto-clear (90 s, concealed pasteboard type), screen-capture-blocked windows
- **Full item model** — all 22 of 1Password's categories with their built-in field templates, custom fields & sections, tags (nested with `/`), favorites, archive, Recently Deleted (30-day purge), multiple vaults, move-between-vaults, **item edit history with restore**, password history, encrypted **file attachments** (25 MB)
- **Three-pane main window** faithful to 1P8: sidebar (account header, All Items, Favorites, Watchtower, vaults, categories with counts, tags, archive, trash), item list with category filter + sort, detail pane with click-to-copy rows, reveal/conceal, **Large Type**, strength bars, colored passwords (blue digits / red symbols), website favicons (fetched directly, no third-party proxy)
- **Password generator** — Random (8–100 chars), Memorable (EFF wordlist, 3–15 words, separators, capitalize), PIN; strength meter backed by a local estimator + top-100k breached-password list
- **TOTP** — RFC 6238 (verified against the RFC test vectors), otpauth:// or bare Base32 secrets, live countdown ring, copy-code actions
- **Quick Access** — ⇧⌘Space global panel (non-activating, works over any app): search, ⏎ copy password, ⌘C username, ⇧⌘C password, ⌥⌘C one-time code, ⇧⌘O open in app
- **Watchtower** — vulnerable passwords (HIBP k-anonymity range API — only 5 SHA-1 hex chars leave the Mac), reused, weak, unsecured http sites, 2FA-available (bundled 2fa.directory dataset), expiring items, duplicates; dashboard cards + per-item banners + per-check dismiss
- **Import / export** — 1Password **.1pux** (categories, fields, tags, history, attachments), CSV (Chrome / Bitwarden / LastPass / generic headers); CSV & JSON export gated behind **full password re-derivation**
- **CloudKit sync** (code complete; see activation below) — CKSyncEngine, encrypted blobs only, last-writer-wins with the losing edit preserved into item history, tombstoned deletions, new-device "sign in with existing account" flow
- Menu bar extra, Settings window (General / Appearance / Security / Privacy / Advanced), light/dark/system themes, login item

## Building

```bash
open Passwards.xcodeproj   # ⌘R — or:
xcodebuild -project Passwards.xcodeproj -scheme Passwards build
```

Unit tests (58 crypto/storage/TOTP/Watchtower/import tests, no signing needed):

```bash
cd Packages/PasswardsCore && swift test
```

## Activating iCloud sync (one-time)

The sync engine ships dormant because creating the iCloud provisioning profile requires your Apple ID in Xcode:

1. Xcode → Settings → Accounts → add your Apple ID (the paid team `L5774582ZK`).
2. Replace the contents of `Passwards/Passwards.entitlements` with `Passwards/Passwards+CloudKit.entitlements` (or point `CODE_SIGN_ENTITLEMENTS` at it).
3. Build once from Xcode — it auto-registers the `iCloud.com.michael.twopassword` container.
4. Before relying on sync day-to-day, deploy the schema to Production in the [CloudKit Console](https://icloud.developer.apple.com) (Development → Deploy Schema Changes).

The app detects the entitlement at runtime; the sync toggle and "sign in to existing account" appear automatically.

## Architecture

```
Packages/PasswardsCore   # SPM package: everything testable without the app
  Crypto/      2SKD key derivation, AES-GCM blobs, KeyStore actor, Keychain, Secure Enclave
  Models/      Item/Field/Section/Category (+ all 22 templates)
  Storage/     GRDB (SQLite) — ciphertext-only columns; repositories encrypt at the boundary
  Sync/        CKSyncEngine + record coding (ciphertext-only CKRecords)
  Generator/   password generator, strength estimator, EFF wordlist
  TOTP/        RFC 6238, otpauth parser, Base32
  Watchtower/  auditor, HIBP k-anonymity client, 2fa.directory matcher
  Importers/   1PUX, CSV, exporters
Passwards/                 # app target (SwiftUI, module name Passwards)
  App/  Theme/  Onboarding/  LockScreen/  Main/  QuickAccess/  Watchtower/
  Generator/  Settings/  Icons/
```

Dependencies: **GRDB**, **KeyboardShortcuts**, **ZIPFoundation**. All cryptography is CryptoKit + CommonCrypto — no third-party code touches key material.

Local data: `~/Library/Containers/com.michael.passwards/Data/Library/Application Support/2Password/` (SQLite DB + encrypted attachment files).

## Deliberately deferred (extension points stubbed in `ExtensionPoints.swift`)

- Browser extension & page autofill
- Passkey provider
- SSH agent + CLI
- Item sharing links (needs a server)

## Security notes

- Exports (CSV/JSON) are **plaintext by design**, mirror of 1Password's behavior; they require re-entering the account password and warn loudly.
- The Secret Key never leaves the device: it is not in the database and not synced to iCloud. Losing both the Mac and the Emergency Kit means the data is unrecoverable — that's the point.
- Swift cannot guarantee memory zeroization; like other Swift/Electron password managers, secrets may persist briefly in freed memory. Threat model = at-rest theft, not a compromised, root-level live machine.
