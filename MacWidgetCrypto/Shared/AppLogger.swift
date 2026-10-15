import Foundation
import os

class AppLogger: ObservableObject {
    static let shared = AppLogger()
    
    private let osLogger = Logger(subsystem: "com.voldermort28.MacWidgetCrypto", category: "App")
    
    @Published var logs: [String] = []
    private let maxLogs = 100
    
    private init() {}
    
    static func log(_ message: String, level: String = "INFO") {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let formatted = "[\(timestamp)] [\(level)] \(message)"
        
        print(formatted)
        
        DispatchQueue.main.async {
            shared.logs.append(formatted)
            if shared.logs.count > shared.maxLogs {
                shared.logs.removeFirst(shared.logs.count - shared.maxLogs)
            }
        }
    }
    
    static func info(_ message: String) {
        log(message, level: "INFO")
    }
    
    static func error(_ message: String) {
        log(message, level: "ERROR")
    }
    
    static func debug(_ message: String) {
        log(message, level: "DEBUG")
    }
    
    func clearLogs() {
        logs.removeAll()
    }
}
