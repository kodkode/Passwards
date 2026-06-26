# Passwards — Test Log

A plain-English record of the automated tests, how to run them yourself, and a
dated log of each run. Re-run the commands below anytime and add a row to the
**Run log** to confirm everything still passes.

---

## How to run the tests yourself

**1. The full automated test suite** (no signing needed — these are the tests
that prove the data-safety and crypto logic):

```bash
cd Packages/PasswardsCore
swift test
```

A healthy result ends with a line like:

```
Test run with 131 tests in 24 suites passed
```

**2. The app builds cleanly** (compiles the whole macOS app):

```bash
xcodebuild -project Passwards.xcodeproj -scheme Passwards -configuration Debug -allowProvisioningUpdates build
```

A healthy result ends with:

```
** BUILD SUCCEEDED **
```

> Tip: to run just one area, e.g. the storage/bootstrap tests:
> `cd Packages/PasswardsCore && swift test --filter Storage`

---

## What the tests cover (in plain English)

There are **24 test suites**. Grouped by what they protect:

**Encryption & keys (the core security)**
- **Encrypted blobs** — data is sealed/opened with AES-256-GCM and the right tag.
- **Key derivation** — PBKDF2 / HKDF match the published reference vectors.
- **Account crypto** — unlock, recover, and change-password all reconstruct the right keys.
- **Secret key** / **KeyStore** — Secret Key parsing/formatting; keys clear on lock.
- **TOTP** — one-time codes match the RFC 6238 reference vectors.

**Your data is never silently lost or orphaned**
- **Storage** — items/vaults save, edit, trash, move, and keep history correctly.
  Includes the **bootstrap data-safety guards** (see highlighted section below).
- **Encrypted backup** — a `.pwbackup` can be created and fully restored.
- **Recovery code** / **RecoveryCode format** / **Recovery storage + sync** — the
  forgotten-password recovery flow works and survives password changes.
- **Model compatibility** — older saved data and synced records still decode
  (so updates don't strand existing items).
- **Sync record coding** — items round-trip to/from the iCloud record format.

**Import / export / passwords**
- **1PUX import** / **CSV import/export** — bringing data in and out works.
- **Password generator** / **Password strength** — generation and strength scoring.
- **Watchtower** / **PublicSuffixList** — weak/reused/breached checks and domain matching.

**Integrations**
- **SSH key** / **SSH agent protocol** — key parsing and the SSH agent socket.
- **CLI control** — the command-line read channel.
- **Browser bridge** / **Browser bridge server** — the extension pairing crypto and replay protection.

---

## ⭐ Highlighted: bootstrap data-safety guards (the June 2026 work)

These tests prove the app can **never orphan your vault** by accidentally
creating a second account over your existing data. They live in the **Storage**
suite — run `swift test --filter Storage`:

- **`createInitialAccountRefusesExistingAccount`** — if an account already
  exists, creating a new one is refused and the original is left untouched.
- **`createInitialAccountRefusesOrphanItems`** — if items remain but the account
  record is missing, a fresh account is refused (so the leftover items aren't
  stranded under a lost key).

What is **not** covered by automated tests (verified by build + reasoning only,
because a test would delete the real on-disk vault):
- `AppDatabase.destroyOnDiskVault()` — the actual file wipe behind "Erase & Start Over".
- The on-screen flows (the database-error screen, Try Again, the typed-`ERASE`
  confirmation). These are thin UI over the tested logic.

---

## Run log

Add a new row each time you run the tests, so we can compare over time.

| Date | Time | What ran | Result | Notes |
|------|------|----------|--------|-------|
| 2026-06-23 | 12:34 IDT | `swift test` (full suite) | ✅ 131/131 passed, 24 suites | After bootstrap fix (round 1, committed `6b65f5d`). |
| 2026-06-23 | ~12:00 IDT | `xcodebuild … build` | ✅ BUILD SUCCEEDED | App compiles with the new database-error screen. |
| 2026-06-23 | 12:39 IDT | `swift test` + `xcodebuild` | ✅ 131/131 passed · BUILD SUCCEEDED | Round 2: gated Erase & Start Over + orphan-items routing. Committed + pushed. |
| 2026-06-24 | 10:50 IDT | `xcodebuild … build` | ✅ BUILD SUCCEEDED | 1P8 fidelity polish: lock-screen redesign + roomier sidebar rows/fonts. UI-only; verified by screenshot. |
| 2026-06-24 | 13:30 IDT | `xcodebuild … build` | ✅ BUILD SUCCEEDED | All Items fidelity: toolbar (wide search + Help + blue New Item), compact account header, empty-pane illustration asset. UI-only; verified by screenshot. |
| 2026-06-24 | 18:11 IDT | `xcodebuild … build` | ✅ BUILD SUCCEEDED | Editor field drag-to-reorder (1P8 grip handles + within-section live reorder). UI-only; editor is behind the master password so it cannot be screenshotted headless — drag needs owner hands-on test. |
| 2026-06-24 | 18:44 IDT | `swift test` + `xcodebuild` | ✅ 131/131 passed · BUILD SUCCEEDED | Editor reorder extended: section reordering + cross-section field drag + empty-section drop zone. Hardened after two adversarial review passes — app-owned drag UTTypes (reject foreign drags / neutralize stale drag-state), empty-only append (no oscillation), section-grip enabled==visible, gutter alignment, and a destination clamp so custom fields can't drop above pinned username/password (1P8). UI-only; drag still needs owner hands-on test. |
| 2026-06-25 | — | `xcodebuild … build` | ✅ BUILD SUCCEEDED | Fix Touch ID auto-prompt loop on the lock screen: dismissing the system dialog (Cancel / Use Password…) re-activated the app and re-fired `didBecomeActive`, re-prompting endlessly so the user could never reach the password field. Now auto-prompt at most once per locked session (`biometricAutoPrompted`, re-armed on each fresh lock); manual Touch ID button unaffected. Needs owner hands-on test (lock screen is behind the master password). |
| 2026-06-25 | — | `xcodebuild … build` | ✅ BUILD SUCCEEDED | Follow-up to the same bug: the **manual** Touch ID button → Cancel still needed two clicks (manual path didn't mark the session prompted, so the dismissal re-activation auto-prompted once more). `unlockWithTouchID()` now sets `biometricAutoPrompted` up front, so any dialog (manual or auto) suppresses the dismissal re-prompt. Needs owner hands-on test. |
| 2026-06-26 | — | `swift test` + `xcodebuild` (macOS app + iOS core/orchestration) | ✅ 132/132 passed · macOS BUILD SUCCEEDED · iOS BUILD SUCCEEDED | **iOS Phase 0 groundwork (additive, macOS unchanged).** Added `.iOS(.v18)` + new `PasswardsOrchestration` SPM target/product (with `PlatformServices` protocol seams) to `Package.swift`; added `AppDatabase.vaultDirectory(appGroupIdentifier:)` overload threaded through `open`/`destroyOnDiskVault` (macOS passes `nil` → byte-identical Application Support path; iOS will pass the App Group id); `#if os(macOS)`-guarded the only iOS-incompatible core API (`homeDirectoryForCurrentUser` socket fallback in SSH/CLI/BrowserBridge servers — unreachable on iOS). Verified: `PasswardsCore` + `PasswardsOrchestration` both build for `generic/platform=iOS`; macOS app still builds; full suite green (131 prior + 1 new orchestration smoke test). Orchestration extraction (AccountController/VaultDataModel) is the next step. |
| 2026-06-26 | — | `xcodebuild` (macOS app) + `swift test` | ✅ 132/132 passed · macOS BUILD SUCCEEDED | **iOS Phase 0 — first orchestration move: `SyncController`.** Moved `Passwards/App/SyncController.swift` → `PasswardsOrchestration` (made `public` + explicit `@MainActor`, since the package target has no default actor isolation); wired the macOS app to link the `PasswardsOrchestration` product (pbxproj: PBXBuildFile + Frameworks phase + packageProductDependencies + XCSwiftPackageProductDependency, mirroring `PasswardsCore`); added `import PasswardsOrchestration` to the 6 app files that use the sync API (AppState, AppDelegate, SettingsScene, OnboardingFlow, VaultStore, MainWindow, SidebarView). Validates the whole cross-module mechanism (pbxproj linking + public/MainActor surface) end-to-end before the larger AccountController/VaultDataModel extraction. macOS app builds; suite green. |
| 2026-06-26 | — | `xcodebuild` (macOS app + iOS orchestration) + `swift test` | ✅ 132/132 passed · macOS BUILD SUCCEEDED · iOS BUILD SUCCEEDED | **iOS Phase 0 — `AccountController` extraction (the account/unlock/lock lifecycle).** Moved ~90% of `AppState` (phase machine, repos, createAccount/signIn/unlock/lock/changePassword/recovery×4/backup×3/applyRestore/unlockWithTouchID) into a shared `@MainActor @Observable AccountController` in `PasswardsOrchestration`; platform behavior injected via the seams (`AutoLockService` — `AutoLockMonitor` now conforms; `PasteboardService` — new `MacPasteboardService` over `ClipboardManager`) + vault hooks (`onVaultShouldClearSecrets/Refresh`). `AppPhase`/`SettingsKeys`/`SymmetricKeyBox` moved to orchestration. macOS `AppState` is now a thin `@Observable` shell forwarding to `core` (views untouched; nested error types kept as typealiases); kept the macOS-only glue (browser/SSH/CLI controllers, `didBecomeActive` observer, `NSApp.isActive`). Made the service protocols `@MainActor` (witnesses touch AppKit) and guarded `SyncController.hasCloudKitEntitlement`'s `SecTask*` probe behind `#if os(macOS)` (iOS returns true — it always carries declared entitlements). macOS app builds, suite green, orchestration builds for iOS. VaultStore/VaultDataModel extraction is next. |

<!--
To add a row, copy the line below and fill it in:
| YYYY-MM-DD | HH:MM TZ | swift test (full suite) | ✅ N/N passed | … |
-->
