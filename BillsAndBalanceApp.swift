import SwiftUI

@main
struct BillsAndBalanceApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var billViewModel: BillViewModel
    @StateObject private var accountViewModel: AccountViewModel
    @StateObject private var notificationManager: NotificationManager
    @StateObject private var paycheckViewModel: PaycheckViewModel
    @StateObject private var creditCardManager = CreditCardManager()
    @StateObject private var categoryManager = CategoryManager()
    @StateObject private var bitcoinPriceService = BitcoinPriceService.shared
    @StateObject private var onboardingManager = OnboardingManager.shared
    @StateObject private var reportsViewModel: ReportsViewModel
    @State private var showSplash = true

    init() {
        let context = PersistenceController.shared.container.viewContext
        let notifManager = NotificationManager()
        let accountVM = AccountViewModel(context: context)
        let paycheckVM = PaycheckViewModel(context: context, accountViewModel: accountVM)
        let creditCardMgr = CreditCardManager()

        let billRepository: BillRepository?
        do {
            // Keep publishable Supabase values outside source code (scheme env vars).
            let supabaseManager = try SupabaseManager()
            billRepository = SupabaseBillRepository(supabaseManager: supabaseManager)
        } catch {
            billRepository = nil
            #if DEBUG
            print("Supabase disabled: \(error.localizedDescription)")
            #endif
        }

        let billVM = BillViewModel(
            context: context,
            notificationManager: notifManager,
            accountViewModel: accountVM,
            billRepository: billRepository
        )

        _notificationManager = StateObject(wrappedValue: notifManager)
        _accountViewModel = StateObject(wrappedValue: accountVM)
        _billViewModel = StateObject(wrappedValue: billVM)
        _paycheckViewModel = StateObject(wrappedValue: paycheckVM)
        _creditCardManager = StateObject(wrappedValue: creditCardMgr)
        _reportsViewModel = StateObject(
            wrappedValue: ReportsViewModel(
                context: context,
                bitcoinPriceService: BitcoinPriceService.shared,
                creditCardManager: creditCardMgr
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if onboardingManager.hasCompletedOnboarding {
                    MainTabView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(billViewModel)
                        .environmentObject(accountViewModel)
                        .environmentObject(paycheckViewModel)
                        .environmentObject(notificationManager)
                        .environmentObject(creditCardManager)
                        .environmentObject(categoryManager)
                        .environmentObject(bitcoinPriceService)
                        .environmentObject(reportsViewModel)
                        .preferredColorScheme(nil)
                        .onAppear {
                            billViewModel.updateAppBadge()
                        }
                } else {
                    OnboardingView()
                        .environmentObject(notificationManager)
                }

                if showSplash && onboardingManager.hasCompletedOnboarding {
                    SplashScreenView(isActive: $showSplash)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
    }
}
