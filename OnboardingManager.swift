//
//  OnboardingManager.swift
//  BillsAndBalance
//
//  Created on 11/6/24.
//

import Foundation
import SwiftUI

class OnboardingManager: ObservableObject {
    @AppStorage("hasCompletedOnboarding") var hasCompletedOnboarding: Bool = false
    @AppStorage("hasRequestedNotifications") var hasRequestedNotifications: Bool = false
    @AppStorage("defaultDigitalWalletCurrency") var defaultDigitalWalletCurrency: String = "USD"
    
    static let shared = OnboardingManager()
    
    private init() {}
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        HapticManager.shared.buttonTapped()
    }
    
    func resetOnboarding() {
        hasCompletedOnboarding = false
        hasRequestedNotifications = false
    }
}



