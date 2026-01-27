//
//  LiveDateTimeView.swift
//  BillsAndBalance
//
//  Created on 1/25/26.
//

import SwiftUI
import Combine

struct LiveDateTimeView: View {
    @State private var currentDate = Date()
    @State private var timer: Timer?
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
    
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 2) {
            Text(timeFormatter.string(from: currentDate))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
            Text(dateFormatter.string(from: currentDate))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            // Update immediately
            currentDate = Date()
            
            // Update every second
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                currentDate = Date()
            }
        }
        .onDisappear {
            // Clean up timer when view disappears
            timer?.invalidate()
            timer = nil
        }
    }
}
