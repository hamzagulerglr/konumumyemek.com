import Charts
import SwiftUI

struct WebPanelView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var directory: KonumumDirectory

    @State private var bayi = ""
    @State private var kitchenPin = ""
    @State private var restaurantAttempted = false
    @State private var showKitchen = false
    @State private var showCustomerGate = false

    var body: some View {
        ZStack {
            KonumumTheme.graphite.ignoresSafeArea()
            RadialGradient(
                colors: [KonumumTheme.neon.opacity(0.16), .clear],
                center: UnitPoint(x: 0.82, y: 0),
                startRadius: 8,
                endRadius: 320
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                browserChrome
                headerBar
                if let customer = directory.customerSession {
                    CustomerDashboardView(customer: customer)
                } else {
                    restaurantWorkspace
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showCustomerGate) {
            CustomerGateSheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(KonumumTheme.graphite)
        }
        .fullScreenCover(isPresented: $showKitchen) {
            RestaurantKitchenView(route: directory.liveKitchenRoute) {
                showKitchen = false
                directory.popToMenusHome()
                dismiss()
            }
            .environment(\.popToHome, {
                showKitchen = false
                directory.popToMenusHome()
                dismiss()
            })
            .environmentObject(directory)
        }
    }

    private var browserChrome: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1, green: 0.38, blue: 0.35)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 1, green: 0.76, blue: 0.18)).frame(width: 10, height: 10)
                Circle().fill(Color(red: 0.22, green: 0.8, blue: 0.4)).frame(width: 10, height: 10)
            }
            Text("https://konumumyemek.com/panel")
                .font(KonumumFont.plate(12))
                .foregroundStyle(Color.white.opacity(0.72))
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 32)
                .background(Color.white.opacity(0.06), in: Capsule())
            Button("Uygulama") { dismiss() }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KonumumTheme.neon)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
    }

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            KonumumBrandMark(size: 42)
            Text("konumumyemek.com - Restoran Kurumsal Yönetim Paneli")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(KonumumTheme.neon)
                .shadow(color: KonumumTheme.neon.opacity(0.55), radius: 8)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 8)
            Button {
                showCustomerGate = true
            } label: {
                Text("Müşteri Girişi")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KonumumTheme.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(KonumumTheme.neon, in: Capsule())
                    .shadow(color: KonumumTheme.neon.opacity(0.7), radius: 10)
            }
            .buttonStyle(KonumumPressStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var restaurantWorkspace: some View {
        GeometryReader { geo in
            let stacked = geo.size.width < 700
            let columns = stacked
                ? [GridItem(.flexible(), spacing: 16)]
                : [GridItem(.flexible(minimum: 240, maximum: 320), spacing: 16), GridItem(.flexible(), spacing: 16)]
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    restaurantGate
                    restaurantStage
                }
                .padding(20)
            }
        }
    }

    private var restaurantGate: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Restoran Giriş")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            labeled("E-posta veya Bayi Kodu")
            webField($bayi, placeholder: "mcd@konumumyemek.com", mono: false)
            labeled("Şifre")
            SecureField("", text: $kitchenPin, prompt: Text("••••••••").foregroundStyle(Color.white.opacity(0.32)))
                .textContentType(.password)
                .font(KonumumFont.plate(16))
                .foregroundStyle(.white)
                .tint(KonumumTheme.neon)
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(webWell())
            if restaurantAttempted && directory.restaurantSession == nil {
                Text("E-posta, bayi kodu veya şifre hatalı")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KonumumTheme.danger)
            }
            Button(action: fillRestaurantDemo) {
                Text("Simülasyon: Restoranı Doldur")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KonumumTheme.neon)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(KonumumTheme.neon.opacity(0.7), lineWidth: 1)
                    }
            }
            .buttonStyle(KonumumPressStyle())
            Button(action: submitRestaurant) {
                Text(directory.restaurantSession == nil ? "Kurumsal Giriş" : "Oturum Açık")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(KonumumTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(KonumumTheme.neon, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(KonumumPressStyle())
            if directory.restaurantSession != nil {
                Button("Restoran Oturumunu Kapat") {
                    directory.signOutRestaurant()
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.6))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(panelCard())
    }

    @ViewBuilder
    private var restaurantStage: some View {
        if let restaurant = directory.restaurantSession {
            VStack(alignment: .leading, spacing: 16) {
                RestaurantSellerDeskView(restaurant: restaurant) {
                    showKitchen = true
                }

                HStack(spacing: 12) {
                    metricCard(
                        title: "Bugün Arabadan Teslim Edilen Toplam Sipariş",
                        value: "\(directory.todayDeliveredCount(for: restaurant))"
                    )
                    metricCard(
                        title: "Kazanılan Toplam Ciro",
                        value: "₺\(directory.todayRevenue(for: restaurant))"
                    )
                }

                Text("Ciro Dağılımı (Sodexo / Metropol / Nakit / Kart)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)

                Chart(directory.revenueByBrand(for: restaurant), id: \.0) { item in
                    BarMark(
                        x: .value("Kanal", item.0.rawValue),
                        y: .value("Ciro", item.1)
                    )
                    .foregroundStyle(KonumumTheme.neon)
                    .cornerRadius(6)
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name).foregroundStyle(Color.white.opacity(0.7))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.12))
                        AxisValueLabel {
                            if let amount = value.as(Int.self) {
                                Text("₺\(amount)").foregroundStyle(Color.white.opacity(0.55))
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(panelCard())
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Kurumsal sahne bekleniyor")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text("E-posta ve şifre doğrulanınca masaüstü tersine takip, firma bilgileri ve ciro paneli açılır.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(panelCard())
        }
    }

    private func metricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            Text(value)
                .font(KonumumFont.plate(26))
                .foregroundStyle(KonumumTheme.neon)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func labeled(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color.white.opacity(0.62))
    }

    private func webField(_ text: Binding<String>, placeholder: String, mono: Bool) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Color.white.opacity(0.32)))
            .textFieldStyle(.plain)
            .font(mono ? KonumumFont.plate(16) : .system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .tint(KonumumTheme.neon)
            .textInputAutocapitalization(mono ? .characters : .never)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(webWell())
    }

    private func webWell() -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
    }

    private func panelCard() -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
    }

    private func fillRestaurantDemo() {
        bayi = "mcd@konumumyemek.com"
        kitchenPin = "mutfak55"
        restaurantAttempted = false
    }

    private func submitRestaurant() {
        restaurantAttempted = true
        _ = directory.signInRestaurant(bayi: bayi, password: kitchenPin)
    }
}

private struct CustomerGateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var directory: KonumumDirectory
    @State private var identifier = ""
    @State private var password = ""
    @State private var attempted = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Müşteri Giriş Odası")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("E-posta veya telefon ve şifre ile web paneline girin. Bilgiler cihazda kalır.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                Text("E-posta / Telefon")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
                TextField("", text: $identifier, prompt: Text("musteri@konumumyemek.com").foregroundStyle(Color.white.opacity(0.32)))
                    .textFieldStyle(.plain)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .tint(KonumumTheme.neon)
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(fieldWell())
                Text("Şifre")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.62))
                SecureField("", text: $password, prompt: Text("••••••••").foregroundStyle(Color.white.opacity(0.32)))
                    .textContentType(.password)
                    .font(KonumumFont.plate(16))
                    .foregroundStyle(.white)
                    .tint(KonumumTheme.neon)
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(fieldWell())
                if attempted {
                    Text("E-posta, telefon veya şifre hatalı")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(KonumumTheme.danger)
                }
                Button {
                    identifier = "musteri@konumumyemek.com"
                    password = "konumum55"
                    attempted = false
                } label: {
                    Text("Simülasyon: Müşteriyi Doldur")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KonumumTheme.neon)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(KonumumTheme.neon.opacity(0.7), lineWidth: 1)
                        }
                }
                .buttonStyle(KonumumPressStyle())
                Button {
                    if directory.signInCustomer(identifier: identifier, password: password) {
                        password = ""
                        dismiss()
                    } else {
                        attempted = true
                    }
                } label: {
                    Text("Panele Gir")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(KonumumTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(KonumumTheme.neon, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(KonumumPressStyle())
                Spacer()
            }
            .padding(22)
            .background(KonumumTheme.graphite.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(KonumumTheme.neon)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func fieldWell() -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
    }
}

private struct CustomerDashboardView: View {
    @EnvironmentObject private var directory: KonumumDirectory
    let customer: KonumumCustomerAccount

    private let timeStamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Müşteri Web Paneli")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        Text(customer.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.62))
                    }
                    Spacer()
                    Button("Çıkış") { directory.signOutCustomer() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KonumumTheme.neon)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Aktif Araç Plakalarım")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    ForEach(customer.plates, id: \.self) { plate in
                        Text(plate)
                            .font(KonumumFont.plate(28))
                            .tracking(4)
                            .foregroundStyle(KonumumTheme.ink)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(KonumumTheme.neon, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: KonumumTheme.neon.opacity(0.85), radius: 12)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(card())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Kayıtlı Yemek Kartlarım")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        ForEach(customer.mealCards) { brand in
                            Text(brand.rawValue)
                                .font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 52)
                                .background(cardFill(brand), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(card())

                VStack(alignment: .leading, spacing: 10) {
                    Text("Geçmiş Arabadan Teslimat Siparişlerim")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 0) {
                        tableRow("Saat", "Restoran", "Plaka", "Ödeme", "Tutar", header: true)
                        ForEach(directory.customerOrders(for: customer)) { order in
                            let restaurant = directory.restaurants.first(where: { $0.id == order.restaurantId })
                            tableRow(
                                timeStamp.string(from: order.createdAt),
                                restaurant?.brandName ?? "—",
                                order.plate,
                                order.payment.rawValue,
                                "₺\(order.total)",
                                header: false,
                                live: !order.delivered
                            )
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(card())
            }
            .padding(20)
        }
    }

    private func tableRow(
        _ a: String,
        _ b: String,
        _ c: String,
        _ d: String,
        _ e: String,
        header: Bool,
        live: Bool = false
    ) -> some View {
        GridRow {
            cell(a, header: header)
            cell(b, header: header)
            cell(c, header: header, mono: true)
            cell(d, header: header)
            cell(e, header: header, mono: true)
        }
        .padding(.vertical, 10)
        .background(live ? KonumumTheme.neon.opacity(0.12) : Color.clear)
    }

    private func cell(_ text: String, header: Bool, mono: Bool = false) -> some View {
        Text(text)
            .font(header ? .system(size: 11, weight: .bold) : (mono ? KonumumFont.plate(12) : .system(size: 12, weight: .medium)))
            .foregroundStyle(header ? Color.white.opacity(0.5) : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .gridColumnAlignment(.leading)
    }

    private func card() -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color.white.opacity(0.04))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
    }

    private func cardFill(_ brand: MealCardBrand) -> Color {
        switch brand {
        case .applePay: .black
        case .googlePay: Color.white
        case .sodexo: Color(red: 0.894, green: 0.094, blue: 0.141)
        case .multinet: Color(red: 0.000, green: 0.306, blue: 0.690)
        case .setcard: Color(red: 0.227, green: 0.639, blue: 0.196)
        case .metropol: Color(red: 1.0, green: 0.08, blue: 0.22)
        case .ticket: Color(red: 0.55, green: 0.08, blue: 0.18)
        case .nakit: Color.white.opacity(0.16)
        case .krediKarti: Color(red: 0.16, green: 0.18, blue: 0.23)
        }
    }
}

#Preview {
    WebPanelView()
        .environmentObject(KonumumDirectory())
        .preferredColorScheme(.dark)
}
