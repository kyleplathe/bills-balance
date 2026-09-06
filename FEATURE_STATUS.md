# Feature Implementation Status

Updated for App Store v1 (local-first).

## Implemented

- Recurring bills with duplicate guards (in-memory pending keys + name/date/amount)
- Auto-pay with skip windows during import and newly created bills
- Multi-account ledger, reconcile, transfers
- Account JSON backup import/export from Manage Accounts
- Statement CSV import from the account screen, including Strike bill-pay CSV
- **Available balance** (projected) on Balance and Account detail, with a local 14/30/60/90-day window
- Relative dates (Today / Yesterday / Tomorrow) on ledger rows
- BTC display format and starting-balance input stay in sync in Account Editor; Bitcoin UI stays hidden until a BTC digital wallet exists
- Custom categories via `CategoryManager` / `CategoryPicker`
- Activity reports (week / month / year) with `CategoryManager` injected so the sheet does not crash
- On-device Core Data only; optional Face ID lock; user-initiated Files / iCloud Drive export
- Onboarding: Start Empty vs Try Sample Data
- Privacy policy and support links in Manage Accounts

## Intentionally parked

- CloudKit auto-sync (`cloudKitContainerOptions` stays nil; entitlements have no iCloud)
- Supabase (auth, RLS, bill repository). Stubs keep the target compiling. Real WIP is in `Parked/SupabaseWIP/`.
- Automatic bank feeds. Import remains CSV/JSON and manual entry.
- Statement import rewrite

## Tests

See `BillsAndBalanceTests/MoneyLogicTests.swift` for recurrence, duplicates, CSV parsing, fee parsing, balance math, notification schedule dates, and an in-memory Core Data recurrence test.
