//
//  ContentView.swift
//  BillsAndBalance
//
//  Created on 11/4/24.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 80))
                .foregroundColor(.blue)
            
            Text("Bills & Balance")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Your bill tracking app is loading...")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding()
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

