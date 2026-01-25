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
}

