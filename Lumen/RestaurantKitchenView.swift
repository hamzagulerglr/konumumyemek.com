import SwiftUI

struct KitchenOrderLine: Hashable, Codable {
    var name: String
    var quantity: Int
    var unitPrice: Int

    var lineTotal: Int { quantity * unitPrice }

    var label: String {
        "\(quantity) Adet \(name) - \(lineTotal) TL"
    }
}

struct RestaurantKitchenView: View {
    let route: CarConsoleRoute
    var onCloseOrder: () -> Void = {}

    @EnvironmentObject private var directory: KonumumDirectory
    @Environment(\.popToHome) private var popToHome

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width >= geo.size.height
            panel
                .frame(width: landscape ? geo.size.width : geo.size.height,
                       height: landscape ? geo.size.height : geo.size.width)
                .rotationEffect(landscape ? .zero : .degrees(90))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .background(KonumumTheme.graphite.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden()
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            requestOrientation(.landscape)
        }
        .onChange(of: directory.customerCollectedNotice) { _, shown in
            guard shown else { return }
            Task {
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                directory.popToMenusHome()
                onCloseOrder()
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: directory.customerCollectedNotice)
        .animation(.easeInOut(duration: 0.2), value: directory.liveMeters)
    }

    private var panel: some View {
        VStack(spacing: 0) {
            Text("konumumyemek.com - CANLI MUTFAK TAKİP PANELİ")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(KonumumTheme.neon)
                .shadow(color: KonumumTheme.neon.opacity(0.9), radius: 10)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.55)
                .lineLimit(2)
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 16)

            if directory.customerCollectedNotice {
                Text("Müşteri Siparişi Teslim Aldı")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(KonumumTheme.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(paidGreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: paidGreen.opacity(0.9), radius: 14)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            HStack(alignment: .top, spacing: 16) {
                approachingCard
                orderCard
            }
            .padding(.horizontal, 20)
            .frame(maxHeight: .infinity)

            Button(action: closeOrder) {
                Text("Yemeği Arabaya Teslim Ettim (Siparişi Kapat)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(KonumumTheme.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.7)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .background(KonumumTheme.neon, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: KonumumTheme.neon.opacity(0.95), radius: 14)
                    .shadow(color: KonumumTheme.neon.opacity(0.45), radius: 26, y: 4)
            }
            .buttonStyle(KonumumPressStyle())
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .background(KonumumTheme.graphite)
    }

    private var approachingCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YAKLAŞAN ARAÇ")
                .font(.system(size: 13, weight: .bold))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.62))

            Text(route.plate)
                .font(KonumumFont.plate(34))
                .tracking(4)
                .foregroundStyle(KonumumTheme.ink)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(KonumumProximity.door.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: KonumumProximity.door.tint.opacity(1), radius: 16)
                .shadow(color: KonumumProximity.door.tint.opacity(0.55), radius: 28)

            Text("Araç: Siyah MacBook Air Tasarımlı Premium Sedan")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(directory.liveMeters == 0
                 ? "Mesafe: 0 m (0 sn) - KAPIDA! (Camdan Teslim)"
                 : "Mesafe: \(KonumumDirectory.formatDistanceEta(meters: directory.liveMeters, seconds: directory.liveSeconds))")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .foregroundStyle(directory.liveMeters == 0 ? KonumumProximity.door.tint : KonumumTheme.neon)
                .shadow(color: (directory.liveMeters == 0 ? KonumumProximity.door.tint : KonumumTheme.neon).opacity(0.8), radius: 8)
                .contentTransition(.numericText())

            if let live = directory.deliveries.first(where: { $0.id == route.deliveryId }) {
                if live.atDoor || directory.liveMeters == 0 {
                    Text("ARAÇ KAPIDA · Hazırlanan paketi araç camından teslim edin")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(KonumumProximity.door.tint)
                } else {
                    Text("Canlı takip aktif · Plaka: \(live.plate)")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(KonumumTheme.neon)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(KonumumProximity.door.tint.opacity(0.55), lineWidth: 1.5)
                }
        }
    }

    private var orderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SİPARİŞ DETAYI")
                .font(.system(size: 13, weight: .bold))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.62))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(route.lines, id: \.self) { line in
                    Text(line.label)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            Spacer(minLength: 12)

            Text("Ödeme Durumu")
                .font(.system(size: 13, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.62))

            Text("\(route.paymentTitle) ile ÖDENDİ")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(KonumumTheme.ink)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(paidGreen, in: Capsule())
                .shadow(color: paidGreen.opacity(0.95), radius: 14)
                .shadow(color: paidGreen.opacity(0.5), radius: 24)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
        }
    }

    private var paidGreen: Color {
        Color(red: 0.22, green: 0.95, blue: 0.48)
    }

    private func closeOrder() {
        if let deliveryId = route.deliveryId {
            directory.markDelivered(id: deliveryId)
        } else {
            directory.markDelivered(plate: route.plate)
        }
        directory.popToMenusHome()
        popToHome()
        onCloseOrder()
    }

    private func requestOrientation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

#Preview {
    RestaurantKitchenView(
        route: CarConsoleRoute(
            restaurantName: "KFC",
            destinationTitle: "KFC - Atakum/Samsun Şubesi",
            plate: "34 KNM 55",
            paymentTitle: "Metropol Card",
            lines: [
                KitchenOrderLine(name: "KFC Kova Menü", quantity: 2, unitPrice: 145)
            ]
        )
    )
    .environmentObject(KonumumDirectory())
}
