import SwiftUI

struct ProjectionSettingsView: View {
    let accountID: UUID?
    let supabaseManager: SupabaseManager

    @State private var selectedDays: Int = 7
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var accountName: String = "Account"

    private let dayOptions: [Int] = [3, 7, 14, 30]

    var body: some View {
        Form {
            Section("Projection Window") {
                Picker("Days", selection: $selectedDays) {
                    ForEach(dayOptions, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isLoading)

                Text("Used to project unpaid bills and calculate disposable balance.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Projection Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isLoading {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await savePreference() }
                    }
                }
            }
        }
        .task {
            await loadPreference()
        }
    }

    private func loadPreference() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let accounts = try await supabaseManager.fetchAccounts()
            guard let account = resolveAccount(from: accounts) else {
                errorMessage = "No account found."
                return
            }
            accountName = account.name
            selectedDays = dayOptions.contains(account.projectionDaysPref) ? account.projectionDaysPref : 7
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load settings for \(accountName): \(error.localizedDescription)"
        }
    }

    private func savePreference() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let accounts = try await supabaseManager.fetchAccounts()
            guard let account = resolveAccount(from: accounts) else {
                errorMessage = "No account found."
                return
            }
            _ = try await supabaseManager.updateProjectionPreference(accountID: account.id, days: selectedDays)
            accountName = account.name
            errorMessage = nil
        } catch {
            errorMessage = "Failed to save settings for \(accountName): \(error.localizedDescription)"
        }
    }

    private func resolveAccount(from accounts: [SupabaseAccount]) -> SupabaseAccount? {
        if let accountID {
            return accounts.first(where: { $0.id == accountID })
        }
        return accounts.first
    }
}

