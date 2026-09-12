# App Store listing

Use this in App Store Connect. Host `PRIVACY.md` publicly (this GitHub file is the in-app / Connect URL until you put it on a simple webpage).

**Current binary:** 1.0.1 (9). First listing was 1.0 (8).

## URLs

- **Privacy Policy:** https://github.com/kyleplathe/bills-balance/blob/main/PRIVACY.md
- **Support:** https://github.com/kyleplathe/bills-balance/issues
- If the GitHub repo is private, publish `PRIVACY.md` on a public page before submit (GitHub Pages or any static host). Apple’s reviewer must be able to open the privacy URL without signing in.

## Name and category

- **Name:** Bills & Balance
- **Subtitle:** Local checkbook for bills
- **Category:** Finance (already `public.app-category.finance`)
- **Age rating:** 4+ (no user-generated public content, no gambling)

## Description

Bills & Balance is a simple checkbook for your phone. See what’s due, what’s been paid, and what’s left — without signing up or sending your numbers to a server.

If other money apps feel like too much, this one is closer to paper: bills on a calendar, a running balance, and reminders when something is coming due.

• Recurring bills with reminders and auto-pay
• Several accounts, with cleared and available balances
• A calendar for bills and income
• Activity by week, month, and year — just to see what happened
• Optional Face ID lock
• Backup to Files or iCloud Drive when you export

Your data stays on this iPhone or iPad until you export it.

## Keywords (100 character limit)

bills,checkbook,ledger,pay,recurring,calendar,accounts,balance,local,reminders

## What’s New (1.0)

First release. A simple checkbook for bills, accounts, a calendar, and optional Face ID — all on your device.

## What’s New (1.0.1)

Activity reports use the system Week / Month / Year picker. Recent transfers show the right direction. Bitcoin Deflation share cards can be saved to Photos, with a dated stamp and quote.

## App Privacy nutrition labels

Data collected by the developer: **none**.

Do not declare contact info, financial info, or location as collected.

Optional third-party: CoinGecko is contacted only after the user adds a Bitcoin digital wallet, for public market prices. That traffic is not linked to an identity in this app. If App Store Connect asks you to disclose a third-party partner for this, list CoinGecko as not linked to the user.

Tracking: **No**.

## Review notes

This app has no login. On first launch, choose **Try Sample Data** to populate demo checking/savings accounts and bills.

Data stays on device (Core Data). There is no cloud account and CloudKit is not enabled.

This is a personal checkbook, not a bank, broker, or cryptocurrency wallet. It does not store keys, send or receive Bitcoin, or facilitate crypto transactions. Optional BTC is a local balance the user types in after adding a Digital Wallet set to BTC. Bitcoin Deflation is a historical comparison using public CoinGecko prices. It is hidden until that wallet exists.

Optional Face ID / device passcode lock is in Manage Accounts → Privacy.

Notifications are requested only after the Smart Notifications onboarding page (Start Empty / Try Sample Data), from Manage Bills → Enable Bill Reminders, or when the user first adds a bill. Skip does not show the permission dialog.

## Screenshots

Capture with **Try Sample Data** in light and/or dark mode. Do not include other apps in the frame.

Required sizes for this binary (iPhone + iPad):

1. **iPhone 6.9"** — 1320×2868 (iPhone 16 Pro Max / 17 Pro Max / 18 Pro Max). 1290×2796 and 1260×2736 are also accepted.
2. **iPad 13"** — 2064×2752 (iPad Pro 13-inch). 2048×2732 is also accepted.

Apple scales the 6.9" set to smaller iPhones. Extra 6.1" / 6.7" sets are optional.

Suggested frames:

1. Bills tab with unpaid bills
2. Balance tab with Total Balance + accounts
3. Calendar month
4. Activity (from the Period Activity chip)
5. Account detail ledger

## Age / encryption

- Export compliance: uses only HTTPS (ITSAppUsesNonExemptEncryption = NO). Answer **No** to non-exempt encryption.
