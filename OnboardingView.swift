//
//  OnboardingView.swift
//  BillsAndBalance
//
//  Created on 11/6/24.
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var onboardingManager = OnboardingManager.shared
    @EnvironmentObject private var notificationManager: NotificationManager
    @State private var currentPage = 0
    @Environment(\.dismiss) private var dismiss
    
    let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "calendar.badge.clock",
            title: "Never Miss a Bill",
            description: "Keep track of all your bills in one place. Get reminders before they're due.",
            color: .blue
        ),
        OnboardingPage(
            icon: "bell.badge.fill",
            title: "Smart Notifications",
            description: "Receive timely reminders so you never miss a payment deadline.",
            color: .orange
        ),
        OnboardingPage(
            icon: "repeat.circle.fill",
            title: "Recurring Bills",
            description: "Set up recurring bills once and let the app handle the rest automatically.",
            color: .green
        ),
        OnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            title: "Track Your Spending",
            description: "See your monthly bills at a glance and stay on top of your finances.",
            color: .purple
        )
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    pages[currentPage].color.opacity(0.3),
                    pages[currentPage].color.opacity(0.1)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)
            
            VStack(spacing: 0) {
                // Skip button
                HStack {
                    Spacer()
                    if currentPage < pages.count - 1 {
                        Button(action: {
                            completeOnboarding()
                        }) {
                            Text("Skip")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                }
                
                Spacer()
                
                // Content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                
                Spacer()
                
                // Bottom buttons
                VStack(spacing: 16) {
                    if currentPage == pages.count - 1 {
                        // On last page - show Get Started button
                        Button(action: {
                            completeOnboarding()
                        }) {
                            Text("Get Started")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(pages[currentPage].color)
                                .cornerRadius(16)
                        }
                        .padding(.horizontal, 32)
                    } else {
                        // On other pages - show Next button
                        Button(action: {
                            withAnimation {
                                currentPage += 1
                            }
                            HapticManager.shared.buttonTapped()
                        }) {
                            Text("Next")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(pages[currentPage].color)
                                .cornerRadius(16)
                        }
                        .padding(.horizontal, 32)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
    
    private func completeOnboarding() {
        // Request notification permissions before completing
        notificationManager.requestAuthorization()
        onboardingManager.hasRequestedNotifications = true
        
        HapticManager.shared.buttonTapped()
        onboardingManager.completeOnboarding()
    }
}

// MARK: - Onboarding Page Model
struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let color: Color
}

// MARK: - Onboarding Page View
struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 30) {
            // Icon
            ZStack {
                Circle()
                    .fill(page.color.opacity(0.2))
                    .frame(width: 160, height: 160)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .opacity(isAnimating ? 0.5 : 1.0)
                
                Image(systemName: page.icon)
                    .font(.system(size: 70))
                    .foregroundColor(page.color)
                    .scaleEffect(isAnimating ? 1.0 : 0.9)
            }
            
            // Title
            Text(page.title)
                .font(.system(size: 28, weight: .bold))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Description
            Text(page.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .lineSpacing(4)
        }
        .padding()
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(NotificationManager())
}

