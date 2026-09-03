# Bills & Balance

A local-first iOS checkbook and bills app: recurring bills, multi-account ledger, calendar, and activity reports. Persistence is **Core Data**, with **CloudKit** as the single sync backend when the user is signed into iCloud.

## What’s in the app

- **Bills** — recurrence, auto-pay, notifications, badge, categories, manage/import/export
- **Balance** — multi-account ledger, cleared vs available, transfers, JSON account export/import, statement CSV import (from Activity)
- **Calendar** — month grid and day drawer for bills and income
- **Activity** — week / month / year spending, income, fees, and categories
- **Extras** — onboarding, CoinGecko BTC price, credit cards, custom categories

## Available balance

**Cleared** is starting balance plus reconciled ledger entries (checkbook).

**Available** is current balance minus unpaid bills plus expected income inside a look-ahead window (14 / 30 / 60 / 90 days). The window lives in Settings on the Balance menu (**Available Balance Window**) and is stored locally in UserDefaults.

## Sync

One backend: **CloudKit** (`iCloud.com.kyle.billsandbalance`).

- Signed into iCloud on device → `NSPersistentCloudKitContainer`
- Simulator / no iCloud / CloudKit store failure → local Core Data fallback
- **Supabase is parked** (stubs in `SupabaseSupport.swift`; WIP under `Parked/SupabaseWIP/`). Do not enable both.

Create the CloudKit container in the Apple Developer portal for the App ID `com.kyle.billsandbalance` if you want multi-device sync.

## Architecture

- SwiftUI, iOS 17+, MVVM
- Core Data model: `Bill`, `Account`, `LedgerEntry`, `Paycheck`
- ViewModels: `BillViewModel`, `AccountViewModel`, `PaycheckViewModel`, `ReportsViewModel` (`@MainActor`)
- Money math that must stay correct lives in testable types: `RecurrenceCalculator`, `DuplicateBillGuard`, `BalanceMath`, `TransactionCSVParser`, `FeeParsing`

## Getting started

1. Open `BillsAndBalance.xcodeproj` in Xcode 15+
2. Select the **BillsAndBalance** shared scheme
3. Build and run on a simulator or device

Unit tests live in the **BillsAndBalanceTests** target (parser, recurrence, duplicate guards, balance math, in-memory Core Data).

## License

Personal use and educational purposes.
