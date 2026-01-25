//
//  YearWrapPopupView.swift
//  BillsAndBalance
//
//  End-of-year “Your 20XX Wrap” popup — highlights, celebration, dismiss.
//

import SwiftUI

struct YearWrapPopupView: View {
    let year: Int
    let data: YearWrapData?
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    private let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let d = data {
                        Text("Your \(year) Wrap")
                            .font(.title.weight(.bold))
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 10)

                        Text("A quick look back at your year")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .opacity(appeared ? 1 : 0)

                        VStack(spacing: 16) {
                            wrapRow("Income", value: d.income, icon: "arrow.down.circle.fill", color: .green)
                            wrapRow("Expenses", value: d.expenses, icon: "arrow.up.circle.fill", color: .red)
                            if d.digitalWalletFees > 0 {
                                wrapRow("Digital Wallet Fees", value: d.digitalWalletFees, icon: "bitcoinsign.circle.fill", color: .orange)
                            }
                            if let rate = d.savingsRate, rate >= 0 {
                                HStack {
                                    Image(systemName: "percent")
                                        .foregroundStyle(.blue)
                                    Text("Savings rate")
                                    Spacer()
                                    Text("\((rate as NSDecimalNumber).doubleValue * 100, specifier: "%.1f")%")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.blue)
                                }
                                .padding()
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                                .opacity(appeared ? 1 : 0)
                                .offset(x: appeared ? 0 : -20)
                            }
                        }
                        .padding(.horizontal)

                        if !d.byCategory.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Top categories")
                                    .font(.headline)
                                ForEach(Array(d.byCategory.prefix(5).enumerated()), id: \.offset) { _, item in
                                    HStack {
                                        Text(item.name)
                                        Spacer()
                                        Text(formatter.string(from: item.amount as NSDecimalNumber) ?? "$0")
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                            .padding(.horizontal)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 12)
                        }

                        Text("Here’s to \(year + 1)!")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.top, 8)
                            .opacity(appeared ? 1 : 0)
                    } else {
                        ProgressView("Loading your year…")
                            .padding(.top, 48)
                    }
                }
                .padding(.vertical, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onDismiss()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    appeared = true
                }
            }
        }
    }

    private func wrapRow(_ label: String, value: Decimal, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .font(.title3)
            Text(label)
            Spacer()
            Text(formatter.string(from: value as NSDecimalNumber) ?? "$0")
                .fontWeight(.semibold)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -20)
    }
}
