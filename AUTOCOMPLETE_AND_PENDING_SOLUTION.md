# Autocomplete & Pending Transaction Solution

## Summary

This document outlines the solution for:
1. **Predictive text/autocomplete** for bill names and transaction titles
2. **Digital wallet fees in pending transactions** (✅ IMPLEMENTED)
3. **Better UX for marking bills as pending**
4. **Available balance forecasting with pending transactions**

## Current Status

### ✅ Already Implemented
- **Pending transactions**: Swipe right on bills to add pending (works)
- **Available balance calculation**: Subtracts future unpaid bills
- **Digital wallet fees**: Now calculated when creating pending transactions (just implemented)

### 🔄 Needs Implementation
- **Predictive text**: `suggestedTitles()` function exists but not used in TextFields
- **Pending toggle in bill editor**: No UI button/toggle for easy pending creation

## Implementation Plan

### 1. Predictive Text/Autocomplete (Recommended Approach)

**Option A: Simple Autocomplete List (Recommended)**
- Show suggestions below TextField as user types
- Use existing `accountViewModel.suggestedTitles(prefix:account:limit:)` function
- Display as a list that user can tap to select

**Option B: iOS Native Autocomplete**
- Use `.textInputAutocorrection()` and `.autocapitalization()`
- Less control, but more native iOS feel

**Recommendation**: Option A - gives better control and user experience

### 2. Pending Transaction UX Improvements

**Current**: Swipe right on bill → "Add Pending"

**Proposed Enhancements**:
1. **Toggle in Bill Editor**: Add "Mark as Pending" toggle next to "Auto-Pay"
2. **Auto-create for Auto-Pay bills**: Automatically create pending when due date approaches
3. **Visual indicator**: Show pending status more prominently in bill list

### 3. Digital Wallet Fees (✅ DONE)

Updated `BillViewModel.addPendingTransaction()` to:
- Check if account is digital wallet
- Calculate fee: `bill_amount * (feePercentage / 100)`
- Add fee to total amount
- Include fee note in transaction notes

### 4. Available Balance

Already works correctly:
- `availableBalance()` subtracts future unpaid bills
- Pending transactions (unreconciled entries) are included in pending balance
- Digital wallet fees are now included in pending transaction amounts

## UX Design Recommendations

### For Mortgage/Auto-Pay Bills:

1. **Create bill** with:
   - Name: "Mortgage Payment"
   - Amount: $2000
   - Due Date: 1st of month
   - Account: Checking Account
   - Auto-Pay: ON
   - **Mark as Pending**: ON (new toggle)

2. **When bill is created with "Mark as Pending"**:
   - Immediately creates pending transaction
   - Shows in account as pending (affects available balance)
   - Bill remains unpaid until reconciled

3. **When bill is paid**:
   - Reconcile pending transaction (or create new if no pending)
   - Mark bill as paid
   - Available balance updates

### For Digital Wallet Bills:

1. **Create bill** with:
   - Name: "Strike Payment"
   - Amount: $100
   - Account: Digital Wallet (with 0.8% fee)
   - **Mark as Pending**: ON

2. **Pending transaction created**:
   - Amount: $100.80 (includes $0.80 fee)
   - Note: "Digital Wallet Fee: 0.80 USD (0.800%)"
   - Shows in account as pending

3. **Available balance**:
   - Shows $100.80 as pending
   - User can forecast available balance accurately

## Next Steps

1. ✅ Add digital wallet fee calculation to pending transactions (DONE)
2. ⏳ Create autocomplete TextField component
3. ⏳ Add "Mark as Pending" toggle to bill editor
4. ⏳ Test available balance with pending transactions including fees
