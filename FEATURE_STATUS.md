# Feature Implementation Status

## ✅ Implemented Features

### 1. Remember Repeating Transaction Inputs
**Status**: ✅ PARTIALLY IMPLEMENTED
- Auto-fills category and entry type when transaction title matches historical data
- Location: `BalanceView.swift` lines 2076-2088
- **Missing**: Doesn't remember amount, notes, or other fields

### 2. Pending Bills for Next Month
**Status**: ✅ PARTIALLY IMPLEMENTED  
- Code exists to show next month's bills (BillListView.swift lines 840-846)
- **Issue**: Only shows bills with pending transactions or unpaid bills
- **Missing**: Should show ALL pending bills for next month, even if they're in the future

### 3. BTC/Sats Formatting
**Status**: ✅ PARTIALLY IMPLEMENTED
- Input format picker exists (AccountEditorSheet line 2415)
- **Issue**: Input format doesn't automatically match display format selection
- **Missing**: When display format changes, input format should update to match

## ❌ Missing Features

### 1. Custom Categories in Transactions
**Status**: ❌ NOT IMPLEMENTED
- Categories are hardcoded in arrays
- Location: `BalanceView.swift` line 2056, `AddEditBillView.swift`
- **Needed**: Ability to add custom categories beyond the predefined list

### 2. Available Balance (Projected Balance)
**Status**: ❌ NOT IMPLEMENTED
- `clearedBalance()` and `totalBalance()` exist but no "available balance"
- **Needed**: Balance that subtracts pending bills to show projected available funds

### 3. Transaction Date Display Format
**Status**: ❌ NOT IMPLEMENTED
- Currently uses `.formatted(date: .abbreviated, time: .omitted)` which can wrap
- Location: `BalanceView.swift` line 2629
- **Needed**: Dynamic dates (Today, Yesterday, etc.) to prevent wrapping

### 4. Calendar View Swipe Gesture for Income
**Status**: ❌ NOT IMPLEMENTED
- Swipe actions exist in BillListView but not in CalendarTabView for paychecks
- **Needed**: Swipe right gesture on income items to show edit/pending options

## 📋 Summary

**Implemented**: 3 features (all partially)
**Missing**: 4 features

The project folder appears to be properly linked, but these features haven't been fully implemented yet. Would you like me to implement the missing features?

