import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

class PortfolioManager: ObservableObject {
    static let shared = PortfolioManager()
    private let userDefaults: UserDefaults
    
    // Enable the same App Group in the app and widget targets to share holdings on device.
    private let appGroupId = "group.com.voldermort28.MacWidgetCrypto"
    
    @Published var holdings: [String: Double] = [:]
    
    init() {
        // Try to load from App Group, fallback to standard if not set up yet (for testing in App)
        if let groupDefaults = UserDefaults(suiteName: appGroupId) {
            self.userDefaults = groupDefaults
        } else {
            self.userDefaults = UserDefaults.standard
        }
        loadHoldings()
    }
    
    func updateHolding(coinId: String, amount: Double) {
        let sanitizedAmount = max(amount, 0)

        if sanitizedAmount == 0 {
            holdings.removeValue(forKey: coinId)
        } else {
            holdings[coinId] = sanitizedAmount
        }

        saveHoldings()
        reloadWidgetTimelines()
    }
    
    func getAmount(for coinId: String) -> Double {
        return holdings[coinId] ?? 0.0
    }
    
    private func saveHoldings() {
        userDefaults.set(holdings, forKey: "user_holdings")
    }
    
    private func loadHoldings() {
        if let saved = userDefaults.dictionary(forKey: "user_holdings") as? [String: Double] {
            self.holdings = saved
        }
    }

    private func reloadWidgetTimelines() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
    
    // Helper to calculate total value given current prices
    func calculateTotalValue(coins: [Coin]) -> Double {
        var total: Double = 0
        for coin in coins {
            let amount = getAmount(for: coin.id)
            total += amount * coin.currentPrice
        }
        return total
    }
}
