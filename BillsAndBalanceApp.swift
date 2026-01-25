//
//  BillsAndBalanceApp.swift
//  BillsAndBalance
//
//  Created on 11/4/24.
//

import SwiftUI

@main
struct BillsAndBalanceApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var billViewModel: BillViewModel
    @StateObject private var accountViewModel: AccountViewModel
    @StateObject private var notificationManager: NotificationManager
    @StateObject private var paycheckViewModel: PaycheckViewModel
    @StateObject private var creditCardManager = CreditCardManager()
    @StateObject private var categoryManager = CategoryManager()
    @StateObject private var bitcoinPriceService = BitcoinPriceService.shared
    @StateObject private var onboardingManager = OnboardingManager.shared
    @StateObject private var reportsViewModel: ReportsViewModel
    @State private var showSplash = true
    
    init() {
        let context = PersistenceController.shared.container.viewContext
        let notifManager = NotificationManager()
        let accountVM = AccountViewModel(context: context)
        let billVM = BillViewModel(context: context, notificationManager: notifManager, accountViewModel: accountVM)
        let paycheckVM = PaycheckViewModel(context: context, accountViewModel: accountVM)
        _notificationManager = StateObject(wrappedValue: notifManager)
        _accountViewModel = StateObject(wrappedValue: accountVM)
        _billViewModel = StateObject(wrappedValue: billVM)
        _paycheckViewModel = StateObject(wrappedValue: paycheckVM)
        _reportsViewModel = StateObject(wrappedValue: ReportsViewModel(context: context, bitcoinPriceService: BitcoinPriceService.shared))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if onboardingManager.hasCompletedOnboarding {
                    MainTabView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(billViewModel)
                        .environmentObject(accountViewModel)
                        .environmentObject(paycheckViewModel)
                        .environmentObject(notificationManager)
                        .environmentObject(creditCardManager)
                        .environmentObject(categoryManager)
                        .environmentObject(bitcoinPriceService)
                        .environmentObject(reportsViewModel)
                        .preferredColorScheme(nil) // Allow dynamic sizing
                        .onAppear {
                            // Update badge count on app launch
                            billViewModel.updateAppBadge()
                        }
                } else {
                    OnboardingView()
                        .environmentObject(notificationManager)
                }
                
                // Only show splash screen if onboarding is already completed
                if showSplash && onboardingManager.hasCompletedOnboarding {
                    SplashScreenView(isActive: $showSplash)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
    }
}

