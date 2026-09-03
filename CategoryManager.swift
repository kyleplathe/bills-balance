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
    static let defaultCategories = ["Housing", "Utilities", "Food & Dining", "Transportation", "Healthcare", "Insurance", "Entertainment", "Shopping", "Personal Care", "Education", "Subscriptions", "Debt Payment", "Savings", "Investments", "Gifts & Donations", "Travel", "Business", "Other"]
    private var defaultCategories: [String] { Self.defaultCategories }
    
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
    
    /// Adds a custom category, or returns the canonical name if it already exists.
    @discardableResult
    func addCategory(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = resolvedName(for: trimmed) {
            return existing
        }
        customCategories.append(trimmed)
        return trimmed
    }

    /// Canonical default/custom name when `raw` matches case-insensitively.
    func resolvedName(for raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let match = Self.defaultCategories.first(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return match
        }
        return customCategories.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }
    
    func removeCategory(_ category: String) {
        customCategories.removeAll { $0.caseInsensitiveCompare(category) == .orderedSame }
    }
    
    func removeCategories(at offsets: IndexSet) {
        customCategories.remove(atOffsets: offsets)
    }
    
    /// Removes custom categories that haven't been used in the last 60 days.
    /// Default categories are never removed.
    /// - Parameter usage: Category usage data from AccountViewModel.categoryUsage()
    func cleanupUnusedCategories(usage: [String: CategoryUsage]) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        
        customCategories.removeAll { category in
            // Never remove if it's a default category
            if defaultCategories.contains(where: { $0.caseInsensitiveCompare(category) == .orderedSame }) {
                return false
            }
            
            // If never used, keep it (might be newly added)
            guard let u = usage[category] else {
                return false
            }
            
            // Remove if last used more than 60 days ago
            return u.lastUsed < cutoff
        }
    }
    
    private func save() {
        UserDefaults.standard.set(customCategories, forKey: storageKey)
    }
}

