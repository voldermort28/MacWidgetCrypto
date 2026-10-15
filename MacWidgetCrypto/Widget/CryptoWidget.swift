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
            do {
                let trackedIds = PortfolioManager.shared.trackedCoinIds
                let coins = try await CryptoService.shared.fetchCoins(for: trackedIds)
                let entry = makeEntry(from: coins, family: context.family)
                completion(entry)
            } catch {
                let cached = CryptoService.shared.getCachedCoins()
                if !cached.isEmpty {
                    completion(makeEntry(from: cached, family: context.family))
                } else {
                    completion(placeholder(in: context))
                }
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        Task {
            let entry: SimpleEntry

            do {
                let trackedIds = PortfolioManager.shared.trackedCoinIds
                let coins = try await CryptoService.shared.fetchCoins(for: trackedIds)
                entry = makeEntry(from: coins, family: context.family)
            } catch {
                let cached = CryptoService.shared.getCachedCoins()
                if !cached.isEmpty {
                    entry = makeEntry(from: cached, family: context.family)
                } else {
                    entry = placeholder(in: context)
                }
            }

            let currentHour = Calendar.current.component(.hour, from: Date())
            let isActiveHours = (7..<23).contains(currentHour)
            let refreshMinutes = isActiveHours ? 15 : 60

            let nextUpdate = Calendar.current.date(byAdding: .minute, value: refreshMinutes, to: Date()) ?? Date().addingTimeInterval(Double(refreshMinutes * 60))
            completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
        }
    }

    private func makeEntry(from coins: [Coin], family: WidgetFamily = .systemMedium) -> SimpleEntry {
        let portfolio = PortfolioManager.shared
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
        let snapshot = PortfolioSnapshotBuilder.makeSnapshot(from: coins, portfolio: portfolio, maxCoins: maxCoins, fallbackToTopCoins: false)

        return SimpleEntry(
            date: Date(),
            coins: snapshot.displayCoins,
            totalHistory: snapshot.totalHistory,
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
        VStack(alignment: .leading, spacing: 4) {
            headerView

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.showsRealHoldings ? "Tổng danh mục" : "MacCrypto")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(entry.portfolioValue.formattedCurrency())
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            if !entry.totalHistory.isEmpty {
                SparklineView(
                    data: entry.totalHistory,
                    lineColor: accentColor,
                    fillColor: accentColor
                )
                .frame(height: 36)
            }

            if entry.coins.isEmpty || !entry.showsRealHoldings {
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

                if entry.coins.isEmpty || !entry.showsRealHoldings {
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

                Text(entry.portfolioValue.formattedCurrency())
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if !entry.totalHistory.isEmpty {
                    SparklineView(
                        data: entry.totalHistory,
                        lineColor: accentColor,
                        fillColor: accentColor
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                Text(entry.showsRealHoldings ? "Đồng bộ từ app" : "Mở app để thêm coin")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                Text(entry.portfolioValue.formattedCurrency())
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            if !entry.totalHistory.isEmpty {
                SparklineView(
                    data: entry.totalHistory,
                    lineColor: accentColor,
                    fillColor: accentColor
                )
                .frame(height: 42)
            }

            Divider()
                .background(Color.white.opacity(0.15))

            if entry.coins.isEmpty || !entry.showsRealHoldings {
                emptyState
            } else {
                VStack(spacing: 5) {
                    ForEach(entry.coins.prefix(6)) { coin in
                        detailedCoinRow(for: coin)
                    }
                }
            }

            Spacer(minLength: 0)
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
        VStack(alignment: .center, spacing: 4) {
            Image(systemName: "chart.pie")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
            Text("Chưa có coin trong danh mục")
                .font(.caption.weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Mở app để nhập số lượng coin")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 4)
    }

    private func compactCoinRow(for coin: Coin) -> some View {
        HStack(spacing: 6) {
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

            VStack(alignment: .leading, spacing: 1) {
                Text(coin.symbol.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
                Text(coin.name)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let prices = coin.sparklineIn7D?.price {
                SparklineView(
                    data: prices,
                    lineColor: coin.priceChangePercentage24H >= 0 ? .green : .red,
                    fillColor: coin.priceChangePercentage24H >= 0 ? .green : .red
                )
                .frame(width: 40, height: 18)
            }

            VStack(alignment: .trailing, spacing: 1) {
                let amount = PortfolioManager.shared.getAmount(for: coin.id)

                if amount > 0 {
                    Text("\(amount.formattedAmount()) \(coin.symbol.uppercased())")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.white)
                }

                HStack(spacing: 4) {
                    Text(coin.formattedPrice)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.85))

                    Text(coin.formattedChange)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(coin.priceChangePercentage24H >= 0 ? .green : .red)
                }
            }
        }
    }

    private func coinBadge(for coin: Coin) -> some View {
        Circle()
            .fill(badgeColor(for: coin.symbol))
            .frame(width: 22, height: 22)
            .overlay(
                Text(String(coin.symbol.uppercased().prefix(1)))
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
            )
    }

    private func badgeColor(for symbol: String) -> Color {
        switch symbol.lowercased() {
        case "btc": return Color.orange
        case "eth": return Color.blue
        case "sol": return Color.purple
        case "usdt": return Color.green
        case "bnb": return Color.yellow
        case "xrp": return Color.teal
        case "doge": return Color.orange.opacity(0.8)
        case "ada": return Color.blue.opacity(0.8)
        default: return Color.gray.opacity(0.7)
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
