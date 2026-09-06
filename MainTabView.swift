//
//  MainTabView.swift
//  BillsAndBalance
//
//  Created on 11/8/25.
//

import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var appLockManager: AppLockManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: Int = 0
    @State private var selectedMonth: Date? = Date()

    var body: some View {
        tabContent
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    appLockManager.lockIfNeeded()
                }
            }
    }

    @ViewBuilder
    private var tabContent: some View {
        if #available(iOS 18.0, *) {
            TabView(selection: $selectedTab.animation(.smooth(duration: 0.32))) {
                Tab("Bills", systemImage: "list.bullet.circle", value: 0) {
                    BillListView()
                }
                Tab("Balance", systemImage: "creditcard", value: 1) {
                    BalanceView()
                }
                Tab("Calendar", systemImage: "calendar", value: 2) {
                    CalendarTabView(selectedMonth: $selectedMonth)
                }
            }
        } else {
            TabView(selection: $selectedTab.animation(.easeInOut(duration: 0.28))) {
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
    }
}
