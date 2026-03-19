import SwiftUI

struct SparklineView: View {
    let data: [Double]
    let lineColor: Color
    let fillColor: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.03))

                if data.count > 1 {
                    fillPath(in: geometry.size)
                        .fill(
                            LinearGradient(
                                colors: [fillColor.opacity(0.28), fillColor.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    linePath(in: geometry.size)
                        .stroke(lineColor, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func linePath(in size: CGSize) -> Path {
        Path { path in
            let points = normalizedPoints(in: size)
            guard let first = points.first else { return }

            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
        }
    }

    private func fillPath(in size: CGSize) -> Path {
        Path { path in
            let points = normalizedPoints(in: size)
            guard let first = points.first, let last = points.last else { return }

            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }

    private func normalizedPoints(in size: CGSize) -> [CGPoint] {
        guard let minValue = data.min(), let maxValue = data.max(), !data.isEmpty else {
            return []
        }

        let yRange = max(maxValue - minValue, 0.0001)

        return data.enumerated().map { index, value in
            let xProgress = data.count == 1 ? 0 : CGFloat(index) / CGFloat(data.count - 1)
            let yProgress = CGFloat((value - minValue) / yRange)

            return CGPoint(
                x: xProgress * size.width,
                y: size.height - (yProgress * size.height)
            )
        }
    }
}
