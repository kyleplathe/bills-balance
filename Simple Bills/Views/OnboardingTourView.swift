import SwiftUI

struct OnboardingTourView: View {
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var hapticManager: HapticManager
    
    var body: some View {
        VStack {
            Text("Welcome to Bills & Balance!")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Your project has been moved to an external drive")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button("Continue") {
                onboardingManager.shouldShowOnboarding = false
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
    }
}
