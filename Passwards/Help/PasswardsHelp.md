<!-- GROUP: Getting Started -->

# Welcome to Passwards

Passwards is a password manager for your Mac. It keeps your logins, credit cards, secure notes, and other sensitive details encrypted and under your control — and fills them in for you when you need them.

## What Passwards does for you

- **Stores everything securely** — passwords, cards, identities, notes, software licenses, SSH keys, and more, all encrypted on your Mac.
- **Fills logins in your browser** — with a companion extension for Chrome, Brave, Edge, and Safari.
- **Generates strong passwords** — so every account can have its own.
- **Keeps a watch on your security** — Watchtower flags weak, reused, and breached passwords.
- **Syncs across your Macs** — privately, through your own iCloud account.
- **Unlocks with Touch ID** — fast access without typing your password every time.

## How your data stays private

Passwards uses **end-to-end encryption**. Everything is scrambled on your Mac before it's stored or synced, and only you hold the keys to unscramble it. Passwards has no servers and no account to sign up for — your data lives on your devices and in your own iCloud, never readable by us or by Apple.

> **The one thing to remember:** keep your **Account Password**, your **Secret Key**, and (once you set one up) your **Recovery Code** somewhere safe. They are the keys to your vault, and by design nobody can get in without them — not even us.

## Where to start

1. **Setting Up Your Account** — create your account and choose a strong password.
2. **Your Secret Key & Emergency Kit** — save the second key that protects your data.
3. **Recovery Codes** — set up a safety net in case you ever forget your password.

New to a feature? Browse the sections on the left — there's an article for every part of the app.


# Setting Up Your Account

The first time you open Passwards, choose **Create Your Account**.

## Step 1: Enter your details

- **Email address** — used to label your account and mixed into the encryption (so two people with the same password still get different keys).
- **Account Password** — choose something **long and memorable**. A short phrase of several unrelated words is both strong and easy to recall. Passwards shows a strength meter as you type and asks for at least 10 characters.

> **Important:** Your Account Password is never stored anywhere and cannot be reset by email, because Passwards never sees it. If you forget it and have no Recovery Code or a Mac with Touch ID still enrolled, your data cannot be recovered. Pick something you won't forget — and set up a **Recovery Code** as a safety net.

## Step 2: Save your Secret Key

After your account is created, Passwards shows your **Secret Key** and lets you save an **Emergency Kit**. Don't skip this — see *Your Secret Key & Emergency Kit*.

## Step 3: Turn on Touch ID (optional)

If your Mac has Touch ID, you can enable fast fingerprint unlock. See *Unlocking with Touch ID*.

Once you've confirmed you've saved your Secret Key, you're ready to start adding items.


# Your Secret Key & Emergency Kit

Your **Secret Key** is the second half of what protects your vault. It's a long random code, created automatically on your Mac when you set up, that looks like this:

```
A3-ABCDEF-GHJKMN-PQRST-VWXYZ-23456-789AB
```

## Why it matters

To unlock your vault you need **two** secrets together: your **Account Password** (something you know) and your **Secret Key** (something stored on your devices). This is called *two-secret encryption*. Because the Secret Key never syncs to iCloud, even someone who breaks into your iCloud account can't read your data.

You'll need your Secret Key whenever you set up Passwards on a **new Mac**.

## Save your Emergency Kit

Click **Save Emergency Kit…** to save a PDF containing your email and Secret Key, with a blank line where you can write your Account Password (and later, your Recovery Code).

- Print it or store it somewhere safe and offline — a drawer, a safe, or with someone you trust.
- You can re-open it anytime from **Settings → Security → View Secret Key & Save Emergency Kit…** (after confirming with your password or Touch ID).

> Anyone who has your Emergency Kit **and** your Account Password can open your vault. Treat the kit like a passport: keep it private and safe.


# Adding Another Mac

Passwards can keep your vault in sync across your Macs using your own private iCloud account. Only encrypted data is ever synced.

## Set up Passwards on a new Mac

1. Sign the Mac in to the **same iCloud account** you use on your other Mac.
2. Open Passwards and choose **Sign in to an existing account**.
3. Enter your **Account Password** and your **Secret Key** (from your Emergency Kit).

Passwards downloads your encrypted vault from iCloud and unlocks it. Your items appear automatically.

> Your Secret Key never syncs through iCloud — that's why you have to enter it by hand on each new device. It's the safeguard that keeps your data locked even if your iCloud account is compromised.

## After signing in

- **Turn on Touch ID** on the new Mac if you'd like fingerprint unlock. Touch ID is set up separately on each Mac.
- Changes you make on either Mac sync to the other automatically, even while the app is locked (only ciphertext moves).

No iCloud? You can still use Passwards on a single Mac — your vault simply stays local to that device.


<!-- GROUP: Everyday Use -->

# Creating & Editing Items

Everything you store in Passwards is an **item** — a login, a credit card, a secure note, an SSH key, and more. This guide covers how to add items, fill them in, and read them back later.

## How the main window works

The window has three columns:

1. **Sidebar** (left) — your account, then **All Items**, **Favorites**, and **Watchtower**, followed by sections for your **Vaults**, **Categories** (only those that contain items), your **Tags**, and finally **Archive** and **Recently Deleted**.
2. **Item list** (middle) — every item in the current view, with its icon, title, and a subtitle (for a Login, that's the username; for a Credit Card, the last four digits).
3. **Detail** (right) — the full item you've selected, or the editor when you're creating or changing an item.

Click any item in the list to open it in the detail column. The list has a **category filter** menu at the top left (defaults to **All Categories**), a count of visible items, and a **sort** menu (sort by **Title**, **Date Edited**, or **Date Created**, with a toggle for **A → Z** / **Newest First**). Use the search field in the toolbar to find items by typing.

## Adding a new item

1. Click the **New Item** button (the **+**) in the toolbar, or press **⌘N**.
2. A sheet titled **"What would you like to add?"** appears. Pick a category — the six everyday ones (**Login**, **Secure Note**, **Credit Card**, **Identity**, **Password**, **Document**) are shown as large cards, with the rest listed below. You can also type in the search box to filter and press Return to choose the first match.
3. The editor opens in the detail column, pre-filled with the right fields for that category. Fill it in and **Save**.

> The category you pick only decides which fields you start with. Every item is just sections and fields underneath, so you can add or remove most of them later.

## Using the editor

At the top of the editor you'll find:

- **Icon** — click it to pick a custom symbol and color from the **Item Icon** popover, or choose **Use Default Icon** to fall back to the website's favicon (if the item has a URL) or the category icon.
- **Title** — the name shown everywhere in the list and search.
- **Vault** — when you're creating a new item and you have more than one vault, a picker appears here so you can choose where the item lives.

### Sections and fields

Items are organized into **sections**, and each section holds **fields** (a label plus a value).

- **Add Field** — at the bottom of any section, click **Add Field** and pick a field type. The new field's label starts as the type name (lowercased); click the label to rename it.
- **Add Section** — adds a new section titled **New Section**; click its title to rename it.
- **Remove a field** — hover over a field and click the red **−** button. (The item's main username and password fields can't be removed, but you can leave them blank — empty fields don't show in the detail view.)
- **Remove a section** — click the trash icon next to a section's title (the first section can't be removed).

### Field types

When you add a field, you choose its type, which controls how the value behaves:

| Type | Use it for |
| --- | --- |
| **Text** | Plain text such as a username or note |
| **Password** | A secret value, hidden behind dots until revealed |
| **Email** | An email address |
| **URL** | A website address |
| **Phone** | A phone number |
| **One-Time Password** | A two-factor authentication secret (see below) |
| **Date** | A date, picked with a calendar |
| **Month/Year** | A month and year, e.g. a card's expiry |
| **Address** | A multi-line street address |
| **File** | An attached file |

**Password fields** show a reveal (eye) toggle, a **strength bar**, and a dice button to open the **password generator** — generated passwords drop straight into the field and are revealed automatically.

**One-Time Password fields** hold the secret your other service gives you when you turn on two-factor authentication (paste in the setup key). Passwards then turns it into the rotating 6-digit code, shown with a countdown in the detail view.

> **SSH Key** items use a multi-line field for the private key. Paste the whole key, including its line breaks, into that field.

### Notes and tags

Below the sections are two more areas:

- **NOTES** — a free-form text box for anything extra. Notes support basic Markdown formatting, which is rendered when you view the item.
- **TAGS** — type comma-separated tags to organize items. Use a slash (`/`) to nest tags, e.g. `Work/Finance`.

### Saving

Click **Save** (or press **⌘S**) to store your changes, or **Cancel** to discard them. Every time you save a change, the previous version is kept in the item's history, so you can look back or restore it later.

## Viewing an item

When you select an item, the detail view shows its icon, title, a **favorite** star you can toggle, and each filled-in field grouped by section. Empty fields are hidden. At the bottom you'll see when the item was last edited (click the **Last edited…** line to open **Item History**), which vault it's in, and when it was created.

To make changes, click **Edit** (the pencil) in the toolbar or press **⌘E**. You can also **Duplicate** the item with **⌘D**.

### Copying values

- **Click any field** to copy its value. A green **Copied** confirmation appears briefly.
- For a **One-Time Password** field, copying gives you the current 6-digit code, not the underlying secret.
- Right-click a field for a **Copy** option, plus, on a Login's website field, **Open & Fill** and **Open in Browser** (other website fields just offer **Open in Browser**).
- In the item list, right-click a Login for quick **Copy Username** and **Copy Password**, plus **Copy One-Time Password** when the item has a one-time code.

> Copied passwords and other secrets are automatically cleared from the clipboard after a short time (90 seconds by default — adjustable under **Settings → Clear copied secrets after**), and immediately when you lock Passwards.

### Revealing concealed fields

Passwords, one-time-password secrets, and SSH keys are hidden behind dots. To see one:

- Hover over the field and click the **eye** icon to reveal it (click again to hide).
- Press **⌘R** to reveal or hide every concealed field in the item at once.
- Hover and click the **Show in Large Type** icon to display a secret as big, easy-to-read characters — handy for typing a password into another device.

### Handy shortcuts in the detail view

- **⌘C** — standard copy of any text you've selected
- **⇧⌘C** — copy the password
- **⌥⌘C** — copy the one-time code
- **⌘R** — reveal/hide all concealed fields
- **⌘E** — edit · **⌘D** — duplicate · **⌘⌫** — move the item to Recently Deleted


# Item Categories

Every item you save in Passwards has a **category** — like **Login**, **Credit Card**, or **Passport**. The category decides which fields the item starts with, so the form already looks right for what you're storing. A Login gives you a username and password; a Credit Card gives you a card number and an expiry date.

> No matter which category you pick, your item is protected exactly the same way: everything is end-to-end encrypted. The category only changes the fields you see, never how securely your data is stored.

## Choosing a category

You pick a category when you create a new item:

1. Click **New Item** (the **+** button), or press **⌘N**.
2. The **What would you like to add?** window appears, with a **Try searching anything** search box at the top.
3. The six everyday categories — **Login**, **Secure Note**, **Credit Card**, **Identity**, **Password**, and **Document** — are shown as large cards, with the rest listed below. Type in the search box to filter the list.
4. Click a category to start a new item with its tailored fields.

You can rename fields, add your own, or leave fields blank — the category's fields are just a helpful starting point.

## The categories

Passwards has 22 categories, the same set as 1Password 8.

### Everyday items

- **Login** — a website username and password, with room for a one-time password (2FA) code and the site address.
- **Password** — a standalone password and an optional website, when you don't need a full login.
- **Secure Note** — free-form text for anything that doesn't fit elsewhere. It starts with no preset fields.
- **Document** — store a file (a PDF, image, or any document) safely in your vault.
- **Identity** — your personal details: name, sex, birth date, occupation and company, address, phone numbers, and internet contact info — handy for filling in forms.

### Money and payments

- **Credit Card** — cardholder name, card type and number, verification number, expiry and valid-from dates, plus issuing-bank contact info and extra details like PIN and credit limit.
- **Bank Account** — bank name, name on account, routing and account numbers, SWIFT, IBAN, PIN, and branch contact details.
- **Crypto Wallet** — recovery phrase, wallet password, and wallet address.
- **Reward Program** — loyalty and points programs: company name, member name and ID, PIN, and customer-service contacts.

### IDs and official documents

- **Passport** — type, issuing country and authority, number, your details, and the issue and expiry dates.
- **Driver License** — full name, address, date of birth, license number and class, conditions/restrictions, state, country, and expiry.
- **Social Security Number** — your name and the number itself.
- **Outdoor License** — hunting and fishing-style licenses: full name, validity dates, approved wildlife, maximum quota, state, and country.
- **Membership** — clubs and memberships: group name, website, member name and ID, PIN, and membership dates.
- **Medical Record** — a visit's date, location, healthcare professional, patient, and reason, plus medication details.

### Tech and work

- **API Credential** — a username and secret credential, with type, filename, validity dates, and hostname.
- **Database** — connection details: type, server, port, database name, username, password, and more.
- **Server** — a server's URL, username, and password, plus admin-console and hosting-provider details.
- **SSH Key** — an SSH private key, public key, fingerprint, and key type. (These keys can also power Passwards' built-in SSH agent.)
- **Software License** — version and license key, who it's licensed to, publisher info, and order details.
- **Email Account** — incoming and SMTP server settings, username and password, security, and provider contacts.
- **Wireless Router** — base-station name and password, IP address, network name, wireless security type, and Wi-Fi passwords.

> Once an item is created, its category is fixed — but you can always add, rename, or remove fields to make any item hold exactly what you need.


# Organizing with Vaults

Vaults are how Passwards keeps your items organized into separate groups. Think of each vault as a labeled container: one might hold your personal logins, another your travel documents, another family accounts. Every item you save lives in exactly one vault.

Vaults are part of how Passwards keeps you secure, too. Each vault is encrypted with its own key, so its contents stay protected.

## The Personal vault

When you first set up Passwards, it creates one vault for you called **Personal** (a blue person icon). This is your default vault, and unless you create more, every item you add goes here. For many people, the Personal vault is all they ever need.

## Finding your vaults

Your vaults appear in the left sidebar under the **VAULTS** heading. Click a vault to see only the items inside it. To see everything across all your vaults at once, click **All Items** near the top of the sidebar instead.

## Creating a new vault

1. In the sidebar, find the **VAULTS** heading.
2. Click the small **+** button next to it (it shows **New Vault** when you hover over it).
3. In the **New Vault** window, type a name.
4. Pick an icon from the row of symbols and a color from the row of dots.
5. Click **Create**.

Your new vault appears in the sidebar right away.

## Editing a vault's name, icon, or color

You can change a vault's appearance at any time:

1. **Right-click** the vault in the sidebar.
2. Choose **Edit Vault…**.
3. In the **Edit Vault** window, change the name, pick a different icon, or choose a new color.
4. Click **Save**.

> The name, icon, and color are the only things you can customize on a vault. There's no description or other settings.

## How items belong to vaults

Every item lives in one vault. Here's how that plays out:

- **When you create an item**, it goes into the vault you currently have selected in the sidebar. (If you're viewing **All Items**, it goes into your first vault, usually **Personal**.)
- **Choosing a vault as you create an item:** if you have more than one vault, the new-item editor shows a **Vault:** picker beneath the title so you can choose where it's saved.
- **Seeing an item's vault:** open any item and its vault name is shown near the bottom of the item's details.

### Moving an item to another vault

If you have more than one vault, you can move an existing item:

1. **Right-click** the item in the list.
2. Choose **Move to Vault**.
3. Pick the destination vault from the submenu.

The item moves over immediately and is re-encrypted for its new vault.

> The **Move to Vault** option only appears when you have at least two vaults. With a single vault, there's nowhere to move items, so the option is hidden.


# Finding & Organizing Items

As your vault grows, Passwards gives you several ways to find what you need fast and keep everything tidy: a quick search, a sortable item list, tags, and item icons you can customize.

## Searching items

Every list has a **Search items** field in the window toolbar. Start typing and the list narrows instantly to matching items.

Search looks across:

- The item's **title**
- Its **subtitle** (for a Login, that's the username; for a credit card, the last 4 digits)
- Any **website / URL** saved on the item
- The item's **tags**

Matching is not case-sensitive and matches anywhere in the text, so typing `mail` finds both "Email" and "Gmail".

> Search only covers the current view, and it never reaches into **Archive**. Archived items are hidden from lists and search.

## The item list

The middle column shows the items for whatever you've selected in the sidebar (a category, a tag, a vault, **Favorites**, and so on). At the top of the list are a few controls:

- **All Categories** menu — pick a single category to show only items of that type, or choose **All Categories** to clear the filter.
- A **count** of how many items are currently shown.
- A **sort** menu (the up/down arrows icon). Under **Sort by** you can choose **Title**, **Date Edited**, or **Date Created**, and the toggle switches between **A → Z** / **Newest First**.

When you sort by a date, items are grouped under month-and-year headers. Sorting by title shows one flat, alphabetical list.

Each row shows the item's icon, title (with a star if it's a favorite), and subtitle. Right-click a row for quick actions. For a Login you'll see **Copy Username** and **Copy Password**; every item offers **Open in Browser** (when it has a URL), **Add to Favorites** / **Remove from Favorites**, **Archive**, **Duplicate**, and **Move to Recently Deleted**.

## Tags

Tags are free-form labels you add to items so you can group them however you like (for example `work`, `family`, or `finances`).

To add tags:

1. Open an item and click **Edit** (the pencil icon in the toolbar).
2. Find the **TAGS** field near the bottom.
3. Type your tags separated by commas, for example: `work, banking, shared`.
4. Click **Save**.

Every tag you've used appears in the sidebar under **TAGS**. Click one to see all items carrying that tag.

### Nested tags

Use a slash to create a hierarchy. For example, an item tagged `work/projects` sits under the `work` tag. Selecting the parent tag (`work`) in the sidebar shows everything beneath it too, so you can organize broadly or narrowly.

## Website URLs

For Login items and many other categories, a **url** field holds the site's address (such as `example.com` or `https://example.com`). Saving a URL does two helpful things:

- It lets Passwards show the site's **favicon** as the item icon (see below).
- It powers the **Open in Browser** action when you right-click the item.

You can save more than one URL on an item. The first one is used for the favicon and for **Open in Browser**.

## Favicons (website icons)

When an item has a website saved, Passwards automatically shows that site's icon, so your Logins look the way you'd expect at a glance.

> Privacy note: icons are fetched **directly from each website** — no third-party icon service ever sees the sites you've saved.

You can manage this in **Settings → Privacy → Rich Icons**:

- **Show website icons** — turn favicons on or off. When off, items fall back to their category tile.
- **Clear Icon Cache** — removes the locally cached icons (handy if a site changed its logo).

## Custom item icons

Want a specific look for an item — for example, a key for your router or a heart for a family account? You can pick your own icon.

1. Open the item and click **Edit**.
2. Click the large icon next to the title (its tooltip reads **Change icon**).
3. In the **Item Icon** popover, choose an SF Symbol from the grid and a color from the row of swatches.
4. Click **Save** to keep the change.

To go back to the automatic icon, open the same popover and click **Use Default Icon**.

## How icon precedence works

Passwards decides which icon to show for an item in this order:

1. **Custom icon** — if you've chosen a symbol and color, that always wins.
2. **Website favicon** — otherwise, if the item has a saved URL (and **Show website icons** is on), the site's favicon is shown.
3. **Category tile** — if neither applies, the item shows the default colored tile for its category (Login, Credit Card, Secure Note, and so on).

So a custom icon overrides everything, and removing it lets the favicon (or category tile) take over again automatically.


# Trash & Item History

Passwards keeps a safety net under your items. Anything you delete goes to **Recently Deleted** first, so you can change your mind. Separately, every content edit you make to an item is quietly saved, so you can look back at — or restore — an earlier version.

## Moving items to Recently Deleted

Deleting an item never removes it right away. It moves to **Recently Deleted**, where it stays until you remove it for good (or it expires automatically — see below).

To move an item to Recently Deleted:

- **From the item list:** right-click the item and choose **Move to Recently Deleted**.
- **From the open item:** press **⌘Delete**.

You'll find **Recently Deleted** in the sidebar, just below **Archive**. When it holds items, a small count appears next to it.

> Archiving and deleting are different. **Archive** hides an item from your lists and search without putting it on the deletion path; **Recently Deleted** is the path to permanent removal.

## Restoring an item

1. Select **Recently Deleted** in the sidebar.
2. Right-click the item you want back.
3. Choose **Restore**.

The item returns to its vault, and the count next to Recently Deleted goes down.

## Deleting an item permanently

To remove a single item without clearing the whole area:

1. Select **Recently Deleted** in the sidebar.
2. Right-click the item.
3. Choose **Delete Permanently**.

> Permanent deletion can't be undone. The item is gone for good — and removed from your other synced Macs.

## Empty Trash

To clear everything in Recently Deleted at once:

1. Select **Recently Deleted** in the sidebar.
2. Click the **Empty Trash** button in the toolbar (it appears only while you're viewing Recently Deleted).

Passwards asks first, with the dialog **Empty Recently Deleted?** and the warning:

> This permanently deletes every item in Recently Deleted. This can't be undone.

Choose **Empty Trash** to proceed, or **Cancel** to back out.

### Automatic cleanup after 30 days

You don't have to empty Recently Deleted yourself. Items are permanently removed once they've been there for more than **30 days** — this cleanup runs automatically when you open Passwards. The empty area reminds you: *"Recently deleted items appear here for 30 days."*

## Item history

Separately from Trash, Passwards keeps a history of changes to each item, so you can see what it looked like before and roll back if needed.

### What gets saved

Each time you **edit and save** an item — its fields, sections, title, tags, website, and so on — Passwards stores a snapshot of the previous version before applying your change. Every saved snapshot is encrypted, just like the item itself.

A couple of things to know:

- Quick toggles that only touch the item's overview — **Add to Favorites / Remove from Favorites** and **Archive / Unarchive** — do *not* create a history entry.
- **Password changes** are tracked separately: when you change an item's main password, the old value is kept in that item's **Password history** card (up to the 50 most recent), apart from the version list described here.

### Viewing previous versions

1. Open the item.
2. At the bottom, click the **Last edited …** line.

The **Item History** sheet opens, listing each saved version newest-first — each labeled with its title and a line like *"Version 3 — Jun 19, 2026 at 2:14 PM."* If an item has never been edited since it was created, you'll see **No previous versions.**

### Restoring an older version

1. Open the item and click the **Last edited …** line.
2. Find the version you want in the **Item History** list.
3. Click **Restore** next to it.

Restoring brings that older version's contents back as the item's current state. Because restoring is itself saved as a new edit, nothing is lost — the version you were on before restoring stays in the history, so you can always go back again.

Click **Done** to close the Item History sheet.


# Quick Access

Quick Access is a small floating search panel you can summon over any app on your Mac. It lets you find an item and copy its username, password, or one-time code in seconds, without switching to the main Passwards window or losing your place in whatever you're doing.

## Opening Quick Access

The default global shortcut is **⇧⌘Space** (Shift-Command-Space). Press it from anywhere — even while another app is in front — and the panel appears slightly above the center of your screen, much like Spotlight.

You can also open it from:

- The **Quick Access** item in the Passwards app menu.
- The menu bar icon: click the lock-shield icon, then **Quick Access  ⇧⌘Space**.

Pressing the shortcut again, pressing **Escape**, or clicking away from the panel closes it.

> You can change the shortcut in **Settings → General**, under **Keyboard Shortcuts → Show Quick Access:**. The same section has **Lock Passwards:**, which defaults to ⇧⌘L.

## Searching

When the panel opens, the search field is ready for you to type. Start typing to filter your items by **title**, subtitle, or website. Before you type anything, Quick Access shows your items with favorites at the top.

- Use the **Up** and **Down** arrow keys to move through the results.
- Results are limited to the top 8 matches, so a few keystrokes usually surface what you want.

## Copying without leaving your app

The highlighted result shows a hint, and the bottom of the panel lists what each shortcut copies. With an item selected:

| Shortcut | Action |
| --- | --- |
| **⏎** | Copy the password |
| **⌘C** | Copy the username |
| **⇧⌘C** | Copy the password |
| **⌥⌘C** | Copy the one-time code |
| **⇧⌘O** | Open the item in the main window |

Clicking a result also copies its password. After a copy, Quick Access shows a brief confirmation (for example, "Password copied") and then closes itself, so you can paste straight into the app or website you were using.

> Copied passwords and one-time codes are marked as concealed, so clipboard managers skip them. Passwards also clears them from the clipboard automatically after a set time (90 seconds by default). You can change this — or turn it off — in **Settings → Security**, under **Clipboard → Clear copied secrets after**.

## Shared unlocked state

Quick Access uses the **same unlocked session as the main Passwards window** — there's no separate lock. If Passwards is unlocked, Quick Access is ready to use immediately. If it's locked, the panel shows **Passwards is locked** with buttons to **Unlock with Touch ID** (when enabled) and **Open Passwards**. Once you unlock anywhere, Quick Access works again right away. Likewise, locking Passwards — or your Mac going to sleep, the screensaver starting, or your screen locking — protects Quick Access too.


# Keyboard Shortcuts

Passwards has keyboard shortcuts for the things you do most often, so you can stay on the keyboard instead of reaching for the mouse. This article lists every shortcut the app supports.

> On a Mac keyboard, `⌘` is Command, `⇧` is Shift, `⌥` is Option, and `⌫` is Delete.

## App-wide shortcuts

These work anywhere in Passwards.

| Shortcut | Action |
| --- | --- |
| `⇧⌘Space` | Show **Quick Access** (the floating search panel) |
| `⇧⌘L` | **Lock Passwards** |
| `⌘N` | **New Item** |
| `⌘?` | Open **Passwards Help** |

> If you keep Passwards in the menu bar, the **Quick Access** and **Lock** items there show their shortcuts right in the menu.

## When viewing an item

These shortcuts apply while an item's details are shown in the main window.

| Shortcut | Action |
| --- | --- |
| `⇧⌘C` | Copy the password |
| `⌥⌘C` | Copy the one-time code |
| `⌘R` | Reveal or conceal hidden fields |
| `⌘E` | **Edit** the item |
| `⌘D` | **Duplicate** the item |
| `⌘⌫` | Move the item to the Trash |

> A copied password or one-time code is removed from the clipboard automatically after a short time, and is also cleared the moment you lock Passwards.

## When editing an item

| Shortcut | Action |
| --- | --- |
| `⌘S` | **Save** your changes |
| `Esc` | **Cancel** and discard changes |

## Customizing Quick Access and Lock

The two app-wide shortcuts for **Show Quick Access** and **Lock Passwards** can be changed to whatever you like:

1. Open **Settings** (`⌘,`).
2. Stay on the **General** tab.
3. Under **Keyboard Shortcuts**, click the field next to **Show Quick Access:** or **Lock Passwards:**.
4. Press the new key combination you want to use.

Their defaults are `⇧⌘Space` for Quick Access and `⇧⌘L` for Lock. The other shortcuts listed above are fixed and cannot be changed.


<!-- GROUP: Passwords & Security Tools -->

# The Password Generator

Reusing the same password everywhere is the single biggest risk to your accounts. Passwards has a built-in generator that creates a strong, unique password every time, so you never have to think one up yourself.

## Opening the generator

There are two ways to reach it:

- **From the toolbar.** Click the **dice** button (its tooltip says **Password Generator**) at the top of the main window. The generator opens on its own, ready for you to copy a password.
- **While creating or editing an item.** A small **dice** button appears next to any password or one-time-password field. Click it to generate a password and drop it straight into that field.

When the generator appears it immediately shows a fresh password. Click the **circular arrow** (**Regenerate**) button at any time to make a new one.

## The three modes

A segmented picker lets you choose how your password is built: **Random**, **Memorable**, or **PIN**.

### Random

A scrambled mix of letters, numbers, and symbols — the strongest option for most logins.

- **Characters** — a slider that sets the length, from **8 to 100** characters. Longer is stronger.
- **Numbers** — include digits (`0`–`9`). On by default.
- **Symbols** — include punctuation such as `! @ # $ % ^ & *`. On by default.

### Memorable

A passphrase made of real words, which is easier to type or read aloud while still being very strong.

- **Words** — a slider for how many words to use, from **3 to 15**.
- **Separator** — what goes between the words: **Hyphens**, **Spaces**, **Periods**, **Commas**, **Underscores**, **Numbers**, or **Numbers and Symbols**.
- **Capitalize** — capitalize the first letter of each word.
- **Full words** — when on, each word is whole; when off, words are shortened into short chunks.

### PIN

A short string of digits only.

- **Digits** — a slider for the length, from **3 to 12**.

## The strength meter

For Random and Memorable passwords, a colored bar below the preview shows how strong the result is, labeled **Terrible**, **Weak**, **Fair**, **Good**, or **Excellent**. Aim for **Good** or **Excellent**. The bar is hidden in PIN mode, since PINs are short by design.

## Copying and using your password

- **Copy** — click **Copy** to put the password on your clipboard. The button briefly changes to **Copied** to confirm.

> For your safety, a copied password is removed from the clipboard automatically after a short time, and it's also cleared whenever you lock Passwards.

- **Use Password** — when you opened the generator from inside an item field, a blue **Use Password** button appears. Click it to insert the password into that field and close the generator. The new password is shown (not hidden) so you can double-check it before saving.

> Your choices — mode, length, word count, separator, and toggles — are remembered, so the generator opens with your preferred settings next time.


# One-Time Codes (2FA)

Many websites offer two-factor authentication (2FA): after your password, they ask for a short code that changes every few seconds. Passwards can store the secret behind that code and generate it for you, so you don't need a separate authenticator app on your phone. These are also called **TOTP** codes (time-based one-time passwords).

## How the code looks

Once a one-time code is set up on an item, it shows live in the item's detail view:

- The current code appears in the accent color. A 6-digit code is split into two groups of three, like `123 456`.
- A small countdown ring and a seconds counter (for example `12s`) show how long until the code changes. The ring turns orange in the final seconds.
- The code refreshes every second, and a fresh one appears when the timer reaches zero.

You never need to see the underlying secret again once it's saved.

## Adding a one-time code to a login

A new **Login** item already includes a field for **one-time password**, ready for you to fill in. To add one to any item:

1. Open the item and click **Edit**.
2. Click **Add Field** and choose **One-Time Password**.
3. Paste your secret into the field (see below for what to paste).
4. Click **Save**.

### What to paste

Passwards accepts either of these:

- **A setup secret** — the string of letters and numbers a website shows when you turn on 2FA (often next to a QR code, labeled something like "manual entry key" or "setup key"). Spaces, dashes, and upper/lowercase don't matter.
- **An `otpauth://` link** — the full text encoded in the site's 2FA QR code. It also carries the issuer name and any non-standard settings (number of digits, refresh interval, or algorithm).

```
otpauth://totp/Example:you@email.com?secret=JBSWY3DPEHPK3PXP&issuer=Example
```

By default, codes are 6 digits and refresh every 30 seconds — the standard almost every website uses. An `otpauth://` link can override these if the site is different.

> If the field shows **Invalid one-time password secret**, the value you pasted couldn't be read. Double-check that you copied the whole setup key (it should be letters A–Z and digits 2–7) and try again.

## Copying the code

When you copy a one-time code, Passwards puts the **current code** on your clipboard — not the secret behind it. From the item's detail view you can:

- Click the one-time code field.
- Press **Option-Command-C** (`⌥⌘C`).

You can also copy it without opening the item:

- In the item list, right-click the item and choose **Copy One-Time Password**.
- In **Quick Access**, select the item and press `⌥⌘C` (shown in the hint bar as "one-time code").

> Copied codes are marked as sensitive, so clipboard managers skip them and Passwards clears them from your clipboard after a while (90 seconds by default), and immediately when you lock. Paste the code before it changes — if the timer is nearly up, wait for the next code so it doesn't expire mid-login.


# Watchtower

**Watchtower** is Passwards' built-in security check. It reviews the items in your vaults and flags anything that could put you at risk, so you know which passwords to fix and where to start.

You'll find it in the sidebar, marked with a shield icon. When there are issues, a number badge appears next to **Watchtower** showing how many were found.

## What Watchtower checks

Watchtower analyzes your active items (trashed and archived items are skipped) and groups any problems into cards. Each card has a title, a short explanation, and a count. The most serious issues appear in red, then orange, then yellow, with informational items in your accent color.

- **Vulnerable Passwords** — passwords that have appeared in known data breaches: *"These passwords appeared in known data breaches. Change them now."* These are the highest priority.
- **Reused Passwords** — the same password used by more than one item. If one site is breached, every account sharing that password is exposed.
- **Weak Passwords** — passwords that are easy to guess.
- **Unsecured Websites** — items whose saved address uses `http://` instead of the secure `https://`.
- **Two-Factor Authentication** — login items for sites that support two-factor (one-time password) codes where you haven't saved one yet.
- **Expiring Items** — items that have expired or will expire within 60 days (for example, a payment card).
- **Duplicate Items** — items that look like duplicates of each other (same type, website, and username).

> Watchtower skips SSH key items when checking passwords, and it won't flag a check you've already dismissed for an item (see "Reading and acting on the results" below).

## How the breach check protects your privacy

The **Vulnerable Passwords** check is the only one that needs the internet. It uses the public **Have I Been Pwned** breach database, and it's designed so your real passwords never leave your Mac. This technique is called **k-anonymity**:

1. Passwards creates a one-way fingerprint (a SHA-1 hash) of your password locally, on your Mac.
2. Only the **first 5 characters** of that fingerprint are sent to the breach service — never the password, and never the full fingerprint.
3. The service replies with a list of breached fingerprints that share those same 5 characters.
4. Passwards compares that list **on your Mac** to find out whether your password was among them.

Because the service only ever sees 5 characters shared by thousands of different passwords, it can't tell which password you actually have. Passwards also asks the service to pad its responses, so even the size of the reply gives nothing away.

> Your passwords stay on this Mac. Only a tiny, ambiguous fragment of a fingerprint is ever sent.

## Reading and acting on the results

### The Watchtower dashboard

Select **Watchtower** in the sidebar to see the dashboard. At the top you'll see when it was last checked and a **Check Now** button to run a fresh scan at any time. Watchtower also re-runs automatically when you open it if the last check is more than a few minutes old.

- If everything looks good, you'll see **All clear** with a green shield.
- Otherwise, you'll see one card per type of issue. **Click a card** to focus the item list on just those items, then open each one to fix it.

### Per-item alerts

When you open an item that Watchtower has flagged, a colored banner appears at the top showing which check it triggered and why. From there you can:

- **Fix the underlying problem** — for example, edit the item and generate a new strong password, switch its address to `https://`, or add a one-time password.
- **Dismiss** — if the flag isn't a real problem for you, click **Dismiss** in the banner. That tells Watchtower not to flag this item for that specific check again. Other checks on the same item still apply.

After you make a change, click **Check Now** (or revisit the dashboard) to confirm the issue has cleared.

## Settings

You can turn the online breach check on or off:

1. Open **Settings**.
2. Go to the **Privacy** tab.
3. Under **Watchtower**, use the **Check for vulnerable passwords** toggle.

This is on by default. The other Watchtower checks (weak, reused, and so on) all run entirely on your Mac and need no internet connection.

> When you lock Passwards, Watchtower discards its results, so a locked app keeps no record of which of your items were weak, reused, or breached.


<!-- GROUP: Browser & Developer Tools -->

# Filling in Your Browser

Passwards comes with a browser extension that fills your logins on the websites you visit and offers to save new ones as you sign in. It works with **Google Chrome**, **Brave**, **Microsoft Edge**, **Arc**, **Vivaldi**, and **Chromium**, plus **Safari**.

> The extension only works while the Passwards app is **unlocked**. If the app is locked, the extension shows "Passwards is locked. Unlock the app to use the extension." — just unlock Passwards and try again.

## Step 1: Register Passwards with your browser

For Chrome, Brave, Edge, Arc, Vivaldi, and Chromium, start in the app:

1. Open Passwards' **Settings**, then choose the **Browser** tab.
2. Under **Browser Extension** you'll see each supported browser found on this Mac.
3. Click **Install…** next to a browser. This registers Passwards so the extension can talk to the app.
4. When it's done, the row shows a green **Connected** badge.

> If a browser shows **Repair…** instead, the link to the app has gone stale (usually because the app moved). Click **Repair…** to fix it.

If you see "No Chromium-based browsers were found on this Mac," none of the supported browsers are installed where Passwards looks for them.

## Step 2: Load the extension

### Chrome, Brave, Edge, Arc, Vivaldi, and Chromium

The extension is loaded "unpacked" from the Passwards source folder:

1. In your browser, open the extensions page (for example, type `chrome://extensions` in the address bar).
2. Turn on **Developer mode**.
3. Click **Load unpacked** and choose the repository's `BrowserExtension` folder.

The Passwards icon appears in your browser's toolbar.

### Safari

The Safari extension is bundled inside the Passwards app, so there's nothing to load by hand. Enable it in **Safari → Settings → Extensions**, where the Passwards extension appears once the app has been run at least once.

## Step 3: Connect (the one-time pairing code)

The first time you use the extension, you pair it with the app. This is a one-time approval that establishes a secure, encrypted link between the two.

1. Click the **Passwards** icon in your browser. It says "Connect this browser to Passwards." Click **Connect…**.
2. A connection tab opens and shows a **6-digit code**.
3. Passwards comes to the front and shows a **Connect Browser Extension?** prompt with its own 6-digit code.
4. **Check that the two codes match**, then click **Connect** in the app.
5. The browser tab shows "Connected!" — you can close it.

> Only approve a pairing if you just installed or re-paired the Passwards extension **and** the codes match. The matching code is what proves the connection is genuine.

Once connected, the extension remembers the pairing, so you won't be asked again.

## Filling a login

Passwards matches logins to the website you're on by its domain. Open a sign-in page, then:

1. Click the **Passwards** toolbar icon.
2. Logins that match the current site appear under **Suggestions**. Below them, **All Logins** lists everything else, and a search box at the top filters across all of them.
3. Click **Fill** on a suggested login to drop the username and password into the page's sign-in form.

You can also click **Copy** on any login to copy its password to the clipboard.

> Filling on a page is limited to logins whose website actually matches that page. A login from a different site won't be filled into the page you're on — though you can still copy any login from the popup.

## Open & Fill

If you're already looking at a login in the Passwards app, you can jump straight to the site and have it filled automatically. This is available on the **website** field of **Login** items:

- Hover over the website field and click the **bolt** button (its tooltip is **Open & Fill**), or
- Right-click the website field and choose **Open & Fill**.

Passwards opens the website in your default browser and, when the sign-in form appears, fills it in and submits it for you. This is a one-time action: it's only honored for the matching site, and only for about a minute after you trigger it.

## Saving new logins

When you sign in to a site that isn't in Passwards yet, the extension shows a small banner in the top-right corner of the page:

- **Save this login in Passwards?** — click **Save** to create a new login.
- If the site is already saved but you signed in with a different password, it offers **Update password for "…" in Passwards?** — click **Update** to save the change.

Saving and updating both happen in the app, and your previous password is kept in the item's history.


# SSH Agent

Passwards can act as your **SSH agent**: it serves the private keys you keep in your vault to command-line tools like `ssh` and `git`, so you don't have to keep unprotected key files lying around on disk. The keys stay encrypted inside Passwards, and Passwards does the signing for you — gated by Touch ID.

## What it does

When the SSH agent is turned on, Passwards listens on a private socket file that tools like `ssh` and `git` connect to. Through it they can:

- **List your keys** — they see the public keys for your **SSH Key** items.
- **Sign with a key** — when you connect to a server, Passwards signs the login challenge with the matching private key.

The private keys themselves never leave Passwards.

> Keys are only served while Passwards is unlocked. When you lock the app, the agent stops offering any keys, so `ssh-add -l` shows nothing until you unlock again.

## Getting your keys into Passwards

The agent serves your **SSH Key** items. Create an SSH Key item and paste your key into its **private key** field. Passwards reads OpenSSH-format private keys — the kind that begin with `-----BEGIN OPENSSH PRIVATE KEY-----`.

> The key must be **unencrypted** (no passphrase). Passphrase-protected keys aren't supported — remove the passphrase before importing.

### Supported key types

| Type | Notes |
|------|-------|
| **Ed25519** | The modern default |
| **ECDSA** | NIST P-256, P-384, and P-521 |
| **RSA** | Including the newer `rsa-sha2-256` / `rsa-sha2-512` signing variants |

## Turning it on

1. Open **Settings → SSH Agent**.
2. Turn on **Use Passwards as my SSH agent**.

Passwards starts serving your SSH Key items right away.

## Touch ID approval

By default, **every signature requires your approval**. The **Require approval for each key use** toggle (under **Authorization**) is on, so each time a tool wants to use one of your keys, Passwards asks for **Touch ID** (or your login password). No program can quietly use your keys without you noticing — even while Passwards is unlocked.

If you'd rather not approve every single signature, use the **Remember approval** option:

- **Ask every time** (the default)
- **For 1 minute**
- **For 5 minutes**

The "remember" window is **per key**, so approving one key doesn't unlock the others.

## Pointing ssh at Passwards

`ssh` finds an agent through an environment variable called `SSH_AUTH_SOCK`. You point it at Passwards once.

1. In **Settings → SSH Agent**, find the **Setup** section. It shows a line like:

   ```bash
   export SSH_AUTH_SOCK="/path/to/agent.sock"
   ```

2. Click **Copy**.
3. Add that line to your shell profile (for the default macOS shell, that's `~/.zshrc`).
4. Open a new terminal window so the change takes effect.

To check it's working, run:

```bash
ssh-add -l
```

Your SSH Key items should be listed. After that, `ssh` and `git` use your Passwards keys automatically.

## From the command line

The `passwards` binary can print the setup line for you and list the keys it's serving:

```bash
passwards ssh-agent   # prints the socket path and the SSH_AUTH_SOCK export line
passwards ssh-keys    # lists the public keys the agent is serving
```

> If `ssh-keys` reports it can't reach the agent, make sure the SSH agent is turned on in **Settings → SSH Agent** and that Passwards is **unlocked**.

## Quick troubleshooting

- **`ssh-add -l` shows nothing** — Passwards is probably locked, or you have no SSH Key items. Unlock the app and confirm your keys are saved as SSH Key items.
- **A key won't load** — check it's in OpenSSH format and has **no passphrase**. Passphrase-protected keys aren't served.
- **Changes to `SSH_AUTH_SOCK` aren't picked up** — open a fresh terminal window after editing your shell profile.


# Command-Line Access

Passwards includes a small command-line tool, `passwards`, that lets you work with your vault from the Terminal. You can list your items, read a single field, and use Passwards as your SSH agent — all without leaving the keyboard.

This is an advanced, optional feature. It's off by default and stays out of your way until you turn it on.

## Turning it on

The commands that read your vault (`item` and `read`) only work after you enable Command-Line Access.

1. Open **Settings** (Passwards menu → **Settings**, or `⌘,`).
2. Go to the **Advanced** tab.
3. Under **Command-Line Access**, turn on **Enable the passwards command-line tool**.

The same section shows the **CLI binary** path — the location of the `passwards` program inside the app. You can select and copy it to run the tool, for example:

```bash
/Applications/Passwards.app/Contents/MacOS/Passwards item list
```

> Passwards must be **unlocked** for the `item` and `read` commands to work. If it's locked, they'll tell you so.

## The commands

Run `passwards help` to see this list at any time.

### `item list`

Lists your active items — each item's id, title, username, and category. (Items in Recently Deleted and archived items aren't shown.) This is overview information only, so it never asks for Touch ID.

```bash
passwards item list
```

### `item get`

Reads one field from an item, found by its id or title.

```bash
passwards item get GitHub
passwards item get GitHub username
```

- With no field name, it reads the **password**.
- You can also ask for `username`, `notes`, or any field by its label.
- The item is matched by exact id first, then an exact title (ignoring case), then any title that contains what you typed.

The secret value is printed on its own line, so you can pipe it into other commands. A short note about which item and field it came from is shown separately.

### `read op://...`

Reads a field using a secret reference, in the form `op://[vault/]item/field`.

```bash
passwards read op://Personal/GitHub/password
passwards read op://GitHub/password
```

This is handy in scripts and config files where you want to point at a specific secret rather than store it.

### `ssh-agent`

Prints the SSH agent's socket path and the `export SSH_AUTH_SOCK=…` line you can add to your shell profile so tools like `ssh` and `git` use Passwards for your keys.

```bash
passwards ssh-agent
```

> The SSH agent itself is enabled separately, under **Settings → SSH Agent**.

### `ssh-keys`

Lists the public keys the SSH agent is currently serving (in `authorized_keys` form). Public keys only — your private keys never leave the app.

```bash
passwards ssh-keys
```

### `version` and `help`

`passwards version` prints the version; `passwards help` shows the full command list.

## Security

Command-Line Access is built to be safe by default:

- It's **opt-in** — `item` and `read` do nothing until you enable Command-Line Access in **Advanced**.
- They only work while Passwards is **unlocked**.
- **Every secret read prompts for Touch ID** (or your login password). The prompt names the exact item and field being read, so a program can't quietly pull values from your vault even when the app is unlocked.
- Listing items (`item list`) and listing SSH public keys (`ssh-keys`) don't expose secrets, so they don't prompt.

> Reading a secret always shows a prompt naming the item and field. If you didn't start that command, deny it.


<!-- GROUP: Security & Privacy -->

# How Passwards Protects Your Data

This article explains, in plain language, how Passwards keeps your data safe. You don't need to understand it to use the app — it's here so you can trust it.

## Everything is encrypted before it's stored

Every password, note, card number, and file you save is encrypted with **AES‑256‑GCM** — the same standard used by banks and governments — *before* it touches your disk or the cloud. The only things kept in readable form are non-sensitive details like internal ID numbers and timestamps. Titles, usernames, passwords, URLs, and notes are all stored as unreadable ciphertext.

Each encrypted item is also bound to its place, so a piece of ciphertext can't be copied from one item and made to open as another.

## How the keys are layered

Your two secrets don't directly encrypt your passwords. Instead there's a chain of keys, so changing your password never requires re-encrypting your whole vault:

```
Account Password ─┐
                  ├─► Account Unlock Key ─► Master Key ─► Vault Keys ─► Item Keys ─► your data
Secret Key       ─┘
```

1. Your **Account Password** is put through a deliberately slow calculation (hundreds of thousands of rounds) so guessing it by brute force is impractical.
2. The result is combined with your **Secret Key** to form the **Account Unlock Key**. Both halves are required.
3. That key unwraps your **Master Key**, which unwraps a key for each vault, which unwraps a key for each item.

Because your password only protects the top of this chain, you can change it anytime and only one small wrapped key is rewritten — your data is untouched.

## Where each secret lives

- **Account Password:** never stored anywhere. It exists only while you type it.
- **Secret Key:** stored in your Mac's Keychain, marked *device-only* so it **never syncs to iCloud**. It's also in your Emergency Kit.
- **Master Key and the rest:** only ever stored encrypted. The unwrapped keys live in memory only while the app is unlocked.

## What a thief or a breach would get

- **Someone who steals your Mac** finds only encrypted data — unreadable without your password (and valid Touch ID).
- **Someone who breaks into your iCloud** finds only encrypted records, and *not* your Secret Key. They can't read anything.
- **Apple** can't read your data. iCloud only ever holds ciphertext.

## Locking erases the keys

Locking Passwards — manually, on sleep, after idle, or after a timeout — immediately wipes the unwrapped keys from memory, clears cached data and any in-progress edit, and clears any password left on your clipboard. After locking, your data is just ciphertext again until you unlock.


# Unlocking with Touch ID

Touch ID lets you unlock Passwards with your fingerprint instead of typing your password. Turn it on in **Settings → Security → Unlock with Touch ID** (while unlocked).

## How it works

When you enable Touch ID, Passwards wraps your **Master Key** to a key held inside your Mac's **Secure Enclave** — a dedicated security chip. That wrapped key can only be unwrapped by your fingerprint, and the Secure Enclave key can never be copied off your Mac. This is real, hardware-backed protection, not just a yes/no switch.

## What to know

- **It's per-device.** Touch ID enrollment never syncs. Enable it separately on each Mac (Settings → Security, while unlocked).
- **Your password is still required periodically.** By default, Passwards asks for your full Account Password again **after 3 days**. You can change this — including "Never" — under **Require account password after** in Settings → Security. Unlocking with Touch ID does not reset that timer; only typing your password does.
- **It can be invalidated.** Touch ID is automatically and permanently turned off if your Mac's fingerprints change (you add or remove one), if you switch it off, or if you reinstall the app. After that you'll need your Account Password (and Secret Key) to get back in, and can re-enable it.

> **Touch ID can rescue a forgotten password — within limits.** Because Touch ID can produce your Master Key without your password, a Mac where Touch ID is still enrolled and valid can unlock your data even if you've forgotten the password. But it's per-device, time-limited, and fragile (a single fingerprint change wipes it). It is *not* a substitute for a **Recovery Code**.


# iCloud Sync & Privacy

Passwards can keep your vault in sync across your Macs using your own private iCloud account. It's designed so that syncing adds convenience without weakening your privacy.

## What syncs — and what doesn't

- **Only encrypted data syncs.** iCloud carries ciphertext only. Because sync never needs your keys, it can run even while the app is **locked**.
- **Your Secret Key never syncs.** It stays in each Mac's Keychain. That's why setting up a new device requires you to enter it by hand.
- **Apple can't read any of it.** iCloud only stores the scrambled records; the keys to unscramble them are never sent to Apple.

## What's stored in readable form

Only non-sensitive bookkeeping is ever in the clear: internal ID numbers, timestamps, and which items still need to sync. Everything sensitive — titles, usernames, passwords, notes, URLs — is encrypted.

## Setting up sync on another Mac

See *Adding Another Mac*: sign in to the same iCloud account, choose **Sign in to an existing account**, and enter your Account Password and Secret Key.

## Changes propagate automatically

Edits you make on one Mac appear on the others shortly after, with no manual step. If the same item is edited in two places, the most recent change wins and the older version is preserved in that item's history so nothing is silently lost.


# Recovery Codes

A **Recovery Code** is an optional backup that lets you get back into Passwards if you forget your Account Password. This is the safety net most people should set up.

## Why you want one

Without a Recovery Code, a forgotten Account Password means your data is **gone** — unless you happen to have a Mac with valid Touch ID. There's no password reset, by design. A Recovery Code gives you a reliable way back in that you control.

## How it works (and why it's safe)

When you create a Recovery Code, Passwards generates a long random code (about 147 bits of randomness — far too large to ever guess) and uses it to lock away a backup copy of your keys as encrypted ciphertext. That backup is stored **on your Mac** alongside your vault — and, if you use iCloud sync, a copy is kept in your iCloud account too.

To recover you need **two independent things**:

1. **The encrypted backup** — already on this Mac, or downloaded from iCloud when you set up a new Mac, and
2. **Your Recovery Code** — to unlock it.

Neither alone is enough. The backup is useless without your Recovery Code, and the code is never stored alongside it — not on disk, not in iCloud, and never sent to Apple or to us. So recovery always takes two separate factors, just like "Password + Secret Key."

> **The honest trade-off.** A Recovery Code is, by design, a second way in. The encrypted backup contains your keys, so anyone who has *both* that backup — from your iCloud account, or from your Mac's disk — *and* your Recovery Code could open your vault. **Guard your Recovery Code as carefully as your Secret Key** — store it somewhere safe and separate. For most people this is a great deal: it removes the risk of permanent lockout while keeping strong, two-factor protection.

## Setting up a Recovery Code

1. Open **Settings → Security → Set Up Recovery Code…**
2. Enter your **current Account Password** (you can only create a recovery path while you still have access).
3. Passwards shows your Recovery Code once. **Copy it and store it safely** — for example, click **Save to Emergency Kit…** to add it to your Emergency Kit PDF.

Your Recovery Code is **reusable** and stays valid even after you change your Account Password.

## Using a Recovery Code to get back in

- **On the same Mac:** on the lock screen, choose **Forgot password? Use your recovery code**, enter the code, and set a new password.
- **On a new or replacement Mac:** open Passwards and choose **Recover with a recovery code**. Enter the code and a new password — Passwards downloads your vault from iCloud and restores your Secret Key automatically.

Either way you'll set a new Account Password during recovery, and your Recovery Code keeps working for next time.

> **Not using iCloud?** Your recovery backup is still saved on this Mac, so the **same-Mac** recovery above works completely offline — forgetting your password doesn't lock you out as long as you have your Recovery Code. But with no iCloud copy there's nothing to restore from if this Mac is lost or damaged, and recovering onto a *new* Mac needs iCloud. If you rely on a single Mac without iCloud, your safest backstop is still keeping your Account Password and Secret Key somewhere safe.

## Viewing, replacing, or turning it off

In **Settings → Security → Manage Recovery Code…** you can:

- **View** your current code again (after confirming with your password or Touch ID).
- **Replace** it with a fresh one (the old code stops working).
- **Turn it off** completely — this destroys the encrypted backup on your Mac and in iCloud, so the old code can no longer be used.


# If You Forget Your Password

Passwards is built so that *only you* can open your vault. That strength has a flip side: if you lose your way in, there's no company that can let you back in. Here's what to do, in order.

## Work down this list

1. **Do you have a Recovery Code?** Use it. On the lock screen choose **Forgot password? Use your recovery code**, or on a new Mac choose **Recover with a recovery code**. Enter the code and set a new password. This is the reliable path. ✅
2. **No Recovery Code, but a Mac with Touch ID still working?** Unlock with Touch ID right away, then immediately set up a Recovery Code (Settings → Security) and/or change to a password you'll remember. Act fast, and don't change your Mac's fingerprints or reinstall the app in the meantime, or Touch ID will be wiped. ⏳
3. **Neither?** Unfortunately your data can't be recovered — this is the deliberate cost of encryption that nobody else can bypass. You'd need to start a new account. ❌

## The takeaway

Setting up a **Recovery Code today** is the single best thing you can do to protect yourself against being locked out. It takes a minute, it's reusable, and it keeps your data just as private. See *Recovery Codes*.


<!-- GROUP: Reference -->

# Settings Reference

Open **Settings** from the **Passwards** menu (or press `⌘,`). The window has seven tabs: **General**, **Appearance**, **Security**, **Privacy**, **Browser**, **SSH Agent**, and **Advanced**. This article walks through each one.

## General

- **Keyboard Shortcuts** — Record global hotkeys that work anywhere on your Mac:
  - **Show Quick Access:** — opens the floating Quick Access search panel. Default: `⌘⇧Space`.
  - **Lock Passwards:** — locks the app immediately. Default: `⌘⇧L`.

  Click a recorder field and press the keys you want to assign a new shortcut.
- **Start Passwards at login** — Launches Passwards automatically when you log in to your Mac.
- **Show Passwards in the menu bar** — Adds the Passwards icon to your menu bar.

## Appearance

- **Theme** — Choose how Passwards looks: **Match System** (follow your Mac's light/dark setting), **Light**, or **Dark**.

## Security

This tab controls your account password, recovery options, Touch ID, and when the app locks.

### Account Password

- **Change Account Password…** — Opens a sheet where you confirm your current password, then choose a new one (10+ characters and at least "fair" strength; it can't match your current password). Your Secret Key and saved data stay the same — only the password changes. Available only while Passwards is unlocked.

### Emergency Kit

- **View Secret Key & Save Emergency Kit…** — Verify with Touch ID or your account password, then reveal your **Secret Key** and save a PDF Emergency Kit. Available only while unlocked.

> Your Emergency Kit contains your Secret Key, which you'll need to set up Passwards on a new device. Keep a copy somewhere safe.

### Recovery Code

- **Set Up Recovery Code…** / **Manage Recovery Code…** — A recovery code lets you regain access if you forget your account password. When one is set up, the management sheet offers **View**, **Replace…**, and **Turn Off…**, and you can save the code to your Emergency Kit PDF.

> Keep your recovery code as safe as your Secret Key. Combined with your iCloud data, it can unlock your vault even without your password.

### Unlock

- **Unlock with Touch ID** — Unlock Passwards with your fingerprint instead of typing your password. This appears only on Macs with Touch ID; otherwise the tab shows "Touch ID is not available on this Mac." You must be unlocked to turn it on, and because it's set up per-device, you'll enable it again on each new Mac.
- **Require account password after** — Even with Touch ID on, Passwards periodically asks for your full account password. Choose **8 hours**, **1 day**, **3 days**, **14 days**, or **Never**.

### Auto-Lock

- **Lock after system is idle for** — Locks when your whole Mac has been inactive. Options: **1 minute**, **5 minutes**, **10 minutes**, **30 minutes**, **1 hour**, or **Never**.
- **Lock when in the background for** — Locks while Passwards is in the background and you keep working in other apps. Options: **1 minute**, **5 minutes**, **15 minutes**, **1 hour**, or **Never**.
- **Lock when the device goes to sleep** — Locks whenever your Mac sleeps.
- **Lock when the screensaver starts** — Locks when the screensaver kicks in.

### Clipboard

- **Clear copied secrets after** — Automatically wipes copied passwords and other secrets from the clipboard. Options: **30 seconds**, **90 seconds**, **3 minutes**, or **Never**.

## Privacy

- **Check for vulnerable passwords** (under **Watchtower**) — Checks your passwords against known breaches using the Have I Been Pwned range API. Only the first 5 characters of a local SHA-1 hash are ever sent — your passwords never leave this Mac.
- **Show website icons** (under **Rich Icons**) — Fetches each site's icon directly from the website, so no third-party icon service sees your saved sites.
- **Clear Icon Cache** — Deletes the locally cached website icons.

## Browser

Connects the Passwards browser extension to the app.

- For each detected Chromium-based browser (Chrome, Brave, Edge, and similar), Passwards shows a status:
  - **Connected** — already set up.
  - **Install…** — click to register Passwards with that browser.
  - **Repair…** — click to fix a setup that's out of date.

After installing, load the extension from the repository's `BrowserExtension` folder via `chrome://extensions` → **Load unpacked**. The first connection asks you to confirm a verification code to pair securely.

> If no Chromium-based browsers are found, the tab shows "No Chromium-based browsers were found on this Mac."

## SSH Agent

Lets Passwards act as your SSH agent, serving the private keys stored in your **SSH Key** items to `ssh`, `git`, and other tools. Keys are only offered while Passwards is unlocked, and the private keys never leave the app.

- **Use Passwards as my SSH agent** — Turns the agent on or off.

When enabled, two more sections appear.

### Authorization

- **Require approval for each key use** — Each SSH signature must be confirmed with Touch ID (or your login password), so no program can use your keys without you noticing — even while Passwards is unlocked.
- **Remember approval** — When approval is required, choose how long an approval is remembered: **Ask every time**, **For 1 minute**, or **For 5 minutes**.

### Setup

Passwards shows the line to add to your shell profile (`~/.zshrc`), for example:

```bash
export SSH_AUTH_SOCK="…/agent.sock"
```

Click **Copy**, paste it into your profile, and open a new terminal. Verify with `ssh-add -l` — your SSH Key items should be listed.

## Advanced

### iCloud Sync

- **Sync with iCloud** — Keeps your vault in sync across your Macs through iCloud.
- **Status** — Shows the current sync state: **Off**, **Up to date**, **Syncing…**, an error message, or **iCloud account unavailable**.

> If the build doesn't have the CloudKit entitlement, this section explains that instead of showing the toggle.

### Command-Line Access

- **Enable the passwards command-line tool** — Lets the `passwards` CLI list items and read a single field (`item get`, `read op://…`). Each secret read prompts for Touch ID, and it only works while Passwards is unlocked.
- **CLI binary** — Shows the path to the command-line tool so you can reference it from scripts.

### Recently Deleted

- A reminder that items in Recently Deleted are permanently removed after 30 days.

### Coming Soon

- A note that passkeys and item sharing have reserved extension points and can be added later.


# Importing & Exporting

Passwards can bring your data in from other password managers and save a copy of your items to a file. All of these options live in the **File** menu, and they appear only while your vault is unlocked.

> **One warning up front:** exports are **not encrypted**. They are plain files anyone can open. Treat an export like a printout of all your passwords. See [Exports are not encrypted](#exports-are-not-encrypted) below.

## Where to find these options

Open the **File** menu in the menu bar. You'll find two import commands and two export commands:

- **Import from 1Password (.1pux)…**
- **Import from CSV…**
- **Export Logins as CSV…**
- **Export All Items as JSON…**

These appear only when your vault is unlocked. If you don't see them, unlock Passwards first.

## Importing

### From 1Password (.1pux)

This is the best way to move from 1Password, because it keeps the most detail.

1. In 1Password, export your data as a `.1pux` file.
2. In Passwards, choose **File → Import from 1Password (.1pux)…**.
3. Pick the `.1pux` file and confirm.

For each vault in the file that contains items, Passwards creates a **new vault** (it won't merge into your existing vaults). If a vault name already exists, Passwards adds a number to keep them separate.

The 1Password import understands all the common item types — Logins, Passwords, Credit Cards, Secure Notes, Identities, Documents, SSH Keys, and more — and carries over titles, usernames, passwords, one-time-password codes, websites, tags, favorites, notes, and password history. File attachments stored inside the export are imported too.

When it finishes, you'll see a message telling you how many items were imported and how many vaults were created. If anything couldn't be read, it tells you how many items were skipped.

### From CSV

CSV import is the catch-all for other apps. Passwards auto-detects the column headers used by common exporters, including **1Password**, **Chrome/Edge**, **Bitwarden**, **LastPass**, and **Safari**.

1. Export a CSV from your other password manager.
2. In Passwards, choose **File → Import from CSV…**.
3. Pick the file and confirm.

> **Where CSV items land:** unlike the 1Password import, CSV import does **not** create a new vault. It adds the imported logins to the vault you currently have selected in the sidebar (or your first vault if none is selected). Select the vault you want *before* importing.

CSV import brings in logins: title, username, password, website, notes, and a one-time-password code if your file has one. Empty or unusable rows are skipped, and the completion message tells you how many logins were imported and how many rows were skipped.

> CSV files only carry simple login fields. If your old app supports `.1pux` or another full-fidelity format, that will preserve more than CSV can.

## Exporting

Passwards offers two export formats.

### Export Logins as CSV

Choose **File → Export Logins as CSV…**. This saves a spreadsheet-friendly file (`Passwards Logins.csv`) with these columns:

`Title, Username, Password, OTPAuth, URL, Notes, Tags`

This export includes **only Login and Password items** — credit cards, identities, notes, and other types are left out. Items in the Trash are not included. It's ideal for moving your logins into another password manager that accepts CSV.

### Export All Items as JSON

Choose **File → Export All Items as JSON…**. This saves a complete file (`Passwards Export.json`) containing **every category of item**, organized by vault, with full structure (all sections, fields, dates, and notes). Items in the Trash are not included. JSON is best for a full backup of everything, or for moving to a tool that can read it.

### Both exports ask for your password first

Before either export runs, Passwards shows a **Confirm your account password** prompt. This is a real security check, not a formality — Passwards re-derives your unlock key from what you type, so the export only proceeds if the password is genuinely correct. You'll then choose where to save the file.

## Exports are not encrypted

This is the most important thing to understand about exporting.

> **An exported `.csv` or `.json` file is plain, readable text. Every password, code, and note inside it is completely unprotected.** Anyone who opens the file — or finds it in your Downloads folder, your Trash, or a cloud backup — can read all of it.

The save dialog reminds you of this, and so does the completion message. To stay safe:

- Save exports to a location only you can reach, never a shared or synced folder you don't control.
- Use the file for its purpose right away (such as importing into another app).
- **Delete the file as soon as you're done**, and empty your Trash afterward.

When in doubt, keep your data in the app, where it stays encrypted, and only create an export when you truly need one.


# FAQ & Glossary

This page answers the most common questions about how Passwards protects your data, then explains the key terms you'll see throughout the app.

## Frequently Asked Questions

### Is my data encrypted?

Yes. Everything you store in Passwards — passwords, notes, card numbers, fields, and file attachments — is encrypted with **AES-256-GCM** before it's written to disk or sent to iCloud. The only things stored in plain form are non-secret bookkeeping like IDs, timestamps, and sync status. Your data is unreadable without your **Account Password** and **Secret Key**.

### Can Passwards or Apple see my passwords?

No. Passwards uses **end-to-end encryption**: your data is encrypted on your Mac, and the keys come from secrets that never leave your control. Your Secret Key is kept only in your Mac's Keychain and is **never** stored in the database or uploaded to iCloud. Apple's servers only ever hold encrypted blobs — neither Apple nor anyone running Passwards can read your contents.

### Does it work offline?

Yes. Passwards is a native Mac app and your vault lives on your Mac. You can browse, search, edit, and create items with no internet connection. iCloud sync simply catches up the next time you're online.

### What if I lose my Mac?

Your data is safe as long as your Account Password and Secret Key stay private. To get back up and running on a new Mac:

1. Install Passwards and choose **"Sign in to an existing account"** during onboarding.
2. Your encrypted vault downloads from iCloud.
3. Enter your **Account Password** and the **Secret Key** from your **Emergency Kit**.

> This relies on iCloud sync — it's what keeps an off-device (encrypted) copy of your vault. If you use Passwards on a single Mac **without** iCloud, a vault that exists only on a lost or damaged Mac can't be recovered. Turn on iCloud sync if you want protection against losing the device.

> Touch ID does not transfer between Macs. Each new Mac re-enrolls Touch ID via the **Unlock with Touch ID** toggle in **Settings → Security**, while unlocked.

### What if I forget my Account Password?

There are two cases:

- **If you set up a Recovery Code:** On the lock screen, click **"Forgot password? Use your recovery code"**, enter the code, and choose a new password. Your Secret Key is restored automatically.
- **If you did not set up a Recovery Code:** Your password cannot be reset or recovered. By design, no one — not even the people behind Passwards — can decrypt your vault without your credentials.

> Set up a Recovery Code now, before you need it: **Settings → Security**, then **Set Up Recovery Code…**. Keep it as safe as your Secret Key.

### What's the difference between my Account Password and my Secret Key?

Your Account Password is something you remember and type often. Your Secret Key is a long random key stored on your Mac and in your Emergency Kit. **Both** are combined to unlock your vault, so a stolen password alone — or a stolen copy of your iCloud data alone — is not enough to open it.

### Where is my vault stored on my Mac?

In your user **Application Support** folder, with attachments alongside it. The file is encrypted at rest.

## Glossary

### End-to-end encryption

A design where your data is encrypted on your own device and can only be decrypted on your own device. Servers (including iCloud) only ever see scrambled data, so no service provider can read your information.

### Account Password

The password you choose when you create your account and type to unlock Passwards. It's combined with your Secret Key to derive the key that unlocks your vault. It's stretched with **PBKDF2-SHA256 (650,000 iterations)** to make guessing impractical. You can change it anytime from **Settings → Security**, with **Change Account Password…**, without affecting your Secret Key.

### Secret Key

A high-entropy key generated when your account is created, shown as `A3-XXXXXX-XXXXXX-XXXXX-XXXXX-XXXXX-XXXXX`. It's the second half of unlocking your vault and is stored only in your Mac's Keychain and your Emergency Kit — **never** in the database or in iCloud. You'll need it to set up Passwards on a new Mac. View it anytime from **Settings → Security**, with **View Secret Key & Save Emergency Kit…**.

### Recovery Code

An optional, high-entropy code (`RC-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX-XXXXX`) that lets you get back into your account if you forget your Account Password. It's independent of your password, so it keeps working after a password change.

> With your Recovery Code **and** your iCloud data, your vault can be unlocked. Guard it as carefully as your Secret Key. Set it up or replace it from **Settings → Security** (**Set Up Recovery Code…** or **Manage Recovery Code…**).

### Master Key

The key that actually protects your vault and items. It's wrapped (encrypted) so it can only be unwrapped by combining your Account Password and Secret Key. The Master Key is never stored in plain form and is cleared from memory whenever you lock.

### Emergency Kit

A PDF you can save (`Passwards Emergency Kit.pdf`) that records your sign-in email and Secret Key, with a blank line to write in your Account Password. Keep a printed or safely stored copy somewhere secure — it's what you'll use to set up a new Mac. Save it from onboarding or from **Settings → Security**.

### Secure Enclave

A dedicated security chip in your Mac. When you turn on **Unlock with Touch ID**, Passwards wraps your Master Key to a non-exportable key inside the Secure Enclave. Touch ID then unlocks the vault cryptographically — it's enforced by hardware, not a setting that can simply be flipped. This key is per-device and never syncs, so each Mac enrolls separately.

### Vault

A container for your items. Items are grouped into vaults so you can organize them and see them in the sidebar. Each vault has its own encryption key under your Master Key.

### Watchtower

Passwards's built-in security checkup. It scans your items and flags issues so you can fix them, including:

- **Vulnerable Passwords** — passwords that appeared in known data breaches
- **Reused Passwords** — the same password used by more than one item
- **Weak Passwords** — passwords that are easy to guess
- **Unsecured Websites** — sites still using `http://`
- **Two-Factor Authentication** — sites that support 2FA where no one-time password is saved
- **Expiring Items** — items that have expired or will within 60 days
- **Duplicate Items** — items that appear to be copies of each other

Breach checks use **Have I Been Pwned**. Only the first 5 characters of a local SHA-1 hash are ever sent (k-anonymity), so your actual passwords never leave your Mac. Turn this on or off with **Check for vulnerable passwords** in **Settings → Privacy**.


