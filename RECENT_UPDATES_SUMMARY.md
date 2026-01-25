# Recent Updates Summary - Potential Duplicate Bill Issues

## Key Functions That Create Bills

### 1. `addBill()` - BillViewModel.swift (lines 100-129)
- Creates new bills when manually added or imported
- Called from:
  - `AddEditBillView.swift` (line 778)
  - `BillListView.swift` - Import functions (lines 1189, 1319)

### 2. `generateNextRecurringBill()` - BillViewModel.swift (lines 307-350)
- Creates next bill in a recurring series when a bill is marked as paid
- **POTENTIAL ISSUE**: Does NOT save context immediately after creating bill
- Called from:
  - `togglePaidStatus()` (line 223) - when marking a recurring bill as paid

### 3. `processAutoPayBills()` - BillViewModel.swift (lines 496-522)
- Automatically processes bills with auto-pay enabled
- Calls `togglePaidStatus()` which can trigger `generateNextRecurringBill()`
- Called from:
  - `fetchBills()` (line 91) - every time bills are fetched

## Potential Duplicate Creation Scenarios

### Issue 1: Race Condition in `generateNextRecurringBill()`
**Location**: BillViewModel.swift, lines 307-350

The duplicate check (lines 319-330) queries the database, but if `generateNextRecurringBill()` is called multiple times before `saveContext()` is called, the new bills won't be in the database yet, so the check won't find them.

**Flow**:
1. Bill marked as paid → `togglePaidStatus()` called
2. `generateNextRecurringBill()` creates new bill (not saved yet)
3. If called again before save, duplicate check fails (bill not in DB yet)
4. Second bill created → duplicates

### Issue 2: `saveContext()` Calls `fetchBills()` Which Can Trigger Auto-Pay
**Location**: BillViewModel.swift, lines 532-541

```swift
private func saveContext() {
    do {
        try context.save()
        fetchBills() // Refresh the list
        accountViewModel?.refreshData()
        updateAppBadge()
    } catch {
        print("Error saving context: \(error)")
    }
}
```

**Flow**:
1. Bill marked as paid → `saveContext()` called
2. `saveContext()` calls `fetchBills()`
3. `fetchBills()` calls `processAutoPayBills()` (line 91)
4. If auto-pay processes bills, it calls `togglePaidStatus()` again
5. This could create additional recurring bills

### Issue 3: Import Functions May Not Check for Existing Bills
**Location**: BillListView.swift, lines 1189-1223 and 1319-1352

The import functions call `addBill()` without checking if a bill with the same name and due date already exists. If imports are run multiple times, duplicates will be created.

## Recommended Fixes

1. **Fix `generateNextRecurringBill()` duplicate check**:
   - Save context immediately after creating the bill, OR
   - Check in-memory pending changes before querying database

2. **Add duplicate check in import functions**:
   - Before calling `addBill()`, check if bill with same name and due date exists

3. **Review `processAutoPayBills()` logic**:
   - Ensure it doesn't process bills that were just created in the same save cycle

## Files Modified (Based on Code Analysis)

1. **BillViewModel.swift**
   - `generateNextRecurringBill()` - Creates recurring bills
   - `togglePaidStatus()` - Triggers recurring bill generation
   - `processAutoPayBills()` - Auto-processes bills
   - `saveContext()` - Saves and refreshes bills

2. **BillListView.swift**
   - Import functions that create bills from JSON/CSV

3. **AddEditBillView.swift**
   - Creates bills when user adds new bill

