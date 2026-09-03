import SwiftUI

@MainActor
final class AppBootstrap: ObservableObject {
    @Published private(set) var isReady = false

    let notificationManager = NotificationManager()
    let creditCardManager = CreditCardManager()
    let categoryManager = CategoryManager()
    let bitcoinPriceService = BitcoinPriceService.shared

    private(set) var billViewModel: BillViewModel!
    private(set) var accountViewModel: AccountViewModel!
    private(set) var paycheckViewModel: PaycheckViewModel!
    private(set) var reportsViewModel: ReportsViewModel!

    func prepareIfNeeded() async {
        guard !isReady else { return }

        await PersistenceController.waitForStores()

        let context = PersistenceController.shared.container.viewContext
        let accountVM = AccountViewModel(context: context)
        let paycheckVM = PaycheckViewModel(context: context, accountViewModel: accountVM)

        let billRepository: BillRepository?
        do {
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
            notificationManager: notificationManager,
            accountViewModel: accountVM,
            billRepository: billRepository
        )

        accountViewModel = accountVM
        paycheckViewModel = paycheckVM
        billViewModel = billVM
        reportsViewModel = ReportsViewModel(
            context: context,
            bitcoinPriceService: bitcoinPriceService,
            creditCardManager: creditCardManager
        )
        isReady = true
    }
}

@main
struct BillsAndBalanceApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var bootstrap = AppBootstrap()
    @StateObject private var onboardingManager = OnboardingManager.shared
    @State private var showSplash = true

    var body: some Scene {
        WindowGroup {
            ZStack {
                if !onboardingManager.hasCompletedOnboarding {
                    OnboardingView()
                        .environmentObject(bootstrap.notificationManager)
                } else if bootstrap.isReady {
                    MainTabView()
                        .environment(\.managedObjectContext, persistenceController.container.viewContext)
                        .environmentObject(bootstrap.billViewModel)
                        .environmentObject(bootstrap.accountViewModel)
                        .environmentObject(bootstrap.paycheckViewModel)
                        .environmentObject(bootstrap.notificationManager)
                        .environmentObject(bootstrap.creditCardManager)
                        .environmentObject(bootstrap.categoryManager)
                        .environmentObject(bootstrap.bitcoinPriceService)
                        .environmentObject(bootstrap.reportsViewModel)
                        .environmentObject(ProjectionPreferences.shared)
                        .preferredColorScheme(nil)
                        .onAppear {
                            bootstrap.billViewModel.updateAppBadge()
                        }
                } else {
                    ProgressView("Loading…")
                }

                if showSplash && onboardingManager.hasCompletedOnboarding && bootstrap.isReady {
                    SplashScreenView(isActive: $showSplash)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .task {
                _ = ShakeDetection.install
                await bootstrap.prepareIfNeeded()
            }
        }
    }
}
