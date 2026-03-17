import WidgetKit
import SwiftUI
import Charts

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), coins: [], totalHistory: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        // Preview snapshot
        let entry = SimpleEntry(date: Date(), coins: MockData.coins, totalHistory: MockData.history)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        Task {
            do {
                let coins = try await CryptoService.shared.fetchCoins()
                let portfolio = PortfolioManager.shared
                
                // Filter only coins user has > 0 or top 5 if none
                var displayCoins = coins.filter { portfolio.getAmount(for: $0.id) > 0 }
                if displayCoins.isEmpty {
                    displayCoins = Array(coins.prefix(5))
                }
                
                // Calculate Total History based on Sparklines
                // Assuming all sparklines have same length (CoinGecko usually 168 hours = 7 days)
                var totalHistory: [Double] = []
                if let first = displayCoins.first?.sparklineIn7D?.price {
                    let count = first.count
                    totalHistory = Array(repeating: 0.0, count: count)
                    
                    for coin in displayCoins {
                        let amount = portfolio.getAmount(for: coin.id)
                        // If no amount (displaying top 5 free), assume amount 1 for viz or just 0?
                        // If user has no coins, chart might be flat 0. Let's assume amount 1 for demo if 0
                        let effectiveAmount = amount > 0 ? amount : (displayCoins.count <= 5 && amount == 0 ? 0 : amount)
                        
                        if let prices = coin.sparklineIn7D?.price, prices.count == count {
                            for i in 0..<count {
                                totalHistory[i] += prices[i] * effectiveAmount
                            }
                        }
                    }
                }
                
                let entry = SimpleEntry(date: Date(), coins: displayCoins, totalHistory: totalHistory)
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
            } catch {
                let entry = SimpleEntry(date: Date(), coins: [], totalHistory: [])
                let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
                let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
                completion(timeline)
            }
        }
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let coins: [Coin]
    let totalHistory: [Double]
}

struct CryptoWidgetEntryView : View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(spacing: 0) {
            // TOP SECTION: Assets List
            VStack(spacing: 8) {
                HStack {
                    Text("MY ASSETS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                ForEach(entry.coins.prefix(4)) { coin in // Show max 4 to fit
                    HStack {
                        // Icon & Name
                        // AsyncImage doesn't work well in Widgets safely without network handling, use text/circle for now
                        Circle().fill(Color.orange).frame(width: 20, height: 20).overlay(Text(coin.symbol.prefix(1)).font(.caption2))
                        
                        VStack(alignment: .leading) {
                            Text(coin.symbol.uppercased())
                                .font(.system(size: 12, weight: .bold))
                            Text(coin.name)
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        // Sparkline
                        if let prices = coin.sparklineIn7D?.price {
                            MiniChart(data: prices, color: coin.priceChangePercentage24H >= 0 ? .green : .red)
                                .frame(width: 40, height: 20)
                        }
                        
                        Spacer()
                        
                        // Price & Amount (The requested "small position")
                        VStack(alignment: .trailing) {
                            let amount = PortfolioManager.shared.getAmount(for: coin.id)
                            Text("\(amount.formattedString()) \(coin.symbol.uppercased())")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                            
                            Text(coin.formattedPrice)
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                                
                            Text(coin.formattedChange)
                                .font(.system(size: 9))
                                .foregroundColor(coin.priceChangePercentage24H >= 0 ? .green : .red)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Color(white: 0.1)) // Slightly lighter dark bg for top
            
            Divider()
            
            // BOTTOM SECTION: Portfolio Chart
            VStack(alignment: .leading) {
                Text("TOTAL PORTFOLIO VALUE")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .padding(.top, 8)
                    .padding(.horizontal)
                
                if let lastValue = entry.totalHistory.last {
                    Text(lastValue.formattedCurrency())
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal)
                }
                
                Chart {
                    ForEach(Array(entry.totalHistory.enumerated()), id: \.offset) { index, value in
                        LineMark(
                            x: .value("Time", index),
                            y: .value("Value", value)
                        )
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.green, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 60)
                .padding(.bottom, 8)
            }
            .background(Color.black)
        }
        .background(Color.black)
    }
}


struct MiniChart: View {
    let data: [Double]
    let color: Color
    
    var body: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Index", index),
                    y: .value("Price", value)
                )
                .foregroundStyle(color)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

@main
struct CryptoWidget: Widget {
    let kind: String = "CryptoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CryptoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Crypto Portfolio")
        .description("Track your crypto assets and total value.")
    }
}

// Helpers
extension Double {
    func formattedString() -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

struct MockData {
    static let coins = [
        Coin(id: "bitcoin", symbol: "btc", name: "Bitcoin", currentPrice: 95431, priceChangePercentage24H: 4.4, sparklineIn7D: SparklineData(price: Array(repeating: 95000, count: 20))),
        // Add more mock data if needed for preview
    ]
    static let history = [100.0, 105.0, 102.0, 108.0, 110.0]
}
