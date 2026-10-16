import Foundation

struct CoinSearchResult: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let marketCapRank: Int?
    let thumb: String?
    let large: String?
}

struct KlinePoint: Identifiable, Codable {
    var id: Double { time.timeIntervalSince1970 }
    let time: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double
}

struct Binance24hStats: Codable {
    let symbol: String
    let priceChange: Double
    let priceChangePercent: Double
    let weightedAvgPrice: Double
    let prevClosePrice: Double
    let lastPrice: Double
    let openPrice: Double
    let highPrice: Double
    let lowPrice: Double
    let volume: Double
    let quoteVolume: Double
    let count: Int
    var high52Week: Double?
    var low52Week: Double?
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
    
    private var detailedKlinesCache: [String: (timestamp: Date, klines: [KlinePoint])] = [:]
    private var stats24hCache: [String: (timestamp: Date, stats: Binance24hStats)] = [:]
    
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

        AppLogger.info("Bắt đầu lấy giá Binance cho: \(targetIds.joined(separator: ", "))")

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
        var klinesMap: [String: [Double]] = [:]

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
                            AppLogger.info("Thành công lấy dữ liệu từ \(host) (\(tickers.count) tickers)")
                            break
                        }
                    }
                } catch {
                    AppLogger.debug("Host \(host) không phản hồi: \(error.localizedDescription)")
                    continue
                }
            }

            if !batchSuccess {
                AppLogger.info("Batch request không thành công, thử lấy từng ticker...")
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

            // Fetch 24h hourly klines in parallel for detailed Apple Stocks style chart
            await withTaskGroup(of: (String, [Double])?.self) { group in
                for sym in symbolsToQuery {
                    group.addTask {
                        if let klines = await self.fetchKlines(symbol: sym) {
                            return (sym, klines)
                        }
                        return nil
                    }
                }
                for await res in group {
                    if let (sym, klines) = res {
                        klinesMap[sym] = klines
                    }
                }
            }
        }

        var resultCoins: [Coin] = []

        for id in targetIds {
            let info = Self.getCoinInfo(for: id)
            if info.ticker == "USDT" {
                let usdtSparkline = SparklineData(price: Array(repeating: 1.0, count: 24))
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
                let sparklinePrices = klinesMap[info.ticker] ?? tickerData.sparkline
                resultCoins.append(Coin(
                    id: id,
                    symbol: info.symbol,
                    name: info.name,
                    image: nil,
                    currentPrice: tickerData.price,
                    priceChangePercentage24H: tickerData.change,
                    sparklineIn7D: SparklineData(price: sparklinePrices)
                ))
            }
        }

        if !resultCoins.isEmpty {
            saveCachedCoins(resultCoins)
            AppLogger.info("Đã cập nhật giá xong cho \(resultCoins.count) coin.")
        } else {
            AppLogger.error("Không lấy được dữ liệu coin nào từ Binance.")
        }
        return resultCoins
    }

    private func fetchKlines(symbol: String) async -> [Double]? {
        for host in apiHosts.prefix(2) {
            guard let url = URL(string: "\(host)/api/v3/klines?symbol=\(symbol)&interval=1h&limit=24") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 3
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { continue }
                if let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
                    let closes = rawArray.compactMap { candle -> Double? in
                        guard candle.count > 4, let closeStr = candle[4] as? String else { return nil }
                        return Double(closeStr)
                    }
                    if closes.count >= 6 {
                        return closes
                    }
                }
            } catch {
                continue
            }
        }
        return nil
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
                AppLogger.error("Lỗi lấy giá từ Binance: \(error.localizedDescription)")
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

    // MARK: - Detailed Klines for Interactive Apple Stocks Chart
    func fetchDetailedKlines(symbol: String, interval: String = "1h", limit: Int = 24) async -> [KlinePoint] {
        let pair = symbol.uppercased().hasSuffix("USDT") ? symbol.uppercased() : symbol.uppercased() + "USDT"
        let key = "\(pair)_\(interval)_\(limit)"
        
        if let cached = detailedKlinesCache[key], Date().timeIntervalSince(cached.timestamp) < 30 {
            return cached.klines
        }

        for host in apiHosts.prefix(3) {
            guard let url = URL(string: "\(host)/api/v3/klines?symbol=\(pair)&interval=\(interval)&limit=\(limit)") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { continue }
                if let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
                    let klines: [KlinePoint] = rawArray.compactMap { candle in
                        guard candle.count > 5,
                              let openTimeMs = candle[0] as? Double,
                              let openStr = candle[1] as? String, let open = Double(openStr),
                              let highStr = candle[2] as? String, let high = Double(highStr),
                              let lowStr = candle[3] as? String, let low = Double(lowStr),
                              let closeStr = candle[4] as? String, let close = Double(closeStr),
                              let volStr = candle[5] as? String, let vol = Double(volStr) else {
                            return nil
                        }
                        return KlinePoint(
                            time: Date(timeIntervalSince1970: openTimeMs / 1000.0),
                            open: open,
                            high: high,
                            low: low,
                            close: close,
                            volume: vol
                        )
                    }
                    if !klines.isEmpty {
                        detailedKlinesCache[key] = (Date(), klines)
                        return klines
                    }
                }
            } catch {
                continue
            }
        }
        return []
    }

    // MARK: - 24h Market Stats (Open, High, Low, Volume, 52W High/Low)
    func fetch24hStats(symbol: String) async -> Binance24hStats? {
        let pair = symbol.uppercased().hasSuffix("USDT") ? symbol.uppercased() : symbol.uppercased() + "USDT"
        
        if let cached = stats24hCache[pair], Date().timeIntervalSince(cached.timestamp) < 30 {
            return cached.stats
        }

        for host in apiHosts.prefix(3) {
            guard let url = URL(string: "\(host)/api/v3/ticker/24hr?symbol=\(pair)") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { continue }

                struct Raw24hr: Codable {
                    let symbol: String
                    let priceChange: String
                    let priceChangePercent: String
                    let weightedAvgPrice: String
                    let prevClosePrice: String
                    let lastPrice: String
                    let openPrice: String
                    let highPrice: String
                    let lowPrice: String
                    let volume: String
                    let quoteVolume: String
                    let count: Int
                }

                if let raw = try? JSONDecoder().decode(Raw24hr.self, from: data) {
                    var stats = Binance24hStats(
                        symbol: raw.symbol,
                        priceChange: Double(raw.priceChange) ?? 0.0,
                        priceChangePercent: Double(raw.priceChangePercent) ?? 0.0,
                        weightedAvgPrice: Double(raw.weightedAvgPrice) ?? 0.0,
                        prevClosePrice: Double(raw.prevClosePrice) ?? 0.0,
                        lastPrice: Double(raw.lastPrice) ?? 0.0,
                        openPrice: Double(raw.openPrice) ?? 0.0,
                        highPrice: Double(raw.highPrice) ?? 0.0,
                        lowPrice: Double(raw.lowPrice) ?? 0.0,
                        volume: Double(raw.volume) ?? 0.0,
                        quoteVolume: Double(raw.quoteVolume) ?? 0.0,
                        count: raw.count,
                        high52Week: nil,
                        low52Week: nil
                    )

                    // Fetch 52-Week High & Low from weekly candles
                    if let weekly52 = await fetchWeekly52Klines(symbol: pair) {
                        stats.high52Week = weekly52.high
                        stats.low52Week = weekly52.low
                    }

                    stats24hCache[pair] = (Date(), stats)
                    return stats
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func fetchWeekly52Klines(symbol: String) async -> (high: Double, low: Double)? {
        for host in apiHosts.prefix(2) {
            guard let url = URL(string: "\(host)/api/v3/klines?symbol=\(symbol)&interval=1w&limit=52") else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 4
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { continue }
                if let rawArray = try? JSONSerialization.jsonObject(with: data) as? [[Any]] {
                    var maxHigh: Double = 0
                    var minLow: Double = Double.greatestFiniteMagnitude
                    for candle in rawArray {
                        if candle.count > 3,
                           let hStr = candle[2] as? String, let h = Double(hStr),
                           let lStr = candle[3] as? String, let l = Double(lStr) {
                            if h > maxHigh { maxHigh = h }
                            if l < minLow { minLow = l }
                        }
                    }
                    if maxHigh > 0 && minLow < Double.greatestFiniteMagnitude {
                        return (maxHigh, minLow)
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }
}
