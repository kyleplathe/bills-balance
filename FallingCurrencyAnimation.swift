//
//  FallingCurrencyAnimation.swift
//  BillsAndBalance
//

import SwiftUI

enum BitcoinCoinFrame: String, CaseIterable {
    case front = "BitcoinCoinFront"
    case angled = "BitcoinCoinAngled"
    case edge = "BitcoinCoinEdge"
    case back = "BitcoinCoinBack"

    /// Face → 3/4 → edge → reverse, then back the other way so a fall looks like a tumble.
    static let spinSequence: [BitcoinCoinFrame] = [
        .front, .angled, .edge, .back, .edge, .angled
    ]
}

enum DollarBillAsset: String, CaseIterable {
    case one = "DollarBill1"
    case five = "DollarBill5"
    case twenty = "DollarBill20"
    case hundred = "DollarBill100"
}

struct FallingBitcoinCoinView: View {
    var size: CGFloat
    var startFrame: Int
    var spinning: Bool
    var spinInterval: Double

    var body: some View {
        Group {
            if spinning {
                TimelineView(.animation(minimumInterval: spinInterval, paused: false)) { timeline in
                    let tick = Int(timeline.date.timeIntervalSinceReferenceDate / max(spinInterval, 0.04))
                    let index = (startFrame + tick) % BitcoinCoinFrame.spinSequence.count
                    coinImage(BitcoinCoinFrame.spinSequence[index])
                }
            } else {
                coinImage(BitcoinCoinFrame.spinSequence[startFrame % BitcoinCoinFrame.spinSequence.count])
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.orange.opacity(0.65), radius: 10)
        .allowsHitTesting(false)
    }

    private func coinImage(_ frame: BitcoinCoinFrame) -> some View {
        Image(frame.rawValue)
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

struct FloatingDollarSpec: Identifiable {
    let id = UUID()
    let asset: DollarBillAsset
    let start: CGPoint
    let endY: CGFloat
    let width: CGFloat
    let duration: Double
    let spawnedAt: Date
    let phase: Double
    let swayAmplitude: CGFloat
    let swayFrequency: Double
    let rollAmplitude: Double
    let yawAmplitude: Double
    let pitchAmplitude: Double
    let driftX: CGFloat
}

struct FallingDollarBillView: View {
    let spec: FloatingDollarSpec

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(spec.spawnedAt))
            let t = min(1, elapsed / max(spec.duration, 0.1))
            let descent = cartoonDescent(t)
            let wave = elapsed * spec.swayFrequency + spec.phase

            // Leaf path: primary sine plus a slower wander so it doesn't look mechanical.
            let y = spec.start.y + (spec.endY - spec.start.y) * descent
            let x = spec.start.x
                + spec.driftX * descent
                + sin(wave) * spec.swayAmplitude
                + sin(wave * 0.45) * spec.swayAmplitude * 0.32

            let roll = sin(wave * 0.85) * spec.rollAmplitude
            let yaw = sin(wave * 1.15) * spec.yawAmplitude
            let pitch = sin(wave * 0.7) * spec.pitchAmplitude
            let glow = 0.5 + 0.5 * sin(elapsed * 2.4 + spec.phase)
            let opacity = t < 0.86 ? 1.0 : Double(1 - (t - 0.86) / 0.14)

            Image(spec.asset.rawValue)
                .renderingMode(.original)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: spec.width)
                .rotation3DEffect(
                    .degrees(pitch),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.7
                )
                .rotation3DEffect(
                    .degrees(yaw),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.55
                )
                .rotationEffect(.degrees(roll))
                .shadow(color: Color.green.opacity(0.28 + 0.42 * glow), radius: 6 + 8 * glow)
                .opacity(opacity)
                .position(x: x, y: y)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    /// Matches the bitcoin drop: ease-in so they pick up speed as they fall.
    private func cartoonDescent(_ t: Double) -> CGFloat {
        let clamped = min(1, max(0, t))
        return CGFloat(clamped * clamped)
    }
}
