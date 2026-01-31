# Bills & Balance

A simple, modern iOS app for tracking bills, managing your balance, projecting cash flow, and staying ahead of your bank — without the stress of traditional budgeting. 💸📅

**Bills & Balance** gives you clear visibility into when bills hit, how your projected income covers them, current account balances, spending trends, and more — all in a clean, low-pressure interface designed for real-life money management.

### Core Philosophy
When money is tight, complex budgets can feel overwhelming. This app keeps things simple: focus on bill timing, balance projection, ledger-style tracking, and calendar-based foresight so you can always be a few steps ahead of settlements.

### Key Features

#### Bills Tab
- Monthly snapshot with progress bar (paid vs. upcoming)
- Clean, searchable list of bills with status colors (green paid, blue upcoming, red overdue)
- Quick actions: check off as paid, edit, delete
- **Toolbar — Bill tools:**
  - Add new bill (+)
  - Search bills
  - Menu: **Manage Bills** (Import CSV, Export CSV/JSON, Add bill), **Show/Hide Paid Bills**
- Recurring bills with smart series handling
- Swipe actions for fast mark paid / edits

#### Balance Tab
- Total balance chip across all active accounts
- Activity summary card (current spending trends — tappable to expand)
- **Toolbar — Balance/Account tools:**
  - Add new account (+)
  - Search
  - Menu: **Manage Accounts** (edit accounts), **Manage Data** (clear bills / income / transactions / all data), **Import/Export**, **Transfer** (move funds between accounts), **Show/Hide inactive accounts**, **Reports** (to full Activity Reports)
- Full Activity Reports:
  - Toggle weekly / monthly / yearly views
  - "Spending more/less" indicators vs. previous period
  - Categories ranked by highest amount
  - Animated tappable pie chart with complex gradients (category color + value intensity)
- Credit card statement import (CSV) for complete monthly spending view
- Planned: Separate credit card payments (from balance accounts) vs. actual spending categories in reports

#### Calendar Tab
- Monthly overview:
  - Remaining projected balance
  - Projected income
  - Next 7 days owed
  - Projected bills for next month
- Tappable days: view/add/edit bills or income
- Bottom insight: "You're living X% above or below your means" (projected income vs. known bills for the month)
- Consistent edit flow + swipe actions (edit/delete); recurring delete options ("this only" vs "all future")
- Delete confirmations for safety

#### Shake to Bitcoin Mode
- Shake device → instantly view all bills and balances denominated in BTC / sats
- Planned: USD vs BTC value-over-time reports for bills and income (track dollar inflation vs. BTC denomination changes)

#### Additional Features
- Local notifications (3 days before due)
- Haptic feedback on key actions
- Manual transaction / paycheck entry
- Account & credit card management (add, edit, detail views with transaction history)
- Onboarding + splash screen
- Dark mode, Dynamic Type, VoiceOver support

### Tech Stack
- SwiftUI (iOS 17+)
- Core Data
- MVVM architecture
- Charts framework (gradients, animations)
- Local notifications + haptics
- CSV parsing for imports

### Screenshots
(Add your latest ones here — e.g., Bills toolbar expanded, Balance activity pie chart animation, Calendar projection with means %, Shake-to-BTC view)

### Roadmap
- Full USD ↔ BTC historical value charts
- Clear separation of credit card payments vs. spending in reports
- Enhanced projected income & means-calculation polish
- PDF/CSV detailed report exports
- Ledger-style running balance verification

Made with ❤️ in Minneapolis. Personal project — stars and feedback super welcome! 🚀
