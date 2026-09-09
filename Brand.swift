import SwiftUI
import UIKit

/// Colors and lockup drawn from the app icon (sky field, navy card, mint check).
enum Brand {
    static let sky = Color(red: 129 / 255, green: 222 / 255, blue: 255 / 255)
    static let navy = Color(red: 17 / 255, green: 53 / 255, blue: 114 / 255)
    static let mint = Color(red: 31 / 255, green: 199 / 255, blue: 145 / 255)

    static let splashBackground = Color("LaunchBackground")
    static let wordmark = Color(light: navy, dark: .white)
    static let action = Color(light: navy, dark: mint)
}

struct BrandMark: View {
    var size: CGFloat = 96

    var body: some View {
        Image("BrandMark")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous))
            .compositingGroup()
            .shadow(color: Brand.navy.opacity(0.22), radius: size * 0.14, y: size * 0.08)
            .accessibilityHidden(true)
    }
}

struct BrandWordmark: View {
    var size: CGFloat = 28
    var textColor: Color = Brand.wordmark

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size * 0.28) {
            Text("Bills")
                .foregroundStyle(textColor)
            Text("&")
                .foregroundStyle(Brand.mint)
            Text("Balance")
                .foregroundStyle(textColor)
        }
        .font(.system(size: size, weight: .semibold))
        .minimumScaleFactor(0.7)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bills & Balance")
    }
}

struct BrandLockup: View {
    var markSize: CGFloat = 96
    var nameSize: CGFloat = 28
    var textColor: Color = Brand.wordmark
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: 18) {
            BrandMark(size: markSize)
            VStack(spacing: 6) {
                BrandWordmark(size: nameSize, textColor: textColor)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(textColor.opacity(0.72))
                        .multilineTextAlignment(.center)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}
