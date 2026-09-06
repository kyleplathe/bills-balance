# Device QA checklist (v1)

## Automated checks (this pass)

- Unit tests: 90 passed on iPhone 16 simulator, including notification schedule dates
- Release archive: succeeded (`generic/platform=iOS`)
- Simulator build: succeeded for iPhone and iPad (same binary, device family 1,2)

Physical-device rows below are still yours before you tap Submit.

## Fresh install

- [ ] Delete the app, install a Release or TestFlight build
- [ ] Onboarding Skip does **not** show the notification permission dialog
- [ ] Start Empty / Try Sample Data **does** show the notification dialog after the Smart Notifications page
- [ ] Try Sample Data seeds checking, savings, and bills

## Core money

- [ ] Add account, bill, paycheck
- [ ] Transfer between two accounts
- [ ] Reconcile / clear a ledger row
- [ ] Available-balance window in Manage Accounts / Balance settings still works
- [ ] Empty states: no accounts, no bills

## Backup and lock

- [ ] Manage Accounts → Export Backup → Save to Files
- [ ] Clear imported data / restore from import
- [ ] Require Face ID: background the app, return, unlock; turn lock off

## Notifications

- [ ] Manage Bills → Enable Bill Reminders (if skipped onboarding)
- [ ] Future-dated bill schedules; past-due bill does **not** fire in ~60 seconds
- [ ] Badge updates when bills are paid

## Tabs and iPad

- [ ] Bills, Balance, and Calendar all remain in portrait and landscape
- [ ] Balance is reachable on iPad (no Bills|Calendar-only split)
- [ ] Manage Accounts / Manage Bills / Activity sheets look correct on iPad

## Bitcoin easter egg

- [ ] No Bitcoin UI until a digital wallet is set to BTC
- [ ] USD vs Bitcoin share graphic from that account
- [ ] Calendar stays in dollars when Bills is in sats

## Visual

- [ ] App icon is the checklist-on-blue asset (not a missing/placeholder icon)
- [ ] Light and dark on iPhone and iPad
