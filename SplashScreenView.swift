import SwiftUI

struct SplashScreenView: View {
    @State private var scale: CGFloat = 0.92
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Brand.splashBackground
                .ignoresSafeArea()

            BrandLockup(markSize: 108, nameSize: 30, textColor: Brand.wordmark)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.18)) {
                scale = 1
                opacity = 1
            }
        }
    }
}

#Preview {
    SplashScreenView()
}
