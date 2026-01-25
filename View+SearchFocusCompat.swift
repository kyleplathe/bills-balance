import SwiftUI

extension View {
    @ViewBuilder
    func searchFocusCompat(_ isFocused: Binding<Bool>) -> some View {
        if #available(iOS 18.0, *) {
            self.searchFocused(isFocused)
        } else {
            self
        }
    }
}
