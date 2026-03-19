import SwiftUI

struct ContentView: View {
    @StateObject private var portfolioManager = PortfolioManager.shared
    @State private var coins: [Coin] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Đang tải dữ liệu...")
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

                        Section(header: Text("Widget")) {
                            Text("Sau khi chạy app, bạn có thể thêm widget từ gallery của hệ thống. Trên iOS 15.5 widget hiển thị ở Home Screen và Today View; trên macOS 14 widget hiển thị trong Notification Center hoặc trên Desktop.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
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
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
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
