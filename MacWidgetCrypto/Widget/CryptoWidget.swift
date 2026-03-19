import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(
            date: Date(),
            coins: MockData.coins,
            totalHistory: MockData.history,
            portfolioValue: MockData.history.last ?? 0,
            showsRealHoldings: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        Task {
            let entry: SimpleEntry

            do {
                let coins = try await CryptoService.shared.fetchCoins()
                entry = makeEntry(from: coins)
            } catch {
                entry = placeholder(in: context)
            }

            let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func makeEntry(from coins: [Coin]) -> SimpleEntry {
        let portfolio = PortfolioManager.shared
        let heldCoins = coins.filter { portfolio.getAmount(for: $0.id) > 0 }
        let showsRealHoldings = !heldCoins.isEmpty
        let displayCoins = Array((showsRealHoldings ? heldCoins : coins).prefix(4))
        let totalHistory = buildTotalHistory(from: displayCoins, portfolio: portfolio, showsRealHoldings: showsRealHoldings)

        let portfolioValue: Double
        if let lastValue = totalHistory.last {
            portfolioValue = lastValue
        } else {
            portfolioValue = displayCoins.reduce(0) { partialResult, coin in
                let amount = showsRealHoldings ? portfolio.getAmount(for: coin.id) : 1
                return partialResult + (coin.currentPrice * amount)
            }
        }

        return SimpleEntry(
            date: Date(),
            coins: displayCoins,
            totalHistory: totalHistory,
            portfolioValue: portfolioValue,
            showsRealHoldings: showsRealHoldings
        )
    }

    private func buildTotalHistory(from coins: [Coin], portfolio: PortfolioManager, showsRealHoldings: Bool) -> [Double] {
        guard let maxPointCount = coins.compactMap({ $0.sparklineIn7D?.price.count }).max(), maxPointCount > 0 else {
            return []
        }

        var totalHistory = Array(repeating: 0.0, count: maxPointCount)

        for coin in coins {
            guard let prices = coin.sparklineIn7D?.price, prices.count == maxPointCount else {
                continue
            }

            let amount = showsRealHoldings ? portfolio.getAmount(for: coin.id) : 1.0
            for index in prices.indices {
                totalHistory[index] += prices[index] * amount
            }
        }

        return totalHistory
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let coins: [Coin]
    let totalHistory: [Double]
    let portfolioValue: Double
    let showsRealHoldings: Bool
}

struct CryptoWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SimpleEntry

    private var accentColor: Color {
        guard let first = entry.totalHistory.first, let last = entry.totalHistory.last else {
            return .green
        }

        return last >= first ? .green : .red
    }

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallWidget
            default:
                mediumWidget
            }
        }
        .padding()
        .background(backgroundGradient)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.10, green: 0.12, blue: 0.18),
                Color(red: 0.03, green: 0.04, blue: 0.07)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerView

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.showsRealHoldings ? "Portfolio Value" : "Market Snapshot")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(entry.portfolioValue.formattedCurrency())
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            SparklineView(
                data: entry.totalHistory,
                lineColor: accentColor,
                fillColor: accentColor
            )
            .frame(height: 56)

            if entry.coins.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.coins.prefix(2)) { coin in
                        compactCoinRow(for: coin)
                    }
                }
            }
        }
    }

    private var mediumWidget: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                headerView

                if entry.coins.isEmpty {
                    emptyState
                } else {
                    ForEach(entry.coins.prefix(4)) { coin in
                        detailedCoinRow(for: coin)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(entry.showsRealHoldings ? "Total Portfolio" : "Top Coins Basket")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(entry.portfolioValue.formattedCurrency())
                    .font(.title2.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                SparklineView(
                    data: entry.totalHistory,
                    lineColor: accentColor,
                    fillColor: accentColor
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(entry.showsRealHoldings ? "Synced from app holdings" : "Add holdings in the app to personalize")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Crypto Widget")
                    .font(.headline)
                    .foregroundColor(.white)
                Text(entry.showsRealHoldings ? "Your tracked assets" : "Live market overview")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No data available")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
            Text("Open the app and refresh prices to populate the widget.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactCoinRow(for coin: Coin) -> some View {
        HStack(spacing: 8) {
            coinBadge(for: coin)

            Text(coin.symbol.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)

            Spacer(minLength: 0)

            Text(coin.formattedChange)
                .font(.caption2.weight(.semibold))
                .foregroundColor(coin.priceChangePercentage24H >= 0 ? .green : .red)
        }
    }

    private func detailedCoinRow(for coin: Coin) -> some View {
        HStack(spacing: 8) {
            coinBadge(for: coin)

            VStack(alignment: .leading, spacing: 2) {
                Text(coin.symbol.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                Text(coin.name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let prices = coin.sparklineIn7D?.price {
                SparklineView(
                    data: prices,
                    lineColor: coin.priceChangePercentage24H >= 0 ? .green : .red,
                    fillColor: coin.priceChangePercentage24H >= 0 ? .green : .red
                )
                .frame(width: 42, height: 22)
            }

            VStack(alignment: .trailing, spacing: 2) {
                let amount = PortfolioManager.shared.getAmount(for: coin.id)

                if entry.showsRealHoldings {
                    Text("\(amount.formattedAmount()) \(coin.symbol.uppercased())")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                }

                Text(coin.formattedPrice)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))

                Text(coin.formattedChange)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(coin.priceChangePercentage24H >= 0 ? .green : .red)
            }
        }
    }

    private func coinBadge(for coin: Coin) -> some View {
        Circle()
            .fill(Color.orange.opacity(0.85))
            .frame(width: 22, height: 22)
            .overlay(
                Text(String(coin.symbol.uppercased().prefix(1)))
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.black)
            )
    }
}

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

@main
struct CryptoWidget: Widget {
    let kind = "CryptoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CryptoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Crypto Portfolio")
        .description("Track crypto prices and your holdings from the Home Screen or Desktop.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct MockData {
    static let coins = [
        Coin(
            id: "bitcoin",
            symbol: "btc",
            name: "Bitcoin",
            currentPrice: 95431,
            priceChangePercentage24H: 4.4,
            sparklineIn7D: SparklineData(price: [93500, 93820, 94210, 94550, 94900, 95220, 95431])
        ),
        Coin(
            id: "ethereum",
            symbol: "eth",
            name: "Ethereum",
            currentPrice: 3410,
            priceChangePercentage24H: 2.1,
            sparklineIn7D: SparklineData(price: [3280, 3300, 3325, 3350, 3378, 3395, 3410])
        )
    ]

    static let history = [10250, 10400, 10320, 10640, 10710, 10890, 10980]
}
