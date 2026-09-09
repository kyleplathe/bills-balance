# Bills & Balance — App Store print checklist

Print this page. Check boxes as you go. Copy-paste text lives in `APP_STORE_LISTING.md`. Device walkthrough lives in `APP_STORE_QA.md`.

**App:** Bills & Balance  
**Bundle ID:** `com.kyle.billsandbalance`  
**Version / build:** 1.0 (1)  
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
- [ ] Description — version page, **Description** box (text in `APP_STORE_LISTING.md`)
- [ ] Keywords — version page, **Keywords** (`bills,checkbook,ledger,pay,recurring,calendar,accounts,balance,local,reminders`)
- [ ] What’s New — version page, **What’s New in This Version**
- [ ] Privacy Policy URL — **App Information** (left sidebar), not the version page
- [ ] Support URL — version page, **Support URL**
- [ ] If App Privacy asked about CoinGecko: public Bitcoin prices only, not linked to the user

---

## 4. Screenshots (use Try Sample Data)

Do not show other apps in the frame.

**iPhone 6.7" (iPhone 16 Pro Max)**
- [ ] Bills
- [ ] Balance
- [ ] Calendar
- [ ] Activity
- [ ] Account detail

**iPhone 6.1" (iPhone 16)**
- [ ] Bills
- [ ] Balance
- [ ] Calendar
- [ ] Activity
- [ ] Account detail

**iPad 13" (iPad Pro 13-inch)**
- [ ] Bills
- [ ] Balance
- [ ] Calendar
- [ ] Activity
- [ ] Account detail

---

## 5. Archive and upload

- [ ] Scheme **BillsAndBalance**, destination **Any iOS Device**
- [ ] Product → Archive
- [ ] Organizer → Distribute App → App Store Connect → Upload
- [ ] Processing email arrived / build shows in App Store Connect
- [ ] Export compliance: **No** (HTTPS only)

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

Data is stored only on device (Core Data). CloudKit and any cloud account are not enabled.

Optional Face ID / device passcode lock is in Manage Accounts → Privacy.

Notifications are requested only after the Smart Notifications onboarding page (Start Empty / Try Sample Data), from Manage Bills → Enable Bill Reminders, or when the user first adds a bill. Skip does not show the permission dialog.

Bitcoin features stay hidden until the reviewer adds a Digital Wallet account and chooses BTC. They are not part of the default experience.

---

## After Apple replies

- [ ] Approved → set release (manual or automatic)
- [ ] Rejected → read the note, fix, bump build number, archive, upload, reply in Resolution Center

**Notes**

________________________________________________________________

________________________________________________________________
