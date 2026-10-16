import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif
#if canImport(WidgetKit)
import WidgetKit
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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var portfolioManager = PortfolioManager.shared
    @State private var coins: [Coin] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var showingAddCoinSheet = false
    @State private var showingSyncSheet = false
    @State private var showingLogsSheet = false
    @State private var autoRefreshTimer: Timer? = nil

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
                                    baselinePrice: snapshot.totalHistory.first,
                                    lineColor: chartAccentColor,
                                    fillColor: chartAccentColor,
                                    showBaseline: true
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

                    Button(action: { showingLogsSheet = true }) {
                        Image(systemName: "terminal")
                    }
                    .help("Xem nhật ký hệ thống (Logs)")

                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button(action: { loadData(isBackgroundRefresh: false) }) {
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
        .sheet(isPresented: $showingLogsSheet) {
            LogsView()
        }
        .onAppear {
            let cached = CryptoService.shared.getCachedCoins()
            if !cached.isEmpty {
                self.coins = cached
            }
            loadData()
            startForegroundTimer()
        }
        .onDisappear {
            stopTimers()
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                AppLogger.info("App mở / Active. Cập nhật giá ngay lập tức và chạy timer 30s.")
                loadData(isBackgroundRefresh: true)
                startForegroundTimer()
                #if canImport(WidgetKit)
                WidgetCenter.shared.reloadAllTimelines()
                #endif
            } else {
                AppLogger.info("App vào background / sleep. Giãn chu kỳ cập nhật lên 60 phút.")
                startBackgroundTimer()
            }
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            AppLogger.info("Mac thức dậy từ chế độ Sleep. Cập nhật giá ngay lập tức.")
            loadData(isBackgroundRefresh: false)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        #elseif os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            AppLogger.info("iOS vào Foreground. Cập nhật giá ngay lập tức.")
            loadData(isBackgroundRefresh: false)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Xong") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        #endif
    }
    
    func loadData(isBackgroundRefresh: Bool = false) {
        if coins.isEmpty || !isBackgroundRefresh {
            isLoading = true
        }

        AppLogger.info("Bắt đầu tải giá (ngầm: \(isBackgroundRefresh))...")
        portfolioManager.reloadHoldings()
        let trackedIds = portfolioManager.trackedCoinIds
        CryptoService.shared.fetchCoins(for: trackedIds) { fetchedCoins in
            DispatchQueue.main.async {
                self.isLoading = false
                if let fetchedCoins = fetchedCoins, !fetchedCoins.isEmpty {
                    self.coins = fetchedCoins
                    self.errorMessage = nil
                    AppLogger.info("Đã cập nhật hiển thị \(fetchedCoins.count) coin.")
                } else {
                    if self.coins.isEmpty {
                        self.coins = CryptoService.shared.getCachedCoins()
                    }
                    self.errorMessage = "Không thể kết nối đến máy chủ Binance. Đang hiển thị dữ liệu lưu gần nhất."
                    AppLogger.error("Không nhận được dữ liệu từ Binance, hiển thị cache.")
                }
                #if canImport(WidgetKit)
                WidgetCenter.shared.reloadAllTimelines()
                #endif
            }
        }
    }

    private func startForegroundTimer() {
        stopTimers()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            loadData(isBackgroundRefresh: true)
        }
    }

    private func startBackgroundTimer() {
        stopTimers()
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            loadData(isBackgroundRefresh: true)
        }
    }

    private func stopTimers() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    func deleteCoin(_ coin: Coin) {
        portfolioManager.removeTrackedCoin(id: coin.id)
        coins.removeAll { $0.id == coin.id }
    }
}

struct CoinRowView: View {
    let coin: Coin
    let initialAmount: Double
    var onDelete: () -> Void
    @State private var amountString: String
    
    init(coin: Coin, amount: Double, onDelete: @escaping () -> Void) {
        self.coin = coin
        self.initialAmount = amount
        self.onDelete = onDelete
        let initialText: String
        if amount > 0 {
            initialText = amount.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", amount) : String(amount)
        } else {
            initialText = ""
        }
        self._amountString = State(initialValue: initialText)
    }

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
            
            Spacer(minLength: 4)

            if let prices = coin.sparklineIn7D?.price, prices.count > 1 {
                let isPositive = coin.priceChangePercentage24H >= 0
                let stockRed = Color(red: 1.0, green: 0.27, blue: 0.23)
                let stockGreen = Color(red: 0.19, green: 0.82, blue: 0.35)
                let accent = isPositive ? stockGreen : stockRed

                SparklineView(
                    data: prices,
                    baselinePrice: prices.first,
                    lineColor: accent,
                    fillColor: accent,
                    showBaseline: true
                )
                .frame(width: 58, height: 24)
            }

            VStack(alignment: .trailing, spacing: 2) {
                Text(coin.formattedPrice)
                    .font(.body.weight(.semibold))
                Text(coin.formattedChange)
                    .foregroundColor(coin.priceChangePercentage24H >= 0 ? .green : .red)
                    .font(.caption.weight(.medium))
            }
            
            TextField("0.0", text: $amountString)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 85)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .onChange(of: amountString) { newStr in
                    if let parsed = parseCryptoAmount(newStr), parsed >= 0 {
                        PortfolioManager.shared.updateHolding(coinId: coin.id, amount: parsed)
                    }
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
    @State private var hasSearched = false
    var onCoinAdded: () -> Void

    var body: some View {
        #if os(iOS)
        NavigationView {
            coinListContent
                .navigationTitle("Thêm Coin mới")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Đóng") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        #else
        VStack(spacing: 0) {
            HStack {
                Text("Thêm Coin mới")
                    .font(.headline)
                Spacer()
                Button("Đóng") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding()

            Divider()

            coinListContent
        }
        .frame(minWidth: 480, idealWidth: 540, minHeight: 520, idealHeight: 600)
        #endif
    }

    private var coinListContent: some View {
        VStack(spacing: 0) {
            // Pinned Search Header
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Tìm theo mã hoặc tên (vd: BTC, SOL, SUI, PEPE...)", text: $searchQuery)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        performSearch()
                    }
                
                if !searchQuery.isEmpty {
                    Button(action: {
                        searchQuery = ""
                        searchResults = []
                        hasSearched = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                
                Button("Tìm kiếm") {
                    performSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(searchQuery.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.secondary.opacity(0.06))

            Divider()

            List {
                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView("Đang tìm kiếm từ Binance...")
                            .padding(.vertical, 24)
                        Spacer()
                    }
                } else if !searchResults.isEmpty {
                    Section(header: Text("Kết quả tìm kiếm (\(searchResults.count))")) {
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
                                        .font(.subheadline.bold())
                                } else {
                                    Button("Thêm") {
                                        portfolioManager.addTrackedCoin(id: result.id)
                                        onCoinAdded()
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else if hasSearched {
                    Section {
                        VStack(spacing: 8) {
                            Image(systemName: "questionmark.folder")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                            Text("Không tìm thấy cặp giao dịch nào phù hợp trên Binance với từ khóa \"\(searchQuery)\"")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 16)
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
                                    .font(.subheadline.bold())
                            } else {
                                Button("Thêm") {
                                    portfolioManager.addTrackedCoin(id: popular.id)
                                    onCoinAdded()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !query.isEmpty else {
            searchResults = []
            hasSearched = false
            return
        }
        isSearching = true
        hasSearched = true
        AppLogger.info("Tìm kiếm coin với từ khóa: \(query)")
        Task {
            do {
                let results = try await CryptoService.shared.searchCoins(query: query)
                await MainActor.run {
                    self.searchResults = results
                    self.isSearching = false
                    AppLogger.info("Binance trả về \(results.count) kết quả tìm kiếm cho \(query).")
                }
            } catch {
                await MainActor.run {
                    // Fallback to local popular coins
                    let localMatches = CryptoService.popularCoins.filter {
                        $0.name.uppercased().contains(query) || $0.symbol.uppercased().contains(query) || $0.id.uppercased().contains(query)
                    }.map {
                        CoinSearchResult(id: $0.id, name: $0.name, symbol: $0.symbol, marketCapRank: nil, thumb: nil, large: nil)
                    }
                    self.searchResults = localMatches
                    self.isSearching = false
                    AppLogger.info("Lỗi tìm kiếm online, khớp nội bộ: \(localMatches.count) coin.")
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
        #if os(iOS)
        NavigationView {
            formContent
                .navigationTitle("Đồng bộ danh mục")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Xong") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        #else
        VStack(spacing: 0) {
            HStack {
                Text("Đồng bộ danh mục")
                    .font(.headline)
                Spacer()
                Button("Xong") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding()

            Divider()

            formContent
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 540, idealHeight: 620)
        #endif
    }

    private var formContent: some View {
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

            Section(header: Text("4. Nhật ký Hệ thống (Logs)")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Xem trạng thái mạng, kết nối Binance và lịch sử làm mới dữ liệu.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: { showingLogs = true }) {
                        HStack {
                            Image(systemName: "terminal")
                            Text("Xem Nhật ký chi tiết (\(AppLogger.shared.logs.count) bản ghi)")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 4)
            }
        }
        .sheet(isPresented: $showingLogs) {
            LogsView()
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Đồng bộ"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
        .onAppear {
            self.syncKeyInput = syncManager.syncKey
        }
    }

    @State private var showingLogs = false

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

struct LogsView: View {
    @Environment(\.presentationMode) private var presentationMode
    @ObservedObject private var logger = AppLogger.shared
    @State private var copyNotice = false

    var body: some View {
        #if os(iOS)
        NavigationView {
            logsContent
                .navigationTitle("Nhật ký Hệ thống (Logs)")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Đóng") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        #else
        VStack(spacing: 0) {
            HStack {
                Text("Nhật ký Hệ thống (Logs)")
                    .font(.headline)
                Spacer()
                Button("Đóng") {
                    presentationMode.wrappedValue.dismiss()
                }
            }
            .padding()

            Divider()

            logsContent
        }
        .frame(minWidth: 550, idealWidth: 600, minHeight: 450, idealHeight: 550)
        #endif
    }

    private var logsContent: some View {
        VStack(spacing: 0) {
            if logger.logs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Chưa có bản ghi nhật ký nào.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(0..<logger.logs.count, id: \.self) { index in
                                let log = logger.logs[index]
                                Text(log)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(logColor(for: log))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(index)
                            }
                        }
                        .padding()
                    }
                    .onAppear {
                        if !logger.logs.isEmpty {
                            proxy.scrollTo(logger.logs.count - 1, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button(action: {
                    let fullLogs = logger.logs.joined(separator: "\n")
                    ClipboardHelper.copy(fullLogs)
                    copyNotice = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copyNotice = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copyNotice ? "checkmark" : "doc.on.doc")
                        Text(copyNotice ? "Đã sao chép!" : "Sao chép tất cả")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(logger.logs.isEmpty)

                Spacer()

                Button(action: {
                    logger.clearLogs()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Xóa log")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(logger.logs.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Color.secondary.opacity(0.06))
        }
    }

    private func logColor(for text: String) -> Color {
        if text.contains("[ERROR]") {
            return .red
        } else if text.contains("[DEBUG]") {
            return .secondary
        } else {
            return .primary
        }
    }
}

