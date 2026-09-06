//
//  NotificationManager.swift
//  BillsAndBalance
//
//  Created on 11/5/24.
//

import Foundation
import UserNotifications
import CoreData

enum NotificationSchedule {
    static func reminderDate(
        dueDate: Date,
        autoPay: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: dueDate)
        components.hour = 9
        components.minute = 0
        guard let morningOfDueDate = calendar.date(from: components) else { return nil }

        let triggerDate = autoPay
            ? morningOfDueDate
            : calendar.date(byAdding: .day, value: -1, to: morningOfDueDate)

        guard let triggerDate, triggerDate > now else { return nil }
        return triggerDate
    }
}

class NotificationManager: ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    init() {
        refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
            }
        }
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else {
                DispatchQueue.main.async {
                    self.authorizationStatus = settings.authorizationStatus
                }
                return
            }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                #if DEBUG
                if let error {
                    print("Notification permission error: \(error.localizedDescription)")
                } else if granted {
                    print("Notification permission granted")
                }
                #endif
                self.refreshAuthorizationStatus()
            }
        }
    }

    func scheduleNotification(for bill: Bill) {
        guard let dueDate = bill.dueDate,
              let billName = bill.name,
              let billId = bill.id else { return }
        let autoPay = bill.autoPay

        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                    DispatchQueue.main.async {
                        self.authorizationStatus = granted ? .authorized : .denied
                    }
                    if granted {
                        self.enqueueReminder(billId: billId, billName: billName, dueDate: dueDate, autoPay: autoPay)
                    }
                }
            case .authorized, .provisional, .ephemeral:
                self.enqueueReminder(billId: billId, billName: billName, dueDate: dueDate, autoPay: autoPay)
            default:
                break
            }
        }
    }

    private func enqueueReminder(billId: UUID, billName: String, dueDate: Date, autoPay: Bool) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [billId.uuidString])

        guard let triggerDate = NotificationSchedule.reminderDate(dueDate: dueDate, autoPay: autoPay) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.sound = .default
        content.badge = 1
        if autoPay {
            content.title = "Auto-Pay Reminder"
            content.body = "\(billName) will be paid today."
        } else {
            content.title = "Bill Due Soon"
            content.body = "\(billName) is due on \(formatDate(dueDate))"
        }

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: billId.uuidString, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            #if DEBUG
            if let error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
            #endif
        }
    }

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
            #if DEBUG
            if let error {
                print("Error delivering auto-pay notification: \(error.localizedDescription)")
            }
            #endif
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
