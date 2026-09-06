import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    policySection("Your data stays on this device") {
                        "Bills & Balance is a local-first checkbook. Accounts, bills, income, and transactions are stored on your iPhone or iPad using Core Data. There is no account to create, and we do not operate a server that receives your ledger."
                    }
                    policySection("Backup") {
                        "Export Backup writes a file you choose to save in Files, iCloud Drive, or another app. Nothing is uploaded unless you share that file."
                    }
                    policySection("Lock") {
                        "Optional Face ID or device passcode lock keeps the app closed until you unlock it. That preference stays on this device. We never see your biometrics."
                    }
                    policySection("Notifications") {
                        "Bill reminders use Apple’s notification system on this device. Permission is optional. Skip during onboarding if you do not want the prompt yet; you can enable reminders later in Manage Bills."
                    }
                    policySection("Bitcoin prices") {
                        "If you add a digital wallet set to Bitcoin, the app may fetch public market prices from CoinGecko. That request does not include your balances, bills, or identity. Bitcoin features stay hidden until you opt in."
                    }
                    policySection("What we do not collect") {
                        "We do not collect contact info, financial info, location, or analytics for our own servers. We do not sell data. We do not use tracking."
                    }
                    policySection("Contact") {
                        "Questions: open a support issue from Manage Accounts."
                    }
                    Text("Last updated September 6, 2026")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("Privacy Policy")
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
                    .accessibilityLabel("Close")
                }
            }
        }
    }

    private func policySection(_ title: String, text: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text())
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}
