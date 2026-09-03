# Feature Implementation Status

Updated to match the shipping app (health-check dial-in).

## Implemented

- Recurring bills with duplicate guards (in-memory pending keys + name/date/amount)
- Auto-pay with skip windows during import and newly created bills
- Multi-account ledger, reconcile, transfers (account detail and Balance menu)
- Account JSON import/export from the Balance menu
- Statement CSV import from Activity, including Strike bill-pay CSV (merged USD + fee + BTC)
- **Available balance** (projected) on Balance and Account detail, with a local 14/30/60/90-day window
- Relative dates (Today / Yesterday / Tomorrow) on ledger rows
- BTC display format and starting-balance input stay in sync in Account Editor
- Custom categories via `CategoryManager` / `CategoryPicker`
- Activity reports (week / month / year) with `CategoryManager` injected so the sheet does not crash
- CloudKit sync when iCloud is available; otherwise local Core Data

## Intentionally parked

- Supabase (auth, RLS, bill repository). Stubs keep the target compiling. Real WIP is in `Parked/SupabaseWIP/`.
- Automatic bank feeds. Import remains CSV/JSON and manual entry.

## Tests

See `BillsAndBalanceTests/MoneyLogicTests.swift` for recurrence, duplicates, CSV parsing, fee parsing, balance math, and an in-memory Core Data recurrence test.
