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
        let relevantCoins = showsRealHoldings ? heldCoins : coins
        let displayCoins = Array(relevantCoins.prefix(maxCoins))
        let totalHistory = buildTotalHistory(from: relevantCoins, portfolio: portfolio, showsRealHoldings: showsRealHoldings)

        let portfolioValue: Double
        if showsRealHoldings {
            portfolioValue = heldCoins.reduce(0) { partialResult, coin in
                partialResult + (coin.currentPrice * portfolio.getAmount(for: coin.id))
            }
        } else {
            portfolioValue = displayCoins.reduce(0) { partialResult, coin in
                partialResult + coin.currentPrice
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
        let counts = coins.compactMap { $0.sparklineIn7D?.price.count }.filter { $0 > 1 }
        guard let minPointCount = counts.min(), minPointCount > 1 else {
            return []
        }

        var totalHistory = Array(repeating: 0.0, count: minPointCount)

        for coin in coins {
            guard let prices = coin.sparklineIn7D?.price, prices.count >= minPointCount else {
                continue
            }

            let alignedPrices = Array(prices.suffix(minPointCount))
            let amount = showsRealHoldings ? portfolio.getAmount(for: coin.id) : 1.0
            for index in 0..<minPointCount {
                totalHistory[index] += alignedPrices[index] * amount
            }
        }

        return totalHistory
    }
}
