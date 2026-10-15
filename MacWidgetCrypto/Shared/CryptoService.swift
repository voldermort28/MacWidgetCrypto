import Foundation

struct CoinSearchResult: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let symbol: String
    let marketCapRank: Int?
    let thumb: String?
    let large: String?
}

private struct CoinGeckoSearchResponse: Codable {
    let coins: [CoinSearchResult]
}

class CryptoService {
    static let shared = CryptoService()
    
    private let appGroupId = "group.com.voldermort28.MacWidgetCrypto"
    private let cacheKey = "cached_coins_data"
    
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
    
    private func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15
        return request
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
    
    func fetchCoins(for ids: [String]? = nil) async throws -> [Coin] {
        let url: URL
        if let ids = ids, !ids.isEmpty {
            let joinedIds = ids.joined(separator: ",")
            guard let customUrl = URL(string: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=\(joinedIds)&order=market_cap_desc&sparkline=true&price_change_percentage=24h") else {
                throw URLError(.badURL)
            }
            url = customUrl
        } else {
            guard let defaultUrl = URL(string: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=20&page=1&sparkline=true&price_change_percentage=24h") else {
                throw URLError(.badURL)
            }
            url = defaultUrl
        }
        
        let request = makeRequest(for: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw NSError(domain: "CryptoService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "CoinGecko API status \(httpResponse.statusCode)"])
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let coins = try decoder.decode([Coin].self, from: data)
        saveCachedCoins(coins)
        return coins
    }
    
    func fetchCoins(for ids: [String]? = nil, completion: @escaping ([Coin]?) -> Void) {
        Task {
            do {
                let coins = try await fetchCoins(for: ids)
                completion(coins)
            } catch {
                print("Error fetching coins: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
    
    func searchCoins(query: String) async throws -> [CoinSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.coingecko.com/api/v3/search?query=\(encoded)") else {
            return []
        }
        
        let request = makeRequest(for: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let result = try decoder.decode(CoinGeckoSearchResponse.self, from: data)
        return result.coins
    }
}
