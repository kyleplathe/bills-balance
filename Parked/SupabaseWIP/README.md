# Parked Supabase WIP

These files are **not** part of the BillsAndBalance Xcode target.

v1 ships **local Core Data only**. Backup is user-initiated export to Files / iCloud Drive.

Supabase remains stubbed in `SupabaseSupport.swift` so the app compiles without `supabase-swift`. CloudKit is also parked (`cloudKitContainerOptions = nil`; no iCloud entitlement).

Do not add these files to the target unless you deliberately switch to a cloud backend.
