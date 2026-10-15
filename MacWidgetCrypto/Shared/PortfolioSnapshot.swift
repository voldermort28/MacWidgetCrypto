import Foundation

struct PortfolioSnapshot {
    let displayCoins: [Coin]
    let totalHistory: [Double]
    let portfolioValue: Double
    let showsRealHoldings: Bool
}

enum PortfolioSnapshotBuilder {
    static func makeSnapshot(from coins: [Coin], portfolio: PortfolioManager, maxCoins: Int = 6, fallbackToTopCoins: Bool = false) -> PortfolioSnapshot {
        let heldCoins = coins
            .filter { portfolio.getAmount(for: $0.id) > 0 }
            .sorted { (coin1, coin2) -> Bool in
                let val1 = coin1.currentPrice * portfolio.getAmount(for: coin1.id)
                let val2 = coin2.currentPrice * portfolio.getAmount(for: coin2.id)
                return val1 > val2
            }
        let showsRealHoldings = !heldCoins.isEmpty

        let relevantCoins: [Coin]
        if showsRealHoldings {
            relevantCoins = heldCoins
        } else if fallbackToTopCoins {
            relevantCoins = coins
        } else {
            relevantCoins = []
        }

        let displayCoins = Array(relevantCoins.prefix(maxCoins))
        let totalHistory = buildTotalHistory(from: relevantCoins, portfolio: portfolio, showsRealHoldings: showsRealHoldings)

        let portfolioValue: Double
        if showsRealHoldings {
            portfolioValue = heldCoins.reduce(0) { partialResult, coin in
                partialResult + (coin.currentPrice * portfolio.getAmount(for: coin.id))
            }
        } else if fallbackToTopCoins {
            portfolioValue = displayCoins.reduce(0) { partialResult, coin in
                partialResult + coin.currentPrice
            }
        } else {
            portfolioValue = 0.0
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
