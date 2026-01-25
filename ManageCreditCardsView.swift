//
//  ManageCreditCardsView.swift
//  BillsAndBalance
//
//  Created on 11/8/25.
//

import SwiftUI

struct ManageCreditCardsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var cardManager: CreditCardManager
    
    @State private var newCardName: String = ""
    @State private var editingCard: String?
    @State private var editedName: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Credit Cards") {
                    if cardManager.cards.isEmpty {
                        Text("Add your credit cards so you can tag bills with the card you used.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    
                    ForEach(cardManager.cards, id: \.self) { card in
                        if editingCard == card {
                            HStack {
                                TextField("Card name", text: $editedName)
                                    .textInputAutocapitalization(.words)
                                    .autocorrectionDisabled()
                                
                                Button("Save") {
                                    cardManager.renameCard(from: card, to: editedName)
                                    editingCard = nil
                                }
                                .disabled(editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                
                                Button("Cancel", role: .cancel) {
                                    editingCard = nil
                                }
                            }
                        } else {
                            HStack {
                                Text(card)
                                Spacer()
                                Button {
                                    editingCard = card
                                    editedName = card
                                } label: {
                                    Image(systemName: "pencil")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                    .onDelete(perform: cardManager.removeCards)
                }
                
                Section("Add Card") {
                    HStack {
                        TextField("Card name", text: $newCardName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        Button("Add") {
                            addCard()
                        }
                        .disabled(newCardName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("Credit Cards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
    }
    
    private func addCard() {
        cardManager.addCard(newCardName)
        newCardName = ""
    }
}

#Preview {
    ManageCreditCardsView()
        .environmentObject(CreditCardManager())
}

