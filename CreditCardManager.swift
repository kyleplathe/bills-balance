//
//  CreditCardManager.swift
//  BillsAndBalance
//
//  Created on 11/8/25.
//

import Foundation

@MainActor
class CreditCardManager: ObservableObject {
    
    @Published private(set) var cards: [String] {
        didSet {
            save()
        }
    }
    
    private let storageKey = "creditCardNames"
    
    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: storageKey) {
            cards = saved
        } else {
            cards = []
        }
    }
    
    func addCard(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !cards.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        cards.append(trimmed)
        // Don't auto-sort - preserve order for manual reordering
    }
    
    func removeCards(at offsets: IndexSet) {
        cards.remove(atOffsets: offsets)
    }
    
    func renameCard(from oldName: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = cards.firstIndex(of: oldName) else { return }
        if cards.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            cards.remove(at: index)
        } else {
            cards[index] = trimmed
        }
        // Don't auto-sort when renaming - preserve order
    }
    
    func reorderCards(from source: IndexSet, to destination: Int) {
        cards.move(fromOffsets: source, toOffset: destination)
    }
    
    func reorderCards(draggedCard: String, targetCard: String) {
        guard let draggedIndex = cards.firstIndex(of: draggedCard),
              let targetIndex = cards.firstIndex(of: targetCard),
              draggedIndex != targetIndex else { return }
        
        let card = cards.remove(at: draggedIndex)
        cards.insert(card, at: targetIndex)
    }
    
    private func save() {
        UserDefaults.standard.set(cards, forKey: storageKey)
    }
}

