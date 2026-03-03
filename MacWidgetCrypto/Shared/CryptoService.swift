import Foundation

class CryptoService {
    static let shared = CryptoService()
    
    // CoinGecko API URL (Free tier)
    // Fetching markets with sparkline
    // vs_currency=usd, order=market_cap_desc, per_page=20, proper_page=1, sparkline=true
    private let urlString = "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&order=market_cap_desc&per_page=20&page=1&sparkline=true&price_change_percentage=24h"
    
    func fetchCoins(completion: @escaping ([Coin]?) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Error fetching coins: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                completion(nil)
                return
            }
            
            do {
                // CoinGecko returns keys with snake_case, verify decoding strategy
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let coins = try decoder.decode([Coin].self, from: data)
                completion(coins)
            } catch {
                print("Error decoding data: \(error)")
                completion(nil)
            }
        }.resume()
    }
    
    // Async/Await version for Widget
    func fetchCoins() async throws -> [Coin] {
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode([Coin].self, from: data)
    }
}
