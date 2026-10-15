import Foundation

class SyncManager: ObservableObject {
    static let shared = SyncManager()
    
    private let syncKeyDefaultsKey = "cloud_sync_key"
    private let appGroupId = "group.com.voldermort28.MacWidgetCrypto"
    private var userDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? UserDefaults.standard
    }
    
    @Published var syncKey: String = ""
    @Published var lastSyncStatus: String? = nil
    @Published var isSyncing: Bool = false
    
    init() {
        let defaults = UserDefaults(suiteName: appGroupId) ?? UserDefaults.standard
        self.syncKey = defaults.string(forKey: syncKeyDefaultsKey) ?? ""
        setupiCloudObserver()
    }
    
    func saveSyncKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.syncKey = trimmed
        userDefaults.set(trimmed, forKey: syncKeyDefaultsKey)
    }
    
    // MARK: - iCloud Key-Value Store
    private func setupiCloudObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(iCloudStoreDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        NSUbiquitousKeyValueStore.default.synchronize()
    }
    
    @objc private func iCloudStoreDidChange(notification: Notification) {
        if let jsonString = NSUbiquitousKeyValueStore.default.string(forKey: "portfolio_backup_json") {
            DispatchQueue.main.async {
                _ = PortfolioManager.shared.importPortfolioJSON(jsonString)
                self.lastSyncStatus = "Đã nhận cập nhật tự động từ iCloud"
            }
        }
    }
    
    func syncToiCloud() {
        if let json = PortfolioManager.shared.exportPortfolioJSON() {
            NSUbiquitousKeyValueStore.default.set(json, forKey: "portfolio_backup_json")
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }
    
    // MARK: - Cloud Sync (Cross-platform sync via Sync Key)
    func uploadToCloud(completion: @escaping (Bool, String) -> Void) {
        let trimmedKey = syncKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            completion(false, "Vui lòng nhập Sync Key trước khi tải lên.")
            return
        }
        
        guard let jsonString = PortfolioManager.shared.exportPortfolioJSON(),
              let data = jsonString.data(using: .utf8) else {
            completion(false, "Không thể đóng gói dữ liệu danh mục.")
            return
        }
        
        isSyncing = true
        let safeKey = trimmedKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? trimmedKey
        guard let url = URL(string: "https://kvdb.io/4y9vQJ7QzCgZ2hM6x7E7gM/\(safeKey)") else {
            isSyncing = false
            completion(false, "Sync Key không hợp lệ.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 12
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                self.isSyncing = false
                if let error = error {
                    let msg = "Lỗi kết nối: \(error.localizedDescription)"
                    self.lastSyncStatus = msg
                    completion(false, msg)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                    self.syncToiCloud()
                    let msg = "Đã đồng bộ lên đám mây thành công!"
                    self.lastSyncStatus = msg
                    completion(true, msg)
                } else {
                    let msg = "Máy chủ phản hồi lỗi khi tải lên."
                    self.lastSyncStatus = msg
                    completion(false, msg)
                }
            }
        }.resume()
    }
    
    func downloadFromCloud(completion: @escaping (Bool, String) -> Void) {
        let trimmedKey = syncKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            completion(false, "Vui lòng nhập Sync Key để tải về.")
            return
        }
        
        isSyncing = true
        let safeKey = trimmedKey.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? trimmedKey
        guard let url = URL(string: "https://kvdb.io/4y9vQJ7QzCgZ2hM6x7E7gM/\(safeKey)") else {
            isSyncing = false
            completion(false, "Sync Key không hợp lệ.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isSyncing = false
                if let error = error {
                    let msg = "Lỗi kết nối: \(error.localizedDescription)"
                    self.lastSyncStatus = msg
                    completion(false, msg)
                    return
                }
                
                guard let data = data, let jsonString = String(data: data, encoding: .utf8), !jsonString.isEmpty else {
                    let msg = "Không tìm thấy dữ liệu đám mây cho Sync Key này."
                    self.lastSyncStatus = msg
                    completion(false, msg)
                    return
                }
                
                let success = PortfolioManager.shared.importPortfolioJSON(jsonString)
                if success {
                    self.syncToiCloud()
                    let msg = "Đã tải về và đồng bộ thành công!"
                    self.lastSyncStatus = msg
                    completion(true, msg)
                } else {
                    let msg = "Định dạng dữ liệu tải về không hợp lệ."
                    self.lastSyncStatus = msg
                    completion(false, msg)
                }
            }
        }.resume()
    }
}
