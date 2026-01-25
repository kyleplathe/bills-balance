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
    
    @State private var selectedBill: Bill?
    
    var body: some View {
        NavigationStack {
            Form {
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
                            .font(.title2)
                    }
                }
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
            Text("Tap a bill to edit it. This view shows all bills, including those that may not appear in the main bills list.")
                .font(.footnote)
        }
    }
}

