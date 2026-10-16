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
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }

        Task {
            PortfolioManager.shared.reloadHoldings()
            let trackedIds = PortfolioManager.shared.trackedCoinIds
            var coins = (try? await CryptoService.shared.fetchCoins(for: trackedIds)) ?? []
            if coins.isEmpty {
                coins = CryptoService.shared.getCachedCoins()
            }
            if coins.isEmpty {
                coins = MockData.coins
            }
            completion(makeEntry(from: coins, family: context.family))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        Task {
            PortfolioManager.shared.reloadHoldings()
            let trackedIds = PortfolioManager.shared.trackedCoinIds
            var coins = (try? await CryptoService.shared.fetchCoins(for: trackedIds)) ?? []
            if coins.isEmpty {
                coins = CryptoService.shared.getCachedCoins()
            }
            if coins.isEmpty {
                coins = MockData.coins
            }
            let entry = makeEntry(from: coins, family: context.family)

            // Background update policy: 30 minutes interval
            let refreshMinutes = 30
            let nextUpdate = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: Date()) ?? Date().addingTimeInterval(Double(refreshMinutes * 60))
            AppLogger.info("Widget cập nhật dữ liệu. Lần tự động cập nhật ngầm tiếp theo: \(refreshMinutes) phút nữa.")
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func makeEntry(from coins: [Coin], family: WidgetFamily = .systemMedium) -> SimpleEntry {
        let portfolio = PortfolioManager.shared
        portfolio.reloadHoldings()
        let maxCoins: Int
        switch family {
        case .systemSmall:
            maxCoins = 2
        case .systemMedium:
            maxCoins = 3
        case .systemLarge:
            maxCoins = 6
        @unknown default:
            maxCoins = 6
        }
        let safeCoins = coins.isEmpty ? MockData.coins : coins
        let snapshot = PortfolioSnapshotBuilder.makeSnapshot(from: safeCoins, portfolio: portfolio, maxCoins: maxCoins, fallbackToTopCoins: true)
        let displayCoins = snapshot.displayCoins.isEmpty ? Array(safeCoins.prefix(maxCoins)) : snapshot.displayCoins

        return SimpleEntry(
            date: Date(),
            coins: displayCoins,
            totalHistory: snapshot.totalHistory.isEmpty ? MockData.history : snapshot.totalHistory,
            portfolioValue: snapshot.portfolioValue,
            showsRealHoldings: snapshot.showsRealHoldings
        )
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
            case .systemLarge:
                largeWidget
            default:
                mediumWidget
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .widgetContainerBackground(backgroundGradient)
    }

    private var backgroundGradient: some View {
        Color(red: 0.10, green: 0.10, blue: 0.12)
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 4) {
            headerView

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.showsRealHoldings ? "Tổng danh mục" : "MacCrypto")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(entry.showsRealHoldings ? entry.portfolioValue.formattedCurrency() : "\(entry.coins.count) Coin theo dõi")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if !entry.totalHistory.isEmpty {
                SparklineView(
                    data: entry.totalHistory,
                    baselinePrice: entry.totalHistory.first,
                    lineColor: accentColor,
                    fillColor: accentColor,
                    showBaseline: true
                )
                .frame(height: 36)
            }

            if entry.coins.isEmpty {
                emptyState
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(entry.coins.prefix(2)) { coin in
                        compactCoinRow(for: coin)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    private var mediumWidget: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                headerView

                if entry.coins.isEmpty {
                    emptyState
                } else {
                    ForEach(entry.coins.prefix(3)) { coin in
                        detailedCoinRow(for: coin)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.showsRealHoldings ? "Tổng giá trị" : "MacCrypto")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(entry.showsRealHoldings ? entry.portfolioValue.formattedCurrency() : "\(entry.coins.count) Coin theo dõi")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if !entry.totalHistory.isEmpty {
                    SparklineView(
                        data: entry.totalHistory,
                        baselinePrice: entry.totalHistory.first,
                        lineColor: accentColor,
                        fillColor: accentColor,
                        showBaseline: true
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Text(entry.showsRealHoldings ? "Đồng bộ từ app" : "Binance Realtime")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var largeWidget: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crypto Portfolio")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(entry.showsRealHoldings ? "Theo dõi tài sản" : "Tổng quan danh mục")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 4)
                Text(entry.showsRealHoldings ? entry.portfolioValue.formattedCurrency() : "\(entry.coins.count) Coin theo dõi")
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.bottom, 4)

            // Biểu đồ tổng giá trị ví (Total Portfolio Chart with Dashed Baseline)
            if !entry.totalHistory.isEmpty {
                SparklineView(
                    data: entry.totalHistory,
                    baselinePrice: entry.totalHistory.first,
                    lineColor: accentColor,
                    fillColor: accentColor,
                    showBaseline: true
                )
                .frame(height: 38)
                .padding(.bottom, 4)
            }

            Divider()
                .background(Color.white.opacity(0.12))

            if entry.coins.isEmpty {
                emptyState
            } else {
                let displayCoins = Array(entry.coins.prefix(5))
                ForEach(0..<displayCoins.count, id: \.self) { index in
                    if index > 0 {
                        Divider()
                            .background(Color.white.opacity(0.12))
                    }
                    detailedCoinRow(for: displayCoins[index])
                        .frame(maxHeight: .infinity)
                }
            }
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Crypto Widget")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Text(entry.showsRealHoldings ? "Tài sản của bạn" : "MacCrypto")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(MockData.coins.prefix(2)) { coin in
                compactCoinRow(for: coin)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compactCoinRow(for coin: Coin) -> some View {
        let isPositive = coin.priceChangePercentage24H >= 0
        let stockRed = Color(red: 1.0, green: 0.27, blue: 0.23)
        let stockGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
        let accent = isPositive ? stockGreen : stockRed

        return HStack(spacing: 4) {
            Image(systemName: isPositive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(accent)

            Text(coin.symbol.uppercased())
                .font(.caption.weight(.bold))
                .foregroundColor(.white)

            Spacer(minLength: 0)

            if let prices = coin.sparklineIn7D?.price, prices.count > 1 {
                SparklineView(
                    data: prices,
                    baselinePrice: prices.first,
                    lineColor: accent,
                    fillColor: accent,
                    showBaseline: true
                )
                .frame(width: 42, height: 16)
            }

            Text(coin.formattedPrice)
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
        }
    }

    private func detailedCoinRow(for coin: Coin) -> some View {
        let isPositive = coin.priceChangePercentage24H >= 0
        let stockRed = Color(red: 1.0, green: 0.27, blue: 0.23)   // Apple Stock Red #FF453A
        let stockGreen = Color(red: 0.19, green: 0.82, blue: 0.35) // Apple Stock Green #30D158
        let accent = isPositive ? stockGreen : stockRed
        let amount = PortfolioManager.shared.getAmount(for: coin.id)

        return HStack(alignment: .center, spacing: 6) {
            // 1. Left Column: Direction arrow + Symbol-USD, Full Name + Holding amount
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: isPositive ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(accent)

                    Text("\(coin.symbol.uppercased())-USD")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(coin.name)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if amount > 0 {
                        Text("• \(amount.formattedAmount())")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 2. Middle Column: Apple Stocks Sparkline with Dashed Baseline
            if let prices = coin.sparklineIn7D?.price, prices.count > 1 {
                SparklineView(
                    data: prices,
                    baselinePrice: prices.first,
                    lineColor: accent,
                    fillColor: accent,
                    showBaseline: true
                )
                .frame(width: 68, height: 26)
            } else {
                Spacer().frame(width: 68)
            }

            // 3. Right Column: Bold Price on top, Change on bottom
            VStack(alignment: .trailing, spacing: 2) {
                Text(coin.formattedPrice)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(coin.formattedChange)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(accent)
                    .lineLimit(1)
            }
            .frame(minWidth: 65, alignment: .trailing)
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 3)
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
            image: "https://assets.coingecko.com/coins/images/1/small/bitcoin.png",
            currentPrice: 95431,
            priceChangePercentage24H: 4.4,
            sparklineIn7D: SparklineData(price: [93500, 93820, 94210, 94550, 94900, 95220, 95431])
        ),
        Coin(
            id: "ethereum",
            symbol: "eth",
            name: "Ethereum",
            image: "https://assets.coingecko.com/coins/images/279/small/ethereum.png",
            currentPrice: 3410,
            priceChangePercentage24H: 2.1,
            sparklineIn7D: SparklineData(price: [3280, 3300, 3325, 3350, 3378, 3395, 3410])
        )
    ]

    static let history = [10250.0, 10400.0, 10320.0, 10640.0, 10710.0, 10890.0, 10980.0]
}

extension View {
    func widgetContainerBackground<B: View>(_ backgroundView: B) -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            return AnyView(self.containerBackground(for: .widget) { backgroundView })
        } else {
            return AnyView(self.background(backgroundView))
        }
        #elseif os(macOS)
        if #available(macOS 14.0, *) {
            return AnyView(self.containerBackground(for: .widget) { backgroundView })
        } else {
            return AnyView(self.background(backgroundView))
        }
        #else
        return AnyView(self.background(backgroundView))
        #endif
    }
}
