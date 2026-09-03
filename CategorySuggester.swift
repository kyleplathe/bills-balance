//
//  CategorySuggester.swift
//  BillsAndBalance
//
//  History first, then keyword matches. Never creates a new category.
//

import Foundation

enum CategorySuggester {
    /// Suggests an existing category for a bill or transaction title.
    /// `priorCategory` is the user's last category for this title, if any.
    static func suggest(for text: String, priorCategory: String? = nil) -> String {
        if let prior = priorCategory?.trimmingCharacters(in: .whitespacesAndNewlines), !prior.isEmpty {
            return prior
        }
        return keywordSuggest(for: text)
    }

    private static func keywordSuggest(for text: String) -> String {
        let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return "" }

        // Strong merchant / phrase matches first (order among these still matters).
        if matches(lowercased, [
            "rent", "mortgage", "apartment", "housing", "hoa", "homeowner"
        ]) { return "Housing" }

        if matches(lowercased, [
            "uber", "lyft", "taxi", "parking", "metro", "transit",
            "chevron", "shell", "exxon", "fuel", "gas station"
        ]) { return "Transportation" }

        if matches(lowercased, [
            "electric", "power", "water", "sewer", "trash", "garbage",
            "utility", "internet", "wifi", "cable", "cellular",
            "at&t", "verizon", "t-mobile", "comcast", "xfinity",
            "spectrum", "cox", "natural gas"
        ]) { return "Utilities" }

        if matches(lowercased, [
            "restaurant", "dining", "grocery", "supermarket", "kroger",
            "safeway", "whole foods", "trader joe", "doordash", "ubereats",
            "grubhub", "instacart", "starbucks", "coffee", "mcdonald", "pizza"
        ]) { return "Food & Dining" }

        if matches(lowercased, [
            "doctor", "medical", "hospital", "clinic", "pharmacy", "pharmacist",
            "dentist", "dental", "optometrist", "cvs", "walgreens", "rite aid",
            "prescription", "medication"
        ]) { return "Healthcare" }

        if matches(lowercased, [
            "insurance", "geico", "state farm", "allstate", "progressive",
            "nationwide", "farmers", "usaa", "aetna", "blue cross",
            "cigna", "unitedhealth", "humana", "kaiser"
        ]) { return "Insurance" }

        if matches(lowercased, [
            "netflix", "hulu", "disney+", "spotify", "pandora", "youtube premium",
            "apple music", "apple tv", "apple one", "amazon prime", "amazon music",
            "adobe", "dropbox", "icloud", "youtube"
        ]) { return "Subscriptions" }

        if matches(lowercased, [
            "hbo", "paramount", "peacock", "movie", "theater", "cinema",
            "playstation", "xbox", "nintendo", "steam", "entertainment", "streaming"
        ]) { return "Entertainment" }

        if matches(lowercased, [
            "school", "university", "college", "tuition", "education",
            "textbook", "learning"
        ]) { return "Education" }

        if matches(lowercased, [
            "salon", "barber", "spa", "massage", "grooming", "personal care",
            "cosmetic", "beauty"
        ]) { return "Personal Care" }

        if matches(lowercased, [
            "credit card", "creditcard", "loan", "debt",
            "capital one", "amex", "american express", "discover"
        ]) { return "Debt Payment" }

        if matches(lowercased, [
            "hotel", "airline", "flight", "airport", "travel", "vacation",
            "expedia", "booking.com", "airbnb", "rental car"
        ]) { return "Travel" }

        if matches(lowercased, [
            "amazon", "ebay", "walmart", "target", "costco"
        ]) { return "Shopping" }

        if matches(lowercased, ["business", "corporate"]) { return "Business" }

        return ""
    }

    private static func matches(_ text: String, _ tokens: [String]) -> Bool {
        tokens.contains { text.contains($0) }
    }
}
