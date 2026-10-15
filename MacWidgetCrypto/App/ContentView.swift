import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

enum ClipboardHelper {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
    
    static func paste() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}

struct ContentView: View {
    @StateObject private var portfolioManager = PortfolioManager.shared
    @State private var coins: [Coin] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showingAddCoinSheet = false
    @State private var showingSyncSheet = false

    private var snapshot: PortfolioSnapshot {
        PortfolioSnapshotBuilder.makeSnapshot(from: coins, portfolio: portfolioManager, maxCoins: 6)
    }

    private var chartAccentColor: Color {
        guard let first = snapshot.totalHistory.first, let last = snapshot.totalHistory.last else {
            return .green
        }
        return last >= first ? .green : .red
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Thử lại") {
                        loadData()
                    }
                    .font(.caption.bold())
                    Button(action: { errorMessage = nil }) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.15))
            }

            List {
                    Section(header: Text("Tài sản của tôi")) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tổng Giá Trị")
                                    .font(.headline)
                                Text(snapshot.showsRealHoldings ? "\(coins.filter { portfolioManager.getAmount(for: $0.id) > 0 }.count) tài sản đang theo dõi" : "Chưa có coin nắm giữ")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(portfolioManager.calculateTotalValue(coins: coins).formattedCurrency())
                                .font(.title2)
                                .bold()
                                .foregroundColor(.green)
                        }

                        Button(action: { showingSyncSheet = true }) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath.icloud")
                                    .foregroundColor(.blue)
                                Text("Đồng bộ & Sao lưu danh mục (Mac ↔ iOS)")
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Section(header: Text("Biểu đồ danh mục")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(snapshot.showsRealHoldings ? "Danh mục hiện tại" : "Chưa có coin trong danh mục")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text(snapshot.portfolioValue.formattedCurrency())
                                .font(.title2.bold())

                            if snapshot.totalHistory.count > 1 {
                                SparklineView(
                                    data: snapshot.totalHistory,
                                    lineColor: chartAccentColor,
                                    fillColor: chartAccentColor
                                )
                                .frame(height: 120)
                            } else {
                                Text("Chưa có đủ dữ liệu để vẽ chart. Hãy nhập số lượng coin bạn đang nắm giữ.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section(header: HStack {
                        Text("Danh sách Coin (\(coins.count))")
                        Spacer()
                        Button(action: { showingAddCoinSheet = true }) {
                            Label("Thêm Coin", systemImage: "plus.circle.fill")
                                .font(.caption.bold())
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }) {
                        if coins.isEmpty {
                            VStack(spacing: 8) {
                                if isLoading {
                                    ProgressView("Đang kết nối Binance...")
                                        .padding(.vertical, 8)
                                } else {
                                    Text("Danh sách coin trống")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Button("Thêm Coin mới") {
                                        showingAddCoinSheet = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                        } else {
                            ForEach(coins) { coin in
                                CoinRowView(
                                    coin: coin,
                                    amount: portfolioManager.getAmount(for: coin.id),
                                    onDelete: {
                                        deleteCoin(coin)
                                    }
                                )
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteCoin(coin)
                                    } label: {
                                        Label("Xóa", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteCoin(coin)
                                    } label: {
                                        Label("Xóa khỏi danh sách", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }

                    Section(header: Text("Widget")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Trên macOS: Control-click lên Desktop > Edit Widgets > Tìm \"Crypto Portfolio\" hoặc \"MacWidgetCrypto\".")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Trên iOS: Chạm giữ Home Screen > Nhấn dấu (+) ở góc trên > Thêm Widget.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
        }
        .navigationTitle("MacCrypto")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    Button(action: { showingAddCoinSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .help("Thêm coin mới vào danh sách")

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(action: loadData) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .help("Làm mới giá từ Binance")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddCoinSheet) {
            AddCoinView {
                showingAddCoinSheet = false
                loadData()
            }
        }
        .sheet(isPresented: $showingSyncSheet) {
            SyncView {
                loadData()
            }
        }
        .onAppear {
            let cached = CryptoService.shared.getCachedCoins()
            if !cached.isEmpty {
                self.coins = cached
            }
            loadData()
        }
    }
    
    func loadData() {
        if coins.isEmpty {
            isLoading = true
        }

        portfolioManager.reloadHoldings()
        let trackedIds = portfolioManager.trackedCoinIds
        CryptoService.shared.fetchCoins(for: trackedIds) { fetchedCoins in
            DispatchQueue.main.async {
                self.isLoading = false
                if let fetchedCoins = fetchedCoins, !fetchedCoins.isEmpty {
                    self.coins = fetchedCoins
                    self.errorMessage = nil
                } else {
                    if self.coins.isEmpty {
                        self.coins = CryptoService.shared.getCachedCoins()
                    }
                    self.errorMessage = "Không thể kết nối đến máy chủ Binance. Đang hiển thị dữ liệu lưu gần nhất."
                }
            }
        }
    }

    func deleteCoin(_ coin: Coin) {
        portfolioManager.removeTrackedCoin(id: coin.id)
        coins.removeAll { $0.id == coin.id }
    }
}

struct CoinRowView: View {
    let coin: Coin
    @State var amount: Double
    var onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            coinImageView
            
            VStack(alignment: .leading, spacing: 2) {
                Text(coin.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(coin.symbol.uppercased())
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 8)
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(coin.formattedPrice)
                    .font(.body.weight(.semibold))
                Text(coin.formattedChange)
                    .foregroundColor(coin.priceChangePercentage24H >= 0 ? .green : .red)
                    .font(.caption.weight(.medium))
            }
            
            TextField("Số lượng", value: $amount, format: .number)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
                .onChange(of: amount) { newValue in
                    PortfolioManager.shared.updateHolding(coinId: coin.id, amount: newValue)
                }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.8))
            }
            .buttonStyle(BorderlessButtonStyle())
            .help("Xóa coin")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var coinImageView: some View {
        if let imageUrl = coin.image, let url = URL(string: imageUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                default:
                    coinPlaceholder
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        } else {
            coinPlaceholder
        }
    }

    private var coinPlaceholder: some View {
        Circle()
            .fill(Color.orange.opacity(0.85))
            .frame(width: 32, height: 32)
            .overlay(
                Text(String(coin.symbol.uppercased().prefix(1)))
                    .font(.caption.bold())
                    .foregroundColor(.white)
            )
    }
}

struct AddCoinView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var portfolioManager = PortfolioManager.shared
    @State private var searchQuery = ""
    @State private var searchResults: [CoinSearchResult] = []
    @State private var isSearching = false
    var onCoinAdded: () -> Void

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Tìm kiếm Coin")) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Nhập tên hoặc ký hiệu (vd: sui, pepe, avax...)", text: $searchQuery)
                            .textFieldStyle(PlainTextFieldStyle())
                            .onSubmit {
                                performSearch()
                            }
                        if !searchQuery.isEmpty {
                            Button(action: { searchQuery = ""; searchResults = [] }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        Button("Tìm") {
                            performSearch()
                        }
                        .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                    }
                    .padding(.vertical, 4)

                    if isSearching {
                        HStack {
                            Spacer()
                            ProgressView("Đang tìm kiếm...")
                            Spacer()
                        }
                    } else if !searchResults.isEmpty {
                        ForEach(searchResults) { result in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name)
                                        .font(.headline)
                                    Text(result.symbol.uppercased())
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if portfolioManager.isTracking(id: result.id) {
                                    Label("Đã thêm", systemImage: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                } else {
                                    Button("Thêm") {
                                        portfolioManager.addTrackedCoin(id: result.id)
                                        onCoinAdded()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section(header: Text("Coin phổ biến")) {
                    ForEach(CryptoService.popularCoins, id: \.id) { popular in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(popular.name)
                                    .font(.headline)
                                Text(popular.symbol)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if portfolioManager.isTracking(id: popular.id) {
                                Label("Đã thêm", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            } else {
                                Button("Thêm") {
                                    portfolioManager.addTrackedCoin(id: popular.id)
                                    onCoinAdded()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Thêm Coin mới")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Đóng") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        isSearching = true
        Task {
            do {
                let results = try await CryptoService.shared.searchCoins(query: query)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.searchResults = []
                    self.isSearching = false
                }
            }
        }
    }
}

struct SyncView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var syncManager = SyncManager.shared
    @State private var syncKeyInput = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    var onSyncComplete: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("1. Đồng bộ qua Universal Clipboard (Mac ↔ iPhone)")) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sử dụng bộ nhớ tạm của Apple (hoạt động tức thì giữa Mac và iPhone qua Wi-Fi / Bluetooth mà không cần cài đặt server).")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button("Sao chép dữ liệu (Copy)") {
                                if let json = PortfolioManager.shared.exportPortfolioJSON() {
                                    ClipboardHelper.copy(json)
                                    alertMessage = "Đã sao chép dữ liệu danh mục vào Clipboard! Trên thiết bị kia, hãy bấm 'Dán & Cập nhật'."
                                    showAlert = true
                                }
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Dán & Cập nhật (Paste)") {
                                if let text = ClipboardHelper.paste(), PortfolioManager.shared.importPortfolioJSON(text) {
                                    alertMessage = "Đã đồng bộ thành công dữ liệu từ Clipboard!"
                                    showAlert = true
                                    onSyncComplete()
                                } else {
                                    alertMessage = "Không tìm thấy dữ liệu hợp lệ trong Clipboard."
                                    showAlert = true
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("2. Đồng bộ qua Cloud Sync Key")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nhập cùng một mã Sync Key trên cả MacBook và iPhone để đồng bộ qua đám mây.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Ví dụ: volpi_crypto_key", text: $syncKeyInput)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .disableAutocorrection(true)
                            Button("Lưu Key") {
                                syncManager.saveSyncKey(syncKeyInput)
                                alertMessage = "Đã lưu Sync Key!"
                                showAlert = true
                            }
                        }

                        HStack(spacing: 12) {
                            Button(action: uploadData) {
                                HStack {
                                    Image(systemName: "arrow.up.circle.fill")
                                    Text("Tải lên Cloud")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(syncManager.isSyncing)

                            Button(action: downloadData) {
                                HStack {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text("Tải về máy")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(syncManager.isSyncing)
                        }

                        if syncManager.isSyncing {
                            ProgressView("Đang đồng bộ...")
                                .font(.caption)
                        }

                        if let status = syncManager.lastSyncStatus {
                            Text(status)
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(header: Text("3. Apple iCloud (Tự động)")) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("iCloud Key-Value Store được tích hợp sẵn. Khi ứng dụng chạy trên macOS hoặc thiết bị có tài khoản Apple ID, dữ liệu sẽ tự động đồng bộ ngầm.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Đồng bộ danh mục")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Xong") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Đồng bộ"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .onAppear {
                self.syncKeyInput = syncManager.syncKey
            }
        }
    }

    private func uploadData() {
        syncManager.saveSyncKey(syncKeyInput)
        syncManager.uploadToCloud { success, msg in
            alertMessage = msg
            showAlert = true
        }
    }

    private func downloadData() {
        syncManager.saveSyncKey(syncKeyInput)
        syncManager.downloadFromCloud { success, msg in
            alertMessage = msg
            showAlert = true
            if success {
                onSyncComplete()
            }
        }
    }
}
