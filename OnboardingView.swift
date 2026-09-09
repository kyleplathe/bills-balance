import SwiftUI

struct OnboardingView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @EnvironmentObject private var notificationManager: NotificationManager
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            systemImage: nil,
            title: "Bills & Balance",
            description: "A local-first checkbook. Track bills, accounts, and what you can actually spend — without creating an account."
        ),
        OnboardingPage(
            systemImage: "calendar.badge.clock",
            title: "Never miss a bill",
            description: "See what’s due and get reminders before payment day."
        ),
        OnboardingPage(
            systemImage: "repeat",
            title: "Set it once",
            description: "Recurring bills and income stay on the calendar automatically."
        ),
        OnboardingPage(
            systemImage: "building.columns",
            title: "Know what’s left",
            description: "Cleared and available balance across every account, in one place."
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        completeOnboarding(loadSampleData: false, requestNotifications: false)
                    }
                    .font(.body)
                    .foregroundStyle(Brand.wordmark.opacity(0.7))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
            }
            .frame(height: 52)

            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(page: page, showsBrandMark: index == 0)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                if currentPage == pages.count - 1 {
                    Button {
                        completeOnboarding(loadSampleData: false, requestNotifications: true)
                    } label: {
                        Text("Start Empty")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Brand.action)

                    Button {
                        completeOnboarding(loadSampleData: true, requestNotifications: true)
                    } label: {
                        Text("Try Sample Data")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(Brand.action)
                } else {
                    Button {
                        withAnimation {
                            currentPage += 1
                        }
                        HapticManager.shared.buttonTapped()
                    } label: {
                        Text("Continue")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Brand.action)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .padding(.top, 8)
        }
        .background {
            Brand.splashBackground
                .ignoresSafeArea()
        }
    }

    private func completeOnboarding(loadSampleData: Bool, requestNotifications: Bool) {
        if requestNotifications {
            notificationManager.requestAuthorization()
            onboardingManager.hasRequestedNotifications = true
        }
        onboardingManager.shouldLoadSampleData = loadSampleData
        HapticManager.shared.buttonTapped()
        onboardingManager.completeOnboarding()
    }
}

private struct OnboardingPage {
    let systemImage: String?
    let title: String
    let description: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    var showsBrandMark: Bool

    var body: some View {
        VStack(spacing: 28) {
            if showsBrandMark {
                BrandLockup(markSize: 112, nameSize: 30, subtitle: page.description)
                    .padding(.horizontal, 32)
            } else {
                if let systemImage = page.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 40, weight: .medium))
                        .foregroundStyle(Brand.navy)
                        .frame(width: 96, height: 96)
                        .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                }

                VStack(spacing: 10) {
                    Text(page.title)
                        .font(.title2.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Brand.wordmark)

                    Text(page.description)
                        .font(.body)
                        .foregroundStyle(Brand.wordmark.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }
                .padding(.horizontal, 32)
            }
        }
        .padding(.bottom, 24)
    }
}

#Preview {
    OnboardingView()
        .environmentObject(NotificationManager())
}
