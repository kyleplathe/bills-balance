import SwiftUI

private let bitcoinOrange = Color(red: 0.969, green: 0.576, blue: 0.102)
private let shareBackground = Color(red: 0.06, green: 0.06, blue: 0.075)

struct UsdBtcShareCard: View {
    let title: String
    let months: [UsdBtcMonthPoint]
    let monthsBack: Int

    private var headlineName: String {
        BillBtcBacktest.shareHeadlineName(from: title)
    }

    private var change: BillBtcBacktest.BitcoinSpendChange? {
        BillBtcBacktest.bitcoinSpendChange(
            btcAmounts: months.map(\.btcAmount),
            monthCount: max(months.count, monthsBack)
        )
    }

    private var yearSpanLabel: String {
        guard let first = months.first?.month, let last = months.last?.month else {
            return "\(max(monthsBack / 12, 1)) years of payments"
        }
        let years = Calendar.current.dateComponents([.year], from: first, to: last).year ?? 0
        if years >= 2 {
            return "\(years)+ years of payments"
        }
        return "\(max(months.count, 1)) months of payments"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BILLS & BALANCE")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.42))

            VStack(alignment: .leading, spacing: 2) {
                Text(headlineName)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("USD vs BTC")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(bitcoinOrange)
            }
            .padding(.top, 14)

            Text(yearSpanLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.5))
                .padding(.top, 8)

            UsdBtcShareChart(months: months)
                .frame(maxWidth: .infinity)
                .frame(height: 168)
                .padding(.top, 18)

            HStack(spacing: 14) {
                legendDot(color: .white.opacity(0.85), title: "USD")
                legendDot(color: bitcoinOrange, title: "BTC today")
            }
            .padding(.top, 10)

            Spacer(minLength: 12)

            if let change {
                let percent = abs((change.percentLess * 100 as NSDecimalNumber).intValue)
                let less = change.percentLess >= 0
                Text("\(percent)%")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(less ? bitcoinOrange : .white)
                    .monospacedDigit()
                Text(less
                     ? "less Bitcoin than \(change.years) years ago"
                     : "more Bitcoin than \(change.years) years ago")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .padding(.top, 2)
            }

            if let change, change.percentLess > 0 {
                Text("Same dollars. Fewer sats over time.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.38))
                    .padding(.top, 12)
            }
        }
        .padding(28)
        .frame(width: UsdBtcShareExport.canvasSide, height: UsdBtcShareExport.canvasSide, alignment: .topLeading)
        .background(shareBackground)
    }

    private func legendDot(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }
}

private struct UsdBtcShareChart: View {
    let months: [UsdBtcMonthPoint]

    var body: some View {
        Canvas { context, size in
            let usd = months.map { NSDecimalNumber(decimal: $0.usdExpenses).doubleValue }
            let btcNow = months.map { NSDecimalNumber(decimal: $0.btcValueNow).doubleValue }
            guard usd.count > 1, usd.count == btcNow.count else { return }

            let maxV = max(usd.max() ?? 1, btcNow.max() ?? 1) * 1.08
            let minV = 0.0
            let span = max(maxV - minV, 1)
            let leading: CGFloat = 4
            let trailing: CGFloat = 4
            let top: CGFloat = 8
            let bottom: CGFloat = 22
            let plot = CGRect(x: leading, y: top, width: size.width - leading - trailing, height: size.height - top - bottom)

            func point(index: Int, value: Double) -> CGPoint {
                let x = plot.minX + plot.width * CGFloat(index) / CGFloat(usd.count - 1)
                let y = plot.maxY - plot.height * CGFloat((value - minV) / span)
                return CGPoint(x: x, y: y)
            }

            var grid = Path()
            for step in 0...3 {
                let y = plot.maxY - plot.height * CGFloat(step) / 3
                grid.move(to: CGPoint(x: plot.minX, y: y))
                grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 1)

            let btcPoints = btcNow.enumerated().map { point(index: $0.offset, value: $0.element) }
            let usdPoints = usd.enumerated().map { point(index: $0.offset, value: $0.element) }

            var area = Path()
            if let first = btcPoints.first, let last = btcPoints.last {
                area.move(to: CGPoint(x: first.x, y: plot.maxY))
                area.addLine(to: first)
                for p in btcPoints.dropFirst() { area.addLine(to: p) }
                area.addLine(to: CGPoint(x: last.x, y: plot.maxY))
                area.closeSubpath()
            }
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [bitcoinOrange.opacity(0.42), bitcoinOrange.opacity(0.02)]),
                    startPoint: CGPoint(x: plot.midX, y: plot.minY),
                    endPoint: CGPoint(x: plot.midX, y: plot.maxY)
                )
            )

            var btcLine = Path()
            if let first = btcPoints.first {
                btcLine.move(to: first)
                for p in btcPoints.dropFirst() { btcLine.addLine(to: p) }
            }
            context.stroke(btcLine, with: .color(bitcoinOrange), style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))

            var usdLine = Path()
            if let first = usdPoints.first {
                usdLine.move(to: first)
                for p in usdPoints.dropFirst() { usdLine.addLine(to: p) }
            }
            context.stroke(usdLine, with: .color(.white.opacity(0.88)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            if let last = btcPoints.last {
                let dot = Path(ellipseIn: CGRect(x: last.x - 3.5, y: last.y - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(bitcoinOrange))
            }

            let labels = yearLabels()
            for (xRatio, text) in labels {
                let resolved = context.resolve(
                    Text(text)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.4))
                )
                let x = plot.minX + plot.width * xRatio
                let anchor: UnitPoint = xRatio < 0.5 ? .bottomLeading : .bottomTrailing
                context.draw(resolved, at: CGPoint(x: x, y: size.height - 6), anchor: anchor)
            }
        }
    }

    private func yearLabels() -> [(CGFloat, String)] {
        guard let first = months.first?.month, let last = months.last?.month else { return [] }
        let cal = Calendar.current
        let startYear = cal.component(.year, from: first)
        let endYear = cal.component(.year, from: last)
        if startYear == endYear {
            return [(0, String(startYear)), (1, String(endYear))]
        }
        return [(0, String(startYear)), (1, String(endYear))]
    }
}

@MainActor
enum UsdBtcShareExport {
    static let canvasSide: CGFloat = 400

    static func pngURL(title: String, months: [UsdBtcMonthPoint], monthsBack: Int) -> URL? {
        let card = UsdBtcShareCard(title: title, months: months, monthsBack: monthsBack)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1080 / canvasSide
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(width: canvasSide, height: canvasSide)
        guard let image = renderer.uiImage, let data = image.pngData() else { return nil }
        let safe = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
