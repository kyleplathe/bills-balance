# Parked Supabase WIP

These files are **not** part of the BillsAndBalance Xcode target.

Sync backend decision: **CloudKit** (see `PersistenceController.swift` and `BillsAndBalance.entitlements`).
Supabase remains stubbed in `SupabaseSupport.swift` so the app compiles without `supabase-swift`.

Do not add these files to the target unless you deliberately switch from CloudKit to Supabase (one backend only).
