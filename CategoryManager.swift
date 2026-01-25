//
//  CategoryManager.swift
//  BillsAndBalance
//
//  Created on 12/30/24.
//

import Foundation

/// Usage info for a category: (transaction count, most recent use date).
typealias CategoryUsage = (count: Int, lastUsed: Date)

@MainActor
class CategoryManager: ObservableObject {
    
    @Published private(set) var customCategories: [String] {
        didSet {
            save()
        }
    }
    
    private let storageKey = "customCategories"
    private let defaultCategories = ["Housing", "Utilities", "Food & Dining", "Transportation", "Healthcare", "Insurance", "Entertainment", "Shopping", "Personal Care", "Education", "Subscriptions", "Debt Payment", "Savings", "Investments", "Gifts & Donations", "Travel", "Business", "Other"]
    
    /// All categories (defaults + custom), unsorted.
    var allCategories: [String] {
        return defaultCategories + customCategories
    }
    
    /// Categories to display: sorted by usage (most used first), hide unused 60+ days.
    /// - Parameters:
    ///   - usage: From `AccountViewModel.categoryUsage()` (LedgerEntry-derived).
    ///   - selected: Always include this category even if it would be filtered (e.g. unused 60+ days).
    func displayCategories(usage: [String: CategoryUsage], selected: String = "") -> [String] {
        let all = allCategories
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        
        var filtered = all.filter { cat in
            guard let u = usage[cat] else { return true }  // never used → keep
            return u.lastUsed >= cutoff  // used within 60 days → keep
        }
        if !selected.isEmpty, !filtered.contains(selected) {
            filtered.append(selected)
        }
        return filtered.sorted { a, b in
            let ua = usage[a] ?? (0, .distantPast)
            let ub = usage[b] ?? (0, .distantPast)
            if ua.count != ub.count { return ua.count > ub.count }
            return ua.lastUsed > ub.lastUsed
        }
    }
    
    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            customCategories = saved
        } else {
            customCategories = []
        }
    }
    
    func addCategory(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !defaultCategories.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        guard !customCategories.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        customCategories.append(trimmed)
    }
    
    func removeCategory(_ category: String) {
        customCategories.removeAll { $0.caseInsensitiveCompare(category) == .orderedSame }
    }
    
    func removeCategories(at offsets: IndexSet) {
        customCategories.remove(atOffsets: offsets)
    }
    
    private func save() {
        UserDefaults.standard.set(customCategories, forKey: storageKey)
    }
}

