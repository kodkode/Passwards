# Handoff: Passwards — iOS Password Manager App

## Overview
Passwards is a consumer iOS password-manager app. It lets a user store logins, passwords, secure notes, credit cards, identities, and Wi-Fi passwords; browse them by vault and category; check an overall security score ("Sentinel"); generate strong passwords; and unlock with Face ID or a passcode. This package documents the full app: onboarding, lock screen, four main tabs, and six modal sheets.

## About the Design Files
The files in this bundle are **design references created in HTML** — interactive prototypes that show the intended look and behavior. **They are not production code to copy directly.** The task is to **recreate these designs in the target codebase's environment** using its established patterns.

Because this is an iOS app, the natural target is **SwiftUI (or UIKit)** in a native iOS project. Recreate the screens with native components, system materials, and navigation. If the team instead builds with React Native / Expo, use that framework's idioms. Do not ship the HTML.

The prototype is built as "Design Components" (`.dc.html`) — a lightweight in-house template runtime. You can open any `.dc.html` in a browser to see it render. `PhoneApp.dc.html` is the entire app (all screens + logic). `Passwards.dc.html` just mounts three theme variants side by side for review. `ios-frame.jsx` is only the device bezel/status bar used for presentation — **not part of the app**; a native build gets the real status bar and safe areas from the OS.

## Fidelity
**High-fidelity.** Final colors, typography, spacing, corner radii, copy, and interactions are all specified. Recreate the UI pixel-accurately. The one thing to swap for native equivalents: the faux "liquid glass" blur on the tab bar (HTML `backdrop-filter`) → use a real system material (`.ultraThinMaterial` / `UIBlurEffect`).

### Chosen direction
The prototype contains three theme variants (`premium`, `friendly`, `playful`). **The committed direction is `playful` in light mode** (referenced as "2b"/"3a" in the review file). Build that. The other variants and dark mode are documented in code (`THEMES` / `PALETTES` objects in `PhoneApp.dc.html`) and can inform a theming layer, but are not required for v1. Note: the app supports a live Light/Dark toggle in Settings, so implement both light and dark palettes for the playful theme.

---

## Design Tokens — Playful theme

### Colors (OKLCH — convert to your color system)
**Light mode**
- `bg`: `oklch(97% 0.016 280)` — app background (very light lavender-white)
- `surface`: `oklch(100% 0.007 280)` — cards, sheets
- `surfaceAlt`: `oklch(94% 0.02 280)` — inset inputs, secondary surfaces
- `border`: `oklch(88% 0.022 280)` — hairline dividers/borders
- `text`: `oklch(19% 0.016 280)` — primary text
- `textMuted`: `oklch(47% 0.018 280)` — secondary text
- `accent`: `oklch(58% 0.19 264)` — primary blue/indigo (buttons, active states, links)
- `accentSoft`: `oklch(90% 0.05 264)` — active tab pill background, avatar background
- `accentText`: `oklch(99% 0 0)` — text/icon on accent (white)

**Dark mode**
- `bg`: `oklch(15% 0.016 280)`, `surface`: `oklch(20% 0.02 280)`, `surfaceAlt`: `oklch(25% 0.022 280)`
- `border`: `oklch(33% 0.022 280)`, `text`: `oklch(97% 0.008 280)`, `textMuted`: `oklch(71% 0.016 280)`
- `accent`: `oklch(64% 0.19 264)`, `accentSoft`: `oklch(33% 0.07 264)`, `accentText`: `oklch(99% 0 0)`

**Semantic / fixed colors**
- Destructive (Delete, Sign Out, errors): `oklch(62% 0.19 25)` (red)
- Item avatar colors (per-item, fixed hex): `#3B82F6 #F59E0B #8B5CF6 #EF4444 #10B981 #06B6D4 #F43F5E #84CC16`
- Sentinel gauge gradient: `#2FB84B` → `#28C0BC` → `#3B9EFF` (green → teal → blue)
- Sentinel gauge pointer: `#34C759`
- Password strength meter: red `oklch(62% 0.19 25)`, amber `oklch(72% 0.16 65)`, green `oklch(60% 0.15 150)`

### Typography (Playful)
- Headings/large titles/numbers: **Fredoka**, weight 600
- Body/labels: **DM Sans**, weights 400/500/700
- Type sizes: large screen title 30px (letter-spacing −0.5px); sheet title 16px/700; row title 15px/600; row subtitle 12.5px; section header 12.5px/700 UPPERCASE letter-spacing 0.5px; body 14.5px; score number 48px/700.

### Radii
- Card / large surface: **28px** (`radiusCard`)
- Badge / pill chip: **20px** (`radiusBadge`)
- Inputs: 14px; item icon tile: 11px; avatar: 50%; sheet top corners: 34px; tab bar: 26px.

### Spacing / layout
- Screen horizontal padding: 20px. Screen content vertical: 64px top (clears status bar), ~110px bottom (clears tab bar).
- Vertical rhythm between blocks: 20px. Section header → card gap: 10px. Row padding: 12px 16px.
- Row dividers: 1px solid `border`, inset to align under text (not full-bleed).

### Shadows
- Floating avatars/buttons and app icon: soft `0 8px 22px rgba(0,0,0,0.18)` range.
- Tab bar: translucent surface + 1px border, `backdrop-filter: blur(20px) saturate(180%)`.

---

## Screens / Views

### 1. Onboarding (3 slides)
- **Purpose:** First-run intro. Skippable.
- **Layout:** Full screen. "Skip" top-right (muted). Centered column: icon (104px), title (Fredoka), body (muted, 15px, line-height 1.5). Page dots near bottom (active dot = 20×6 pill in accent; inactive = 6×6 muted 40% opacity). Full-width primary button at bottom (accent, pill, 16px/700).
- **Slides (copy is playful theme):**
  1. Icon = **Passwards app icon** (`app_icon.png`, 104px, radius 24). Title "Your secrets, locked down" / body "Passwords, cards, notes — all sealed up tight and just for you."
  2. Icon = glossy "password" glyph. "Passwords, but make them strong" / "One tap and boom — a password no one is guessing. Ever."
  3. Icon = glossy "key" glyph. "Breeze through sign-ins" / "Autofill swoops in so you can skip the typing and get on with it."
- Button label: "Next" on slides 1–2, "Get Started" on slide 3. Skip or finishing → Lock screen.

### 2. Lock Screen
- **Purpose:** Authenticate to enter the app.
- **Layout:** Centered brand block (Passwards app icon 92px, "Passwards" title, muted greeting "You're back! Let's go"). Bottom auth area.
- **Two modes:**
  - **Face ID (default):** Large 74px circular accent button with a Face-ID glyph. Tapping runs a scan pulse animation. **First tap intentionally fails** (shows "Not recognized — try again", button shakes/turns red briefly); **second tap succeeds** → app. Link below: "Enter Passcode Instead".
  - **Passcode:** 4 dot indicators + 3×4 numeric keypad (keys are 60px circles, active state = subtle fill; bottom-right = backspace ⌫). **Demo correct code = `1234`.** Wrong 4-digit entry → dots shake (`pw-shake` animation), red "Wrong passcode — try again", then clears. Correct → app. Link: "Use Face ID Instead". (In the real app, wire to LocalAuthentication / real passcode.)

### 3. Home tab
- Header row: tappable avatar "AR" (accentSoft bg) + chevron on left (opens Settings); circular "+" button on right (opens Add sheet). This header row is shared across all four tabs.
- Large title (greeting, e.g. "Hey, Alex!") + muted subtitle.
- **Nudge card:** row with message + a "1 step" badge pill (accent bg, white).
- **Promo card:** accent-colored card with a globe icon, title "Passwards, now in your browser", body. White text on accent.
- **Favorites** (collapsible section, chevron rotates): card list of favorite items (avatar tile with letter, name, subtitle). Tapping a row opens Item Detail.
- **Recently Created** (collapsible): same row style. New items the user saves appear here.

### 4. Items tab
- Shared header + large title ("Your Stuff").
- **All Items** row (card with a list icon + chevron) → opens Collection sheet listing every item.
- **Vaults** section: rows for "Personal" and "Shared", each with a glossy icon. Tapping → **Vault Detail sheet**.
- **Categories** section: rows for Logins, Secure Notes, Credit Cards, Identities, Wi-Fi Passwords — each a glossy icon + chevron. Tapping → Collection sheet filtered to that category (only Logins has seed data; others show empty state).

### 5. Sentinel tab (security score)
- Shared header + large title ("Sentinel").
- **Speedometer gauge:** open-bottom 270° arc, ~240×172. Gradient stroke green→teal→blue, width 22, with tick-mark notches cut through it (short lines in the bg color, ~36 ticks). A small green triangle **pointer** sits along the arc at the score position (high score → left/green zone). Centered inside: big score number (48px) + uppercase muted label ("EXCELLENT" / theme-specific). *Implementation note: in the prototype this is an inline SVG whose arc path, tick coordinates, and pointer polygon are computed from center (120,118), radius 90, start angle 135°, sweep 270°. Recreate with a native gauge/Canvas/SwiftUI `Path`.*
- **Share My Score** button (surface card, share icon).
- Body paragraph explaining the score.
- **Overall Password Strength** card: label + a full-width gradient bar (green→amber→red).
- **Alert cards:** e.g. "2 passwords are reused", "1 login has no two-factor" — title + body.

### 6. Search tab
- Shared header + large title ("Search").
- Search input (inset card, magnifier icon). As the user types, results filter live (matches item name) into a card list; no query = nothing; query with no matches = "No items match your search".

---

## Modal Sheets (bottom sheets)
All sheets slide up from the bottom (`translateY` 100%→0, 0.35s cubic-bezier(.2,.9,.25,1)), have a 34px top corner radius, a grabber handle at top, and **start at `top: 54px`** so their header clears the status bar. A dimmed backdrop (rgba(0,0,0,0.45)) sits behind. Tapping the backdrop or the close control dismisses.

### Add sheet
Header "Add Item" + close (X). Search field ("What do you want to save?"). 2-column grid of type tiles (Login, Password, Secure Note, Credit Card, Identity, Wi-Fi Password), each a glossy icon + label. Filtered live by the search field. Selecting a tile → Editor sheet for that type.

### Editor sheet (Add / Edit)
Header: "Cancel" (left) / "New <Type>" or "Edit <Type>" (center) / "Save" (right, dimmed to 45% until a title is entered). Body: glossy type icon + title input; then a grouped input card whose fields depend on type:
- **Login/Password:** Username, Password (secret — eye toggle + generate button), Website.
- **Credit Card:** Cardholder, Card Number (secret), Expiry.
- **Identity:** Full Name, Email, Phone.
- **Wi-Fi:** Network Name, Password (secret).
- **Secure Note:** title + multiline note textarea.
- **Generate** button fills the password with a random 16-char strong string and reveals it.
- **Password strength meter** (only for secret password fields, when non-empty): 4-segment bar + label. Scoring: +1 length≥8, +1 length≥14, +1 has upper&lower, +1 has digit, +1 has symbol; capped at 1 if length<8. Labels Very weak→Very strong; color red/amber/green by score.
- Save adds the item to the live data (appears in Recently Created, Search, its category/vault) and toasts "Saved to Personal" (or "Changes saved" when editing).

### Item Detail sheet
Header: close (X) / type label (e.g. "Login") / "Edit". Body: item avatar tile + name; a grouped card of **type-aware fields** (same field set as the editor) — each row shows label + value, with copy buttons on copyable fields, an eye toggle on secret fields (masked by default as ••••••••••••), and website shown in accent. Secure Notes render the note text in a block. Bottom: destructive **Delete**. Edit → opens Editor prefilled.

### Settings sheet
Header: spacer / "Settings" / "Done". Sections: profile row (avatar, "Alex Rivera", email, chevron); **Appearance** segmented control (Light / Dark — flips the whole app theme live); **Security** card (Unlock with Face ID toggle; Auto-Lock row that cycles Immediately / 30 seconds / 1 minute / 5 minutes on tap). **Lock Now** (→ lock screen). **Sign Out** (destructive; → lock screen).

### Collection sheet
Header: close (X) / collection title / spacer. Lists items for a category / vault / "All Items". Empty state: "Nothing here yet" + "Items you save to <name> will show up here."

### Vault Detail sheet
Header: close (X) / "Vault" / spacer. Body: glossy vault icon + vault name + "N items". **Members** section: card list of members (avatar, name, email, role in accent — Owner / Can edit / Can view). Personal = just the owner; Shared = owner + "Jordan Lee" (Can edit) + "Sam Patel" (Can view). **Invite People** button (accent, +, pill) → toasts "Invitation link copied". **Items** section: items in that vault, or "No items in this vault yet".

### Toast
Small centered pill near the bottom that fades in (`pw-toast-in`), auto-dismisses after ~2.2s. Used for copy/save/delete/share confirmations.

---

## Bottom Tab Bar
Floating pill, 18px inset from edges, 14px from bottom, translucent (blur + saturate), 1px border, 26px radius. Four tabs: **Home** (house), **Items** (two rows), **Sentinel** (shield), **Search** (magnifier). Active tab = accent icon + label on an accentSoft rounded pill; inactive = muted. Tap press state = scale(0.92). (In the playful/premium themes the Sentinel label reads "Sentinel"; friendly theme calls it "Checkup".)

## Interactions & Behavior
- **Navigation:** tab switching (instant), sheet present/dismiss (slide + backdrop fade), collapsible sections (chevron rotate + expand).
- **Animations/keyframes:** `pw-toast-in` (fade+rise 0.25s), `pw-scan-pulse` (Face ID scanning, 0.6s loop), `pw-shake` (0.4s — failed Face ID button and wrong passcode dots). Sheet transition 0.35s cubic-bezier(.2,.9,.25,1). Chevron/press transitions 0.2s.
- **Press states:** rows dim to ~0.6 opacity; buttons scale to 0.92–0.98.
- **Forms:** Save disabled until title present; password generate + strength meter; live search + live add-type filter.
- **Auth logic:** Face ID fails once then succeeds; passcode `1234`; both routes land on the app.

## State Management
Single screen-level state (see `Component` class in `PhoneApp.dc.html`):
- `stage`: `onboarding | lock | app`; `onboardStep`; `passcodeMode`, `passcodeDigits`, `passcodeError`, `scanning`, `faceIdAttempts`, `faceIdFailed`.
- `tab`: `home | items | sentinel | search`; `sheet`: `null | add | editor | settings | detail | collection | vault`.
- `dark` (theme), `faceId`, `autoLockIdx`, `favOpen`, `recentOpen`.
- Editor: `pendingType`, `editorTitle/F1/F2/F3/Notes`, `pwVisible`, `editingId`, `editingFav`.
- Data: `addedItems`, `deletedIds` (merged with seed `SAMPLE_ITEMS` to form the live item list), `detailItem`, `collectionKind/Value/Title`, `vaultName`.
- No network in the prototype — all data is in-memory seed data. A real build wires this to the vault store / keychain / sync backend.

## Assets
- `app_icon.png` — the Passwards app icon (blue rounded-square with a shield/lock). Used on onboarding slide 1, the lock screen, and the review header. Ship the real app icon asset.
- **Glossy icons** (`GlossyIcon.dc.html`): stylized glyphs (`key`, `password`, `note`, `card`, `id`, `wifi`, `shield`) rendered on colored rounded tiles with a gloss highlight. Recreate with your icon set (SF Symbols are the natural iOS choice) on colored tiles.
- All other icons are simple inline SVG strokes (chevrons, plus, eye, copy, share, magnifier, Face ID) — replace with SF Symbols / your icon library.
- Fonts: **Fredoka** and **DM Sans** (Google Fonts). Bundle them or pick the closest available faces.

## Files (in this bundle)
- `PhoneApp.dc.html` — **the whole app**: every screen, sheet, all state and logic. Primary reference.
- `Passwards.dc.html` — review canvas that mounts the theme variants (2b/3a = the chosen playful light-mode build). Context only.
- `GlossyIcon.dc.html` — the glossy tile-icon component.
- `ios-frame.jsx` — presentation-only device bezel + status bar. **Not part of the app.**
- `support.js` — the `.dc.html` template runtime (lets you open the prototypes in a browser). Not something to port.
- `app_icon.png` — app icon asset.

To preview: open `PhoneApp.dc.html` in a modern browser. Default view is the `premium` dark theme; the committed direction is `playful` light — see `THEMES.playful` / `PALETTES.playful.light` in that file for exact values.
