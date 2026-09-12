import SwiftUI
import UIKit

struct ShareFileItem: Identifiable {
    let id = UUID()
    let url: URL?
    let image: UIImage?

    var activityItems: [Any] {
        if let image { return [image] }
        if let url { return [url] }
        return []
    }

    init(url: URL) {
        self.url = url
        self.image = nil
    }

    init(image: UIImage) {
        self.url = nil
        self.image = image
    }
}

struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let completion: (() -> Void)?

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            completion?()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
