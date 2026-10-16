import Foundation

extension Double {
    func formattedCurrency() -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }

    func formattedAmount(maximumFractionDigits: Int = 4) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

func parseCryptoAmount(_ input: String) -> Double? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return 0.0 }

    // Check if it contains both comma and dot (e.g. copied directly from Binance: "2,577.00")
    if trimmed.contains(",") && trimmed.contains(".") {
        if let lastComma = trimmed.lastIndex(of: ","), let lastDot = trimmed.lastIndex(of: ".") {
            if lastComma < lastDot {
                // US style: "2,577.00" -> remove comma
                let cleaned = trimmed.replacingOccurrences(of: ",", with: "")
                return Double(cleaned)
            } else {
                // EU style: "2.577,00" -> remove dot, replace comma with dot
                let cleaned = trimmed.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                return Double(cleaned)
            }
        }
    }

    let standardized = trimmed.replacingOccurrences(of: ",", with: ".")
    return Double(standardized)
}
