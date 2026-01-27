//
//  ManageBillsView.swift
//  BillsAndBalance
//
//  Created on 1/2/25.
//

import SwiftUI
import CoreData

struct ManageBillsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var billViewModel: BillViewModel
    @EnvironmentObject private var accountViewModel: AccountViewModel
    @EnvironmentObject private var cardManager: CreditCardManager
    @EnvironmentObject private var categoryManager: CategoryManager
    
    @State private var selectedBill: Bill?
    @State private var showingAddBill = false
    @State private var showingImportPicker = false
    @State private var showingExportSheet = false
    @State private var exportURL: URL?
    @State private var exportErrorMessage: String?
    @State private var showExportErrorAlert = false
    @State private var importErrorMessage: String?
    @State private var showImportErrorAlert = false
    @State private var showImportSuccessAlert = false
    @State private var importedCount = 0
    
    enum ExportFormat {
        case csv
        case json
    }
    
    var body: some View {
        NavigationStack {
            Form {
                billsSection
            }
            .navigationTitle("Manage Bills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        showingAddBill = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    
                    Menu {
                        Button {
                            exportBills(format: .csv)
                        } label: {
                            Label("Export as CSV", systemImage: "doc.text")
                        }
                        
                        Button {
                            exportBills(format: .json)
                        } label: {
                            Label("Export as JSON", systemImage: "doc.badge.gearshape")
                        }
                        
                        Divider()
                        
                        Button {
                            showingImportPicker = true
                        } label: {
                            Label("Import Bills", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showingAddBill) {
                AddEditBillView()
                    .environmentObject(billViewModel)
                    .environmentObject(accountViewModel)
                    .environmentObject(cardManager)
                    .environmentObject(categoryManager)
            }
            .sheet(item: $selectedBill) { bill in
                AddEditBillView(bill: bill)
                    .environmentObject(billViewModel)
                    .environmentObject(accountViewModel)
                    .environmentObject(cardManager)
                    .environmentObject(categoryManager)
            }
            .sheet(isPresented: $showingExportSheet, onDismiss: cleanupExportFile) {
                if let url = exportURL {
                    BillsShareSheet(activityItems: [url]) {
                        cleanupExportFile()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImportPicker,
                allowedContentTypes: [.json, .commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                handleImportResult(result)
            }
            .alert("Export Error", isPresented: $showExportErrorAlert, presenting: exportErrorMessage) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
            .alert("Import Error", isPresented: $showImportErrorAlert, presenting: importErrorMessage) { _ in
                Button("OK", role: .cancel) { }
            } message: { message in
                Text(message)
            }
            .alert("Import Successful", isPresented: $showImportSuccessAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Successfully imported \(importedCount) bill\(importedCount == 1 ? "" : "s").")
            }
        }
    }
    
    private var billsSection: some View {
        Section {
            if billViewModel.bills.isEmpty {
                Text("No bills added yet.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            } else {
                ForEach(billViewModel.bills, id: \.objectID) { bill in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bill.name ?? "Bill")
                                .font(.body)
                            if let amount = bill.amount {
                                Text(amount.decimalValue, format: .currency(code: "USD"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            selectedBill = bill
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.borderless)
                    }
                    .contentShape(Rectangle())
                }
            }
        } header: {
            Text("All Bills (\(billViewModel.bills.count))")
        } footer: {
            Text("Tap a bill to edit it. This view shows all bills, including those that may not appear in the main bills list.")
                .font(.footnote)
        }
    }
    
    // MARK: - Export Functions
    
    private func exportBills(format: ExportFormat) {
        guard !billViewModel.bills.isEmpty else {
            showExportError("There are no bills to export.")
            return
        }
        
        // Deduplicate recurring bills - only export one bill per series
        let deduplicatedBills = deduplicateRecurringBills(billViewModel.bills)
        let sortedBills = deduplicatedBills.sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        
        do {
            let url: URL
            switch format {
            case .csv:
                url = try writeBillsCSV(for: sortedBills)
            case .json:
                url = try writeBillsJSON(for: sortedBills)
            }
            exportURL = url
            showingExportSheet = true
        } catch {
            showExportError(error.localizedDescription)
        }
    }
    
    private func deduplicateRecurringBills(_ bills: [Bill]) -> [Bill] {
        var seenSeries: Set<UUID> = []
        var result: [Bill] = []
        
        // Sort by due date, then by creation date to get consistent ordering
        let sorted = bills.sorted { first, second in
            let firstDate = first.dueDate ?? Date.distantFuture
            let secondDate = second.dueDate ?? Date.distantFuture
            if firstDate != secondDate {
                return firstDate < secondDate
            }
            let firstCreated = first.createdAt ?? Date.distantFuture
            let secondCreated = second.createdAt ?? Date.distantFuture
            return firstCreated < secondCreated
        }
        
        for bill in sorted {
            // If it's a recurring bill (has seriesId)
            if let seriesId = bill.seriesId {
                // Only include the first bill we see for this series
                if !seenSeries.contains(seriesId) {
                    seenSeries.insert(seriesId)
                    result.append(bill)
                }
            } else {
                // Non-recurring bills are always included
                result.append(bill)
            }
        }
        
        return result
    }
    
    private func writeBillsCSV(for bills: [Bill]) throws -> URL {
        var lines: [String] = ["Due Date,Bill,Amount,Recurrence,Recurrence Interval,Status,Paid Date,Account,Auto-Pay,Category,Notes"]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        numberFormatter.maximumFractionDigits = 2
        numberFormatter.minimumFractionDigits = 0
        numberFormatter.locale = Locale(identifier: "en_US_POSIX")
        for bill in bills {
            let dateString = bill.dueDate.map { dateFormatter.string(from: $0) } ?? ""
            let amountDecimal = bill.amount?.decimalValue ?? 0
            let amountString = numberFormatter.string(from: amountDecimal as NSDecimalNumber) ?? ""
            let recurrenceType = bill.recurrenceType ?? "none"
            let recurrenceInterval = recurrenceType == "none" ? "" : String(bill.recurrenceInterval)
            let status = bill.isPaid ? "Paid" : "Open"
            let paidDateString = bill.paidDate.map { dateFormatter.string(from: $0) } ?? ""
            let accountName = bill.account?.name ?? ""
            let autoPay = bill.autoPay ? "Yes" : "No"
            let category = bill.category ?? ""
            let row = [
                escapeCSVField(dateString),
                escapeCSVField(bill.name ?? ""),
                amountString,
                escapeCSVField(recurrenceType),
                recurrenceInterval,
                status,
                escapeCSVField(paidDateString),
                escapeCSVField(accountName),
                autoPay,
                escapeCSVField(category),
                escapeCSVField(bill.notes ?? "")
            ].joined(separator: ",")
            lines.append(row)
        }
        let csvString = lines.joined(separator: "\n")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "Bills_Export_\(timestamp).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try csvString.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    private func escapeCSVField(_ value: String) -> String {
        var field = value
        if field.contains("\"") {
            field = field.replacingOccurrences(of: "\"", with: "\"\"")
        }
        if field.contains(",") || field.contains("\n") || field.contains("\"") {
            field = "\"\(field)\""
        }
        return field
    }
    
    private func writeBillsJSON(for bills: [Bill]) throws -> URL {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateFormatter.string(from: date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let billData = bills.map { bill -> [String: Any] in
            var dict: [String: Any] = [:]
            if let id = bill.id?.uuidString {
                dict["id"] = id
            }
            dict["name"] = bill.name ?? ""
            dict["amount"] = bill.amount?.decimalValue.description ?? "0"
            if let dueDate = bill.dueDate {
                dict["dueDate"] = dateFormatter.string(from: dueDate)
            }
            dict["notes"] = bill.notes ?? ""
            dict["recurrenceType"] = bill.recurrenceType ?? "none"
            dict["recurrenceInterval"] = Int(bill.recurrenceInterval)
            dict["autoPay"] = bill.autoPay
            dict["isPaid"] = bill.isPaid
            if let paidDate = bill.paidDate {
                dict["paidDate"] = dateFormatter.string(from: paidDate)
            }
            dict["paymentCard"] = bill.paymentCard ?? ""
            dict["accountName"] = bill.account?.name ?? ""
            dict["category"] = bill.category ?? ""
            if let createdAt = bill.createdAt {
                dict["createdAt"] = dateFormatter.string(from: createdAt)
            }
            if let updatedAt = bill.updatedAt {
                dict["updatedAt"] = dateFormatter.string(from: updatedAt)
            }
            return dict
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: ["bills": billData], options: [.prettyPrinted, .sortedKeys])
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileName = "Bills_Export_\(timestamp).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try jsonData.write(to: url)
        return url
    }
    
    private func cleanupExportFile() {
        if let url = exportURL {
            try? FileManager.default.removeItem(at: url)
        }
        exportURL = nil
    }
    
    private func showExportError(_ message: String) {
        exportErrorMessage = message
        showExportErrorAlert = true
    }
    
    // MARK: - Import Functions
    
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                importBills(from: url)
            }
        case .failure(let error):
            showImportError("Failed to access file: \(error.localizedDescription)")
        }
    }
    
    private func importBills(from url: URL) {
        // Start accessing security-scoped resource
        guard url.startAccessingSecurityScopedResource() else {
            showImportError("Unable to access the selected file.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let data = try Data(contentsOf: url)
            let fileExtension = url.pathExtension.lowercased()
            
            if fileExtension == "json" {
                try importBillsFromJSON(data: data)
            } else if fileExtension == "csv" {
                try importBillsFromCSV(data: data)
            } else {
                showImportError("Unsupported file format. Please use JSON or CSV.")
                return
            }
        } catch {
            showImportError("Failed to read file: \(error.localizedDescription)")
        }
    }
    
    private func importBillsFromJSON(data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let billsArray = json["bills"] as? [[String: Any]] else {
            throw NSError(domain: "ImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        
        var imported = 0
        var skipped = 0
        var errors: [String] = []
        var createdBills: [Bill] = []
        var importKeys: Set<String> = []
        
        for billDict in billsArray {
            guard let name = billDict["name"] as? String, !name.isEmpty else {
                errors.append("Bill missing name")
                continue
            }
            
            let amountString = billDict["amount"] as? String ?? "0"
            guard let amount = Decimal(string: amountString) else {
                errors.append("'\(name)': Invalid amount")
                continue
            }
            
            guard let dueDateString = billDict["dueDate"] as? String,
                  let dueDate = dateFormatter.date(from: dueDateString) else {
                errors.append("'\(name)': Invalid or missing due date")
                continue
            }
            
            let calendar = Calendar.current
            let dateKey = calendar.startOfDay(for: dueDate).timeIntervalSince1970
            let amountKey = NSDecimalNumber(decimal: amount).stringValue
            let importKey = "\(name)-\(dateKey)-\(amountKey)"
            
            if importKeys.contains(importKey) {
                skipped += 1
                continue
            }
            
            let notes = billDict["notes"] as? String ?? ""
            let recurrenceType = billDict["recurrenceType"] as? String ?? "none"
            let recurrenceInterval = billDict["recurrenceInterval"] as? Int ?? 0
            let autoPay = billDict["autoPay"] as? Bool ?? false
            let paymentCard = billDict["paymentCard"] as? String
            let accountName = billDict["accountName"] as? String
            let category = billDict["category"] as? String
            let isPaid = billDict["isPaid"] as? Bool ?? false
            let paidDateString = billDict["paidDate"] as? String
            let paidDate = paidDateString != nil ? dateFormatter.date(from: paidDateString!) : nil
            
            var account: Account? = nil
            if let accountName = accountName, !accountName.isEmpty {
                account = accountViewModel.accounts.first { $0.name == accountName }
            }
            
            if billViewModel.billExists(name: name, dueDate: dueDate, amount: amount) {
                skipped += 1
                continue
            }
            
            guard let newBill = billViewModel.addBill(
                name: name,
                amount: amount,
                dueDate: dueDate,
                notes: notes,
                recurrenceType: recurrenceType,
                recurrenceInterval: recurrenceInterval,
                autoPay: autoPay,
                paymentCard: paymentCard,
                account: account,
                category: category,
                skipDuplicateCheck: true,
                skipSave: true
            ) else {
                skipped += 1
                continue
            }
            
            importKeys.insert(importKey)
            
            if isPaid {
                newBill.isPaid = true
                newBill.paidDate = paidDate ?? dueDate
                
                if account != nil, let amountDecimal = newBill.amount?.decimalValue {
                    let transactionDate = paidDate ?? dueDate
                    accountViewModel.recordLedgerEntry(
                        for: newBill,
                        amount: amountDecimal,
                        date: transactionDate,
                        isCredit: false,
                        title: newBill.name,
                        notes: newBill.notes
                    )
                }
            }
            
            createdBills.append(newBill)
            imported += 1
        }
        
        if imported > 0 {
            do {
                let context = PersistenceController.shared.container.viewContext
                try context.save()
            } catch {
                errors.append("Error saving imported bills: \(error.localizedDescription)")
            }
            
            importedCount = imported
            showImportSuccessAlert = true
            billViewModel.skipAutoPayProcessing(for: 5.0)
            billViewModel.fetchBills(skipAutoPay: true)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let result = billViewModel.performComprehensiveCleanup()
                if result.duplicatesRemoved > 0 {
                    print("🧹 Post-import cleanup: Removed \(result.duplicatesRemoved) duplicate bills")
                }
            }
        } else if skipped > 0 {
            showImportError("All bills were skipped (already exist).")
        } else if !errors.isEmpty {
            showImportError("Failed to import bills:\n\(errors.prefix(5).joined(separator: "\n"))")
        } else {
            showImportError("No bills were imported.")
        }
    }
    
    private func importBillsFromCSV(data: Data) throws {
        guard let csvString = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "ImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read CSV file"])
        }
        
        let lines = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else {
            throw NSError(domain: "ImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "CSV file is empty or has no data rows"])
        }
        
        let header = parseCSVLine(lines[0])
        guard let dateIndex = header.firstIndex(of: "Due Date") ?? header.firstIndex(of: "dueDate"),
              let nameIndex = header.firstIndex(of: "Bill") ?? header.firstIndex(of: "bill") ?? header.firstIndex(of: "Name") ?? header.firstIndex(of: "name"),
              let amountIndex = header.firstIndex(of: "Amount") ?? header.firstIndex(of: "amount") else {
            throw NSError(domain: "ImportError", code: 1, userInfo: [NSLocalizedDescriptionKey: "CSV file missing required columns (Due Date, Bill/Name, Amount)"])
        }
        
        let recurrenceIndex = header.firstIndex(of: "Recurrence") ?? header.firstIndex(of: "recurrence")
        let recurrenceIntervalIndex = header.firstIndex(of: "Recurrence Interval") ?? header.firstIndex(of: "recurrenceInterval")
        let categoryIndex = header.firstIndex(of: "Category") ?? header.firstIndex(of: "category")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        
        var imported = 0
        var skipped = 0
        var errors: [String] = []
        var createdBills: [Bill] = []
        var importKeys: Set<String> = []
        
        for (index, line) in lines.dropFirst().enumerated() {
            let fields = parseCSVLine(line)
            guard fields.count > max(dateIndex, nameIndex, amountIndex) else {
                errors.append("Row \(index + 2): Not enough columns")
                continue
            }
            
            let name = fields[nameIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else {
                errors.append("Row \(index + 2): Missing bill name")
                continue
            }
            
            guard let dueDate = dateFormatter.date(from: fields[dateIndex].trimmingCharacters(in: .whitespacesAndNewlines)) else {
                errors.append("Row \(index + 2) ('\(name)'): Invalid date format")
                continue
            }
            
            let amountString = fields[amountIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let amount = Decimal(string: amountString.replacingOccurrences(of: ",", with: "")) else {
                errors.append("Row \(index + 2) ('\(name)'): Invalid amount")
                continue
            }
            
            let calendar = Calendar.current
            let dateKey = calendar.startOfDay(for: dueDate).timeIntervalSince1970
            let amountKey = NSDecimalNumber(decimal: amount).stringValue
            let importKey = "\(name)-\(dateKey)-\(amountKey)"
            
            if importKeys.contains(importKey) {
                skipped += 1
                continue
            }
            
            let statusIndex = header.firstIndex(of: "Status") ?? header.firstIndex(of: "status")
            let isPaid = statusIndex != nil && fields.indices.contains(statusIndex!) && fields[statusIndex!].lowercased() == "paid"
            
            let paidDateIndex = header.firstIndex(of: "Paid Date") ?? header.firstIndex(of: "paidDate")
            let paidDateString = paidDateIndex != nil && fields.indices.contains(paidDateIndex!) ? fields[paidDateIndex!].trimmingCharacters(in: .whitespacesAndNewlines) : nil
            let paidDate = paidDateString != nil && !paidDateString!.isEmpty ? dateFormatter.date(from: paidDateString!) : nil
            
            let notesIndex = header.firstIndex(of: "Notes") ?? header.firstIndex(of: "notes")
            let notes = notesIndex != nil && fields.indices.contains(notesIndex!) ? fields[notesIndex!] : ""
            
            let accountIndex = header.firstIndex(of: "Account") ?? header.firstIndex(of: "account")
            var account: Account? = nil
            if let accountIndex = accountIndex, fields.indices.contains(accountIndex) {
                let accountName = fields[accountIndex].trimmingCharacters(in: .whitespacesAndNewlines)
                if !accountName.isEmpty {
                    account = accountViewModel.accounts.first { $0.name == accountName }
                }
            }
            
            let autoPayIndex = header.firstIndex(of: "Auto-Pay") ?? header.firstIndex(of: "autoPay") ?? header.firstIndex(of: "Auto Pay")
            let autoPay = autoPayIndex != nil && fields.indices.contains(autoPayIndex!) && fields[autoPayIndex!].lowercased() == "yes"
            
            let recurrenceType = recurrenceIndex != nil && fields.indices.contains(recurrenceIndex!) ? fields[recurrenceIndex!].trimmingCharacters(in: .whitespacesAndNewlines) : "none"
            let recurrenceIntervalString = recurrenceIntervalIndex != nil && fields.indices.contains(recurrenceIntervalIndex!) ? fields[recurrenceIntervalIndex!].trimmingCharacters(in: .whitespacesAndNewlines) : "0"
            let recurrenceInterval = Int(recurrenceIntervalString) ?? 0
            
            let category = categoryIndex != nil && fields.indices.contains(categoryIndex!) ? fields[categoryIndex!].trimmingCharacters(in: .whitespacesAndNewlines) : nil
            
            if billViewModel.billExists(name: name, dueDate: dueDate, amount: amount) {
                skipped += 1
                continue
            }
            
            guard let newBill = billViewModel.addBill(
                name: name,
                amount: amount,
                dueDate: dueDate,
                notes: notes,
                recurrenceType: recurrenceType,
                recurrenceInterval: recurrenceInterval,
                autoPay: autoPay,
                paymentCard: nil,
                account: account,
                category: category,
                skipDuplicateCheck: true,
                skipSave: true
            ) else {
                skipped += 1
                continue
            }
            
            importKeys.insert(importKey)
            
            if isPaid {
                newBill.isPaid = true
                newBill.paidDate = paidDate ?? dueDate
                
                if account != nil, let amountDecimal = newBill.amount?.decimalValue {
                    let transactionDate = paidDate ?? dueDate
                    accountViewModel.recordLedgerEntry(
                        for: newBill,
                        amount: amountDecimal,
                        date: transactionDate,
                        isCredit: false,
                        title: newBill.name,
                        notes: newBill.notes
                    )
                }
            }
            
            createdBills.append(newBill)
            imported += 1
        }
        
        if imported > 0 {
            do {
                let context = PersistenceController.shared.container.viewContext
                try context.save()
            } catch {
                errors.append("Error saving imported bills: \(error.localizedDescription)")
            }
            
            importedCount = imported
            showImportSuccessAlert = true
            billViewModel.skipAutoPayProcessing(for: 5.0)
            billViewModel.fetchBills(skipAutoPay: true)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let result = billViewModel.performComprehensiveCleanup()
                if result.duplicatesRemoved > 0 {
                    print("🧹 Post-import cleanup: Removed \(result.duplicatesRemoved) duplicate bills")
                }
            }
        } else if skipped > 0 {
            showImportError("All bills were skipped (already exist).")
        } else if !errors.isEmpty {
            showImportError("Failed to import bills:\n\(errors.prefix(5).joined(separator: "\n"))")
        } else {
            showImportError("No bills were imported.")
        }
    }
    
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false
        
        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        fields.append(currentField)
        
        return fields.map { field in
            var cleaned = field.trimmingCharacters(in: .whitespaces)
            if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") {
                cleaned = String(cleaned.dropFirst().dropLast())
            }
            return cleaned.replacingOccurrences(of: "\"\"", with: "\"")
        }
    }
    
    private func showImportError(_ message: String) {
        importErrorMessage = message
        showImportErrorAlert = true
    }
}

// MARK: - Bills Share Sheet

private struct BillsShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let completion: (() -> Void)?
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            completion?()
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
