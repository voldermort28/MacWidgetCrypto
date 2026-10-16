import Foundation

extension Double {
    func formattedCurrency(maxDecimals: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = maxDecimals
        formatter.minimumFractionDigits = min(2, maxDecimals)
        return formatter.string(from: NSNumber(value: self)) ?? "$0.00"
    }

    func formattedVolume() -> String {
        if self >= 1_000_000_000 {
            return String(format: "%.2fB", self / 1_000_000_000)
        } else if self >= 1_000_000 {
            return String(format: "%.2fM", self / 1_000_000)
        } else if self >= 1_000 {
            return String(format: "%.1fK", self / 1_000)
        } else {
            return String(format: "%.2f", self)
        }
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
