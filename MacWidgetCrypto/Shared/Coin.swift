import Foundation

struct Coin: Identifiable, Codable {
    let id: String
    let symbol: String
    let name: String
    let currentPrice: Double
    let priceChangePercentage24H: Double
    let sparklineIn7D: SparklineData?

    var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: currentPrice)) ?? "$0.00"
    }
    
    var formattedChange: String {
        return String(format: "%.2f%%", priceChangePercentage24H)
    }
}

struct SparklineData: Codable {
    let price: [Double]
}

// Wrapper for API response if needed, or straight usage
