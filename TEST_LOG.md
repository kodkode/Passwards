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
| 2026-06-26 | — | `xcodebuild` (PasswardsiOS) | ✅ iOS BUILD SUCCEEDED | **Fix: iOS items not downloading after sign-in.** On-device sign-in now succeeds (creds were always correct; the wrapped field revealed the full `A3-SH…` key, and iCloud got authenticated). But the list stayed empty — `IOSHomeView.task` only called `load()` once, so items CloudKit delivered in the background never refreshed the UI. Mirrored macOS `MainWindow`: wire `core.sync.onRemoteChanges = { reload }` + `sync.kick()` in the home `.task`, so the list reloads when each sync round finishes. Also added pull-to-refresh (`.refreshable { vault.refresh() }`) and made the list always-present with the empty state as an overlay (so refresh works even when empty). iOS builds. Awaiting owner re-test (items should populate after sync; pull-to-refresh as fallback). |
| 2026-06-26 | — | `swift test` + `xcodebuild` (macOS app + PasswardsiOS sim) | ✅ **147/147 passed** · macOS BUILD SUCCEEDED · iOS BUILD SUCCEEDED | **Fix: iOS sign-in Secret Key UX + robust parsing.** Owner's on-device sign-in failed with correct creds; the entered key read `SD5W-…` (6 groups/30 chars) instead of the valid `A3-…` (7 groups/34 chars) — most likely the single-line field scrolled the leading `A3-XXXXXX-` off-screen. Fixes: (1) `SecretKey(parsing:)` now strips ALL non-alphanumerics (en/em dashes from iOS smart-punctuation, NBSP, any whitespace) instead of only `-`/space — robustness; added en/em-dash + whitespace cases to `parsingRoundTrip`. (2) New `AccountController.UnlockError.invalidSecretKeyFormat`, thrown when the key won't parse (vs `.wrongCredentials` for an unlock failure), so the UI distinguishes "bad key format" from "wrong password". (3) iOS sign-in field now wraps (`axis: .vertical`, 2–4 lines) so the WHOLE key is visible, with a "starts with A3-, 7 groups" hint and specific per-error messages. Crypto suite + full 147 green; both apps build. Awaiting owner re-test on device. |
| 2026-06-26 | — | `xcodebuild` (macOS app + PasswardsiOS sim) + `simctl` screenshots | ✅ macOS BUILD SUCCEEDED · iOS app BUILD SUCCEEDED · **item UI renders (list/detail/editor/generator/picker)** | **iOS Phase 1f–1g — the item UI + generator.** Added `IOSVaultModel` (iOS vault view-model: summary cache + CRUD via the shared repos, filter/sort/derivation via `VaultQuery`; the iOS analog of macOS `VaultStore`, with a `#if DEBUG seedPreview()`), wired to the controller's vault hooks in `IOSAppModel`. Built `IOSItemListView` (searchable, month-sectioned, swipe favorite/trash, sort menu, "+"→picker), `IOSItemDetailView` (header + filled fields with tap-to-copy / reveal / **live TOTP countdown** / open-URL + notes), `IOSItemEditorView` (local-`@State`-copy edit/create, secure fields + reveal + generate, create→`vault.create`/edit→`vault.save`), `IOSCategoryPickerView` (all 22 categories with 1P8 `IconTile`/`CategoryIcon`), and `IOSGeneratorView` (random/memorable/PIN + colored output + strength + copy). Home tab bar now wires Items→list, Generator→generator. Verified on the simulator via `-uiPreview` with seeded data: **list, detail (live OTP "244 530"/4s), editor, generator (Excellent), and the 22-category picker all render** with correct 1P8 tile colors/glyphs. macOS app still builds. Owner approved the slice design (proceed); app-mark art TBD by owner. |
| 2026-06-26 | — | `xcodebuild` (macOS app + PasswardsiOS sim) + `simctl` run/screenshots | ✅ macOS BUILD SUCCEEDED · iOS app BUILD SUCCEEDED · **4 screens render on simulator** | **iOS Phase 1c–1d + onboarding — the UI vertical slice.** Built iOS `Theme` (brand azure/hero gradient/strength colors, `Color(light:dark:)` via UIColor, `AppMark`, `StrengthBar`), `IOSOnboardingView` (welcome → create account → Secret Key → Face ID, + sign-in via `SyncController.fetchRemoteAccount` + `core.signInToExistingAccount`), `IOSLockView` (dark 1P8 lock screen: app mark + reveal/submit password field + Face ID + Secret Key field when needed), `IOSHomeView` (bottom `TabView`: Items/Generator/Settings with a working **Lock Now**), and an `IOSDatabaseErrorView`. `IOSRootView` now switches to the real views. Added a `#if DEBUG` `-uiPreview <screen>` launch-arg router to render one screen for capture. Verified on the simulator: **welcome, create-account, lock, and home all render** correctly (screenshots captured). macOS app still builds (pbxproj edits via the xcodeproj gem didn't disturb it). Next: full item list/detail/editor + generator. |
| 2026-06-26 | — | `xcodebuild` (macOS app + PasswardsiOS sim) + `simctl` run | ✅ macOS BUILD SUCCEEDED · iOS app BUILD SUCCEEDED · **runs on simulator → onboarding** | **iOS Phase 1a — the `PasswardsiOS` app target exists, builds, and runs.** Created the iOS app target via the `xcodeproj` Ruby gem (bundle id `com.michael.passwards`, iOS 18, iPhone-only, MainActor default isolation, `GENERATE_INFOPLIST_FILE`, Face ID usage string), linked both `PasswardsCore` + `PasswardsOrchestration` products, and added `PasswardsiOS/` sources. New `PasswardsiOS.entitlements`: App Group `group.com.michael.passwards` (iOS-style, for the app + future AutoFill ext), keychain group + iCloud container matching macOS exactly. Minimal SwiftUI app (`IOSAppModel` owns the shared `AccountController` + iOS `PasteboardService`/`AutoLockService`; `IOSRootView` switches on phase). Verified: macOS app still builds (gem didn't disturb it); the iOS app builds for the simulator AND **launches → bootstraps via the shared AccountController → App Group container resolves → empty vault → onboarding screen renders**. Confirms the entire shared orchestration runs on iOS. Next: iOS Theme + the real lock/onboarding/items UI. |
| 2026-06-26 | — | `swift test` + `xcodebuild` (macOS app + iOS orchestration) + relaunch smoke test | ✅ **147/147 passed** · macOS BUILD SUCCEEDED · iOS BUILD SUCCEEDED · app bootstraps to lock screen | **iOS Phase 0 COMPLETE — shared `VaultQuery` + gate.** Extracted the pure, complex, reusable vault logic — `filteredSorted` (sidebar/search/category filter + sort), `grouped` (1P8 month sections), `reconcileOverview` (subtitle/urls/OTP/strength) — into a navigation-free `VaultQuery` in `PasswardsOrchestration` with a neutral `VaultFilter`/`VaultSortKey` (Watchtower resolved to flagged IDs by the app, so the layer stays Watchtower-free). macOS `VaultStore` now delegates to it (public surface unchanged: `reconcileOverview`/`visibleSummaries`/`groupedSummaries`/`SortKey`/`SidebarFilter` all intact → zero view churn). The navigation-coupled data ops (CRUD that mutates selection) stay platform-side by design; iOS's VaultDataModel will reuse the same repos + `VaultQuery`. Added **15 `VaultQueryTests`** (filter/search/sort/group/reconcile/credit-card-mask). Gate: 147 tests green, macOS app builds, orchestration builds for `generic/platform=iOS`; relaunched the macOS app — it bootstraps against the real vault and sits idle at the lock screen (PID stable, 0% CPU, no crash report). **Owner hands-on test still needed:** unlock → browse → edit → lock (behind the master password; can't be done headless). |

<!--
To add a row, copy the line below and fill it in:
| YYYY-MM-DD | HH:MM TZ | swift test (full suite) | ✅ N/N passed | … |
-->
