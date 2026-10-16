import SwiftUI

struct DetailChartView: View {
    let klines: [KlinePoint]
    let selectedTimeframe: String
    let isPositive: Bool
    var baselinePrice: Double? = nil
    @Binding var hoveredPoint: KlinePoint?

    @State private var dragX: CGFloat? = nil

    private var stockGreen: Color { Color(red: 0.19, green: 0.82, blue: 0.35) }
    private var stockRed: Color { Color(red: 1.0, green: 0.27, blue: 0.23) }
    private var accentColor: Color { isPositive ? stockGreen : stockRed }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let w = geometry.size.width
                let h = geometry.size.height
                
                // Reserving right margin for Y-axis labels and bottom margin for X-axis labels
                let yAxisWidth: CGFloat = 65
                let xAxisHeight: CGFloat = 22
                let chartW = max(w - yAxisWidth, 10)
                let chartH = max(h - xAxisHeight - 40, 10) // 40px for volume bars
                
                if klines.count > 1 {
                    let closes = klines.map(\.close)
                    let minClose = closes.min() ?? 0
                    let maxClose = closes.max() ?? 1
                    let baseline = baselinePrice ?? closes.first ?? minClose
                    let overallMin = min(minClose, baseline)
                    let overallMax = max(maxClose, baseline)
                    let range = max(overallMax - overallMin, 0.00001)

                    // Volume calculations
                    let volumes = klines.map(\.volume)
                    let maxVol = max(volumes.max() ?? 1.0, 0.0001)

                    ZStack(alignment: .topLeading) {
                        // 1. Horizontal Grid Lines & Right Y-Axis Price Labels
                        horizontalGridAndLabels(chartW: chartW, chartH: chartH, w: w, minVal: overallMin, maxVal: overallMax, range: range)

                        // 2. Vertical Grid Lines & Bottom X-Axis Time Labels
                        verticalGridAndLabels(chartW: chartW, chartH: chartH, h: h, xAxisHeight: xAxisHeight)

                        // 3. Dashed Baseline (Apple Stocks signature)
                        dashedBaseline(chartW: chartW, chartH: chartH, baseline: baseline, minVal: overallMin, range: range)

                        // 4. Gradient Fill under the line
                        gradientFillPath(chartW: chartW, chartH: chartH, minVal: overallMin, range: range)
                            .fill(
                                LinearGradient(
                                    colors: [accentColor.opacity(0.28), accentColor.opacity(0.0)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // 5. Sharp Volatility Polyline (Gấp khúc chi tiết)
                        sharpLinePath(chartW: chartW, chartH: chartH, minVal: overallMin, range: range)
                            .stroke(
                                accentColor,
                                style: StrokeStyle(lineWidth: 2.0, lineCap: .round, lineJoin: .round)
                            )

                        // 6. Volume Histogram Bars (Underneath the line chart)
                        volumeBarsView(chartW: chartW, chartH: chartH, maxVol: maxVol)

                        // 7. Interactive Crosshair & Scrubbing Indicator
                        if let currentX = dragX, let hovered = hoveredPoint {
                            crosshairView(currentX: currentX, chartH: chartH, chartW: chartW, hovered: hovered, minVal: overallMin, range: range)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let locX = max(0, min(value.location.x, chartW))
                                self.dragX = locX
                                let fraction = locX / chartW
                                let index = Int(round(fraction * CGFloat(klines.count - 1)))
                                let safeIndex = max(0, min(index, klines.count - 1))
                                self.hoveredPoint = klines[safeIndex]
                            }
                            .onEnded { _ in
                                self.dragX = nil
                                self.hoveredPoint = nil
                            }
                    )
                } else {
                    VStack {
                        Spacer()
                        ProgressView("Đang tải dữ liệu nến Binance...")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    // MARK: - Subviews & Paths
    private func horizontalGridAndLabels(chartW: CGFloat, chartH: CGFloat, w: CGFloat, minVal: Double, maxVal: Double, range: Double) -> some View {
        let levels = 4
        return Group {
            ForEach(0...levels, id: \.self) { i in
                let y = chartH * CGFloat(i) / CGFloat(levels)
                let price = maxVal - (range / Double(levels)) * Double(i)

                ZStack {
                    // Horizontal line
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: chartW, y: y))
                    }
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)

                    // Right price label
                    Text(formatPrice(price))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.60))
                        .position(x: chartW + 35, y: y)
                }
            }
        }
    }

    private func verticalGridAndLabels(chartW: CGFloat, chartH: CGFloat, h: CGFloat, xAxisHeight: CGFloat) -> some View {
        let count = min(klines.count, 6)
        return Group {
            if count > 1 {
                ForEach(0..<count, id: \.self) { idx in
                    let fraction = CGFloat(idx) / CGFloat(count - 1)
                    let x = chartW * fraction
                    let klineIndex = Int(round(fraction * CGFloat(klines.count - 1)))
                    let point = klines[min(max(klineIndex, 0), klines.count - 1)]

                    ZStack {
                        // Vertical grid line
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: chartH))
                        }
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)

                        // Bottom time label
                        Text(formatDate(point.time))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.65))
                            .position(x: x, y: h - 10)
                    }
                }
            }
        }
    }

    private func dashedBaseline(chartW: CGFloat, chartH: CGFloat, baseline: Double, minVal: Double, range: Double) -> some View {
        let baseY = chartH - CGFloat((baseline - minVal) / range) * chartH
        return Path { path in
            path.move(to: CGPoint(x: 0, y: baseY))
            path.addLine(to: CGPoint(x: chartW, y: baseY))
        }
        .stroke(
            Color.white.opacity(0.30),
            style: StrokeStyle(lineWidth: 1.0, dash: [4, 4])
        )
    }

    private func sharpLinePath(chartW: CGFloat, chartH: CGFloat, minVal: Double, range: Double) -> Path {
        Path { path in
            guard let first = klines.first else { return }
            let firstY = chartH - CGFloat((first.close - minVal) / range) * chartH
            path.move(to: CGPoint(x: 0, y: firstY))

            for (index, pt) in klines.enumerated().dropFirst() {
                let x = chartW * CGFloat(index) / CGFloat(klines.count - 1)
                let y = chartH - CGFloat((pt.close - minVal) / range) * chartH
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
    }

    private func gradientFillPath(chartW: CGFloat, chartH: CGFloat, minVal: Double, range: Double) -> Path {
        Path { path in
            guard let first = klines.first else { return }
            let firstY = chartH - CGFloat((first.close - minVal) / range) * chartH

            path.move(to: CGPoint(x: 0, y: chartH))
            path.addLine(to: CGPoint(x: 0, y: firstY))

            for (index, pt) in klines.enumerated().dropFirst() {
                let x = chartW * CGFloat(index) / CGFloat(klines.count - 1)
                let y = chartH - CGFloat((pt.close - minVal) / range) * chartH
                path.addLine(to: CGPoint(x: x, y: y))
            }

            path.addLine(to: CGPoint(x: chartW, y: chartH))
            path.closeSubpath()
        }
    }

    private func volumeBarsView(chartW: CGFloat, chartH: CGFloat, maxVol: Double) -> some View {
        let volTop = chartH + 6
        let volHeight: CGFloat = 30
        let barCount = CGFloat(klines.count)
        let barWidth = max((chartW / barCount) - 1.5, 1.5)

        return Group {
            ForEach(0..<klines.count, id: \.self) { idx in
                let pt = klines[idx]
                let x = chartW * CGFloat(idx) / CGFloat(klines.count - 1)
                let h = max(CGFloat(pt.volume / maxVol) * volHeight, 2)
                let isUp = pt.close >= pt.open
                let barColor = isUp ? stockGreen.opacity(0.40) : stockRed.opacity(0.40)

                Rectangle()
                    .fill(barColor)
                    .frame(width: barWidth, height: h)
                    .position(x: x, y: volTop + volHeight - (h / 2.0))
            }
        }
    }

    private func crosshairView(currentX: CGFloat, chartH: CGFloat, chartW: CGFloat, hovered: KlinePoint, minVal: Double, range: Double) -> some View {
        let y = chartH - CGFloat((hovered.close - minVal) / range) * chartH

        return ZStack {
            // Vertical cursor line
            Path { path in
                path.move(to: CGPoint(x: currentX, y: 0))
                path.addLine(to: CGPoint(x: currentX, y: chartH + 36))
            }
            .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))

            // Circle indicator at intersection
            Circle()
                .fill(accentColor)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .position(x: currentX, y: y)
        }
    }

    private func formatPrice(_ val: Double) -> String {
        if val >= 1000 {
            return val.formattedCurrency(maxDecimals: 0)
        } else if val >= 1 {
            return val.formattedCurrency(maxDecimals: 2)
        } else {
            return String(format: "US$%.4f", val)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch selectedTimeframe {
        case "1D":
            formatter.dateFormat = "HH:mm"
        case "1W":
            formatter.dateFormat = "EEE"
        case "1M":
            formatter.dateFormat = "dd/MM"
        case "6M", "1Y":
            formatter.dateFormat = "MMM"
        case "ALL":
            formatter.dateFormat = "yyyy"
        default:
            formatter.dateFormat = "dd/MM"
        }
        return formatter.string(from: date)
    }
}
