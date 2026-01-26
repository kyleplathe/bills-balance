//
//  MainTabView.swift
//  BillsAndBalance
//
//  Created on 11/8/25.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var categoryManager: CategoryManager
    @EnvironmentObject private var accountViewModel: AccountViewModel
    
    @State private var selectedTab: Int = 0
    @State private var selectedMonth: Date? = Date()
    @State private var isLandscape: Bool = false

    var body: some View {
        GeometryReader { geometry in
            Group {
                if geometry.size.width > geometry.size.height {
                    landscapeLayout(geometry: geometry)
                } else {
                    portraitLayout
                }
            }
            .onAppear {
                updateLandscape(geometry.size)
                // Cleanup unused categories on app launch
                let usage = accountViewModel.categoryUsage()
                categoryManager.cleanupUnusedCategories(usage: usage)
            }
            .onChange(of: geometry.size) { _, newSize in
                updateLandscape(newSize)
            }
        }
    }

    private func updateLandscape(_ size: CGSize) {
        isLandscape = size.width > size.height
    }
    
    private var portraitLayout: some View {
        TabView(selection: $selectedTab) {
            BillListView()
                .tag(0)
                .tabItem {
                    Label("Bills", systemImage: "list.bullet.circle")
                }
            
            BalanceView()
                .tag(1)
                .tabItem {
                    Label("Balance", systemImage: "creditcard")
                }
            
            CalendarTabView(selectedMonth: $selectedMonth)
                .tag(2)
                .tabItem {
                    Label("Calendar", systemImage: "calendar")
                }
        }
    }
    
    private func landscapeLayout(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Bills - Left Side (filtered by selected month)
                BillListView(filterMonth: selectedMonth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                
                // Subtle divider - matches system separator style
                Divider()
                    .background(Color(.separator).opacity(0.3))
                
                // Calendar - Right Side
                CalendarTabView(selectedMonth: $selectedMonth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                selectedTab = index
            }
            HapticManager.shared.buttonTapped()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption2)
            }
            .foregroundColor(selectedTab == index ? .accentColor : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedTab == index ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}


