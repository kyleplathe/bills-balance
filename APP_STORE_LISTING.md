# App Store listing

Use this in App Store Connect for version 1.0. Host `PRIVACY.md` publicly (this GitHub file is the in-app / Connect URL until you put it on a simple webpage).

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

Bills & Balance is a local-first checkbook. Track recurring bills, multiple accounts, and what you can actually spend — without creating an account or sending your ledger to a server.

• Recurring bills with reminders and auto-pay
• Multi-account ledger with cleared and available balance
• Calendar for bills and income
• Activity by week, month, and year
• Optional Face ID lock
• Backup to Files or iCloud Drive when you export

Your data stays on this iPhone or iPad until you export it.

## Keywords (100 character limit)

bills,budget,checkbook,ledger,finance,recurring,calendar,accounts,balance,local

## What’s New (1.0)

First release. Recurring bills, multi-account ledger, calendar, activity, optional Face ID, and on-device backup.

## App Privacy nutrition labels

Data collected by the developer: **none**.

Do not declare contact info, financial info, or location as collected.

Optional third-party: CoinGecko is contacted only after the user adds a Bitcoin digital wallet, for public market prices. That traffic is not linked to an identity in this app. If App Store Connect asks you to disclose a third-party partner for this, list CoinGecko as not linked to the user.

Tracking: **No**.

## Review notes

This app has no login. On first launch, choose **Try Sample Data** to populate demo checking/savings accounts and bills.

Data is stored only on device (Core Data). CloudKit and any cloud account are not enabled.

Optional Face ID / device passcode lock is in Manage Accounts → Privacy.

Notifications are requested only after the Smart Notifications onboarding page (Start Empty / Try Sample Data), from Manage Bills → Enable Bill Reminders, or when the user first adds a bill. Skip does not show the permission dialog.

Bitcoin features stay hidden until the reviewer adds a Digital Wallet account and chooses BTC. They are not part of the default experience.

## Screenshots

Capture with **Try Sample Data** in light and/or dark mode. Do not include other apps in the frame.

Required sizes for this binary (iPhone + iPad):

1. iPhone 6.7" (e.g. iPhone 16 Pro Max)
2. iPhone 6.1" (e.g. iPhone 16)
3. iPad 13" (e.g. iPad Pro 13-inch)

Suggested frames:

1. Bills tab with unpaid bills
2. Balance tab with Total Balance + accounts
3. Calendar month
4. Activity (from the Period Activity chip)
5. Account detail ledger

## Age / encryption

- Export compliance: uses only HTTPS (ITSAppUsesNonExemptEncryption = NO). Answer **No** to non-exempt encryption.
