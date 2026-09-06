import Foundation
import LocalAuthentication
import SwiftUI

@MainActor
final class AppLockManager: ObservableObject {
    static let shared = AppLockManager()
    private static let requireFaceIDKey = "requireFaceID"

    @Published var requireFaceID: Bool
    @Published var isUnlocked: Bool

    private init() {
        let enabled = UserDefaults.standard.bool(forKey: Self.requireFaceIDKey)
        requireFaceID = enabled
        isUnlocked = !enabled
    }

    func lockIfNeeded() {
        guard requireFaceID else {
            isUnlocked = true
            return
        }
        isUnlocked = false
    }

    func setRequireFaceID(_ enabled: Bool) async -> String? {
        if enabled {
            do {
                try await authenticate(reason: "Enable Face ID to lock Bills & Balance")
                requireFaceID = true
                UserDefaults.standard.set(true, forKey: Self.requireFaceIDKey)
                isUnlocked = true
                return nil
            } catch {
                return error.localizedDescription
            }
        } else {
            requireFaceID = false
            UserDefaults.standard.set(false, forKey: Self.requireFaceIDKey)
            isUnlocked = true
            return nil
        }
    }

    func unlock() async {
        guard requireFaceID, !isUnlocked else {
            isUnlocked = true
            return
        }
        do {
            try await authenticate(reason: "Unlock Bills & Balance")
            isUnlocked = true
        } catch {
            isUnlocked = false
        }
    }

    private func authenticate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? LAError(.biometryNotAvailable)
        }
        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}

struct AppLockOverlay: View {
    @EnvironmentObject private var appLockManager: AppLockManager

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Bills & Balance is Locked")
                    .font(.title3.weight(.semibold))
                Button {
                    Task { await appLockManager.unlock() }
                } label: {
                    Label("Unlock", systemImage: "faceid")
                        .font(.headline)
                        .frame(maxWidth: 220)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task {
            await appLockManager.unlock()
        }
    }
}
