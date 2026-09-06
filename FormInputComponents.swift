//
//  FormInputComponents.swift
//  BillsAndBalance
//
//  Shared input primitives for add/edit sheets.
//

import SwiftUI
import UIKit

enum MoneyTone {
    case inflow
    case outflow
    case neutral

    var color: Color {
        switch self {
        case .inflow: return .green
        case .outflow: return .red
        case .neutral: return .primary
        }
    }
}

// MARK: - Amount header

struct MoneyAmountHeader: View {
    @Binding var text: String
    var kind: MoneyKind = .usd
    var tone: MoneyTone = .neutral
    var placeholder: String? = nil
    var accessibilityLabel: String = "Amount"
    var showsDirectionPicker: Bool = false
    var isCredit: Binding<Bool>? = nil
    var isFocused: FocusState<Bool>.Binding

    private var resolvedTone: MoneyTone {
        if showsDirectionPicker, let isCredit {
            return isCredit.wrappedValue ? .inflow : .outflow
        }
        return tone
    }

    var body: some View {
        VStack(spacing: 12) {
            amountRow
            if showsDirectionPicker, let isCredit {
                Picker("Type", selection: isCredit) {
                    Text("Add").tag(true)
                    Text("Subtract").tag(false)
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Transaction type")
            }
        }
        .onChange(of: isFocused.wrappedValue) { _, focused in
            if !focused {
                text = MoneyFormatting.formatForDisplay(text, kind: kind)
            }
        }
    }

    private var amountRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let prefix = kind.prefix {
                Text(prefix)
                    .font(.title.weight(.semibold))
                    .foregroundStyle(resolvedTone.color.opacity(0.7))
                    .accessibilityHidden(true)
            }
            TextField("", text: $text, prompt: Text(placeholder ?? kind.placeholder).foregroundStyle(.secondary))
                .keyboardType(kind.keyboard)
                .font(.system(.largeTitle, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(resolvedTone.color)
                .focused(isFocused)
                .accessibilityLabel(accessibilityLabel)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            if kind == .sats {
                Text("sats")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear amount")
            }
        }
    }
}

// MARK: - Secondary amount field

struct MoneyTextField: View {
    @Binding var text: String
    var kind: MoneyKind = .usd
    var placeholder: String = ""
    var accessibilityLabel: String = "Amount"
    var suffix: String? = nil
    var showsPrefix: Bool = true
    var textAlignment: TextAlignment = .leading
    var autoFocus: Bool = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            if showsPrefix, let prefix = kind.prefix {
                Text(prefix)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            TextField("", text: $text, prompt: Text(placeholder.isEmpty ? kind.placeholder : placeholder).foregroundStyle(.secondary))
                .keyboardType(kind.keyboard)
                .multilineTextAlignment(textAlignment == .trailing ? .trailing : .leading)
                .focused($isFocused)
                .accessibilityLabel(accessibilityLabel)
                .monospacedDigit()
            if let suffix {
                Text(suffix)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Clear \(accessibilityLabel.lowercased())")
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                text = MoneyFormatting.formatForDisplay(text, kind: kind)
            }
        }
        .onAppear {
            if autoFocus { isFocused = true }
        }
    }
}

// MARK: - Notes

struct NotesField: View {
    @Binding var text: String

    var body: some View {
        HStack(alignment: .top) {
            TextField("Notes", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .textInputAutocapitalization(.sentences)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .padding(.top, 4)
                .accessibilityLabel("Clear notes")
            }
        }
    }
}

// MARK: - Recurrence

@ViewBuilder
func RecurrenceFields(
    recurrenceType: Binding<String>,
    recurrenceInterval: Binding<Int>,
    noneLabel: String = "Never"
) -> some View {
    let options = ["none", "daily", "weekly", "monthly", "quarterly", "semiannually", "yearly"]
    Picker("Repeat", selection: recurrenceType) {
        ForEach(options, id: \.self) { option in
            Text(recurrenceDisplayName(option, noneLabel: noneLabel)).tag(option)
        }
    }
    .pickerStyle(.menu)
    .onChange(of: recurrenceType.wrappedValue) { oldType, newType in
        guard oldType != newType else { return }
        clampRecurrenceInterval(recurrenceInterval, for: newType)
    }

    if recurrenceType.wrappedValue == "daily" || recurrenceType.wrappedValue == "weekly" {
        let maxInterval = recurrenceType.wrappedValue == "daily" ? 365 : 52
        let unit = recurrenceIntervalUnit(type: recurrenceType.wrappedValue, interval: recurrenceInterval.wrappedValue)
        HStack {
            Text("Every")
                .foregroundStyle(.secondary)
            Stepper(value: recurrenceInterval, in: 1...maxInterval) {
                HStack {
                    Text("\(recurrenceInterval.wrappedValue)")
                        .fontWeight(.medium)
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityLabel("Repeat interval")
        }
    }
}

private func recurrenceDisplayName(_ option: String, noneLabel: String) -> String {
    switch option {
    case "none": return noneLabel
    case "daily": return "Daily"
    case "weekly": return "Weekly"
    case "monthly": return "Monthly"
    case "quarterly": return "Quarterly"
    case "semiannually": return "Semi-annually"
    case "yearly": return "Yearly"
    default: return option.capitalized
    }
}

private func recurrenceIntervalUnit(type: String, interval: Int) -> String {
    switch type {
    case "daily": return interval == 1 ? "day" : "days"
    case "weekly": return interval == 1 ? "week" : "weeks"
    default: return ""
    }
}

private func clampRecurrenceInterval(_ interval: Binding<Int>, for type: String) {
    switch type {
    case "none":
        break
    case "daily":
        interval.wrappedValue = min(max(interval.wrappedValue, 1), 365)
    case "weekly":
        interval.wrappedValue = min(max(interval.wrappedValue, 1), 52)
    default:
        interval.wrappedValue = 1
    }
}

// MARK: - Toolbar

struct FormSheetToolbar: ToolbarContent {
    var saveTitle: String = "Save"
    var canSave: Bool = true
    var showDelete: Bool = false
    let onClose: () -> Void
    let onSave: () -> Void
    var onDelete: (() -> Void)? = nil

    var body: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .accessibilityLabel("Close")
        }
        ToolbarItemGroup(placement: .confirmationAction) {
            if showDelete {
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            Button(saveTitle, action: onSave)
                .fontWeight(.semibold)
                .disabled(!canSave)
        }
    }
}

// MARK: - Keyboard + scroll

extension View {
    func formEntryChrome() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
    }
}
