//
//  BillRowView.swift
//  BillsAndBalance
//

import SwiftUI
import CoreData

struct BillRowView: View {
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var bitcoinPriceService: BitcoinPriceService
    let bill: Bill
    var onMarkPaid: ((Bill) -> Void)? = nil
    var compact: Bool = false
    
    private var isOverdue: Bool {
        guard let dueDate = bill.dueDate else { return false }
        return dueDate < Date() && !bill.isPaid
    }
    
    private var daysUntilDue: Int {
        guard let dueDate = bill.dueDate else { return 0 }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: dueDate)).day ?? 0
    }
    
    var body: some View {
        HStack(spacing: compact ? 10 : 16) {
            Button {
                let willMarkPaid = !bill.isPaid
                
                if willMarkPaid {
                    if let callback = onMarkPaid {
                        callback(bill)
                    } else {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                            billViewModel.togglePaidStatus(for: bill)
                        }
                        HapticManager.shared.billMarkedPaid()
                    }
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                        billViewModel.togglePaidStatus(for: bill)
                    }
                    HapticManager.shared.buttonTapped()
                }
            } label: {
                Circle()
                    .fill(bill.isPaid ? statusColor : Color.clear)
                    .frame(width: compact ? 22 : 26, height: compact ? 22 : 26)
                    .overlay(
                        Circle()
                            .stroke(bitcoinPriceService.showInBitcoin && !bill.isPaid ? .orange : statusColor, lineWidth: 2)
                    )
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: compact ? 11 : 14, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(bill.isPaid ? 1 : 0)
                    )
                    .padding(.vertical, compact ? 0 : 4)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(bill.isPaid ? "Mark unpaid" : "Mark paid")
            .accessibilityHint("Tap to toggle paid state")
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bitcoinPriceService.showInBitcoin)
            
            billInfoColumn
            Spacer(minLength: compact ? 8 : 12)
            billAmountColumn
                .layoutPriority(1)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: bitcoinPriceService.showInBitcoin)
        }
        .padding(.vertical, compact ? 0 : 4)
    }
    
    private var billInfoColumn: some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            HStack(spacing: 6) {
                Text(bill.name ?? "Unknown")
                    .font(compact ? .subheadline.weight(.medium) : .body.weight(.medium))
                    .strikethrough(bill.isPaid)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                if bill.autoPay {
                    Image(systemName: "bolt.fill")
                        .font(compact ? .caption2 : .caption)
                        .foregroundColor(.orange)
                }
                
                if bill.isPaid {
                    statusBadge("PAID", color: .green)
                }
            }
            
            if hasMetaContent {
                billMetaRow
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var hasMetaContent: Bool {
        if let accountName = bill.account?.name, !accountName.isEmpty { return true }
        if let paymentCard = bill.paymentCard, !paymentCard.isEmpty { return true }
        if bill.recurrenceType != "none", bill.recurrenceType != nil { return true }
        return false
    }
    
    private var billMetaRow: some View {
        HStack(spacing: 6) {
            if let accountName = bill.account?.name, !accountName.isEmpty {
                Text(accountName)
                    .font(compact ? .caption2 : .caption)
                    .foregroundColor(.secondary)
            }
            
            if let paymentCard = bill.paymentCard, !paymentCard.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "creditcard.fill")
                    Text(paymentCard)
                }
                .font(compact ? .caption2 : .caption)
                .foregroundColor(.secondary)
            }
            
            if bill.recurrenceType != "none", let recurrenceType = bill.recurrenceType {
                Text("• \(formatRecurrenceType(recurrenceType, interval: Int(bill.recurrenceInterval)))")
                    .font(compact ? .caption2 : .caption)
                    .foregroundColor(.secondary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    
    private func statusBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .foregroundColor(.white)
            .padding(.horizontal, compact ? 5 : 6)
            .padding(.vertical, compact ? 1 : 2)
            .background(color)
            .cornerRadius(compact ? 3 : 4)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    @ViewBuilder
    private var billAmountColumn: some View {
        VStack(alignment: .trailing, spacing: compact ? 1 : 2) {
            if bitcoinPriceService.showInBitcoin, let amount = bill.amount?.decimalValue {
                Text(bitcoinPriceService.formatAsSats(amount))
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .foregroundColor(bill.isPaid ? .green : .orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                Text("$\(bill.amount?.stringValue ?? "0")")
                    .font(compact ? .subheadline.weight(.semibold) : .headline)
                    .foregroundColor(bill.isPaid ? .green : .primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            
            dueDateCaption
        }
    }
    
    @ViewBuilder
    private var dueDateCaption: some View {
        if let dueDate = bill.dueDate {
            if !bill.isPaid, daysUntilDue < 0 {
                Text("\(abs(daysUntilDue))d overdue")
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundColor(.red)
            } else if !bill.isPaid, daysUntilDue <= 3 {
                Text("\(daysUntilDue)d left")
                    .font(compact ? .caption2 : .caption)
                    .foregroundColor(.orange)
            } else {
                Text(dateFormatter.string(from: dueDate))
                    .font(compact ? .caption2 : .caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var statusColor: Color {
        if bill.isPaid {
            return .green
        } else if isOverdue {
            return .red
        } else if daysUntilDue <= 3 {
            return .orange
        } else {
            return .blue
        }
    }
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
    
    private func formatRecurrenceType(_ type: String, interval: Int) -> String {
        switch type {
        case "none":
            return ""
        case "daily":
            return interval == 1 ? "Daily" : "Every \(interval) days"
        case "weekly":
            return interval == 1 ? "Weekly" : "Every \(interval) weeks"
        case "biweekly":
            return "Bi-weekly"
        case "monthly":
            return interval == 1 ? "Monthly" : "Every \(interval) months"
        case "bimonthly":
            return "Bi-monthly"
        case "quarterly":
            return interval == 1 ? "Quarterly" : "Every \(interval) quarters"
        case "semiannually":
            return "Semi-annually"
        case "yearly":
            return interval == 1 ? "Yearly" : "Every \(interval) years"
        default:
            return type.capitalized
        }
    }
}

#Preview {
    let controller = PersistenceController.preview
    let notif = NotificationManager()
    let accountVM = AccountViewModel(context: controller.container.viewContext)
    let billVM = BillViewModel(context: controller.container.viewContext,
                               notificationManager: notif,
                               accountViewModel: accountVM)
    BillListView()
        .environmentObject(billVM)
        .environmentObject(accountVM)
        .environmentObject(notif)
}
