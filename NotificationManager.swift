//
//  NotificationManager.swift
//  BillsAndBalance
//
//  Created on 11/5/24.
//

import Foundation
import UserNotifications
import CoreData

class NotificationManager: ObservableObject {
    
    init() {
        requestAuthorization()
    }
    
    // MARK: - Request Authorization
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("Notification permission granted")
            } else if let error = error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Schedule Notification
    func scheduleNotification(for bill: Bill) {
        guard let dueDate = bill.dueDate,
              let billName = bill.name,
              let billId = bill.id else { return }
        
        let calendar = Calendar.current
        let now = Date()
        
        let content = UNMutableNotificationContent()
        content.sound = .default
        content.badge = 1
        
        cancelNotification(for: bill)
        
        var triggerDate: Date?
        
        if bill.autoPay {
            content.title = "Auto-Pay Reminder"
            content.body = "\(billName) will be paid today."
            
            var components = calendar.dateComponents([.year, .month, .day], from: dueDate)
            components.hour = 9
            components.minute = 0
            triggerDate = calendar.date(from: components)
        } else {
            content.title = "Bill Due Soon"
            content.body = "\(billName) is due on \(formatDate(dueDate))"
            
            var components = calendar.dateComponents([.year, .month, .day], from: dueDate)
            components.hour = 9
            components.minute = 0
            if let morningOfDueDate = calendar.date(from: components) {
                triggerDate = calendar.date(byAdding: .day, value: -1, to: morningOfDueDate)
            }
        }
        
        let trigger: UNNotificationTrigger
        if let date = triggerDate, date > now {
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        } else {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 60, repeats: false)
        }
        
        let request = UNNotificationRequest(identifier: billId.uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Cancel Notification
    func cancelNotification(for bill: Bill) {
        guard let billId = bill.id else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [billId.uuidString])
    }
    
    func deliverAutoPayNotification(for bill: Bill) {
        guard let billId = bill.id,
              let billName = bill.name else { return }
        
        let content = UNMutableNotificationContent()
        content.title = "Auto-Pay Processed"
        content.body = "\(billName) has been paid today."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: billId.uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error delivering auto-pay notification: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Helper
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

