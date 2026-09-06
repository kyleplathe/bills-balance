# Bills & Balance

A local-first iOS checkbook and bills app: recurring bills, multi-account ledger, calendar, and activity reports. Persistence is **Core Data on this device**. Backup is a file you export to Files or iCloud Drive. There is no cloud account and no CloudKit sync in this release.

## What’s in the app

- **Bills** — recurrence, auto-pay, optional notifications, badge, categories, manage/import/export
- **Balance** — multi-account ledger, cleared vs available, transfers, JSON backup in Manage Accounts, statement CSV import on the account
- **Calendar** — month grid and day drawer for bills and income
- **Activity** — week / month / year spending, income, fees, and categories
- **Extras** — onboarding with sample data, optional Face ID lock, CoinGecko BTC price only after a Bitcoin digital wallet

## Available balance

**Cleared** is starting balance plus reconciled ledger entries (checkbook).

**Available** is current balance minus unpaid bills plus expected income inside a look-ahead window (14 / 30 / 60 / 90 days). The window lives in settings on the Balance menu (**Available Balance Window**) and is stored locally in UserDefaults.

## Storage and privacy

- Signed-out, on-device SQLite via Core Data (`NSPersistentContainer`)
- Optional Face ID / device passcode lock in Manage Accounts
- Export / Import backup in Manage Accounts (share sheet → Files or iCloud Drive)
- **Supabase is parked** (stubs in `SupabaseSupport.swift`; WIP under `Parked/SupabaseWIP/`)
- **CloudKit is parked** — do not enable the iCloud capability for v1

See [PRIVACY.md](PRIVACY.md). App Store listing copy is in [APP_STORE_LISTING.md](APP_STORE_LISTING.md).

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
