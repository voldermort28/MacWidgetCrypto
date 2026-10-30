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

enum NavigationTarget: Hashable {
    case portfolio
    case coin(String)
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var portfolioManager = PortfolioManager.shared
    @State private var coins: [Coin] = []
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    // Apple Stocks State
    @State private var selectedTarget: NavigationTarget = .portfolio
    @State private var navigateToDetail: Bool = false
    @State private var selectedTimeframe: String = "1D"
    @State private var searchQuery: String = ""
    @State private var showPercentage: Bool = true
    @State private var coinKlines: [KlinePoint] = []
    @State private var coinStats: Binance24hStats? = nil
    @State private var isLoadingDetail: Bool = false
    @State private var hoveredPoint: KlinePoint? = nil

    // Sheets & Modals
    @State private var showingAddCoinSheet = false
    @State private var showingSyncSheet = false
    @State private var showingLogsSheet = false
    @State private var activeHoldingTarget: HoldingTarget? = nil

    @State private var autoRefreshTimer: Timer? = nil

    private var currentSelectedCoin: Coin? {
        if case .coin(let id) = selectedTarget {
            return coins.first(where: { $0.id == id })
        }
        return coins.first
    }

    private var filteredCoins: [Coin] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if q.isEmpty { return coins }
        return coins.filter {
            $0.symbol.uppercased().contains(q) || $0.name.uppercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            Group {
                #if os(macOS)
                NavigationSplitView {
                    sidebarView
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 400)
                } detail: {
                    detailView
                        .frame(minWidth: 520, idealWidth: 700)
                }
                #else
                NavigationView {
                    ZStack {
                        sidebarView

                        NavigationLink(
                            destination: detailView,
                            isActive: $navigateToDetail
                        ) {
                            EmptyView()
                        }
                        .hidden()
                    }
                    .navigationTitle("MacCrypto")
                    .navigationBarTitleDisplayMode(.inline)
                }
                .navigationViewStyle(StackNavigationViewStyle())
                #endif
            }

            // Custom Holding Amount Modal Overlay for ContentView
            if let target = activeHoldingTarget {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeHoldingTarget = nil
                        }
                    }

                HoldingAmountModalView(
                    target: target,
                    currentAmount: portfolioManager.getAmount(for: target.coinId),
                    onSave: { amount in
                        portfolioManager.updateHolding(coinId: target.coinId, amount: amount)
                        loadData(isBackgroundRefresh: true)
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeHoldingTarget = nil
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeHoldingTarget = nil
                        }
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture { }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeHoldingTarget != nil)
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
        .onAppear(perform: handleOnAppear)
        .onDisappear(perform: stopTimers)
        .onChange(of: scenePhase) { newPhase in
            handleScenePhaseChange(newPhase)
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
        #endif
    }

    // MARK: - Left Sidebar View
    private var sidebarView: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Search", text: $searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12))
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.08))
            .cornerRadius(8)
            .padding(.horizontal, 10)
            .padding(.top, 8)

            // Clickable Portfolio Summary Card
            portfolioSummaryCard
                .padding(.horizontal, 10)
                .padding(.top, 8)

            // My Symbols Header
            HStack {
                Text("My Symbols")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Binance Realtime")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.8))
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)

            // Coin List
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filteredCoins) { coin in
                        sidebarCoinRow(for: coin)
                    }
                }
                .padding(.horizontal, 6)
            }

            Spacer(minLength: 0)

            // Bottom Action Strip
            HStack {
                Button(action: { showingAddCoinSheet = true }) {
                    Label("Thêm Coin", systemImage: "plus")
                        .font(.caption.bold())
                }
                .buttonStyle(BorderlessButtonStyle())

                Spacer()

                Button(action: { showingSyncSheet = true }) {
                    Image(systemName: "arrow.triangle.2.circlepath.icloud")
                        .font(.caption)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Đồng bộ danh mục")

                Button(action: { showingLogsSheet = true }) {
                    Image(systemName: "terminal")
                        .font(.caption)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help("Xem Logs")

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: { loadData(isBackgroundRefresh: false) }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .help("Làm mới giá từ Binance")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
        }
        .background(Color(red: 0.10, green: 0.10, blue: 0.12))
    }



    private func handleOnAppear() {
        let cached = CryptoService.shared.getCachedCoins()
        if !cached.isEmpty {
            self.coins = cached
        }
        loadData()
        startForegroundTimer()
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .active {
            AppLogger.info("App mở / Active. Cập nhật giá ngay lập tức và chạy timer 30s.")
            loadData(isBackgroundRefresh: true)
            startForegroundTimer()
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            WidgetCenter.shared.reloadTimelines(ofKind: "CryptoWidget")
            #endif
        } else {
            AppLogger.info("App vào background / sleep. Giãn chu kỳ cập nhật lên 60 phút.")
            startBackgroundTimer()
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            WidgetCenter.shared.reloadTimelines(ofKind: "CryptoWidget")
            #endif
        }
    }

    private var portfolioHistory: [Double] {
        PortfolioSnapshotBuilder.makeSnapshot(from: coins, portfolio: portfolioManager).totalHistory
    }

    // MARK: - Portfolio Summary Card in Sidebar
    private var portfolioSummaryCard: some View {
        PortfolioSummaryCardView(
            isSelected: selectedTarget == .portfolio,
            totalVal: portfolioManager.calculateTotalValue(coins: coins),
            heldCount: coins.filter { portfolioManager.getAmount(for: $0.id) > 0 }.count,
            history: portfolioHistory,
            onSelect: {
                selectedTarget = .portfolio
                loadDetailData()
                #if os(iOS)
                navigateToDetail = true
                #endif
            }
        )
    }

    // MARK: - Sidebar Coin Row
    private func sidebarCoinRow(for coin: Coin) -> some View {
        let amount = portfolioManager.getAmount(for: coin.id)
        return SidebarCoinRowView(
            coin: coin,
            isSelected: selectedTarget == .coin(coin.id),
            showPercentage: showPercentage,
            amount: amount,
            onSelect: {
                selectedTarget = .coin(coin.id)
                loadDetailData()
                #if os(iOS)
                navigateToDetail = true
                #endif
            },
            onTogglePercentage: {
                showPercentage.toggle()
            },
            onEditAmount: {
                activeHoldingTarget = HoldingTarget(
                    coinId: coin.id,
                    symbol: coin.symbol,
                    name: coin.name,
                    currentPrice: coin.currentPrice,
                    isNew: false
                )
            },
            onDelete: {
                deleteCoin(coin)
            }
        )
    }

    // MARK: - Right Detail View
    private var detailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                #if os(iOS)
                HStack {
                    Button(action: { navigateToDetail = false }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Danh sách")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.accentColor)
                    }
                    Spacer()
                }
                .padding(.bottom, 2)
                #endif

                if selectedTarget == .portfolio {
                    portfolioDetailSection
                } else {
                    coinDetailSection
                }
            }
            .padding(20)
        }
        .background(Color(red: 0.11, green: 0.11, blue: 0.13))
        #if os(iOS)
        .navigationTitle(selectedTarget == .portfolio ? "Tổng danh mục" : "\(currentSelectedCoin?.symbol.uppercased() ?? "")-USD")
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Coin Detail Section
    private var coinDetailSection: some View {
        let coin = currentSelectedCoin
        let isUp = (coinStats?.priceChangePercent ?? coin?.priceChangePercentage24H ?? 0) >= 0

        return VStack(alignment: .leading, spacing: 16) {
            // Hero Header
            coinDetailHeader

            // Timeframe Selector: 1D, 1W, 1M, 6M, 1Y, ALL
            timeframeSelector

            // Interactive Volatility Chart with X-axis, Y-axis, dashed baseline & Volume bars
            DetailChartView(
                klines: coinKlines,
                selectedTimeframe: selectedTimeframe,
                isPositive: isUp,
                baselinePrice: coinKlines.first?.close,
                hoveredPoint: $hoveredPoint
            )
            .frame(height: 280)
            .padding(10)
            .background(Color.black.opacity(0.30))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            // User Holdings Card
            userHoldingsCard

            // Market Statistics Grid (Live from Binance 24hr API)
            marketStatsGrid
        }
    }

    private var coinDetailHeader: some View {
        let coin = currentSelectedCoin
        let symbol = coin?.symbol.uppercased() ?? "COIN"
        let name = coin?.name ?? "Crypto Asset"
        let currentPrice = coin?.currentPrice ?? 0
        let displayPrice = hoveredPoint?.close ?? coinStats?.lastPrice ?? currentPrice

        let baseline = coinKlines.first?.close ?? coinStats?.openPrice ?? displayPrice
        let changeVal = displayPrice - baseline
        let changePct = baseline > 0 ? (changeVal / baseline) * 100.0 : (coinStats?.priceChangePercent ?? 0)
        let isUp = changeVal >= 0
        let accent = isUp ? Color(red: 0.19, green: 0.82, blue: 0.35) : Color(red: 1.0, green: 0.27, blue: 0.23)

        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(symbol)-USD")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text(name)
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                Text("BINANCE SPOT · USD")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatDisplayPrice(displayPrice))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    Text(String(format: "%@%.2f (%@%.2f%%)", isUp ? "+" : "", changeVal, isUp ? "+" : "", changePct))
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(accent)

                    if let hovered = hoveredPoint {
                        Text(formatHoverTime(hovered.time))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        Text(timeframePeriodLabel)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var timeframeSelector: some View {
        HStack(spacing: 8) {
            ForEach(["1D", "1W", "1M", "6M", "1Y", "ALL"], id: \.self) { tf in
                Button(action: {
                    selectedTimeframe = tf
                    loadDetailData()
                }) {
                    Text(tf)
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            selectedTimeframe == tf
                                ? Color.white.opacity(0.22)
                                : Color.clear
                        )
                        .foregroundColor(
                            selectedTimeframe == tf
                                ? .white
                                : .secondary
                        )
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(red: 0.19, green: 0.82, blue: 0.35))
                    .frame(width: 6, height: 6)
                Text("Binance Realtime")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var userHoldingsCard: some View {
        let coin = currentSelectedCoin
        let coinId = coin?.id ?? ""
        let amount = portfolioManager.getAmount(for: coinId)
        let price = coin?.currentPrice ?? 0
        let totalVal = amount * price
        let totalPortVal = portfolioManager.calculateTotalValue(coins: coins)
        let sharePct = totalPortVal > 0 ? (totalVal / totalPortVal) * 100.0 : 0.0

        return HStack {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 40, height: 40)
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tài sản trong ví của bạn")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        Text("\(amount.formattedAmount()) \(coin?.symbol.uppercased() ?? "")")
                            .font(.title3.bold())
                            .foregroundColor(.white)
                        if totalVal > 0 {
                            Text("≈ \(totalVal.formattedCurrency())")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(Color(red: 0.19, green: 0.82, blue: 0.35))
                        }
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Tỷ trọng ví")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.2f%%", sharePct))
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Button("Sửa số lượng") {
                    if let c = coin {
                        activeHoldingTarget = HoldingTarget(
                            coinId: c.id,
                            symbol: c.symbol,
                            name: c.name,
                            currentPrice: c.currentPrice,
                            isNew: false
                        )
                    }
                }
                .font(.caption2.bold())
                .foregroundColor(.blue)
                .buttonStyle(BorderlessButtonStyle())
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private var marketStatsGrid: some View {
        let stats = coinStats
        return VStack(alignment: .leading, spacing: 8) {
            Text("Thống Kê Giao Dịch & Thị Trường (Binance 24h)")
                .font(.caption.weight(.bold))
                .foregroundColor(.secondary)

            Divider().background(Color.white.opacity(0.12))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                statRow(label: "Today's Open", value: stats != nil ? stats!.openPrice.formattedCurrency() : "—")
                statRow(label: "52-Week High", value: stats?.high52Week != nil ? stats!.high52Week!.formattedCurrency() : "—")

                statRow(label: "Today's High", value: stats != nil ? stats!.highPrice.formattedCurrency() : "—")
                statRow(label: "52-Week Low", value: stats?.low52Week != nil ? stats!.low52Week!.formattedCurrency() : "—")

                statRow(label: "Today's Low", value: stats != nil ? stats!.lowPrice.formattedCurrency() : "—")
                statRow(label: "24h Volume (Coin)", value: stats != nil ? stats!.volume.formattedVolume() : "—")

                statRow(label: "24h Volume (USDT)", value: stats != nil ? stats!.quoteVolume.formattedVolume() : "—")
                statRow(label: "Weighted Avg Price", value: stats != nil ? stats!.weightedAvgPrice.formattedCurrency() : "—")
            }
        }
    }

    // MARK: - Portfolio Detail Section
    private var portfolioDetailSection: some View {
        let totalVal = portfolioManager.calculateTotalValue(coins: coins)
        let heldCoins = coins.filter { portfolioManager.getAmount(for: $0.id) > 0 }

        return VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("PORTFOLIO")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Tổng Giá Trị Danh Mục Ví")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    Text("\(heldCountText) • Realtime Valuation USD")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(totalVal.formattedCurrency())
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Danh mục hoạt động")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color(red: 0.19, green: 0.82, blue: 0.35))
                }
            }

            // Timeframe Selector
            timeframeSelector

            // Portfolio Volatility Chart
            DetailChartView(
                klines: coinKlines,
                selectedTimeframe: selectedTimeframe,
                isPositive: true,
                baselinePrice: coinKlines.first?.close,
                hoveredPoint: $hoveredPoint
            )
            .frame(height: 280)
            .padding(10)
            .background(Color.black.opacity(0.30))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )

            // Asset Allocation Breakdown Table
            VStack(alignment: .leading, spacing: 10) {
                Text("Cơ Cấu Phân Bổ Danh Mục Ví")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.secondary)

                Divider().background(Color.white.opacity(0.12))

                if heldCoins.isEmpty {
                    Text("Chưa có coin nào được nhập số lượng trong ví. Hãy bấm vào từng đồng coin bên trái để nhập số dư.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(heldCoins) { coin in
                        allocationRow(coin: coin, totalVal: totalVal)
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .cornerRadius(12)
        }
    }

    private func allocationRow(coin: Coin, totalVal: Double) -> some View {
        let amount = portfolioManager.getAmount(for: coin.id)
        let val = amount * coin.currentPrice
        let share = totalVal > 0 ? (val / totalVal) * 100.0 : 0.0

        return Button(action: {
            activeHoldingTarget = HoldingTarget(
                coinId: coin.id,
                symbol: coin.symbol,
                name: coin.name,
                currentPrice: coin.currentPrice,
                isNew: false
            )
        }) {
            VStack(spacing: 4) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(coin.symbol.uppercased())-USD")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text(coin.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(amount.formattedAmount()) \(coin.symbol.uppercased())")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(val.formattedCurrency())
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Text(String(format: "%.1f%% danh mục", share))
                            .font(.caption2)
                            .foregroundColor(Color(red: 0.19, green: 0.82, blue: 0.35))
                    }
                    Image(systemName: "pencil.circle")
                        .font(.caption)
                        .foregroundColor(.blue.opacity(0.8))
                        .padding(.leading, 4)
                }
                .padding(.vertical, 4)
                Divider().background(Color.white.opacity(0.06))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var heldCountText: String {
        let count = coins.filter { portfolioManager.getAmount(for: $0.id) > 0 }.count
        return "\(count) Coin đang nắm giữ"
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption.bold())
                .foregroundColor(.white)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.white.opacity(0.03))
        .cornerRadius(6)
    }

    private var timeframePeriodLabel: String {
        switch selectedTimeframe {
        case "1D": return "Past 24 Hours"
        case "1W": return "Past Week"
        case "1M": return "Past Month"
        case "6M": return "Past 6 Months"
        case "1Y": return "Past Year"
        case "ALL": return "All Time"
        default: return "Past 24 Hours"
        }
    }

    private func formatDisplayPrice(_ price: Double) -> String {
        if price >= 1000 {
            return price.formattedCurrency(maxDecimals: 2)
        } else if price >= 1 {
            return price.formattedCurrency(maxDecimals: 2)
        } else {
            return String(format: "US$%.4f", price)
        }
    }

    private func formatHoverTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM HH:mm"
        return f.string(from: date)
    }

    // MARK: - Data Loading
    func loadData(isBackgroundRefresh: Bool = false) {
        if coins.isEmpty || !isBackgroundRefresh {
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
                }
                self.loadDetailData()
                #if canImport(WidgetKit)
                WidgetCenter.shared.reloadAllTimelines()
                #endif
            }
        }
    }

    private func loadDetailData() {
        if case .portfolio = selectedTarget {
            loadPortfolioDetailKlines()
            return
        }

        guard let coin = currentSelectedCoin else { return }
        let info = CryptoService.getCoinInfo(for: coin.id)
        let (interval, limit) = timeframeParameters(for: selectedTimeframe)

        isLoadingDetail = true
        Task {
            let klines = await CryptoService.shared.fetchDetailedKlines(symbol: info.ticker, interval: interval, limit: limit)
            let stats = await CryptoService.shared.fetch24hStats(symbol: info.ticker)
            await MainActor.run {
                self.coinKlines = klines
                self.coinStats = stats
                self.isLoadingDetail = false
            }
        }
    }

    private func loadPortfolioDetailKlines() {
        let heldCoins = coins.filter { portfolioManager.getAmount(for: $0.id) > 0 }
        guard !heldCoins.isEmpty else {
            self.coinKlines = []
            self.coinStats = nil
            return
        }

        let (interval, limit) = timeframeParameters(for: selectedTimeframe)
        isLoadingDetail = true
        Task {
            var coinKlinesList: [[KlinePoint]] = []
            for coin in heldCoins {
                let info = CryptoService.getCoinInfo(for: coin.id)
                let pts = await CryptoService.shared.fetchDetailedKlines(symbol: info.ticker, interval: interval, limit: limit)
                if !pts.isEmpty {
                    coinKlinesList.append(pts)
                }
            }

            await MainActor.run {
                self.isLoadingDetail = false
                guard !coinKlinesList.isEmpty else { return }
                let minCount = coinKlinesList.map(\.count).min() ?? 0
                guard minCount > 1 else { return }

                var mergedPoints: [KlinePoint] = []
                for i in 0..<minCount {
                    var sumClose = 0.0
                    var sumOpen = 0.0
                    var sumHigh = 0.0
                    var sumLow = 0.0
                    var sumVol = 0.0
                    var ptTime = Date()

                    for (cIndex, coin) in heldCoins.enumerated() {
                        if cIndex < coinKlinesList.count {
                            let pts = coinKlinesList[cIndex]
                            let pt = pts[pts.count - minCount + i]
                            ptTime = pt.time
                            let amt = portfolioManager.getAmount(for: coin.id)
                            sumClose += pt.close * amt
                            sumOpen += pt.open * amt
                            sumHigh += pt.high * amt
                            sumLow += pt.low * amt
                            sumVol += pt.volume
                        }
                    }
                    mergedPoints.append(KlinePoint(time: ptTime, open: sumOpen, high: sumHigh, low: sumLow, close: sumClose, volume: sumVol))
                }
                self.coinKlines = mergedPoints
            }
        }
    }

    private func timeframeParameters(for tf: String) -> (String, Int) {
        switch tf {
        case "1D": return ("1h", 24)
        case "1W": return ("4h", 42)
        case "1M": return ("1d", 30)
        case "6M": return ("1w", 26)
        case "1Y": return ("1w", 52)
        case "ALL": return ("1M", 60)
        default: return ("1h", 24)
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
        if case .coin(let id) = selectedTarget, id == coin.id {
            selectedTarget = .portfolio
            loadDetailData()
        }
    }
}

// MARK: - Standalone Portfolio Summary Card Component
struct PortfolioSummaryCardView: View {
    let isSelected: Bool
    let totalVal: Double
    let heldCount: Int
    let history: [Double]
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "wallet.pass.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.blue)
                        Text("TỔNG GIÁ TRỊ VÍ")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(heldCount) tài sản")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(red: 0.19, green: 0.82, blue: 0.35))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.19, green: 0.82, blue: 0.35).opacity(0.18))
                        .cornerRadius(4)
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(totalVal.formattedCurrency())
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text("Xem biểu đồ ví ›")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.blue)
                }

                if history.count > 1 {
                    SparklineView(
                        data: history,
                        baselinePrice: history.first,
                        lineColor: Color(red: 0.19, green: 0.82, blue: 0.35),
                        fillColor: Color(red: 0.19, green: 0.82, blue: 0.35),
                        showBaseline: true
                    )
                    .frame(height: 28)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.blue.opacity(0.20) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? Color.blue : Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Standalone Sidebar Coin Row Component
struct SidebarCoinRowView: View {
    let coin: Coin
    let isSelected: Bool
    let showPercentage: Bool
    let amount: Double
    let onSelect: () -> Void
    let onTogglePercentage: () -> Void
    let onEditAmount: () -> Void
    let onDelete: () -> Void

    private var isUp: Bool { coin.priceChangePercentage24H >= 0 }
    private var stockRed: Color { Color(red: 1.0, green: 0.27, blue: 0.23) }
    private var stockGreen: Color { Color(red: 0.19, green: 0.82, blue: 0.35) }
    private var accent: Color { isUp ? stockGreen : stockRed }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                // Left: Symbol & Name
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(coin.symbol.uppercased())-USD")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(coin.name)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        if amount > 0 {
                            Text("• \(amount.formattedAmount())")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Middle: Sharp 24h zigzag sparkline with dashed baseline
                if let prices = coin.sparklineIn7D?.price, prices.count > 1 {
                    SparklineView(
                        data: prices,
                        baselinePrice: prices.first,
                        lineColor: accent,
                        fillColor: accent,
                        showBaseline: true
                    )
                    .frame(width: 58, height: 24)
                } else {
                    Spacer().frame(width: 58)
                }

                // Right: Price & Capsule Badge
                VStack(alignment: .trailing, spacing: 2) {
                    Text(coin.formattedPrice)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Button(action: onTogglePercentage) {
                        Text(showPercentage ? coin.formattedChange : String(format: "%@%.2f", isUp ? "+" : "", (coin.currentPrice * coin.priceChangePercentage24H / 100.0)))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(accent)
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .frame(minWidth: 62, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected ? Color.white.opacity(0.12) : Color.clear
            )
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button("Sửa số lượng nắm giữ", action: onEditAmount)
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Xóa khỏi danh mục", systemImage: "trash")
            }
        }
    }
}

// MARK: - Holding Target & Modal Component
struct HoldingTarget: Identifiable, Equatable {
    var id: String { coinId }
    let coinId: String
    let symbol: String
    let name: String
    let currentPrice: Double?
    let isNew: Bool
}

struct HoldingAmountModalView: View {
    let target: HoldingTarget
    let currentAmount: Double
    let onSave: (Double) -> Void
    let onCancel: () -> Void

    @State private var amountText: String
    @FocusState private var isFieldFocused: Bool

    init(target: HoldingTarget, currentAmount: Double, onSave: @escaping (Double) -> Void, onCancel: @escaping () -> Void) {
        self.target = target
        self.currentAmount = currentAmount
        self.onSave = onSave
        self.onCancel = onCancel
        let initial = currentAmount > 0 ? (currentAmount.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", currentAmount) : String(currentAmount)) : ""
        _amountText = State(initialValue: initial)
    }

    private var parsedValue: Double {
        parseCryptoAmount(amountText) ?? 0.0
    }

    private var estimatedValue: Double? {
        guard let price = target.currentPrice, price > 0, parsedValue > 0 else { return nil }
        return parsedValue * price
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.18))
                            .frame(width: 40, height: 40)
                        Image(systemName: target.isNew ? "plus.circle.fill" : "wallet.pass.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(target.isNew ? "Thêm \(target.symbol.uppercased()) vào ví" : "Sửa số lượng \(target.symbol.uppercased())")
                            .font(.headline)
                            .foregroundColor(.white)

                        HStack(spacing: 4) {
                            Text(target.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let price = target.currentPrice, price > 0 {
                                Text("• \(price.formattedCurrency())")
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(Color(red: 0.19, green: 0.82, blue: 0.35))
                            }
                        }
                    }
                }

                Spacer()

                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom, 16)

            // Input Box
            VStack(alignment: .leading, spacing: 6) {
                Text("SỐ LƯỢNG NẮM GIỮ")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    TextField("0.0", text: $amountText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .focused($isFieldFocused)
                        .textFieldStyle(PlainTextFieldStyle())

                    if !amountText.isEmpty {
                        Button(action: { amountText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Text(target.symbol.uppercased())
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.35))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isFieldFocused ? Color.blue : Color.white.opacity(0.12), lineWidth: 1.5)
                )

                // Subtitle / Valuation
                if let est = estimatedValue {
                    HStack(spacing: 4) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.caption2)
                        Text("Ước tính giá trị: \(est.formattedCurrency())")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(Color(red: 0.19, green: 0.82, blue: 0.35))
                    .padding(.top, 2)
                } else {
                    Text(target.isNew ? "Nhập số coin bạn sở hữu hoặc bấm nút bên dưới nếu chỉ muốn theo dõi giá." : "Đặt số lượng là 0 nếu bạn không còn sở hữu coin này.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(.bottom, 18)

            // Action Buttons
            VStack(spacing: 8) {
                Button(action: {
                    onSave(parsedValue)
                }) {
                    Text(target.isNew ? (parsedValue > 0 ? "Lưu vào ví (\(parsedValue.formattedAmount()) \(target.symbol.uppercased()))" : "Xác nhận thêm") : "Lưu thay đổi")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())

                if target.isNew {
                    Button(action: {
                        onSave(0.0)
                    }) {
                        Text("Chỉ theo dõi giá (Số lượng: 0)")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.white.opacity(0.08))
                            .foregroundColor(.secondary)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                } else if currentAmount > 0 {
                    Button(action: {
                        onSave(0.0)
                    }) {
                        Text("Đặt về 0 (Chỉ theo dõi)")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(Color(red: 1.0, green: 0.27, blue: 0.23))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(18)
        .background(Color(red: 0.14, green: 0.14, blue: 0.17))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 25, x: 0, y: 12)
        .frame(maxWidth: 380)
        .padding(.horizontal, 24)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFieldFocused = true
            }
        }
    }
}

struct AddCoinView: View {
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject var portfolioManager = PortfolioManager.shared
    @State private var searchQuery = ""
    @State private var searchResults: [CoinSearchResult] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var activeHoldingTarget: HoldingTarget? = nil
    var onCoinAdded: () -> Void

    var body: some View {
        ZStack {
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

            // Holding Amount Modal Overlay in AddCoinView
            if let target = activeHoldingTarget {
                Color.black.opacity(0.65)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeHoldingTarget = nil
                        }
                    }

                HoldingAmountModalView(
                    target: target,
                    currentAmount: portfolioManager.getAmount(for: target.coinId),
                    onSave: { amount in
                        if amount > 0 {
                            portfolioManager.updateHolding(coinId: target.coinId, amount: amount)
                        } else {
                            portfolioManager.addTrackedCoin(id: target.coinId)
                            portfolioManager.updateHolding(coinId: target.coinId, amount: 0)
                        }
                        onCoinAdded()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeHoldingTarget = nil
                        }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            activeHoldingTarget = nil
                        }
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture { }
                .transition(.scale(scale: 0.95).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: activeHoldingTarget != nil)
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
                            let isTracked = portfolioManager.isTracking(id: result.id)
                            let cachedPrice = CryptoService.shared.getCachedCoins().first(where: {
                                $0.id.lowercased() == result.id.lowercased() || $0.symbol.uppercased() == result.symbol.uppercased()
                            })?.currentPrice
                            let currentAmt = portfolioManager.getAmount(for: result.id)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(result.name)
                                        .font(.headline)
                                    HStack(spacing: 6) {
                                        Text(result.symbol.uppercased())
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        if currentAmt > 0 {
                                            Text("• Đang có \(currentAmt.formattedAmount())")
                                                .font(.caption.bold())
                                                .foregroundColor(Color(red: 0.19, green: 0.82, blue: 0.35))
                                        }
                                    }
                                }
                                Spacer()
                                if isTracked {
                                    HStack(spacing: 8) {
                                        Label("Đã thêm", systemImage: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.caption.bold())

                                        Button("Sửa SL") {
                                            activeHoldingTarget = HoldingTarget(
                                                coinId: result.id,
                                                symbol: result.symbol,
                                                name: result.name,
                                                currentPrice: cachedPrice,
                                                isNew: false
                                            )
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                } else {
                                    Button("Thêm") {
                                        activeHoldingTarget = HoldingTarget(
                                            coinId: result.id,
                                            symbol: result.symbol,
                                            name: result.name,
                                            currentPrice: cachedPrice,
                                            isNew: true
                                        )
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                activeHoldingTarget = HoldingTarget(
                                    coinId: result.id,
                                    symbol: result.symbol,
                                    name: result.name,
                                    currentPrice: cachedPrice,
                                    isNew: !isTracked
                                )
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
                        let isTracked = portfolioManager.isTracking(id: popular.id)
                        let cachedPrice = CryptoService.shared.getCachedCoins().first(where: {
                            $0.id.lowercased() == popular.id.lowercased() || $0.symbol.uppercased() == popular.symbol.uppercased()
                        })?.currentPrice
                        let currentAmt = portfolioManager.getAmount(for: popular.id)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(popular.name)
                                    .font(.headline)
                                HStack(spacing: 6) {
                                    Text(popular.symbol)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    if currentAmt > 0 {
                                        Text("• Đang có \(currentAmt.formattedAmount())")
                                            .font(.caption.bold())
                                            .foregroundColor(Color(red: 0.19, green: 0.82, blue: 0.35))
                                    }
                                }
                            }
                            Spacer()
                            if isTracked {
                                HStack(spacing: 8) {
                                    Label("Đã thêm", systemImage: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption.bold())

                                    Button("Sửa SL") {
                                        activeHoldingTarget = HoldingTarget(
                                            coinId: popular.id,
                                            symbol: popular.symbol,
                                            name: popular.name,
                                            currentPrice: cachedPrice,
                                            isNew: false
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            } else {
                                Button("Thêm") {
                                    activeHoldingTarget = HoldingTarget(
                                        coinId: popular.id,
                                        symbol: popular.symbol,
                                        name: popular.name,
                                        currentPrice: cachedPrice,
                                        isNew: true
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            activeHoldingTarget = HoldingTarget(
                                coinId: popular.id,
                                symbol: popular.symbol,
                                name: popular.name,
                                currentPrice: cachedPrice,
                                isNew: !isTracked
                            )
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

