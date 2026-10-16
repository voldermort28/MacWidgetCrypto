import SwiftUI

struct SparklineView: View {
    let data: [Double]
    var baselinePrice: Double? = nil
    let lineColor: Color
    let fillColor: Color
    var showBaseline: Bool = true

    var body: some View {
        GeometryReader { geometry in
            let points = smoothedData
            if points.count > 1 {
                let baseline = baselinePrice ?? points.first ?? 0.0
                let minVal = min(points.min() ?? baseline, baseline)
                let maxVal = max(points.max() ?? baseline, baseline)
                let range = max(maxVal - minVal, 0.00001)

                // Add vertical padding so the peaks and baseline don't clip
                let padMin = minVal - range * 0.08
                let padMax = maxVal + range * 0.08
                let totalRange = max(padMax - padMin, 0.00001)

                let baselineY = geometry.size.height - CGFloat((baseline - padMin) / totalRange) * geometry.size.height

                ZStack {
                    // 1. Dashed Horizontal Baseline (Apple Stocks signature)
                    if showBaseline {
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: baselineY))
                            path.addLine(to: CGPoint(x: geometry.size.width, y: baselineY))
                        }
                        .stroke(
                            lineColor.opacity(0.40),
                            style: StrokeStyle(lineWidth: 1.0, dash: [2.5, 2.5])
                        )
                    }

                    // 2. Soft Gradient Shadow under the curve
                    fillPath(points: points, padMin: padMin, totalRange: totalRange, in: geometry.size)
                        .fill(
                            LinearGradient(
                                colors: [fillColor.opacity(0.32), fillColor.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // 3. Sharp Price Curve Line
                    linePath(points: points, padMin: padMin, totalRange: totalRange, in: geometry.size)
                        .stroke(
                            lineColor,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                        )
                }
            }
        }
    }

    private var smoothedData: [Double] {
        guard data.count > 1 else { return data }
        if data.count >= 20 { return data }

        // Linear interpolation preserves sharp peaks and market volatility (gấp khúc chi tiết)
        var result: [Double] = []
        let targetCount = 24
        for i in 0..<targetCount {
            let t = Double(i) / Double(targetCount - 1) * Double(data.count - 1)
            let lowerIndex = Int(floor(t))
            let upperIndex = min(lowerIndex + 1, data.count - 1)
            let fraction = t - Double(lowerIndex)
            let interpolated = data[lowerIndex] * (1.0 - fraction) + data[upperIndex] * fraction
            result.append(interpolated)
        }
        return result
    }

    private func linePath(points: [Double], padMin: Double, totalRange: Double, in size: CGSize) -> Path {
        Path { path in
            let coords = normalizedCoords(points: points, padMin: padMin, totalRange: totalRange, in: size)
            guard let first = coords.first else { return }

            path.move(to: first)
            for pt in coords.dropFirst() {
                path.addLine(to: pt)
            }
        }
    }

    private func fillPath(points: [Double], padMin: Double, totalRange: Double, in size: CGSize) -> Path {
        Path { path in
            let coords = normalizedCoords(points: points, padMin: padMin, totalRange: totalRange, in: size)
            guard let first = coords.first, let last = coords.last else { return }

            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            for pt in coords.dropFirst() {
                path.addLine(to: pt)
            }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }

    private func normalizedCoords(points: [Double], padMin: Double, totalRange: Double, in size: CGSize) -> [CGPoint] {
        let count = points.count
        guard count > 1 else { return [] }

        return points.enumerated().map { index, val in
            let x = size.width * CGFloat(index) / CGFloat(count - 1)
            let y = size.height - CGFloat((val - padMin) / totalRange) * size.height
            return CGPoint(x: x, y: y)
        }
    }
}
