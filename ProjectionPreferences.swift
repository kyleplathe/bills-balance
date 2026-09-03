import Foundation
import SwiftUI

/// Local projection window for available-balance. Stored in UserDefaults (no cloud prefs).
@MainActor
final class ProjectionPreferences: ObservableObject {
    static let shared = ProjectionPreferences()
    static let windowDaysKey = "projectionWindowDays"
    static let allowedWindows = [14, 30, 60, 90]

    @Published var windowDays: Int {
        didSet {
            UserDefaults.standard.set(windowDays, forKey: Self.windowDaysKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.integer(forKey: Self.windowDaysKey)
        windowDays = Self.allowedWindows.contains(stored) ? stored : 30
    }
}

struct ProjectionSettingsView: View {
    @ObservedObject var preferences: ProjectionPreferences = .shared

    var body: some View {
        Form {
            Section {
                Picker("Lookahead", selection: $preferences.windowDays) {
                    ForEach(ProjectionPreferences.allowedWindows, id: \.self) { days in
                        Text("\(days) days").tag(days)
                    }
                }
                .pickerStyle(.inline)
            } header: {
                Text("Available Balance")
            } footer: {
                Text("Available subtracts unpaid bills and adds expected income due within this window.")
            }
        }
        .navigationTitle("Projection Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
