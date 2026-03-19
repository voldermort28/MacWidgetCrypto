import Foundation

struct PortfolioSnapshot {
    let displayCoins: [Coin]
    let totalHistory: [Double]
    let portfolioValue: Double
    let showsRealHoldings: Bool
}

enum PortfolioSnapshotBuilder {
    static func makeSnapshot(from coins: [Coin], portfolio: PortfolioManager, maxCoins: Int = 4) -> PortfolioSnapshot {
        let heldCoins = coins.filter { portfolio.getAmount(for: $0.id) > 0 }
        let showsRealHoldings = !heldCoins.isEmpty
        let displayCoins = Array((showsRealHoldings ? heldCoins : coins).prefix(maxCoins))
        let totalHistory = buildTotalHistory(from: displayCoins, portfolio: portfolio, showsRealHoldings: showsRealHoldings)

        let portfolioValue: Double
        if let lastValue = totalHistory.last {
            portfolioValue = lastValue
        } else {
            portfolioValue = displayCoins.reduce(0) { partialResult, coin in
                let amount = showsRealHoldings ? portfolio.getAmount(for: coin.id) : 1.0
                return partialResult + (coin.currentPrice * amount)
            }
        }

        return PortfolioSnapshot(
            displayCoins: displayCoins,
            totalHistory: totalHistory,
            portfolioValue: portfolioValue,
            showsRealHoldings: showsRealHoldings
        )
    }

    private static func buildTotalHistory(from coins: [Coin], portfolio: PortfolioManager, showsRealHoldings: Bool) -> [Double] {
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
