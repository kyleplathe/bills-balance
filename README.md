# Bills & Balance - Personal Finance Management iOS App

A clean, modern iOS app that combines bill tracking with disciplined financial practices through manual verification of all transactions.

## Features

### Phase 1: Core Bill Tracking (Implemented)

#### ✅ Bill Management
- **Add/Edit Bills**: Create and modify bills with essential details
- **Mark as Paid**: Quick toggle to mark bills as paid/unpaid
- **Delete Bills**: Remove individual bills or recurring bill series
- **Bill Details**: Name, amount, due date, notes, recurrence

#### ✅ Recurring Bills
- Support for weekly, monthly, quarterly, yearly, and custom intervals
- Smart handling of recurring bill series
- Option to delete single occurrence or entire series
- Automatic creation of next bill when current one is paid

#### ✅ Bill Organization
- **Monthly View**: Group bills by month with clear headers
- **Status Indicators**: Visual indicators for paid, unpaid, overdue, and auto-pay bills
- **Smart Grouping**: Show current month + next 2 months by default
- **Future Bills**: Expandable section for upcoming months

#### ✅ Visual Design
- **Clean List Interface**: Modern, card-based bill rows
- **Status Colors**: Green (paid), Blue (upcoming), Red (overdue), Gray (inactive)
- **Haptic Feedback**: Subtle haptic responses for interactions
- **Swipe Actions**: Swipe to edit, mark paid, or delete
- **Context Menus**: Long-press for additional options

#### ✅ Notifications
- Local notifications for bill reminders (3 days before due date)
- Smart notification management (cancel when paid, reschedule when edited)

### Phase 2: Ledger Integration (Planned)
- Checkbook-style ledger with running balance
- Manual verification of all transactions
- Bank integration and transaction sync
- Smart matching between bills and bank transactions
- Monthly reconciliation tools

## Technical Architecture

### Core Technologies
- **SwiftUI** for modern, declarative UI
- **Core Data** for persistent storage
- **MVVM Pattern** with ViewModels for clean separation of concerns
- **iOS 17+** target for latest features
- **Clean, modular code structure**

### Core Data Model
```swift
Bill Entity:
- id: UUID (unique identifier)
- name: String (bill name)
- amount: Decimal (bill amount)
- dueDate: Date (due date)
- isPaid: Bool (payment status)
- paidDate: Date? (when paid)
- notes: String? (optional notes)
- recurrenceType: String (weekly, monthly, etc.)
- recurrenceInterval: Int16 (interval for recurring)
- seriesId: UUID? (links recurring bills)
- autoPay: Bool (auto-pay indicator)
- createdAt: Date
- updatedAt: Date
```

### Key Components

#### Views
- `BillListView`: Main list with monthly grouping
- `AddEditBillView`: Form for creating/editing bills
- `BillRowView`: Individual bill row component
- `BillSummaryHeader`: Monthly summary with totals

#### ViewModels
- `BillViewModel`: Core bill management logic
- `PersistenceController`: Core Data stack management
- `NotificationManager`: Local notifications for reminders
- `HapticManager`: Haptic feedback management

#### Models
- `BillRecurrenceType`: Enum for recurrence patterns
- `BillStatus`: Bill status with colors and display names

## Getting Started

### Prerequisites
- Xcode 15.0 or later
- iOS 17.0 or later
- Swift 5.9 or later

### Installation
1. Clone the repository
2. Open `BillsAndBalance.xcodeproj` in Xcode
3. Build and run on iOS Simulator or device

### First Launch
1. Grant notification permissions when prompted
2. Add your first bill using the "+" button
3. Explore recurring bills and monthly organization

## Usage Guide

### Adding Bills
1. Tap the "+" button in the top right
2. Fill in bill details:
   - Name (required)
   - Amount (required)
   - Due date (required)
   - Recurrence (optional)
   - Auto-pay toggle (optional)
   - Notes (optional)
3. Tap "Save"

### Managing Bills
- **Mark as Paid**: Tap the circle icon or swipe right
- **Edit**: Tap on the bill or long-press for context menu
- **Delete**: Swipe left or use context menu
- **Recurring Bills**: Choose to delete single occurrence or entire series

### Recurring Bills
- Set recurrence type (weekly, monthly, quarterly, yearly)
- Set interval (e.g., every 2 months)
- When you mark a recurring bill as paid, the next occurrence is automatically created
- Use series ID to link all occurrences of the same bill

### Notifications
- Bills send reminders 3 days before due date
- Notifications are automatically managed (canceled when paid, rescheduled when edited)
- Grant notification permissions in Settings if needed

## Design Philosophy

### Disciplined Financial Practices
- Manual verification of all transactions (Phase 2)
- Encourages regular balance checking
- No automatic payments without explicit confirmation
- Clear visual hierarchy for financial status

### Modern iOS Design
- Follows Apple's Human Interface Guidelines
- Supports both Light and Dark modes
- Optimized for iPhone and iPad
- Accessibility support with VoiceOver and Dynamic Type

### User Experience
- Smooth animations and transitions
- Haptic feedback for interactions
- Intuitive swipe gestures
- Clear visual status indicators

## Future Roadmap

### Phase 2: Ledger Integration
- [ ] Checkbook-style transaction register
- [ ] Running balance calculation
- [ ] Bank account integration
- [ ] Transaction import and matching
- [ ] Monthly reconciliation tools

### Additional Features
- [ ] Export/Import functionality
- [ ] Advanced filtering and search
- [ ] Bill categories and tags
- [ ] Spending analytics and reports
- [ ] Multiple account support

## Contributing

This is a personal finance app focused on disciplined money management. The codebase is designed to be:
- Clean and maintainable
- Well-documented
- Following iOS best practices
- Accessible to all users

## License

This project is for personal use and educational purposes.

## Support

For questions or issues, please refer to the code documentation or create an issue in the repository.

---

**Bills & Balance** - Take control of your finances with disciplined tracking and verification.
