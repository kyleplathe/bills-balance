//
//  LiveDateTimeView.swift
//  BillsAndBalance
//
//  Created on 1/25/26.
//

import SwiftUI

struct LiveDateTimeView: View {
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
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 2) {
                Text(timeFormatter.string(from: context.date))
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text(dateFormatter.string(from: context.date))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
