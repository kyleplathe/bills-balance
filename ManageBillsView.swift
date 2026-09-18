//
//  ManageBillsView.swift
//  BillsAndBalance
//
//  Created on 1/2/25.
//

import SwiftUI
import CoreData

struct ManageBillsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var cardManager: CreditCardManager
    @EnvironmentObject private var categoryManager: CategoryManager
    @EnvironmentObject private var notificationManager: NotificationManager

    @State private var selectedBill: Bill?
    @State private var showingAddBill = false

    var body: some View {
        NavigationStack {
            Form {
                remindersSection
                billsSection
            }
            .navigationTitle("Manage Bills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddBill = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddBill) {
                AddEditBillView()
                    .environmentObject(billViewModel)
                    .environmentObject(accountViewModel)
                    .environmentObject(cardManager)
                    .environmentObject(categoryManager)
            }
            .sheet(item: $selectedBill) { bill in
                AddEditBillView(bill: bill)
                    .environmentObject(billViewModel)
                    .environmentObject(accountViewModel)
                    .environmentObject(cardManager)
                    .environmentObject(categoryManager)
            }
        }
    }

    private var remindersSection: some View {
        Section {
            if notificationManager.authorizationStatus == .authorized
                || notificationManager.authorizationStatus == .provisional {
                Label("Reminders are on", systemImage: "bell.fill")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    notificationManager.requestAuthorization()
                    OnboardingManager.shared.hasRequestedNotifications = true
                } label: {
                    Label("Enable Bill Reminders", systemImage: "bell.badge")
                }
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Get a reminder the day before a bill is due, or the morning of auto-pay. Auto-pay waits and you’ll get a warning if paying would leave the linked account below its reserve.")
                .font(.footnote)
        }
        .onAppear {
            notificationManager.refreshAuthorizationStatus()
        }
    }

    private var billsSection: some View {
        Section {
            if billViewModel.bills.isEmpty {
                Text("No bills added yet.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(billViewModel.bills, id: \.objectID) { bill in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bill.name ?? "Bill")
                                .font(.body)
                            if let amount = bill.amount {
                                Text(amount.decimalValue, format: .currency(code: "USD"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            selectedBill = bill
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                }
            }
        } header: {
            Text("All Bills (\(billViewModel.bills.count))")
        } footer: {
            Text("Tap a bill to edit it. Back up bills with Export Backup in Manage Accounts.")
                .font(.footnote)
        }
    }
}
