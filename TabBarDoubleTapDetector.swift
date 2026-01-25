//
//  TabBarDoubleTapDetector.swift
//  BillsAndBalance
//
//  Created on 11/13/25.
//

import SwiftUI

struct TabBarDoubleTapDetector: UIViewRepresentable {
    let onDoubleTap: () -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tapGesture.numberOfTapsRequired = 2
        view.addGestureRecognizer(tapGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onDoubleTap = onDoubleTap
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleTap: onDoubleTap)
    }
    
    class Coordinator: NSObject {
        var onDoubleTap: () -> Void
        
        init(onDoubleTap: @escaping () -> Void) {
            self.onDoubleTap = onDoubleTap
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            onDoubleTap()
        }
    }
}





