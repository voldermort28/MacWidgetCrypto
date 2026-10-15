import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

class PortfolioManager: ObservableObject {
    static let shared = PortfolioManager()
    private let userDefaults: UserDefaults
    
    // Enable the same App Group in the app and widget targets to share holdings on device.
    private let appGroupId = "group.com.voldermort28.MacWidgetCrypto"
    private let trackedCoinsKey = "user_tracked_coins"
    private let defaultTrackedCoins = ["bitcoin", "ethereum", "solana", "tether", "binancecoin", "ripple"]
    
    @Published var holdings: [String: Double] = [:]
    @Published var trackedCoinIds: [String] = []
    
    init() {
        // Try to load from App Group, fallback to standard if not set up yet (for testing in App)
        let groupDefaults = UserDefaults(suiteName: appGroupId)
        let defaults = groupDefaults ?? UserDefaults.standard
        self.userDefaults = defaults

        // Auto-migrate from legacy/standard defaults if App Group is newly created and empty
        if let groupDefaults = groupDefaults {
            let currentGroupHoldings = groupDefaults.dictionary(forKey: "user_holdings") as? [String: Double]
            if currentGroupHoldings == nil || currentGroupHoldings?.isEmpty == true {
                if let legacyHoldings = UserDefaults.standard.dictionary(forKey: "user_holdings") as? [String: Double], !legacyHoldings.isEmpty {
                    groupDefaults.set(legacyHoldings, forKey: "user_holdings")
                    if let legacyCoins = UserDefaults.standard.stringArray(forKey: trackedCoinsKey), !legacyCoins.isEmpty {
                        groupDefaults.set(legacyCoins, forKey: trackedCoinsKey)
                    }
                    AppLogger.info("Đã tự động khôi phục danh mục từ bộ nhớ chuẩn sang App Group.")
                }
            }
        }

        reloadHoldings()
        loadTrackedCoins()
    }
    
    func updateHolding(coinId: String, amount: Double) {
        let sanitizedAmount = max(amount, 0)

        if sanitizedAmount == 0 {
            holdings.removeValue(forKey: coinId)
        } else {
            holdings[coinId] = sanitizedAmount
            if !trackedCoinIds.contains(coinId) {
                trackedCoinIds.append(coinId)
                saveTrackedCoins()
            }
        }

        saveHoldings()
        reloadWidgetTimelines()
    }
    
    func getAmount(for coinId: String) -> Double {
        return holdings[coinId] ?? 0.0
    }
    
    private func saveHoldings() {
        userDefaults.set(holdings, forKey: "user_holdings")
        UserDefaults.standard.set(holdings, forKey: "user_holdings")
    }
    
    func reloadHoldings() {
        let saved = (userDefaults.dictionary(forKey: "user_holdings") as? [String: Double]) ?? [:]
        if self.holdings != saved {
            self.holdings = saved
            AppLogger.info("Reloaded holdings: \(saved.keys.joined(separator: ", "))")
        }
        loadTrackedCoins()
    }

    func loadTrackedCoins() {
        let saved = userDefaults.stringArray(forKey: trackedCoinsKey) ?? defaultTrackedCoins
        var current = saved.isEmpty ? defaultTrackedCoins : saved

        for (id, amount) in holdings where amount > 0 {
            if !current.contains(id) {
                current.append(id)
            }
        }

        if self.trackedCoinIds != current {
            self.trackedCoinIds = current
            userDefaults.set(current, forKey: trackedCoinsKey)
            AppLogger.info("Loaded tracked coins: \(current.joined(separator: ", "))")
        }
    }

    private func saveTrackedCoins() {
        userDefaults.set(trackedCoinIds, forKey: trackedCoinsKey)
        UserDefaults.standard.set(trackedCoinIds, forKey: trackedCoinsKey)
    }

    func addTrackedCoin(id: String) {
        if !trackedCoinIds.contains(id) {
            trackedCoinIds.append(id)
            saveTrackedCoins()
            reloadWidgetTimelines()
        }
    }

    func removeTrackedCoin(id: String) {
        trackedCoinIds.removeAll { $0 == id }
        saveTrackedCoins()
        holdings.removeValue(forKey: id)
        saveHoldings()
        reloadWidgetTimelines()
    }

    func isTracking(id: String) -> Bool {
        trackedCoinIds.contains(id)
    }

    // JSON Export / Import for backup & synchronization
    func exportPortfolioJSON() -> String? {
        reloadHoldings()
        let payload: [String: Any] = [
            "version": 1,
            "timestamp": Date().timeIntervalSince1970,
            "holdings": holdings,
            "tracked_coins": trackedCoinIds
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let jsonString = String(data: data, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }

    func importPortfolioJSON(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }

        if let savedHoldings = json["holdings"] as? [String: Double] {
            self.holdings = savedHoldings
            saveHoldings()
        }

        if let savedTracked = json["tracked_coins"] as? [String] {
            self.trackedCoinIds = savedTracked
            saveTrackedCoins()
        }

        reloadWidgetTimelines()
        return true
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
