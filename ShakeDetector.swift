//
//  ShakeDetector.swift
//  BillsAndBalance
//
//  Created on 11/13/25.
//

import SwiftUI
import UIKit
import ObjectiveC

enum ShakeDetection {
    static let notification = Notification.Name("deviceDidShakeNotification")

    private static var lastPostUptime: TimeInterval = 0

    static let install: Void = {
        let originalSelector = #selector(UIWindow.motionEnded(_:with:))
        let swizzledSelector = #selector(UIWindow.bb_motionEnded(_:with:))
        guard
            let originalMethod = class_getInstanceMethod(UIWindow.self, originalSelector),
            let swizzledMethod = class_getInstanceMethod(UIWindow.self, swizzledSelector)
        else { return }
        method_exchangeImplementations(originalMethod, swizzledMethod)
    }()

    static func postIfNeeded() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPostUptime > 0.25 else { return }
        lastPostUptime = now
        NotificationCenter.default.post(name: notification, object: nil)
    }
}

extension UIWindow {
    @objc func bb_motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            ShakeDetection.postIfNeeded()
        }
        bb_motionEnded(motion, with: event)
    }
}

struct ShakeDetector: ViewModifier {
    let onShake: () -> Void

    func body(content: Content) -> some View {
        content
            .background(ShakeCatcherView())
            .onAppear { _ = ShakeDetection.install }
            .onReceive(NotificationCenter.default.publisher(for: ShakeDetection.notification)) { _ in
                onShake()
            }
    }
}

extension View {
    func onShake(perform action: @escaping () -> Void) -> some View {
        self.modifier(ShakeDetector(onShake: action))
    }
}

private struct ShakeCatcherView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeCatcherController {
        ShakeCatcherController()
    }

    func updateUIViewController(_ uiViewController: ShakeCatcherController, context: Context) {}
}

final class ShakeCatcherController: UIViewController {
    override var canBecomeFirstResponder: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            ShakeDetection.postIfNeeded()
        } else {
            super.motionEnded(motion, with: event)
        }
    }
}
