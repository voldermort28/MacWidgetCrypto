import Foundation

struct CoinSearchResult: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let marketCapRank: Int?
    let thumb: String?
    let large: String?
}

private struct BinanceTickerResponse: Codable {
    let symbol: String
    let lastPrice: String
    let priceChangePercent: String
    let openPrice: String?
    let highPrice: String?
    let lowPrice: String?
    let weightedAvgPrice: String?
}

class CryptoService {
    static let shared = CryptoService()
    
    private let appGroupId = "group.com.voldermort28.MacWidgetCrypto"
    private let cacheKey = "cached_coins_data"
    
    // Official Binance endpoints (Binance Vision public data cluster is unblocked in Vietnam)
    private let apiHosts = [
        "https://data-api.binance.vision",
        "https://api1.binance.com",
        "https://api3.binance.com",
        "https://api.binance.com"
    ]
    
    private var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? UserDefaults.standard
    }
    
    static let popularCoins: [(id: String, name: String, symbol: String)] = [
        ("bitcoin", "Bitcoin", "BTC"),
        ("ethereum", "Ethereum", "ETH"),
        ("solana", "Solana", "SOL"),
        ("tether", "Tether", "USDT"),
        ("binancecoin", "BNB", "BNB"),
        ("ripple", "XRP", "XRP"),
        ("cardano", "Cardano", "ADA"),
        ("dogecoin", "Dogecoin", "DOGE"),
        ("avalanche-2", "Avalanche", "AVAX"),
        ("sui", "Sui", "SUI"),
        ("chainlink", "Chainlink", "LINK"),
        ("polkadot", "Polkadot", "DOT"),
        ("near", "NEAR Protocol", "NEAR"),
        ("toncoin", "Toncoin", "TON"),
        ("pepe", "Pepe", "PEPE"),
        ("shiba-inu", "Shiba Inu", "SHIB")
    ]

    private static let knownIdToSymbol: [String: (symbol: String, name: String, ticker: String)] = [
        "bitcoin": ("BTC", "Bitcoin", "BTCUSDT"),
        "btc": ("BTC", "Bitcoin", "BTCUSDT"),
        "ethereum": ("ETH", "Ethereum", "ETHUSDT"),
        "eth": ("ETH", "Ethereum", "ETHUSDT"),
        "solana": ("SOL", "Solana", "SOLUSDT"),
        "sol": ("SOL", "Solana", "SOLUSDT"),
        "tether": ("USDT", "Tether", "USDT"),
        "usdt": ("USDT", "Tether", "USDT"),
        "binancecoin": ("BNB", "BNB", "BNBUSDT"),
        "bnb": ("BNB", "BNB", "BNBUSDT"),
        "ripple": ("XRP", "XRP", "XRPUSDT"),
        "xrp": ("XRP", "XRP", "XRPUSDT"),
        "cardano": ("ADA", "Cardano", "ADAUSDT"),
        "ada": ("ADA", "Cardano", "ADAUSDT"),
        "dogecoin": ("DOGE", "Dogecoin", "DOGEUSDT"),
        "doge": ("DOGE", "Dogecoin", "DOGEUSDT"),
        "avalanche-2": ("AVAX", "Avalanche", "AVAXUSDT"),
        "avax": ("AVAX", "Avalanche", "AVAXUSDT"),
        "sui": ("SUI", "Sui", "SUIUSDT"),
        "chainlink": ("LINK", "Chainlink", "LINKUSDT"),
        "link": ("LINK", "Chainlink", "LINKUSDT"),
        "polkadot": ("DOT", "Polkadot", "DOTUSDT"),
        "dot": ("DOT", "Polkadot", "DOTUSDT"),
        "near": ("NEAR", "NEAR Protocol", "NEARUSDT"),
        "toncoin": ("TON", "Toncoin", "TONUSDT"),
        "ton": ("TON", "Toncoin", "TONUSDT"),
        "pepe": ("PEPE", "Pepe", "PEPEUSDT"),
        "shiba-inu": ("SHIB", "Shiba Inu", "SHIBUSDT"),
        "shib": ("SHIB", "Shiba Inu", "SHIBUSDT")
    ]

    static func getCoinInfo(for id: String) -> (symbol: String, name: String, ticker: String) {
        let lower = id.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let info = knownIdToSymbol[lower] {
            return info
        }
        let cleanSymbol = lower.replacingOccurrences(of: "usdt", with: "").uppercased()
        let name = cleanSymbol
        let ticker = cleanSymbol + "USDT"
        return (cleanSymbol, name, ticker)
    }

    func saveCachedCoins(_ coins: [Coin]) {
        guard !coins.isEmpty else { return }
        if let data = try? JSONEncoder().encode(coins) {
            userDefaults.set(data, forKey: cacheKey)
        }
    }
    
    func getCachedCoins() -> [Coin] {
        guard let data = userDefaults.data(forKey: cacheKey),
              let coins = try? JSONDecoder().decode([Coin].self, from: data) else {
            return []
        }
        return coins
    }

    // MARK: - Binance Fetching
    func fetchCoins(for ids: [String]? = nil) async throws -> [Coin] {
        let targetIds: [String]
        if let ids = ids, !ids.isEmpty {
            targetIds = ids
        } else {
            targetIds = ["bitcoin", "ethereum", "solana", "tether", "binancecoin", "ripple"]
        }

        var tickerMap: [String: String] = [:]
        var symbolsToQuery: [String] = []

        for id in targetIds {
            let info = Self.getCoinInfo(for: id)
            if info.ticker != "USDT" {
                tickerMap[info.ticker] = id
                if !symbolsToQuery.contains(info.ticker) {
                    symbolsToQuery.append(info.ticker)
                }
            }
        }

        var binanceTickerData: [String: (price: Double, change: Double, sparkline: [Double])] = [:]

        if !symbolsToQuery.isEmpty {
            var batchSuccess = false
            for host in apiHosts {
                let encodedSymbols = "%5B" + symbolsToQuery.map { "%22\($0)%22" }.joined(separator: "%2C") + "%5D"
                guard let url = URL(string: "\(host)/api/v3/ticker/24hr?symbols=\(encodedSymbols)") else {
                    continue
                }

                var request = URLRequest(url: url)
                request.timeoutInterval = 4
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                        let decoder = JSONDecoder()
                        if let tickers = try? decoder.decode([BinanceTickerResponse].self, from: data) {
                            for item in tickers {
                                let price = Double(item.lastPrice) ?? 0.0
                                let change = Double(item.priceChangePercent) ?? 0.0
                                let open = Double(item.openPrice ?? "") ?? price
                                let high = Double(item.highPrice ?? "") ?? price
                                let low = Double(item.lowPrice ?? "") ?? price
                                let avg = Double(item.weightedAvgPrice ?? "") ?? price
                                let sparkline = [open, (open + low) / 2.0, low, avg, (high + price) / 2.0, price]
                                binanceTickerData[item.symbol] = (price, change, sparkline)
                            }
                            batchSuccess = true
                            break
                        }
                    }
                } catch {
                    continue
                }
            }

            if !batchSuccess {
                await withTaskGroup(of: (String, Double, Double, [Double])?.self) { group in
                    for symbol in symbolsToQuery {
                        group.addTask {
                            return await self.fetchSingleTicker(symbol: symbol)
                        }
                    }
                    for await result in group {
                        if let (sym, price, change, sparkline) = result {
                            binanceTickerData[sym] = (price, change, sparkline)
                        }
                    }
                }
            }
        }

        var resultCoins: [Coin] = []

        for id in targetIds {
            let info = Self.getCoinInfo(for: id)
            if info.ticker == "USDT" {
                let usdtSparkline = SparklineData(price: Array(repeating: 1.0, count: 6))
                resultCoins.append(Coin(
                    id: id,
                    symbol: "USDT",
                    name: "Tether",
                    image: nil,
                    currentPrice: 1.0,
                    priceChangePercentage24H: 0.0,
                    sparklineIn7D: usdtSparkline
                ))
            } else if let tickerData = binanceTickerData[info.ticker] {
                resultCoins.append(Coin(
                    id: id,
                    symbol: info.symbol,
                    name: info.name,
                    image: nil,
                    currentPrice: tickerData.price,
                    priceChangePercentage24H: tickerData.change,
                    sparklineIn7D: SparklineData(price: tickerData.sparkline)
                ))
            }
        }

        if !resultCoins.isEmpty {
            saveCachedCoins(resultCoins)
        }
        return resultCoins
    }

    private func fetchSingleTicker(symbol: String) async -> (String, Double, Double, [Double])? {
        for host in apiHosts.prefix(2) {
            guard let url = URL(string: "\(host)/api/v3/ticker/24hr?symbol=\(symbol)") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    let decoder = JSONDecoder()
                    if let item = try? decoder.decode(BinanceTickerResponse.self, from: data) {
                        let price = Double(item.lastPrice) ?? 0.0
                        let change = Double(item.priceChangePercent) ?? 0.0
                        let open = Double(item.openPrice ?? "") ?? price
                        let high = Double(item.highPrice ?? "") ?? price
                        let low = Double(item.lowPrice ?? "") ?? price
                        let avg = Double(item.weightedAvgPrice ?? "") ?? price
                        let sparkline = [open, (open + low) / 2.0, low, avg, (high + price) / 2.0, price]
                        return (symbol, price, change, sparkline)
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    func fetchCoins(for ids: [String]? = nil, completion: @escaping ([Coin]?) -> Void) {
        Task {
            do {
                let coins = try await fetchCoins(for: ids)
                completion(coins)
            } catch {
                print("Error fetching from Binance: \(error.localizedDescription)")
                let cached = getCachedCoins()
                completion(cached.isEmpty ? nil : cached)
            }
        }
    }

    // MARK: - Binance Search
    func searchCoins(query: String) async throws -> [CoinSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !trimmed.isEmpty else { return [] }

        for host in apiHosts.prefix(2) {
            guard let url = URL(string: "\(host)/api/v3/ticker/price") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    continue
                }

                struct TickerPrice: Codable {
                    let symbol: String
                    let price: String
                }

                let decoder = JSONDecoder()
                if let pairs = try? decoder.decode([TickerPrice].self, from: data) {
                    let matched = pairs
                        .filter { $0.symbol.hasSuffix("USDT") && $0.symbol.contains(trimmed) }
                        .prefix(20)

                    return matched.map { item in
                        let clean = item.symbol.replacingOccurrences(of: "USDT", with: "")
                        return CoinSearchResult(
                            id: clean.lowercased(),
                            name: clean,
                            symbol: clean,
                            marketCapRank: nil,
                            thumb: nil,
                            large: nil
                        )
                    }
                }
            } catch {
                continue
            }
        }
        return []
    }
}
