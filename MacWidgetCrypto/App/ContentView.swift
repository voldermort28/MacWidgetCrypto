import SwiftUI

struct ContentView: View {
    @StateObject private var portfolioManager = PortfolioManager.shared
    @State private var coins: [Coin] = []
    @State private var isLoading = false

    private var snapshot: PortfolioSnapshot {
        PortfolioSnapshotBuilder.makeSnapshot(from: coins, portfolio: portfolioManager, maxCoins: 4)
    }

    private var chartAccentColor: Color {
        guard let first = snapshot.totalHistory.first, let last = snapshot.totalHistory.last else {
            return .green
        }

        return last >= first ? .green : .red
    }
    
    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Đang tải dữ liệu...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(header: Text("Tài sản của tôi")) {
                        HStack {
                            Text("Tổng Giá Trị")
                                .font(.headline)
                            Spacer()
                            Text(portfolioManager.calculateTotalValue(coins: coins).formattedCurrency())
                                .font(.title2)
                                .bold()
                                .foregroundColor(.green)
                        }
                    }

                    Section(header: Text("Biểu đồ danh mục")) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(snapshot.showsRealHoldings ? "Danh mục hiện tại" : "Xem trước từ top coin")
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
                                .frame(height: 140)
                            } else {
                                Text("Chưa có đủ dữ liệu để vẽ chart. Hãy nhập số lượng coin bạn đang nắm giữ.")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Section(header: Text("Widget")) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Widget không tự hiện trong cửa sổ app. Trên macOS, hãy Control-click lên Desktop rồi chọn Edit Widgets, sau đó tìm \"Crypto Portfolio\" hoặc \"MacWidgetCrypto\" để thêm ra Desktop hoặc Notification Center.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("Nếu vẫn chưa thấy trong gallery, hãy đóng app, copy app vào thư mục Applications, mở lại app một lần rồi thử Edit Widgets lại.")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Section(header: Text("Danh sách Coin")) {
                        ForEach(coins) { coin in
                            CoinRowView(coin: coin, amount: portfolioManager.getAmount(for: coin.id))
                        }
                    }
                }
            }
        }
        .navigationTitle("MacCrypto")
        .toolbar {
            Button(action: loadData) {
                Image(systemName: "arrow.clockwise")
            }
        }
        .onAppear(perform: loadData)
    }
    
    func loadData() {
        isLoading = true
        CryptoService.shared.fetchCoins { fetchedCoins in
            DispatchQueue.main.async {
                self.coins = fetchedCoins ?? []
                self.isLoading = false
            }
        }
    }
}

struct CoinRowView: View {
    let coin: Coin
    @State var amount: Double
    
    var body: some View {
        HStack {
            AsyncImage(url: URL(string: "https://assets.coingecko.com/coins/images/1/small/bitcoin.png")) { image in
                image.resizable() // Placeholder, real app should map coin image URL if available in model
            } placeholder: {
                Circle().fill(Color.gray).frame(width: 30, height: 30)
            }
            .frame(width: 30, height: 30)
            
            VStack(alignment: .leading) {
                Text(coin.name).font(.headline)
                Text(coin.symbol.uppercased()).font(.subheadline).foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(coin.formattedPrice)
                Text(coin.formattedChange)
                    .foregroundColor(coin.priceChangePercentage24H >= 0 ? .green : .red)
                    .font(.caption)
            }
            
            // Editable TextField for Amount
            TextField("Số lượng", value: $amount, format: .number)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
                .onChange(of: amount) { newValue in
                    PortfolioManager.shared.updateHolding(coinId: coin.id, amount: newValue)
                }
        }
        .padding(.vertical, 4)
    }
}
