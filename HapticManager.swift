//
//  HapticManager.swift
//  BillsAndBalance
//
//  Created on 11/5/24.
//

import Foundation
import UIKit
import AudioToolbox

class HapticManager: ObservableObject {
    static let shared = HapticManager()
    
    private init() {}
    
    // MARK: - Haptic Feedback Methods
    func buttonTapped() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    func longPressDetected() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }
    
    func billMarkedPaid() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    func billDeleted() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    func errorOccurred() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
    
    func success() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        // Play system sound for success
        AudioServicesPlaySystemSound(1057) // System sound for success
    }

    /// Extra flourish when every bill for the month is paid.
    func allBillsPaid() {
        AudioServicesPlaySystemSound(1057)

        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        let medium = UIImpactFeedbackGenerator(style: .medium)
        let light = UIImpactFeedbackGenerator(style: .light)
        heavy.prepare()
        medium.prepare()
        light.prepare()

        heavy.impactOccurred(intensity: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            medium.impactOccurred(intensity: 0.92)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            light.impactOccurred(intensity: 0.7)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            light.impactOccurred(intensity: 0.4)
        }
    }
}

