import SwiftUI
import UniformTypeIdentifiers

private let bitcoinOrange = Color(red: 0.969, green: 0.576, blue: 0.102)
private let shareBackground = Color(red: 0.06, green: 0.06, blue: 0.075)

enum UsdBtcBillStyle {
    static let palette: [Color] = [
        bitcoinOrange,
        Color(red: 0.22, green: 0.47, blue: 0.93),
        Color(red: 0.20, green: 0.62, blue: 0.38),
        Color(red: 0.76, green: 0.28, blue: 0.48),
        Color(red: 0.55, green: 0.36, blue: 0.96),
        Color(red: 0.18, green: 0.66, blue: 0.72),
        Color(red: 0.90, green: 0.72, blue: 0.18),
        Color(red: 0.42, green: 0.45, blue: 0.58)
    ]

    static func color(at index: Int) -> Color {
        palette[index % palette.count]
    }

    static func color(forName name: String, in names: [String]) -> Color {
        color(at: names.firstIndex(of: name) ?? 0)
    }
}

struct UsdBtcShareCard: View {
    let title: String
    let bills: [UsdBtcBillSeries]
    let monthsBack: Int
    var colorNames: [String] = []
    var quote: BillBtcBacktest.BitcoinQuote = BillBtcBacktest.randomBitcoinQuote()

    private var change: BillBtcBacktest.BitcoinSpendChange? {
        BillBtcBacktest.storyChange(bills: bills, monthsBack: monthsBack)
    }

    private var thenNow: BillBtcBacktest.ThenNowSnapshot? {
        BillBtcBacktest.thenNow(from: bills)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image("BrandMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .opacity(0.6)
                Text("BILLS & BALANCE")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.42))
            }

            UsdBtcStoryHeadline(change: change, billCount: bills.count, style: .share)
                .padding(.top, 10)

            if let thenNow {
                UsdBtcThenNowComparison(
                    snapshot: thenNow,
                    style: .share
                )
                .padding(.top, 12)
            }

            UsdBtcComparisonChart(
                bills: bills,
                style: .share,
                colorNames: colorNames,
                showsKey: true,
                plotHeight: 118
            )
            .padding(.top, 12)

            Spacer(minLength: 8)

            VStack(spacing: 4) {
                Text(BillBtcBacktest.twoLineQuote(quote.text))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .italic()
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white.opacity(0.48))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                Text("— \(quote.attribution)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(bitcoinOrange.opacity(0.72))
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 3) {
                Text(BillBtcBacktest.shareChartFooter())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(Color.white.opacity(0.38))
                Text(BillBtcBacktest.shareDisclaimer)
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.22))
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: Self.canvasWidth, height: Self.canvasHeight, alignment: .topLeading)
        .background(shareBackground)
    }

    static let canvasWidth: CGFloat = 400
    static let canvasHeight: CGFloat = 500

    static func pngImage(
        title: String,
        bills: [UsdBtcBillSeries],
        monthsBack: Int,
        colorNames: [String] = []
    ) -> UIImage? {
        let snapshotID = UUID()
        let quote = BillBtcBacktest.randomBitcoinQuote()
        let card = UsdBtcShareCard(
            title: title,
            bills: bills,
            monthsBack: monthsBack,
            colorNames: colorNames,
            quote: quote
        )
        let renderer = ImageRenderer(content: card.id(snapshotID))
        renderer.scale = 1080 / canvasWidth
        renderer.isOpaque = true
        renderer.proposedSize = ProposedViewSize(width: canvasWidth, height: canvasHeight)
        return renderer.uiImage
    }

    static func pngURL(
        title: String,
        bills: [UsdBtcBillSeries],
        monthsBack: Int,
        colorNames: [String] = []
    ) -> URL? {
        removeStaleSharePNGs()
        guard let image = pngImage(
            title: title,
            bills: bills,
            monthsBack: monthsBack,
            colorNames: colorNames
        ), let data = image.pngData() else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bitcoin-deflation-\(UUID().uuidString).png")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private static func removeStaleSharePNGs() {
        let tmp = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tmp,
            includingPropertiesForKeys: nil
        ) else { return }
        for url in files {
            let name = url.lastPathComponent
            let isOldTitle = name.hasSuffix(".png") && name.contains("USD vs BTC")
            let isPriorExport = name.hasPrefix("bitcoin-deflation-") && name.hasSuffix(".png")
            if isOldTitle || isPriorExport {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}

struct UsdBtcStoryHeadline: View {
    let change: BillBtcBacktest.BitcoinSpendChange?
    let billCount: Int
    var style: UsdBtcComparisonChart.Style = .inApp

    private var isShare: Bool { style == .share }

    var body: some View {
        if let change {
            let percent = BillBtcBacktest.percentPoints(change.percentLess)
            let noun = billCount <= 1 ? "bill" : "bills"
            let word = change.percentLess >= 0 ? "less" : "more"
            let accent = change.percentLess >= 0 ? Color.green : (isShare ? Color.white : Color.primary)
            (
                Text("Same \(noun). ")
                    .foregroundStyle(isShare ? Color.white : Color.primary)
                + Text("\(percent)%")
                    .foregroundStyle(accent)
                + Text(" \(word) Bitcoin.")
                    .foregroundStyle(isShare ? Color.white : Color.primary)
            )
            .font(isShare
                  ? .system(size: 17, weight: .semibold, design: .rounded)
                  : .title3.weight(.semibold))
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(BillBtcBacktest.storyHeadline(percentLess: change.percentLess, billCount: billCount))
        } else {
            Text(BillBtcBacktest.sameDollarsCaption(billCount: billCount))
                .font(isShare
                      ? .system(size: 17, weight: .semibold, design: .rounded)
                      : .title3.weight(.semibold))
                .foregroundStyle(isShare ? Color.white : Color.primary)
        }
    }
}

struct UsdBtcThenNowComparison: View {
    let snapshot: BillBtcBacktest.ThenNowSnapshot
    var style: UsdBtcComparisonChart.Style = .inApp

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var nowVisible = false

    private var isShare: Bool { style == .share }

    private var muted: Color {
        isShare ? Color.white.opacity(0.42) : Color.secondary
    }

    private var primary: Color {
        isShare ? Color.white : Color.primary
    }

    private var usdLabel: String {
        "\(BillBtcBacktest.compactUsd((snapshot.monthlyUsd as NSDecimalNumber).doubleValue))/mo avg"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            column(
                eyebrow: "Then",
                detail: "\(snapshot.thenLabel)  ·  \(usdLabel)",
                sats: snapshot.thenSats,
                highlight: false
            )
            Rectangle()
                .fill(muted.opacity(0.7))
                .frame(width: isShare ? 16 : 20, height: 1)
                .accessibilityHidden(true)
            column(
                eyebrow: "Now",
                detail: usdLabel,
                sats: snapshot.nowSats,
                highlight: true
            )
            .opacity(isShare || reduceMotion || nowVisible ? 1 : 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .onAppear(perform: revealNow)
    }

    private func amountLabel(_ sats: Double) -> String {
        isShare ? BillBtcBacktest.bitcoinCaption(fromSats: sats) : BillBtcBacktest.satsCaption(sats)
    }

    private var accessibilityText: String {
        let then = amountLabel(snapshot.thenSats)
        let now = amountLabel(snapshot.nowSats)
        return "\(snapshot.thenLabel) \(then). Now \(now). Same \(usdLabel)."
    }

    private func column(eyebrow: String, detail: String, sats: Double, highlight: Bool) -> some View {
        VStack(alignment: highlight ? .trailing : .leading, spacing: isShare ? 3 : 4) {
            Text(eyebrow.uppercased())
                .font(.system(size: isShare ? 10 : 11, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(highlight ? bitcoinOrange.opacity(0.85) : muted)
            Text(amountLabel(sats))
                .font(.system(size: isShare ? 15 : 18, weight: .bold, design: .rounded))
                .foregroundStyle(highlight ? bitcoinOrange : primary)
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: isShare ? 11 : 12, weight: .medium, design: .rounded))
                .foregroundStyle(muted)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: highlight ? .trailing : .leading)
    }

    private func revealNow() {
        guard !isShare, !reduceMotion else {
            nowVisible = true
            return
        }
        nowVisible = false
        withAnimation(.easeOut(duration: 0.55).delay(0.08)) {
            nowVisible = true
        }
    }
}

struct UsdBtcComparisonChart: View {
    enum Style {
        case share
        case inApp
        case compact
    }

    let bills: [UsdBtcBillSeries]
    var style: Style = .share
    var colorNames: [String] = []
    var showsKey: Bool = true
    var plotHeight: CGFloat? = nil
    var onReorder: (([String]) -> Void)? = nil

    @State private var draggingName: String?

    private var isCompact: Bool { style == .compact }

    private var gridColor: Color {
        style == .share ? Color.white.opacity(0.08) : Color.secondary.opacity(0.22)
    }

    private var labelColor: Color {
        style == .share ? Color.white.opacity(0.42) : Color.secondary
    }

    private var resolvedPlotHeight: CGFloat {
        if let plotHeight { return plotHeight }
        switch style {
        case .share: return 140
        case .compact: return 72
        case .inApp: return 188
        }
    }

    private var plottedBill: UsdBtcBillSeries {
        BillBtcBacktest.combinedBillSeries(from: bills)
    }

    private var backtestLabel: String {
        BillBtcBacktest.backtestCaption(
            monthCount: BillBtcBacktest.backtestMonthSpan(from: plottedBill.months.map(\.month))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: style == .share ? 10 : (isCompact ? 0 : 14)) {
            if !isCompact {
                HStack(alignment: .firstTextBaseline) {
                    Text(style == .share ? "Bitcoin needed" : "Sats needed")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(labelColor)
                    Spacer(minLength: 8)
                    Text(backtestLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                }
            }
            chartCanvas
                .frame(maxWidth: .infinity)
                .frame(height: resolvedPlotHeight)
            if showsKey {
                chartKey
            }
        }
    }

    private var keyItems: [BillBtcBacktest.ChartKeyItem] {
        BillBtcBacktest.chartKeyItems(from: bills)
    }

    private var canReorder: Bool {
        style == .inApp && onReorder != nil && keyItems.count > 1
    }

    private var chartKey: some View {
        let items = keyItems
        let visibleItems = style == .share ? Array(items.prefix(3)) : items
        let overflow = items.count - visibleItems.count
        return Group {
            if !items.isEmpty {
                let rows = VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(visibleItems.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().opacity(style == .share ? 0.18 : 1)
                        }
                        keyRow(item)
                            .opacity(draggingName == item.name ? 0.55 : 1)
                            .modifier(UsdBtcKeyReorderModifier(
                                enabled: canReorder,
                                name: item.name,
                                items: items.map(\.name),
                                draggingName: $draggingName,
                                onReorder: onReorder
                            ))
                    }
                    if overflow > 0 {
                        Text("+\(overflow) more")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(labelColor)
                            .padding(.top, 6)
                    }
                    if canReorder {
                        Text("Hold a row to reorder")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                    }
                }
                if style == .inApp, items.count > 4 {
                    ScrollView {
                        rows
                    }
                    .frame(maxHeight: 240)
                    .scrollIndicators(.visible)
                } else {
                    rows
                }
            }
        }
    }

    private func keyRow(_ item: BillBtcBacktest.ChartKeyItem) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Capsule(style: .continuous)
                .fill(markerMuted)
                .frame(width: 3, height: style == .share ? 22 : 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: style == .share ? 13 : 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
                Text("\(BillBtcBacktest.compactUsd((item.monthlyUsd as NSDecimalNumber).doubleValue))/mo avg · \(BillBtcBacktest.actualDataCaption(actualMonths: item.actualMonths))")
                    .font(.system(size: style == .share ? 10 : 11, weight: .medium, design: .rounded))
                    .foregroundStyle(amountColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 8)
            Text(BillBtcBacktest.signedPercentLabel(
                BillBtcBacktest.BitcoinSpendChange(
                    percentLess: item.percentLess,
                    years: 1,
                    monthCount: 1
                )
            ))
            .font(.system(size: style == .share ? 13 : 15, weight: .semibold, design: .rounded))
            .foregroundStyle(item.percentLess >= 0 ? Color.green : Color.red.opacity(0.85))
            .monospacedDigit()
            .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.vertical, style == .share ? 4 : 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var markerMuted: Color {
        style == .share ? Color.white.opacity(0.28) : Color.secondary.opacity(0.45)
    }

    private var amountColor: Color {
        style == .share ? Color.white.opacity(0.55) : Color.secondary
    }

    private var nameColor: Color {
        style == .share ? Color.white.opacity(0.9) : Color.primary
    }

    private var chartCanvas: some View {
        Canvas { context, size in
            let datesAxis = Array(Set(plottedBill.months.map(\.month))).sorted()
            guard let line = BillBtcBacktest.indexedAverageLine(from: plottedBill.months),
                  datesAxis.count > 1 else { return }

            let values = line.sats
            let maxV = BillBtcBacktest.plotMax(values)
            let minV = 0.0
            let span = max(maxV - minV, 1)
            let leading: CGFloat = 4
            let trailing: CGFloat = isCompact ? 4 : 44
            let top: CGFloat = isCompact ? 6 : 8
            let bottom: CGFloat = isCompact ? 16 : 22
            let plot = CGRect(
                x: leading,
                y: top,
                width: size.width - leading - trailing,
                height: size.height - top - bottom
            )

            func xPosition(for date: Date) -> CGFloat {
                guard let index = datesAxis.firstIndex(of: date) else { return plot.minX }
                return plot.minX + plot.width * CGFloat(index) / CGFloat(max(datesAxis.count - 1, 1))
            }

            func point(date: Date, value: Double) -> CGPoint {
                CGPoint(
                    x: xPosition(for: date),
                    y: plot.maxY - plot.height * CGFloat((value - minV) / span)
                )
            }

            if isCompact {
                var baseline = Path()
                baseline.move(to: CGPoint(x: plot.minX, y: plot.maxY))
                baseline.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                context.stroke(baseline, with: .color(gridColor.opacity(0.55)), lineWidth: 1)
            } else {
                var grid = Path()
                let gridSteps = 4
                for step in 0...gridSteps {
                    let y = plot.maxY - plot.height * CGFloat(step) / CGFloat(gridSteps)
                    grid.move(to: CGPoint(x: plot.minX, y: y))
                    grid.addLine(to: CGPoint(x: plot.maxX, y: y))
                }
                context.stroke(grid, with: .color(gridColor), lineWidth: 1)
            }

            let points = zip(line.dates, values).map { point(date: $0, value: $1) }
            var area = Path()
            if let first = points.first, let last = points.last {
                area.move(to: CGPoint(x: first.x, y: plot.maxY))
                area.addLine(to: first)
                for p in points.dropFirst() { area.addLine(to: p) }
                area.addLine(to: CGPoint(x: last.x, y: plot.maxY))
                area.closeSubpath()
                context.fill(
                    area,
                    with: .linearGradient(
                        Gradient(colors: [
                            bitcoinOrange.opacity(style == .share ? 0.38 : 0.24),
                            bitcoinOrange.opacity(0.02)
                        ]),
                        startPoint: CGPoint(x: plot.midX, y: plot.minY),
                        endPoint: CGPoint(x: plot.midX, y: plot.maxY)
                    )
                )
            }

            var path = Path()
            if let first = points.first {
                path.move(to: first)
                for p in points.dropFirst() { path.addLine(to: p) }
            }
            context.stroke(
                path,
                with: .color(bitcoinOrange),
                style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
            )

            if let first = points.first {
                let dot = Path(ellipseIn: CGRect(x: first.x - 3.5, y: first.y - 3.5, width: 7, height: 7))
                context.fill(dot, with: .color(bitcoinOrange.opacity(0.55)))
            }
            if let last = points.last {
                let dot = Path(ellipseIn: CGRect(x: last.x - 4, y: last.y - 4, width: 8, height: 8))
                context.fill(dot, with: .color(bitcoinOrange))
            }

            if !isCompact {
                let gridSteps = 4
                for step in 0...gridSteps {
                    let value = minV + (maxV - minV) * Double(step) / Double(gridSteps)
                    let y = plot.maxY - plot.height * CGFloat(step) / CGFloat(gridSteps)
                    let resolved = context.resolve(
                        Text(style == .share ? BillBtcBacktest.compactBitcoinAxis(value) : BillBtcBacktest.compactSats(value))
                            .font(.caption2)
                            .foregroundColor(labelColor)
                    )
                    context.draw(resolved, at: CGPoint(x: size.width - 4, y: y), anchor: .trailing)
                }
            }

            let labels = yearLabels(from: datesAxis)
            for (xRatio, text) in labels {
                let resolved = context.resolve(
                    Text(text)
                        .font(.system(size: isCompact ? 9 : 10, weight: .medium, design: .rounded))
                        .foregroundColor(labelColor)
                )
                let x = plot.minX + plot.width * xRatio
                let anchor: UnitPoint = xRatio == 0 ? .bottomLeading : (xRatio == 1 ? .bottomTrailing : .bottom)
                context.draw(resolved, at: CGPoint(x: x, y: size.height - 6), anchor: anchor)
            }
        }
        .accessibilityLabel(style == .share ? "Backtest of Bitcoin needed over time" : "Backtest of sats needed over time")
    }

    private func yearLabels(from dates: [Date]) -> [(CGFloat, String)] {
        guard let first = dates.first, let last = dates.last else { return [] }
        let cal = Calendar.current
        let startYear = cal.component(.year, from: first)
        let endYear = cal.component(.year, from: last)
        if startYear == endYear {
            return [(0, String(startYear))]
        }
        if !isCompact, endYear - startYear >= 3 {
            let mid = startYear + (endYear - startYear) / 2
            return [(0, String(startYear)), (0.5, String(mid)), (1, String(endYear))]
        }
        return [(0, String(startYear)), (1, String(endYear))]
    }
}

private struct UsdBtcKeyReorderModifier: ViewModifier {
    let enabled: Bool
    let name: String
    let items: [String]
    @Binding var draggingName: String?
    var onReorder: (([String]) -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    draggingName = name
                    return NSItemProvider(object: name as NSString)
                }
                .onDrop(
                    of: [UTType.plainText],
                    delegate: UsdBtcKeyDropDelegate(
                        name: name,
                        items: items,
                        draggingName: $draggingName,
                        onReorder: onReorder
                    )
                )
        } else {
            content
        }
    }
}

private struct UsdBtcKeyDropDelegate: DropDelegate {
    let name: String
    let items: [String]
    @Binding var draggingName: String?
    var onReorder: (([String]) -> Void)?

    func dropEntered(info: DropInfo) {
        guard let draggingName, draggingName != name,
              let from = items.firstIndex(of: draggingName),
              let to = items.firstIndex(of: name),
              from != to else { return }
        var next = items
        next.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        onReorder?(next)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingName = nil
        return true
    }
}

struct UsdBtcActivityCard: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var reportsViewModel: ReportsViewModel
    let onOpen: () -> Void

    private var report: UsdBtcReportData? {
        guard let full = reportsViewModel.usdBtcReport else { return nil }
        return BillBtcBacktest.windowed(
            reportsViewModel.filteredUsdBtcReport(full),
            monthsBack: reportsViewModel.usdBtcMonthsBack
        )
    }

    private var previewBills: [UsdBtcBillSeries] {
        guard let report else { return [] }
        return [BillBtcBacktest.combinedMonthlySeries(from: report)]
    }

    private var legendNames: [String] {
        guard let report else { return [] }
        return reportsViewModel.orderedUsdBtcNames(report.bills.map(\.name))
    }

    private var billCount: Int { report?.bills.count ?? 0 }

    private var change: BillBtcBacktest.BitcoinSpendChange? {
        guard let report else { return nil }
        return BillBtcBacktest.storyChange(from: report)
    }

    private var averages: BillBtcBacktest.MonthlyAverages? {
        guard let report else { return nil }
        return BillBtcBacktest.storyAverages(from: report)
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                UsdBtcStoryHeadline(change: change, billCount: billCount, style: .inApp)
                if let averages {
                    Text("\(BillBtcBacktest.compactUsd((averages.monthlyUsd as NSDecimalNumber).doubleValue))/mo avg")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if !previewBills.isEmpty {
                    UsdBtcComparisonChart(
                        bills: previewBills,
                        style: .compact,
                        colorNames: legendNames,
                        showsKey: false,
                        plotHeight: 56
                    )
                }
                HStack(alignment: .center, spacing: 8) {
                    billLegend
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(activitySnapshotChrome)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bitcoin Deflation")
        .accessibilityHint("Opens Bitcoin Deflation")
    }

    private var billLegend: some View {
        let names = legendNames
        let visible = Array(names.prefix(4))
        return HStack(spacing: 10) {
            ForEach(visible, id: \.self) { name in
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.secondary.opacity(0.45))
                        .frame(width: 6, height: 6)
                    Text(name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if names.count > 4 {
                Text("+\(names.count - 4)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(names.isEmpty ? "Bitcoin bills" : names.joined(separator: ", "))
    }

    private var activitySnapshotChrome: some View {
        let backgroundColor: Color = colorScheme == .dark
            ? Color.black.opacity(0.82)
            : Color(.secondarySystemBackground)
        let borderColor: Color = colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.06)
        return RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(borderColor)
            )
    }
}
