//
//  CategorySuggester.swift
//  BillsAndBalance
//
//  Shared keyword-based category suggestion for bills and transactions.
//

import Foundation

enum CategorySuggester {
    /// Suggests a category based on keyword matches in the given text (e.g. bill name, transaction title).
    /// Returns a default category name or "" if no match.
    static func suggest(for text: String) -> String {
        let lowercased = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercased.isEmpty else { return "" }
        
        // Housing
        if lowercased.contains("rent") || lowercased.contains("mortgage") ||
           lowercased.contains("apartment") || lowercased.contains("housing") ||
           lowercased.contains("hoa") || lowercased.contains("homeowner") {
            return "Housing"
        }
        
        // Utilities
        if lowercased.contains("electric") || lowercased.contains("power") ||
           lowercased.contains("gas") || lowercased.contains("water") ||
           lowercased.contains("sewer") || lowercased.contains("trash") ||
           lowercased.contains("garbage") || lowercased.contains("utility") ||
           lowercased.contains("internet") || lowercased.contains("wifi") ||
           lowercased.contains("cable") || lowercased.contains("phone") ||
           lowercased.contains("cellular") || lowercased.contains("mobile") ||
           lowercased.contains("at&t") || lowercased.contains("verizon") ||
           lowercased.contains("t-mobile") || lowercased.contains("sprint") ||
           lowercased.contains("comcast") || lowercased.contains("xfinity") ||
           lowercased.contains("spectrum") || lowercased.contains("cox") {
            return "Utilities"
        }
        
        // Food & Dining
        if lowercased.contains("restaurant") || lowercased.contains("food") ||
           lowercased.contains("dining") || lowercased.contains("grocery") ||
           lowercased.contains("supermarket") || lowercased.contains("walmart") ||
           lowercased.contains("target") || lowercased.contains("kroger") ||
           lowercased.contains("safeway") || lowercased.contains("whole foods") ||
           lowercased.contains("trader joe") || lowercased.contains("costco") ||
           lowercased.contains("doordash") || lowercased.contains("ubereats") ||
           lowercased.contains("grubhub") || lowercased.contains("instacart") ||
           lowercased.contains("starbucks") || lowercased.contains("coffee") ||
           lowercased.contains("mcdonald") || lowercased.contains("pizza") {
            return "Food & Dining"
        }
        
        // Transportation
        if lowercased.contains("gas") || lowercased.contains("fuel") ||
           lowercased.contains("uber") || lowercased.contains("lyft") ||
           lowercased.contains("taxi") || lowercased.contains("parking") ||
           lowercased.contains("metro") || lowercased.contains("transit") ||
           lowercased.contains("bus") || lowercased.contains("train") ||
           lowercased.contains("car") || lowercased.contains("vehicle") ||
           lowercased.contains("auto") || lowercased.contains("tesla") ||
           lowercased.contains("chevron") || lowercased.contains("shell") ||
           lowercased.contains("bp") || lowercased.contains("exxon") {
            return "Transportation"
        }
        
        // Healthcare
        if lowercased.contains("doctor") || lowercased.contains("medical") ||
           lowercased.contains("hospital") || lowercased.contains("clinic") ||
           lowercased.contains("pharmacy") || lowercased.contains("pharmacist") ||
           lowercased.contains("dentist") || lowercased.contains("dental") ||
           lowercased.contains("vision") || lowercased.contains("eye") ||
           lowercased.contains("optometrist") || lowercased.contains("cvs") ||
           lowercased.contains("walgreens") || lowercased.contains("rite aid") ||
           lowercased.contains("health") || lowercased.contains("therapy") ||
           lowercased.contains("prescription") || lowercased.contains("medication") {
            return "Healthcare"
        }
        
        // Insurance
        if lowercased.contains("insurance") || lowercased.contains("geico") ||
           lowercased.contains("state farm") || lowercased.contains("allstate") ||
           lowercased.contains("progressive") || lowercased.contains("nationwide") ||
           lowercased.contains("farmers") || lowercased.contains("usaa") ||
           lowercased.contains("aetna") || lowercased.contains("blue cross") ||
           lowercased.contains("cigna") || lowercased.contains("unitedhealth") ||
           lowercased.contains("humana") || lowercased.contains("kaiser") {
            return "Insurance"
        }
        
        // Subscriptions (before Entertainment)
        if lowercased.contains("subscription") || lowercased.contains("subscribe") ||
           lowercased.contains("monthly") || lowercased.contains("annual") ||
           lowercased.contains("yearly") || lowercased.contains("membership") ||
           lowercased.contains("prime") || lowercased.contains("amazon prime") ||
           lowercased.contains("costco") || lowercased.contains("sam's club") ||
           lowercased.contains("gym") || lowercased.contains("fitness") ||
           lowercased.contains("youtube") || lowercased.contains("youtube premium") ||
           lowercased.contains("adobe") || lowercased.contains("microsoft") ||
           lowercased.contains("office") || lowercased.contains("dropbox") ||
           lowercased.contains("icloud") || lowercased.contains("google") ||
           lowercased.contains("apple music") || lowercased.contains("apple tv") ||
           lowercased.contains("apple one") || lowercased.contains("netflix") ||
           lowercased.contains("hulu") || lowercased.contains("disney+") ||
           lowercased.contains("spotify") || lowercased.contains("pandora") ||
           lowercased.contains("amazon music") || lowercased.contains("apple") {
            return "Subscriptions"
        }
        
        // Entertainment
        if lowercased.contains("hbo") || lowercased.contains("paramount") ||
           lowercased.contains("peacock") || lowercased.contains("music") ||
           lowercased.contains("movie") || lowercased.contains("theater") ||
           lowercased.contains("cinema") || lowercased.contains("game") ||
           lowercased.contains("playstation") || lowercased.contains("xbox") ||
           lowercased.contains("nintendo") || lowercased.contains("steam") ||
           lowercased.contains("entertainment") || lowercased.contains("streaming") ||
           lowercased.contains("disney") {
            return "Entertainment"
        }
        
        // Education
        if lowercased.contains("school") || lowercased.contains("university") ||
           lowercased.contains("college") || lowercased.contains("tuition") ||
           lowercased.contains("student") || lowercased.contains("education") ||
           lowercased.contains("course") || lowercased.contains("class") ||
           lowercased.contains("textbook") || lowercased.contains("learning") {
            return "Education"
        }
        
        // Personal Care
        if lowercased.contains("hair") || lowercased.contains("salon") ||
           lowercased.contains("barber") || lowercased.contains("spa") ||
           lowercased.contains("massage") || lowercased.contains("nail") ||
           lowercased.contains("grooming") || lowercased.contains("personal care") ||
           lowercased.contains("cosmetic") || lowercased.contains("beauty") {
            return "Personal Care"
        }
        
        // Debt Payment
        if lowercased.contains("credit card") || lowercased.contains("creditcard") ||
           lowercased.contains("loan") || lowercased.contains("debt") ||
           lowercased.contains("payment") || lowercased.contains("chase") ||
           lowercased.contains("capital one") || lowercased.contains("amex") ||
           lowercased.contains("american express") || lowercased.contains("discover") ||
           lowercased.contains("citi") || lowercased.contains("bank of america") ||
           lowercased.contains("paypal") || lowercased.contains("venmo") {
            return "Debt Payment"
        }
        
        // Travel
        if lowercased.contains("hotel") || lowercased.contains("airline") ||
           lowercased.contains("flight") || lowercased.contains("airport") ||
           lowercased.contains("travel") || lowercased.contains("trip") ||
           lowercased.contains("vacation") || lowercased.contains("booking") ||
           lowercased.contains("expedia") || lowercased.contains("booking.com") ||
           lowercased.contains("airbnb") || lowercased.contains("uber") ||
           lowercased.contains("lyft") || lowercased.contains("rental car") {
            return "Travel"
        }
        
        // Business
        if lowercased.contains("business") || lowercased.contains("office") ||
           lowercased.contains("professional") || lowercased.contains("work") ||
           lowercased.contains("corporate") || lowercased.contains("company") {
            return "Business"
        }
        
        // Shopping
        if lowercased.contains("amazon") || lowercased.contains("ebay") ||
           lowercased.contains("shop") || lowercased.contains("store") ||
           lowercased.contains("retail") || lowercased.contains("purchase") ||
           lowercased.contains("buy") || lowercased.contains("mall") {
            return "Shopping"
        }
        
        return ""
    }
}
