# Bills & Balance — App Store print checklist

Print this page. Check boxes as you go. Copy-paste text lives in `APP_STORE_LISTING.md`. Device walkthrough lives in `APP_STORE_QA.md`.

**App:** Bills & Balance  
**Bundle ID:** `com.kyle.billsandbalance`  
**Version / build:** 1.0.1 (9) — next update after 1.0 (8) is live  
**Team:** `3GG234YCUT`  
**Category:** Finance  
**Date:** _______________

---

## 1. Apple account

- [x] Apple Developer Program is active and paid
- [x] Signed into Xcode with the same Apple ID as that team
- [x] App ID `com.kyle.billsandbalance` exists
- [x] Do **not** turn on iCloud / CloudKit for this release
- [x] App Store Connect app exists (name **Bills & Balance**, SKU e.g. `billsandbalance`)

---

## 2. Privacy URL (required — reviewer must open it with no login)

- [x] `PRIVACY.md` is on a **public** page
- [x] If GitHub is private, host it on GitHub Pages or any public site first
- [x] Open the URL in a private/incognito window and confirm it loads

**Privacy URL (paste into App Store Connect → App Information → Privacy Policy URL):**  
https://github.com/kyleplathe/bills-balance/blob/main/PRIVACY.md

**Support URL (paste into the iOS version page → Support URL):**  
https://github.com/kyleplathe/bills-balance/issues

---

## 3. App Store Connect listing

Copy from `APP_STORE_LISTING.md` into **App Store Connect → Apps → Bills & Balance → the iOS 1.0 version** (English (U.S.)). These fields do not fill themselves.

- [x] Name: Bills & Balance
- [x] Subtitle: Local checkbook for bills
- [x] Category: Finance
- [x] Age rating: 4+
- [x] Copyright: Instakyle Tech Solutions LLC (c) 2026
- [x] App Privacy: data collected = **none**; tracking = **No**
- [x] Description — version page, **Description** box (text in `APP_STORE_LISTING.md`)
- [x] Keywords — version page, **Keywords** (`bills,checkbook,ledger,pay,recurring,calendar,accounts,balance,local,reminders`)
- [x] What’s New — not shown for first 1.0 version
- [x] Privacy Policy URL — **App Privacy** (already `PRIVACY.md` on GitHub)
- [x] Support URL — version page, **Support URL**
- [x] If App Privacy asked about CoinGecko: public Bitcoin prices only, not linked to the user

---

## 4. Screenshots (use Try Sample Data)

Do not show other apps in the frame. Apple only requires the 6.9" iPhone set and 13" iPad set; smaller iPhone sizes scale from 6.9".

**iPhone 6.9" (iPhone 16 Pro Max — 1320×2868)**
- [x] Bills
- [x] Balance
- [x] Calendar
- [ ] Activity (optional; sample data has $0 activity)
- [ ] Account detail (optional)

**iPad 13" (iPad Pro 13-inch — 2064×2752)**
- [x] Bills
- [x] Balance
- [x] Calendar
- [ ] Activity (optional; sample data has $0 activity)
- [ ] Account detail (optional)

---

## 5. Archive and upload

- [x] Scheme **BillsAndBalance**, destination **Any iOS Device**
- [x] Product → Archive
- [x] Organizer → Distribute App → App Store Connect → Upload
- [x] Processing email arrived / build shows in App Store Connect
- [x] Export compliance: **No** (HTTPS only)

**Build uploaded:** 1.0 (8) — TestFlight status **Ready to Submit** (Sep 11, 2026 9:33 AM).

Screenshots to drop onto the version page live in `AppStoreScreenshots/` (iPhone 6.5" 1284×2778 + iPad 13" 2064×2752). Then select **build 8** (replace expired build 2) and tap **Add for Review**.

---

## 6. TestFlight on real devices

Install the build on iPhone **and** iPad. Light and dark.

**First launch**
- [ ] Skip does **not** ask for notifications
- [ ] Start Empty / Try Sample Data **does** ask after Smart Notifications
- [ ] Try Sample Data shows checking, savings, and bills

**Money**
- [ ] Add account, bill, paycheck
- [ ] Transfer between two accounts
- [ ] Clear / reconcile a ledger row
- [ ] Empty states look fine

**Backup and lock**
- [ ] Manage Accounts → Export Backup → Save to Files
- [ ] Import backup works
- [ ] Face ID lock: leave app, return, unlock; then turn lock off

**Notifications**
- [ ] Manage Bills → Enable Bill Reminders (if you skipped)
- [ ] Future bill reminds; past-due bill does not ping in ~60 seconds

**Layout**
- [ ] Bills, Balance, and Calendar exist in portrait and landscape
- [ ] Balance is reachable on iPad
- [ ] Sheets look correct on iPad

**Bitcoin (optional check)**
- [ ] Hidden until a digital wallet is set to BTC
- [ ] Calendar stays in dollars when Bills is in sats

**Look**
- [ ] App icon is the blue checklist (not a blank square)
- [ ] Light and dark both look right

---

## 7. Submit for review

- [ ] Select the processed TestFlight / App Store build
- [ ] Screenshots attached for iPhone 6.7", 6.1", and iPad 13"
- [ ] Review notes pasted (below)
- [ ] Submit

**Review notes (paste this):**

This app has no login. On first launch, choose Try Sample Data to populate demo checking/savings accounts and bills.

Data stays on device (Core Data). There is no cloud account and CloudKit is not enabled.

This is a personal checkbook, not a bank, broker, or cryptocurrency wallet. It does not store keys, send or receive Bitcoin, or facilitate crypto transactions. Optional BTC is a local balance the user types in after adding a Digital Wallet set to BTC. Bitcoin Deflation is a historical comparison using public CoinGecko prices. It is hidden until that wallet exists.

Optional Face ID is in Manage Accounts → Privacy. Notifications are requested only after Smart Notifications (Start Empty / Try Sample Data), Manage Bills → Enable Bill Reminders, or when the user first adds a bill. Skip does not prompt.

---

## After Apple replies

- [ ] Approved → set release (manual or automatic)
- [ ] Rejected → read the note, fix, bump **build** (10, 11, …), keep marketing version 1.0.1, archive, upload, reply in Resolution Center

## 1.0.1 update (after 1.0 is Ready for Sale)

Do not upload another 1.0 build. In App Store Connect: **+ Version → 1.0.1**, paste What’s New from `APP_STORE_LISTING.md`, archive **1.0.1 (9)**, attach that build, submit.

- Marketing version (`CFBundleShortVersionString`): **1.0.1** — what customers see
- Build (`CFBundleVersion`): **9** — must always go up (never reuse 8)
- What’s New: required from 1.0.1 onward

**Notes**

________________________________________________________________

________________________________________________________________
