import SwiftUI
import UIKit

struct OrderPaymentView: View {
    let profile: KonumumProfile

    @EnvironmentObject private var directory: KonumumDirectory
    @AppStorage(KonumumMemberStore.language) private var lang = "tr"
    @ObservedObject private var location = KonumumLocation.shared
    @State private var restaurant: RestaurantBrand?
    @State private var quantities: [String: Int] = [:]
    @State private var payment: MealPayment? = .metropol
    @State private var paymentRoom: MealPayment?
    @State private var paymentConfirmed = false
    @State private var attemptedSend = false
    @State private var memberTab: KonumumMemberTab = .home
    @State private var searchQuery = ""
    @State private var cuisineFilter: String?
    @State private var onlyOpen = false
    @State private var pickedVar: [String: String] = [:]
    @State private var atPayment = false
    @State private var orderReceived = false
    @State private var placedOrderId: String?
    @State private var couponCode = ""
    @State private var couponOn = false
    @State private var couponPercent = 20

    private var payableTotal: Int {
        guard couponOn else { return total }
        let factor = max(0.0, min(1.0, Double(100 - couponPercent) / 100.0))
        return max(0, Int((Double(total) * factor).rounded()))
    }

    private var total: Int {
        guard let restaurant else { return 0 }
        return cartRows(of: restaurant).reduce(0) { sum, row in
            sum + row.unitPrice * row.qty
        }
    }

    private struct CartRow: Identifiable {
        let id: String
        let dish: MenuDish
        let variation: KonumumDishVariation
        let qty: Int
        var displayName: String {
            variation.priceDelta == 0 ? dish.name : "\(dish.name) · \(variation.name)"
        }
        var unitPrice: Int {
            dish.price + variation.priceDelta
        }
    }

    private func cartKey(for dish: MenuDish, variation: KonumumDishVariation) -> String {
        "\(dish.id)::\(variation.id)"
    }

    private func countOf(_ dish: MenuDish) -> Int {
        let chosen = variation(of: dish)
        let key = cartKey(for: dish, variation: chosen)
        if let v = quantities[key] { return v }
        if chosen.id == (dish.variations.first?.id ?? "std"), let legacy = quantities[dish.id] {
            return legacy
        }
        return 0
    }

    private func setCount(_ dish: MenuDish, to newValue: Int) {
        let chosen = variation(of: dish)
        let key = cartKey(for: dish, variation: chosen)
        quantities.removeValue(forKey: dish.id)
        let clamped = max(0, min(9, newValue))
        if clamped == 0 {
            quantities.removeValue(forKey: key)
        } else {
            quantities[key] = clamped
        }
    }

    private func cartRows(of brand: RestaurantBrand) -> [CartRow] {
        var rows: [CartRow] = []
        for dish in dishes(of: brand) where !dish.soldOut {
            let vars = dish.variations.isEmpty
                ? [KonumumDishVariation(id: "std", name: "Standart", priceDelta: 0)]
                : dish.variations
            for v in vars {
                let key = cartKey(for: dish, variation: v)
                let qty = quantities[key] ?? (v.id == vars.first?.id ? (quantities[dish.id] ?? 0) : 0)
                if qty > 0 {
                    rows.append(CartRow(id: key, dish: dish, variation: v, qty: qty))
                }
            }
        }
        return rows
    }

    private func soldOutCartNames(of brand: RestaurantBrand) -> [String] {
        var names: [String] = []
        for dish in dishes(of: brand) where dish.soldOut {
            let vars = dish.variations.isEmpty
                ? [KonumumDishVariation(id: "std", name: "Standart", priceDelta: 0)]
                : dish.variations
            for v in vars {
                let key = cartKey(for: dish, variation: v)
                let qty = quantities[key] ?? (v.id == vars.first?.id ? (quantities[dish.id] ?? 0) : 0)
                if qty > 0 && !names.contains(dish.name) {
                    names.append(dish.name)
                }
            }
        }
        return names
    }

    var body: some View {
        VStack(spacing: 0) {
            if let bannerText = directory.kitchenBannerText, memberTab != .orders {
                HStack(alignment: .center, spacing: 10) {
                    Text(bannerText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(directory.kitchenBannerKind == "ready" ? KonumumTheme.ink : .white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        memberTab = .orders
                        directory.kitchenBannerText = nil
                    } label: {
                        Text(L("Gör", "View"))
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(directory.kitchenBannerKind == "ready" ? .white : KonumumTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                directory.kitchenBannerKind == "ready" ? KonumumTheme.ink : KonumumTheme.neon,
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    Button {
                        directory.kitchenBannerText = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle((directory.kitchenBannerKind == "ready" ? KonumumTheme.ink : Color.white).opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    directory.kitchenBannerKind == "cancel"
                    ? KonumumTheme.danger
                    : directory.kitchenBannerKind == "ready"
                    ? Color(red: 0.22, green: 0.95, blue: 0.48)
                    : Color(red: 0.14, green: 0.22, blue: 0.34)
                )
            }

            Group {
                switch memberTab {
                case .home:
                    homeStack
                case .orders:
                    SiparislerimView(profile: profile)
                case .campaigns:
                    KampanyalarView()
                case .profile:
                    UyelikProfilView(profile: profile)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            KonumumBottomBar(selection: $memberTab, onHome: openHomeTab)
        }
        .background(KonumumTheme.graphite.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .environment(\.popToHome, goMenusHome)
        .onAppear {
            directory.popToMenusHome = goMenusHome
            location.pingForDistance()
            applyReorder(directory.pendingReorder)
        }
        .onChange(of: directory.pendingReorder) { _, draft in
            applyReorder(draft)
        }
    }

    private func allBrands() -> [RestaurantBrand] {
        var result = RestaurantBrand.staticCases
        let staticIds = Set(result.map(\.directoryId))
        let dynamicBrands = directory.restaurants
            .filter { !staticIds.contains($0.id) }
            .map { RestaurantBrand.custom($0) }
        result.insert(contentsOf: dynamicBrands, at: 0)
        return result
    }

    private func applyReorder(_ draft: KonumumReorderDraft?) {
        guard let draft,
              let brand = allBrands().first(where: { $0.directoryId == draft.restaurantId })
        else { return }
        restaurant = brand
        quantities = [:]
        for line in draft.lines {
            if let dish = dishes(of: brand).first(where: { line.name.contains($0.name) || $0.name == line.name }) {
                let matchedVar = dish.variations.first(where: { line.name.contains($0.name) })
                    ?? dish.variations.first
                    ?? KonumumDishVariation(id: "std", name: "Standart", priceDelta: 0)
                pickedVar[dish.id] = matchedVar.id
                quantities[cartKey(for: dish, variation: matchedVar)] = line.quantity
            }
        }
        directory.pendingReorder = nil
        memberTab = .home
        atPayment = false
        orderReceived = false
        placedOrderId = nil
        paymentRoom = nil
    }

    private func openHomeTab() {
        memberTab = .home
        restaurant = nil
        quantities = [:]
        pickedVar = [:]
        atPayment = false
        orderReceived = false
        placedOrderId = nil
        paymentRoom = nil
        couponOn = false
        couponCode = ""
        attemptedSend = false
        paymentConfirmed = false
    }

    private var homeStack: some View {
        ZStack {
            KonumumTheme.graphite.ignoresSafeArea()

            RadialGradient(
                colors: [KonumumTheme.neon.opacity(0.14), .clear],
                center: UnitPoint(x: 0.5, y: 0),
                startRadius: 8,
                endRadius: 240
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            if let restaurant {
                restaurantDetail(restaurant)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                restaurantList
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .animation(.spring(response: 0.46, dampingFraction: 0.88), value: restaurant)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: payment)
        .animation(.spring(response: 0.38, dampingFraction: 0.86), value: orderReceived)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: paymentRoom)
        .animation(.snappy(duration: 0.22), value: total)
    }

    private func goMenusHome() {
        payment = .metropol
        paymentConfirmed = false
        attemptedSend = false
        quantities = [:]
        pickedVar = [:]
        restaurant = nil
        atPayment = false
        orderReceived = false
        placedOrderId = nil
        paymentRoom = nil
        couponOn = false
        couponCode = ""
        memberTab = .home
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
    }

    private func venueAccount(for brand: RestaurantBrand) -> KonumumRestaurantAccount? {
        directory.restaurants.first(where: { $0.id == brand.directoryId })
    }

    private func isBrandOpen(_ brand: RestaurantBrand) -> Bool {
        venueAccount(for: brand)?.effectiveOpen ?? true
    }

    private func brandHours(_ brand: RestaurantBrand) -> String {
        venueAccount(for: brand)?.hours ?? "10:00-23:00"
    }

    private func brandBusy(_ brand: RestaurantBrand) -> String {
        venueAccount(for: brand)?.busyLevel ?? "mid"
    }

    private var filteredBrands: [RestaurantBrand] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = allBrands().filter { brand in
            guard !q.isEmpty else { return true }
            return brand.name.lowercased().contains(q) || brand.destinationTitle.lowercased().contains(q)
        }
        return onlyOpen ? base.filter { isBrandOpen($0) } : base
    }

    private var restaurantList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(L("Popüler Restoranlar", "Popular Restaurants"))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                KonumumLangToggle()
            }
            .padding(.top, 18)

            Text(profile.plates.joined(separator: "   ·   "))
                .font(KonumumFont.plate(13))
                .foregroundStyle(Color.white.opacity(0.62))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.top, 8)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                TextField(
                    "",
                    text: $searchQuery,
                    prompt: Text(L("Restoran veya şube ara", "Search restaurant or branch")).foregroundStyle(Color.white.opacity(0.35))
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .tint(KonumumTheme.neon)
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
            .padding(.top, 12)

            HStack(spacing: 8) {
                Button {
                    onlyOpen = false
                } label: {
                    Text(L("Tümü", "All"))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(!onlyOpen ? KonumumTheme.ink : Color.white.opacity(0.75))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(!onlyOpen ? KonumumTheme.neon : Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onlyOpen = true
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(red: 0.22, green: 0.95, blue: 0.48))
                            .frame(width: 6, height: 6)
                        Text(L("Sadece Açık Restoranlar", "Open Now Only"))
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(onlyOpen ? KonumumTheme.ink : Color.white.opacity(0.75))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(onlyOpen ? KonumumTheme.neon : Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.top, 10)

            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    ForEach(filteredBrands) { brand in
                        let open = isBrandOpen(brand)
                        let hours = brandHours(brand)
                        let busy = brandBusy(brand)
                        Button {
                            quantities = [:]
                            pickedVar = [:]
                            attemptedSend = false
                            atPayment = false
                            orderReceived = false
                            placedOrderId = nil
                            paymentRoom = nil
                            couponOn = false
                            couponCode = ""
                            restaurant = brand
                        } label: {
                            VStack(spacing: 6) {
                                brand.emblem
                                    .frame(height: 44)
                                    .opacity(open ? 1 : 0.48)
                                Text(brand.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.65)
                                    .frame(height: 28)

                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(open ? Color(red: 0.22, green: 0.95, blue: 0.48) : KonumumTheme.danger)
                                        .frame(width: 5, height: 5)
                                    Text(open ? L("AÇIK", "OPEN") : L("KAPALI", "CLOSED"))
                                        .font(.system(size: 8.5, weight: .heavy))
                                        .foregroundStyle(open ? Color(red: 0.22, green: 0.95, blue: 0.48) : KonumumTheme.danger)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    (open ? Color(red: 0.22, green: 0.95, blue: 0.48) : KonumumTheme.danger).opacity(0.14),
                                    in: Capsule()
                                )

                                if busy == "high" && open {
                                    Text(L("🔥 Yoğun (+5 dk)", "🔥 Busy (+5m)"))
                                        .font(.system(size: 8, weight: .heavy))
                                        .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.16))
                                        .lineLimit(1)
                                } else {
                                    Text(hours)
                                        .font(KonumumFont.plate(8.5))
                                        .foregroundStyle(Color.white.opacity(0.52))
                                        .lineLimit(1)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 4)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(open ? 0.045 : 0.025))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(
                                                open ? Color.white.opacity(0.10) : KonumumTheme.danger.opacity(0.35),
                                                lineWidth: 1
                                            )
                                    }
                            }
                        }
                        .buttonStyle(KonumumPressStyle())
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 16)
            }
        }
        .padding(.horizontal, 24)
    }

    private func restaurantDetail(_ brand: RestaurantBrand) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                backButton(
                    orderReceived ? L("Ana sayfa", "Home")
                    : paymentRoom != nil ? L("Ödeme", "Payment")
                    : atPayment ? L("Menü", "Menu")
                    : L("Restoranlar", "Restaurants")
                ) {
                    if orderReceived {
                        goMenusHome()
                    } else if paymentRoom != nil {
                        paymentRoom = nil
                    } else if atPayment {
                        atPayment = false
                    } else {
                        quantities = [:]
                        pickedVar = [:]
                        couponOn = false
                        couponCode = ""
                        restaurant = nil
                    }
                }
                Spacer()
                KonumumLangToggle()
                brand.emblem
                    .frame(width: 36, height: 36)
            }
            .padding(.top, 8)

            Text(
                orderReceived ? L("Sipariş Alındı", "Order Received")
                : paymentRoom != nil ? L("Kart bilgileri", "Card Details")
                : atPayment ? L("Ödeme", "Payment")
                : brand.name
            )
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 14)

            if !atPayment {
                let open = isBrandOpen(brand)
                let hours = brandHours(brand)
                let busy = brandBusy(brand)
                let busyLabel = busy == "high" ? L("Yoğun", "Busy") : busy == "low" ? L("Sakin", "Quiet") : L("Normal", "Normal")
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(open ? Color(red: 0.22, green: 0.95, blue: 0.48) : KonumumTheme.danger)
                            .frame(width: 7, height: 7)
                        Text(open ? L("MAĞAZA AÇIK", "STORE OPEN") : L("MAĞAZA KAPALI", "STORE CLOSED"))
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(open ? Color(red: 0.22, green: 0.95, blue: 0.48) : KonumumTheme.danger)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        (open ? Color(red: 0.22, green: 0.95, blue: 0.48) : KonumumTheme.danger).opacity(0.14),
                        in: Capsule()
                    )

                    Text("🕒 \(hours)")
                        .font(KonumumFont.plate(11))
                        .foregroundStyle(Color.white.opacity(0.75))

                    Text("· \(L("Yoğunluk", "Load")): \(busyLabel)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(busy == "high" ? Color(red: 1, green: 0.82, blue: 0.16) : Color.white.opacity(0.65))

                    Spacer()
                }
                .padding(.top, 8)

                if busy == "high" {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(L("Şube şu an yoğun (+5 dk ek hazırlık süresi)", "Branch is currently busy (+5 min extra prep time)"))
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.16))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(red: 1, green: 0.82, blue: 0.16).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 6)
                }

                let soldNames = soldOutCartNames(of: brand)
                if !soldNames.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.octagon.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text(L(
                            "Sepetinizdeki şu ürün az önce tükendi (86): \(soldNames.joined(separator: ", "))",
                            "Item in your cart just sold out (86): \(soldNames.joined(separator: ", "))"
                        ))
                        .font(.system(size: 11.5, weight: .bold))
                        Spacer()
                        Button(L("Temizle", "Clear")) {
                            for dish in dishes(of: brand) where dish.soldOut {
                                quantities.removeValue(forKey: dish.id)
                                for v in dish.variations {
                                    quantities.removeValue(forKey: cartKey(for: dish, variation: v))
                                }
                            }
                        }
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                    }
                    .foregroundStyle(KonumumTheme.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(KonumumTheme.danger.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 6)
                }
            }

            if atPayment {
                paymentPage(brand)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(menuSections(of: brand), id: \.title) { section in
                            Text(localizedCategoryTitle(section.title))
                                .font(.system(size: 13, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(Color.white.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                            ForEach(section.dishes) { dish in
                                menuRow(dish)
                            }
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                .scrollIndicators(.hidden)

                cartBar
            }
        }
        .padding(.horizontal, 24)
    }

    private func localizedCategoryTitle(_ title: String) -> String {
        switch title {
        case "Ana yemek": L("Ana yemek", "Main Dishes")
        case "Yan": L("Yan", "Sides")
        case "İçecek": L("İçecek", "Drinks")
        default: title
        }
    }

    private func menuSections(of brand: RestaurantBrand) -> [(title: String, dishes: [MenuDish])] {
        var buckets: [String: [MenuDish]] = [:]
        for dish in dishes(of: brand) {
            let cat = (dish.category?.isEmpty == false) ? dish.category! : category(of: dish.name)
            buckets[cat, default: []].append(dish)
        }
        let order = ["Ana yemek", "Yan", "İçecek"]
        var result: [(title: String, dishes: [MenuDish])] = order.compactMap { title in
            guard let rows = buckets[title], !rows.isEmpty else { return nil }
            return (title, rows)
        }
        for (key, rows) in buckets where !order.contains(key) && !rows.isEmpty {
            result.append((key, rows))
        }
        return result
    }

    private func category(of name: String) -> String {
        let n = name.lowercased()
        if n.contains("cola") || n.contains("kola") || n.contains("ayran") || n.contains("çay") || n.contains("shake") { return "İçecek" }
        if n.contains("patates") || n.contains("halka") || n.contains("termos") { return "Yan" }
        return "Ana yemek"
    }

    private func menuRow(_ dish: MenuDish) -> some View {
        let count = countOf(dish)
        let chosen = variation(of: dish)

        return HStack(alignment: .top, spacing: 10) {
            Text(dish.photo)
                .font(.system(size: 28))
                .frame(width: 56, height: 56)
                .background(Color(hex: dish.photoBg), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(dish.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if dish.soldOut {
                        Text(L("TÜKENDİ", "SOLD OUT"))
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(KonumumTheme.ink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(KonumumTheme.danger, in: Capsule())
                    }
                }
                HStack(spacing: 8) {
                    Text(tl(unitPrice(dish)))
                        .font(KonumumFont.plate(14))
                        .foregroundStyle(Color.white.opacity(0.78))
                    if dish.kcal > 0 {
                        Text("\(dish.kcal) kcal")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
                if !dish.allergens.isEmpty {
                    Text(dish.allergens.joined(separator: " · "))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.16))
                }
                if dish.variations.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(dish.variations) { item in
                            Button {
                                pickedVar[dish.id] = item.id
                            } label: {
                                Text(item.priceDelta == 0 ? item.name : "\(item.name) +₺\(item.priceDelta)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(chosen.id == item.id ? KonumumTheme.ink : .white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        chosen.id == item.id ? KonumumTheme.neon : Color.white.opacity(0.08),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(dish.soldOut)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            if !dish.soldOut {
                HStack(spacing: 0) {
                    quantityButton("-") {
                        setCount(dish, to: count - 1)
                    }
                    .opacity(count == 0 ? 0.35 : 1)
                    .disabled(count == 0)

                    Text("\(count)")
                        .font(KonumumFont.plate(14))
                        .foregroundStyle(.white)
                        .frame(width: 24)
                        .contentTransition(.numericText())

                    quantityButton("+") {
                        setCount(dish, to: min(dish.stock, count + 1))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .opacity(dish.soldOut ? 0.55 : 1)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(count > 0 ? 0.06 : 0.035))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            count > 0 ? KonumumTheme.neon.opacity(0.55) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                }
        }
    }

    private func quantityButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(KonumumTheme.ink)
                .frame(width: 30, height: 30)
                .background(KonumumTheme.neon, in: Circle())
        }
        .buttonStyle(KonumumPressStyle())
    }

    private var cartBar: some View {
        let storeOpen = restaurant.map { isBrandOpen($0) } ?? true
        let storeHours = restaurant.map { brandHours($0) } ?? "10:00-23:00"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Toplam", "Total"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
                Spacer()
                Text(tl(total))
                    .font(KonumumFont.plate(22))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            Button {
                attemptedSend = true
                guard storeOpen && total > 0 else { return }
                atPayment = true
            } label: {
                Text(
                    !storeOpen
                    ? L("Mağaza Şu Anda Kapalı (\(storeHours))", "Store Currently Closed (\(storeHours))")
                    : total == 0 ? L("Menüden ürün ekleyin", "Add items from menu") : L("Ödemeye Geç", "Proceed to Payment")
                )
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(!storeOpen ? .white : KonumumTheme.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    !storeOpen ? KonumumTheme.danger : KonumumTheme.neon,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .shadow(color: (!storeOpen ? KonumumTheme.danger : KonumumTheme.neon).opacity(0.65), radius: 10)
            }
            .buttonStyle(KonumumPressStyle())
            .disabled(!storeOpen)
            .opacity(storeOpen && total == 0 ? 0.45 : 1)
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private func paymentPage(_ brand: RestaurantBrand) -> some View {
        if orderReceived {
            orderReceivedPage(brand)
        } else if let method = paymentRoom {
            SecurePaymentRoom(
                method: method,
                cartTotal: payableTotal,
                onComplete: completeCardPayment,
                onCancel: { paymentRoom = nil }
            )
        } else {
            checkoutForm(brand)
        }
    }

    private func checkoutForm(_ brand: RestaurantBrand) -> some View {
        let busy = brandBusy(brand)
        let soldNames = soldOutCartNames(of: brand)
        return VStack(alignment: .leading, spacing: 12) {
            if busy == "high" {
                HStack(spacing: 6) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 12, weight: .bold))
                    Text(L("Yoğunluk nedeniyle tahmini hazırlık süresine +5 dk eklenmiştir.", "Due to high kitchen load, +5 min added to estimated prep time."))
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(Color(red: 1, green: 0.82, blue: 0.16))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 1, green: 0.82, blue: 0.16).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            if !soldNames.isEmpty {
                Text(L(
                    "⚠️ Sepetinizdeki \(soldNames.joined(separator: ", ")) ürünü az önce tükendi ve toplamdan çıkarıldı.",
                    "⚠️ \(soldNames.joined(separator: ", ")) in your cart just sold out and was removed from total."
                ))
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(KonumumTheme.danger)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(cartRows(of: brand)) { row in
                        HStack {
                            Text("\(row.qty)× \(row.displayName)")
                                .foregroundStyle(.white)
                            Spacer()
                            Text(tl(row.unitPrice * row.qty))
                                .font(KonumumFont.plate(14))
                                .foregroundStyle(.white)
                        }
                        .font(.system(size: 14, weight: .medium))
                    }
                }
            }
            .frame(maxHeight: 140)

            HStack(spacing: 8) {
                TextField(L("Kupon", "Promo Code"), text: $couponCode)
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(.white)
                Button(L("Uygula", "Apply")) {
                    let entered = couponCode.trimmingCharacters(in: .whitespaces).uppercased()
                    if let matched = directory.webCampaigns.first(where: {
                        ($0.code ?? "KONUMUM20").uppercased() == entered &&
                        ($0.restaurantId == nil || $0.restaurantId == brand.directoryId)
                    }) {
                        couponOn = true
                        couponPercent = matched.discountPercent ?? 20
                    } else if ["KONUMUM20", "YUSUF15", "MUTFAK40", "METROPOL2X", "METRO50"].contains(entered) {
                        couponOn = true
                        couponPercent = entered == "YUSUF15" ? 15 : 20
                    } else {
                        couponOn = false
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(KonumumTheme.neon)
            }
            if couponOn {
                Text(L("\(couponCode.uppercased()) · %\(couponPercent) uygulandı", "\(couponCode.uppercased()) · \(couponPercent)% discount applied"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KonumumTheme.neon)
            }

            Text(L("Yemek kartı veya kredi kartı", "Meal card or credit card"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach([
                    MealPayment.metropol, .sodexo, .multinet,
                    .setcard, .ticket, .card
                ]) { method in
                    paymentButton(method)
                }
            }

            if attemptedSend && payment == nil {
                Text(L("Ödeme yöntemi seçin", "Please select a payment method"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KonumumTheme.danger)
                    .frame(maxWidth: .infinity)
            }

            HStack {
                Text(L("Ödenecek", "Amount Due"))
                    .foregroundStyle(Color.white.opacity(0.7))
                Spacer()
                Text(tl(payableTotal))
                    .font(KonumumFont.plate(22))
                    .foregroundStyle(.white)
            }

            Button {
                finishCheckout()
            } label: {
                Text(L("Ödemeyi Tamamla", "Complete Payment"))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(KonumumTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background(KonumumTheme.neon, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(KonumumPressStyle())
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
    }

    private var carPlayHandoff: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sipariş restorana iletildi")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Text(directory.carPlayConnected
                 ? "Navigasyon araç CarPlay ekranında."
                 : "Aracınıza CarPlay bağlayın. Rota telefon ekranında açılmaz.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(KonumumTheme.neon)
            if directory.liveMeters == 0 {
                Button {
                    directory.confirmCustomerCollected(
                        deliveryId: directory.liveDeliveryId,
                        plate: profile.plates.first ?? "34 KNM 55"
                    )
                    goMenusHome()
                } label: {
                    Text("Yemeği Teslim Aldım")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(KonumumTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.22, green: 0.95, blue: 0.48), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(KonumumPressStyle())
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(KonumumTheme.neon.opacity(0.45), lineWidth: 1)
        }
    }

    private func paymentButton(_ method: MealPayment) -> some View {
        let selected = payment == method
        let glowing = selected || method == .metropol

        return Button {
            guard !orderReceived else { return }
            payment = method
            paymentConfirmed = false
        } label: {
            method.mark
                .frame(maxWidth: .infinity)
                .frame(height: 68)
                .background(method.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Color.white : Color.white.opacity(0.16), lineWidth: selected ? 2 : 1)
                }
                .shadow(color: glowing ? method.glow.opacity(selected ? 1 : 0.85) : .clear, radius: selected ? 16 : 10)
                .scaleEffect(selected ? 1.045 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(method.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func backButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                Text(title)
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(KonumumTheme.neon)
        }
        .buttonStyle(.plain)
    }

    private func variation(of dish: MenuDish) -> KonumumDishVariation {
        let rows = dish.variations
        let id = pickedVar[dish.id] ?? rows.first?.id
        return rows.first(where: { $0.id == id })
            ?? rows.first
            ?? KonumumDishVariation(id: "std", name: "Standart", priceDelta: 0)
    }

    private func unitPrice(_ dish: MenuDish) -> Int {
        dish.price + variation(of: dish).priceDelta
    }

    private func dishes(of brand: RestaurantBrand) -> [MenuDish] {
        if let cloud = directory.cloudMenu(for: brand.directoryId) {
            return cloud.map { MenuDish(from: $0) }
        }
        let extra = directory.dishes(for: brand.directoryId)
        let built = brand.menu
        let known = Set(built.map(\.id))
        return built + extra.compactMap { dish in
            guard !known.contains(dish.id) else { return nil }
            return MenuDish(from: dish)
        }
    }

    private func tl(_ amount: Int) -> String {
        "₺\(amount)"
    }

    private func finishCheckout() {
        attemptedSend = true
        guard !orderReceived else { return }
        if payment == nil { payment = .metropol }
        guard let method = payment else { return }
        paymentConfirmed = false
        paymentRoom = method
    }

    private func completeCardPayment() {
        paymentConfirmed = true
        markOrderReceived()
    }

    private func markOrderReceived() {
        guard !orderReceived else { return }
        orderReceived = true
        atPayment = true
        paymentRoom = nil
        if placedOrderId == nil {
            placedOrderId = sendToRestaurant()
        }
    }

    @discardableResult
    private func sendToRestaurant() -> String? {
        guard placedOrderId == nil, total > 0, let payment, let restaurant else { return placedOrderId }
        let lines = cartRows(of: restaurant).map { row in
            KitchenOrderLine(name: row.displayName, quantity: row.qty, unitPrice: row.unitPrice)
        }
        guard !lines.isEmpty else { return nil }
        let plate = profile.plates.first ?? "34 KNM 55"
        return directory.recordOrder(
            plate: plate,
            restaurantName: restaurant.name,
            payment: payment.directoryBrand,
            lines: lines
        )
    }

    private func orderReceivedPage(_ brand: RestaurantBrand) -> some View {
        let placed = directory.deliveries.first(where: { $0.id == placedOrderId })
        let plate = placed?.plate ?? profile.plates.first ?? "34 KNM 55"
        let paid = payment?.title ?? placed?.payment.rawValue ?? "Kart"
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(Color(red: 0.22, green: 0.95, blue: 0.48))
                    .shadow(color: Color(red: 0.22, green: 0.95, blue: 0.48).opacity(0.7), radius: 12)

                Text(L("Siparişiniz alınmıştır", "Your order has been received"))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                Text(L(
                    "Restoran takibi başladı. Aracınız kapıya geldiğinde paketiniz araç camından teslim edilir.",
                    "Live kitchen tracking has started. When your car arrives at the restaurant, your order will be handed through your car window."
                ))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))

                Text(plate)
                    .font(KonumumFont.plate(22))
                    .tracking(2)
                    .foregroundStyle(KonumumTheme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(KonumumTheme.neon, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text(brand.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    ForEach(cartRows(of: brand)) { row in
                        HStack {
                            Text("\(row.qty)× \(row.displayName)")
                                .foregroundStyle(Color.white.opacity(0.82))
                            Spacer()
                            Text(tl(row.unitPrice * row.qty))
                                .font(KonumumFont.plate(14))
                                .foregroundStyle(.white)
                        }
                        .font(.system(size: 14, weight: .medium))
                    }
                    HStack {
                        Text(paid)
                        Spacer()
                        Text(tl(payableTotal))
                            .font(KonumumFont.plate(18))
                    }
                    .foregroundStyle(KonumumTheme.neon)
                    .padding(.top, 4)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                Button {
                    quantities = [:]
                    pickedVar = [:]
                    restaurant = nil
                    atPayment = false
                    orderReceived = false
                    placedOrderId = nil
                    paymentRoom = nil
                    couponOn = false
                    couponCode = ""
                    memberTab = .orders
                } label: {
                    Text(L("Siparişlerimi Gör", "View My Orders"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(KonumumTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(KonumumTheme.neon, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(KonumumPressStyle())

                Button {
                    goMenusHome()
                } label: {
                    Text(L("Ana sayfa", "Home"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(KonumumTheme.neon)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
            }
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }
}

private struct MenuDish: Identifiable {
    let id: String
    let name: String
    let price: Int
    var photo: String
    var photoBg: String
    var allergens: [String]
    var kcal: Int
    var variations: [KonumumDishVariation]
    var soldOut: Bool
    var category: String?
    var stock: Int

    init(from dish: KonumumWebDish) {
        id = dish.id
        name = dish.name
        price = dish.price
        photo = dish.photo ?? Self.guessPhoto(dish.name)
        photoBg = dish.photoBg ?? "#1a2433"
        allergens = dish.allergens ?? []
        kcal = dish.kcal ?? 0
        variations = dish.variations ?? [KonumumDishVariation(id: "std", name: "Standart", priceDelta: 0)]
        let s = dish.stock ?? 99
        stock = max(0, min(9, s))
        soldOut = (dish.soldOut ?? false) || s <= 0
        category = dish.category
    }

    init(id: String, name: String, price: Int) {
        self.init(from: KonumumWebDish(id: id, name: name, price: price))
    }

    private static func guessPhoto(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("pizza") || n.contains("margarita") { return "🍕" }
        if n.contains("simit") { return "🥯" }
        if n.contains("döner") || n.contains("dürüm") { return "🌯" }
        if n.contains("köfte") { return n.contains("çiğ") ? "🥗" : "🥩" }
        if n.contains("patates") { return "🍟" }
        if n.contains("cola") || n.contains("kola") { return "🥤" }
        if n.contains("çay") { return "🍵" }
        if n.contains("termos") { return "🫖" }
        if n.contains("ayran") { return "🥛" }
        if n.contains("kanat") || n.contains("wing") || n.contains("tavuk") || n.contains("chicken") { return "🍗" }
        if n.contains("burger") || n.contains("mac") || n.contains("whopper") { return "🍔" }
        return "🍽️"
    }
}

private enum RestaurantBrand: Hashable, Identifiable {
    case mcdonalds
    case burgerKing
    case kfc
    case yusuf
    case adiyorem
    case calikusu
    case haciDoner
    case pizzacilar
    case simitciler
    case custom(KonumumRestaurantAccount)

    static let staticCases: [RestaurantBrand] = [
        .mcdonalds, .burgerKing, .kfc, .yusuf, .adiyorem,
        .calikusu, .haciDoner, .pizzacilar, .simitciler
    ]

    var id: String { directoryId }

    var directoryId: String {
        switch self {
        case .mcdonalds: "mcd-samsun"
        case .burgerKing: "bk-samsun"
        case .kfc: "kfc-samsun"
        case .yusuf: "yusuf-samsun"
        case .adiyorem: "adiyorem-samsun"
        case .calikusu: "calikusu-samsun"
        case .haciDoner: "haci-samsun"
        case .pizzacilar: "pizza-samsun"
        case .simitciler: "simit-samsun"
        case .custom(let acc): acc.id
        }
    }

    var name: String {
        switch self {
        case .mcdonalds: "McDonald's"
        case .burgerKing: "Burger King"
        case .kfc: "KFC"
        case .yusuf: "Köfteci Yusuf"
        case .adiyorem: "Adıyörem Çiğ Köfte"
        case .calikusu: "Çalıkuşu Döner"
        case .haciDoner: "Hacı Döner"
        case .pizzacilar: "Pizzacılar"
        case .simitciler: "Simitçiler"
        case .custom(let acc): acc.brandName
        }
    }

    var destinationTitle: String {
        switch self {
        case .mcdonalds: "McDonald's - Bulvar/Samsun Şubesi"
        case .burgerKing: "Burger King - Piazza/Samsun Şubesi"
        case .kfc: "KFC - Atakum/Samsun Şubesi"
        case .yusuf: "Köfteci Yusuf - İlkadım/Samsun Şubesi"
        case .adiyorem: "Adıyörem Çiğ Köfte - İlkadım/Samsun"
        case .calikusu: "Çalıkuşu Döner - Atakum/Samsun"
        case .haciDoner: "Hacı Döner - Bulvar/Samsun"
        case .pizzacilar: "Pizzacılar - Piazza/Samsun"
        case .simitciler: "Simitçiler - Çarşı/Samsun"
        case .custom(let acc): acc.branchTitle
        }
    }

    var menu: [MenuDish] {
        switch self {
        case .mcdonalds:
            [
                MenuDish(id: "mcd-bigmac", name: "Big Mac", price: 215),
                MenuDish(id: "mcd-mcchicken", name: "McChicken", price: 165),
                MenuDish(id: "mcd-fries", name: "Patates Kızartması", price: 75),
                MenuDish(id: "mcd-cola", name: "Coca-Cola", price: 55)
            ]
        case .burgerKing:
            [
                MenuDish(id: "bk-whopper", name: "Whopper", price: 230),
                MenuDish(id: "bk-chicken", name: "King Chicken", price: 175),
                MenuDish(id: "bk-rings", name: "Soğan Halkası", price: 70),
                MenuDish(id: "bk-shake", name: "Milkshake", price: 85)
            ]
        case .kfc:
            [
                MenuDish(id: "kfc-wings", name: "Hot Wings", price: 195),
                MenuDish(id: "kfc-zinger", name: "Zinger Burger", price: 180),
                MenuDish(id: "kfc-colonel", name: "Colonel Burger", price: 170),
                MenuDish(id: "kfc-fries", name: "Patates", price: 70)
            ]
        case .yusuf:
            [
                MenuDish(id: "yusuf-izgara", name: "Izgara Köfte", price: 240),
                MenuDish(id: "yusuf-porsiyon", name: "Porsiyon Köfte", price: 220),
                MenuDish(id: "yusuf-pirzola", name: "Pirzola", price: 310),
                MenuDish(id: "yusuf-ayran", name: "Ayran", price: 35),
                MenuDish(id: "yusuf-cay", name: "Çay", price: 20),
                MenuDish(id: "yusuf-termos", name: "Termosumu Kendim Uzatıcam", price: 45)
            ]
        case .adiyorem:
            [
                MenuDish(id: "adi-porsiyon", name: "Adıyörem Çiğ Köfte Porsiyon", price: 120),
                MenuDish(id: "adi-durum", name: "Dürüm Çiğ Köfte", price: 90),
                MenuDish(id: "adi-ayran", name: "Ayran", price: 25),
                MenuDish(id: "adi-salgam", name: "Şalgam", price: 30),
                MenuDish(id: "adi-cay", name: "Çay", price: 20),
                MenuDish(id: "adi-termos", name: "Termosumu Kendim Uzatıcam", price: 45)
            ]
        case .calikusu:
            [
                MenuDish(id: "cali-tavuk", name: "Tavuk Döner Dürüm", price: 140),
                MenuDish(id: "cali-et", name: "Et Döner Porsiyon", price: 220),
                MenuDish(id: "cali-iskender", name: "İskender", price: 250),
                MenuDish(id: "cali-ayran", name: "Ayran", price: 30),
                MenuDish(id: "cali-cay", name: "Çay", price: 20),
                MenuDish(id: "cali-termos", name: "Termosumu Kendim Uzatıcam", price: 45)
            ]
        case .haciDoner:
            [
                MenuDish(id: "haci-durum", name: "Hacı Döner Dürüm", price: 130),
                MenuDish(id: "haci-karisik", name: "Karışık Döner", price: 180),
                MenuDish(id: "haci-pilav", name: "Pilav Üstü Döner", price: 200),
                MenuDish(id: "haci-kola", name: "Kola", price: 45),
                MenuDish(id: "haci-cay", name: "Çay", price: 20),
                MenuDish(id: "haci-termos", name: "Termosumu Kendim Uzatıcam", price: 45)
            ]
        case .pizzacilar:
            [
                MenuDish(id: "piz-karisik", name: "Karışık Pizza", price: 280),
                MenuDish(id: "piz-margarita", name: "Margarita", price: 220),
                MenuDish(id: "piz-sucuk", name: "Sucuklu Pizza", price: 250),
                MenuDish(id: "piz-malzemos", name: "Bol Malzemos", price: 320)
            ]
        case .simitciler:
            [
                MenuDish(id: "sim-sade", name: "Sade Simit", price: 25),
                MenuDish(id: "sim-susam", name: "Susamlı Simit", price: 30),
                MenuDish(id: "sim-pogaca", name: "Peynirli Poğaça", price: 35),
                MenuDish(id: "sim-cay", name: "Çay", price: 20),
                MenuDish(id: "sim-termos", name: "Termosumu Kendim Uzatıcam", price: 45)
            ]
        case .custom:
            [
                MenuDish(id: "cust-menu-1", name: "Özel Menü Porsiyon", price: 180),
                MenuDish(id: "cust-menu-2", name: "Günün Spesiyali", price: 150),
                MenuDish(id: "cust-cay", name: "Çay", price: 15)
            ]
        }
    }

    @ViewBuilder
    var emblem: some View {
        switch self {
        case .mcdonalds:
            Text("M")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(Color(red: 1.0, green: 0.78, blue: 0.04))
                .frame(width: 46, height: 46)
                .background(Color(red: 0.86, green: 0.08, blue: 0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .burgerKing:
            ZStack {
                Circle().fill(Color(red: 0.84, green: 0.11, blue: 0.14))
                Circle().fill(Color(red: 0.98, green: 0.76, blue: 0.16)).padding(5)
                Circle().fill(Color(red: 0.13, green: 0.29, blue: 0.62)).padding(10)
                Text("BK")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
        case .kfc:
            Text("KFC")
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color(red: 0.89, green: 0.0, blue: 0.17), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .yusuf:
            VStack(spacing: 0) {
                Text("KÖFTECİ")
                    .font(.system(size: 6, weight: .bold))
                    .tracking(0.6)
                Text("Yusuf")
                    .font(.system(size: 13, weight: .black, design: .serif))
            }
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(Color(red: 0.55, green: 0.07, blue: 0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .adiyorem:
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.72, green: 0.12, blue: 0.10))
                Image(systemName: "leaf.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(red: 1.0, green: 0.62, blue: 0.18))
                    .offset(y: 4)
                Text("AÇ")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .offset(y: -10)
            }
            .frame(width: 46, height: 46)
        case .calikusu:
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.92, green: 0.62, blue: 0.08))
                Image(systemName: "bird.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 0.42, green: 0.18, blue: 0.04))
            }
            .frame(width: 46, height: 46)
        case .haciDoner:
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.42, blue: 0.22))
                Image(systemName: "fork.knife")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 46, height: 46)
        case .pizzacilar:
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.72, green: 0.14, blue: 0.12))
                Circle()
                    .fill(Color(red: 0.96, green: 0.78, blue: 0.22))
                    .frame(width: 28, height: 28)
                Circle()
                    .fill(Color(red: 0.86, green: 0.22, blue: 0.16))
                    .frame(width: 6, height: 6)
                    .offset(x: -5, y: -3)
                Circle()
                    .fill(Color(red: 0.86, green: 0.22, blue: 0.16))
                    .frame(width: 5, height: 5)
                    .offset(x: 6, y: 2)
                Circle()
                    .fill(Color(red: 0.18, green: 0.52, blue: 0.22))
                    .frame(width: 5, height: 5)
                    .offset(x: 1, y: 6)
            }
            .frame(width: 46, height: 46)
        case .simitciler:
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.42, green: 0.24, blue: 0.10))
                Circle()
                    .strokeBorder(Color(red: 0.86, green: 0.62, blue: 0.28), lineWidth: 7)
                    .frame(width: 28, height: 28)
            }
            .frame(width: 46, height: 46)
        case .custom(let acc):
            let mark = acc.logoMark.isEmpty ? String(acc.brandName.prefix(2)).uppercased() : acc.logoMark
            let bgHex = acc.logoBg.isEmpty ? "#3AF1D7" : acc.logoBg
            let fgHex = acc.logoFg.isEmpty ? "#0B0F19" : acc.logoFg
            Text(mark)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(Color(hex: fgHex))
                .frame(width: 46, height: 46)
                .background(Color(hex: bgHex), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private enum MealPayment: String, CaseIterable, Identifiable {
    case card
    case sodexo
    case multinet
    case setcard
    case metropol
    case ticket

    var id: String { rawValue }

    var isMealCard: Bool { [.sodexo, .multinet, .setcard, .metropol, .ticket].contains(self) }

    var title: String {
        switch self {
        case .card: "Kart · Visa Mastercard Troy"
        case .sodexo: "Sodexo"
        case .multinet: "Multinet"
        case .setcard: "Setcard"
        case .metropol: "Metropol Card"
        case .ticket: "Ticket Restaurant"
        }
    }

    var directoryBrand: MealCardBrand {
        switch self {
        case .sodexo: .sodexo
        case .multinet: .multinet
        case .setcard: .setcard
        case .metropol: .metropol
        case .ticket: .ticket
        case .card: .krediKarti
        }
    }

    var fill: Color {
        switch self {
        case .sodexo: Color(red: 0.894, green: 0.094, blue: 0.141)
        case .multinet: Color(red: 0.000, green: 0.306, blue: 0.690)
        case .setcard: Color(red: 0.227, green: 0.639, blue: 0.196)
        case .metropol: Color(red: 1.0, green: 0.08, blue: 0.22)
        case .ticket: Color(red: 0.55, green: 0.08, blue: 0.18)
        case .card: Color(red: 0.16, green: 0.18, blue: 0.23)
        }
    }

    var glow: Color {
        switch self {
        case .metropol: Color(red: 1.0, green: 0.15, blue: 0.28)
        case .card: KonumumTheme.neon
        default: fill
        }
    }

    @ViewBuilder
    var mark: some View {
        switch self {
        case .sodexo:
            Text("sodexo")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        case .multinet:
            Text("multinet")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        case .setcard:
            Text("Setcard")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        case .metropol:
            VStack(spacing: 0) {
                Text("Metropol")
                Text("Card")
            }
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: Color(red: 1, green: 0.35, blue: 0.4), radius: 4)
            .minimumScaleFactor(0.6)
        case .ticket:
            Text("Ticket")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        case .card:
            VStack(spacing: 3) {
                Text("Visa · MC · Troy")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(.white)
                Text("3D Secure")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(KonumumTheme.neon)
            }
        }
    }
}

private extension Color {
    init(hex: String) {
        var raw = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if raw.count == 3 {
            raw = raw.map { "\($0)\($0)" }.joined()
        }
        var value: UInt64 = 0
        Scanner(string: raw).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

private struct KonumumSavedCard: Codable, Identifiable, Equatable {
    var id: String
    var methodRaw: String
    var alias: String
    var holder: String
    var panDigits: String
    var expiryMonth: String
    var expiryYear: String
    var isDefault: Bool

    var last4: String {
        String(panDigits.suffix(4))
    }

    var maskedPAN: String {
        "•••• •••• •••• \(last4)"
    }

    var networkLabel: String {
        if panDigits.hasPrefix("4") { return "VISA" }
        if panDigits.hasPrefix("5") { return "MASTERCARD" }
        if panDigits.hasPrefix("9792") || panDigits.hasPrefix("65") { return "TROY" }
        return "KART"
    }
}

private struct SecurePaymentRoom: View {
    let method: MealPayment
    let cartTotal: Int
    var onComplete: () -> Void
    var onCancel: () -> Void = {}

    @AppStorage(KonumumMemberStore.language) private var lang = "tr"
    @AppStorage(KonumumMemberStore.savedCards) private var savedCardsJSON = "[]"
    @State private var savedCards: [KonumumSavedCard] = []
    @State private var selectedCardId: String? = nil
    @State private var showingNewCardForm = false
    @State private var cardAlias = ""
    @State private var saveFeedback = ""
    @State private var pan = ""
    @State private var otp = ""
    @State private var holder = ""
    @State private var expiryMonth = ""
    @State private var expiryYear = ""
    @State private var cvv = ""
    @State private var secure3D = true
    @State private var balanceVisible = false
    @State private var attempted = false
    @FocusState private var expiryPart: ExpiryPart?

    private enum ExpiryPart: Hashable {
        case month
        case year
    }

    private let paidGreen = Color(red: 0.22, green: 0.95, blue: 0.48)

    private var methodCards: [KonumumSavedCard] {
        savedCards.filter { $0.methodRaw == method.rawValue }
    }

    private var panDigits: String { pan.filter(\.isNumber) }
    private var panReady: Bool { panDigits.count == 16 }
    private var otpReady: Bool { otp.filter(\.isNumber).count == 6 }
    private var holderReady: Bool {
        let parts = holder.trimmingCharacters(in: .whitespaces).split(separator: " ")
        return parts.count >= 2
    }
    private var expiryReady: Bool {
        expiryMonth.range(of: #"^(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil
            && expiryYear.count == 2
    }
    private var cvvReady: Bool { (3...4).contains(cvv.filter(\.isNumber).count) }

    private var canSaveCurrentCard: Bool {
        guard panReady else { return false }
        if method.isMealCard { return true }
        return holderReady && expiryReady
    }

    private var canPay: Bool {
        guard cartTotal > 0 else { return false }
        guard panReady else { return false }
        if method.isMealCard { return otpReady }
        return holderReady && expiryReady && cvvReady && secure3D
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                    header
                    savedCardsSection
                    if method.isMealCard {
                        mealCardFields
                    } else {
                        bankCardFields
                    }
                    if !saveFeedback.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.seal.fill")
                            Text(saveFeedback)
                        }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(paidGreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if attempted && !canPay {
                        Text(cartTotal == 0 ? L("Menüden bir ürün ekleyin", "Add an item from the menu") : L("Eksik alanları tamamlayın (CVV / SMS kodunu kontrol edin)", "Please complete all required fields"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(KonumumTheme.danger)
                            .frame(maxWidth: .infinity)
                    }
                    Button(action: confirm) {
                        Text(L("Ödemeyi Güvenli Tamamla", "Complete Secure Payment"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(KonumumTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(KonumumTheme.neon, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: KonumumTheme.neon.opacity(0.85), radius: 12)
                    }
                    .buttonStyle(KonumumPressStyle())
                    .padding(.bottom, 12)
            }
            .padding(20)
        }
        .background(KonumumTheme.graphite.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .onAppear(perform: loadSavedCards)
        .onChange(of: method) { _, _ in
            saveFeedback = ""
            autoSelectDefaultCard()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                method.mark
                    .frame(width: 72, height: 48)
                    .background(method.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        method.isMealCard ? L("Güvenli Mobil Ödeme", "Secure Mobile Payment")
                        : L("Kredi / Banka Kartı ile Güvenli Ödeme", "Secure Credit / Debit Card Payment")
                    )
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                        Text("SSL · TEST MODU (Karttan Ücret Çekilmez)")
                    }
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(paidGreen)
                }
            }
            Text(method.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))
            Text("\(L("Sepet", "Total")): ₺\(cartTotal)")
                .font(KonumumFont.plate(16))
                .foregroundStyle(KonumumTheme.neon)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(method.fill.opacity(method.isMealCard ? 0.22 : 0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var savedCardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "creditcard.and.123")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(KonumumTheme.neon)
                    Text(L("KAYITLI KARTLARIM (\(methodCards.count))", "SAVED CARDS (\(methodCards.count))"))
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(Color.white.opacity(0.78))
                }
                Spacer()
                Button {
                    withAnimation(.snappy) {
                        clearFormForNewCard()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text(L("Yeni Kart", "New Card"))
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(KonumumTheme.neon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(KonumumTheme.neon.opacity(0.14), in: Capsule())
                }
                .buttonStyle(KonumumPressStyle())
            }

            if methodCards.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(KonumumTheme.neon)
                    Text(
                        L(
                            "Aşağıdan kart bilgilerini girip \"Kartı Ekle\" butonuna basarak birden fazla kart kaydedebilir, sonraki siparişlerde tek dokunuşla seçebilirsiniz.",
                            "Enter your card details below and tap \"Add Card\" to save multiple cards for one-tap selection on future orders."
                        )
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(methodCards) { card in
                            savedCardTile(card)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func savedCardTile(_ card: KonumumSavedCard) -> some View {
        let isSelected = selectedCardId == card.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "creditcard.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isSelected ? KonumumTheme.neon : Color.white.opacity(0.65))
                Text(card.alias)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if card.isDefault {
                    Text(L("Varsayılan", "Default"))
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(KonumumTheme.ink)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(KonumumTheme.neon, in: Capsule())
                }
                Button {
                    withAnimation(.snappy) {
                        deleteSavedCard(card.id)
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .padding(5)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }

            Text(card.maskedPAN)
                .font(KonumumFont.plate(13))
                .foregroundStyle(isSelected ? KonumumTheme.neon : .white)

            HStack {
                Text(method.isMealCard ? method.title : (card.holder.isEmpty ? card.networkLabel : card.holder))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .lineLimit(1)
                Spacer()
                if !card.expiryMonth.isEmpty && !card.expiryYear.isEmpty {
                    Text("\(card.expiryMonth)/\(card.expiryYear)")
                        .font(KonumumFont.plate(11))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }

            if !card.isDefault {
                Button {
                    withAnimation(.snappy) {
                        setDefaultSavedCard(card.id)
                    }
                } label: {
                    Text(L("Varsayılan Yap", "Set Default"))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(KonumumTheme.neon)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 215, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? KonumumTheme.neon.opacity(0.14) : Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isSelected ? KonumumTheme.neon : Color.white.opacity(0.12),
                            lineWidth: isSelected ? 1.8 : 1
                        )
                }
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            withAnimation(.snappy) {
                applySavedCard(card)
            }
        }
    }

    private var saveCardControlBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            labeled(L("Kart Başlığı (İsteğe Bağlı · Örn: Şahsi, Şirket, Bonus)", "Card Label (Optional · e.g. Personal, Corporate)"))
            HStack(spacing: 8) {
                field($cardAlias, placeholder: method.isMealCard ? "\(method.title) Kartım" : L("Örn: Maaş Kartım / Şirket Kartım", "e.g. Personal / Work Card"), mono: false)
                Button {
                    withAnimation(.snappy) {
                        saveCurrentCardToWallet()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.rectangle.on.folder.fill")
                        Text(L("Kartı Ekle", "Add Card"))
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(canSaveCurrentCard ? KonumumTheme.ink : Color.white.opacity(0.45))
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(
                        canSaveCurrentCard ? KonumumTheme.neon : Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
                .buttonStyle(KonumumPressStyle())
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var mealCardFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeled(L("16 Haneli Kart Numarası", "16-Digit Card Number"))
            HStack(spacing: 8) {
                field(panBinding, placeholder: "XXXX XXXX XXXX XXXX", mono: true)
                    .keyboardType(.numberPad)
                Button {
                    guard panReady else {
                        attempted = true
                        return
                    }
                    withAnimation(.snappy) { balanceVisible = true }
                } label: {
                    Text(L("Güncel Bakiye Sorgula", "Check Balance"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(KonumumTheme.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .frame(width: 108, height: 52)
                        .background(KonumumTheme.neon, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(KonumumPressStyle())
            }
            if balanceVisible {
                Text(L("Güncel Kart Bakiyeniz: 450,00 TL", "Available Card Balance: 450.00 TL"))
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(paidGreen)
                    .shadow(color: paidGreen.opacity(0.9), radius: 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            saveCardControlBar
            labeled(L("SMS Doğrulama Şifresi (OTP)", "SMS Verification Code (OTP)"))
            field(
                Binding(
                    get: { otp },
                    set: { otp = String($0.filter(\.isNumber).prefix(6)) }
                ),
                placeholder: L("6 haneli kod", "6-digit code"),
                mono: true
            )
            .keyboardType(.numberPad)
        }
    }

    private var bankCardFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            labeled(L("Kart Üzerindeki Ad Soyad", "Cardholder Name"))
            field($holder, placeholder: L("Ad Soyad", "Full Name"), mono: false)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            labeled(L("16 Haneli Kart Numarası", "16-Digit Card Number"))
            field(panBinding, placeholder: "XXXX XXXX XXXX XXXX", mono: true)
                .keyboardType(.numberPad)
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    labeled(L("Son Kullanma Tarihi (AA/YY)", "Expiry Date (MM/YY)"))
                    expiryField
                }
                VStack(alignment: .leading, spacing: 8) {
                    labeled(L("CVV (Güvenlik Kodu)", "CVV (Security Code)"))
                    field(
                        Binding(
                            get: { cvv },
                            set: { cvv = String($0.filter(\.isNumber).prefix(4)) }
                        ),
                        placeholder: "•••",
                        mono: true
                    )
                    .keyboardType(.numberPad)
                }
            }
            saveCardControlBar
            Toggle(isOn: $secure3D) {
                Text(L("3D Secure ile Güvenli Öde", "Pay Securely with 3D Secure"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .tint(KonumumTheme.neon)
            .padding(.top, 4)
        }
    }

    private var expiryField: some View {
        HStack(spacing: 0) {
            TextField("", text: monthBinding, prompt: Text("AA").foregroundStyle(Color.white.opacity(0.32)))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(KonumumFont.plate(16))
                .foregroundStyle(.white)
                .tint(KonumumTheme.neon)
                .keyboardType(.numberPad)
                .focused($expiryPart, equals: .month)
                .frame(maxWidth: .infinity)
                .submitLabel(.next)
                .onSubmit { expiryPart = .year }

            Text("/")
                .font(KonumumFont.plate(20))
                .foregroundStyle(KonumumTheme.neon)
                .frame(width: 22)

            TextField("", text: yearBinding, prompt: Text("YY").foregroundStyle(Color.white.opacity(0.32)))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(KonumumFont.plate(16))
                .foregroundStyle(.white)
                .tint(KonumumTheme.neon)
                .keyboardType(.numberPad)
                .focused($expiryPart, equals: .year)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                }
        )
    }

    private var monthBinding: Binding<String> {
        Binding(
            get: { expiryMonth },
            set: { newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(2))
                expiryMonth = digits
                if digits.count == 2 {
                    expiryPart = .year
                }
            }
        )
    }

    private var yearBinding: Binding<String> {
        Binding(
            get: { expiryYear },
            set: { newValue in
                let digits = String(newValue.filter(\.isNumber).prefix(2))
                if digits.isEmpty && !expiryYear.isEmpty {
                    expiryYear = ""
                    expiryPart = .month
                    return
                }
                expiryYear = digits
            }
        )
    }

    private var panBinding: Binding<String> {
        Binding(
            get: { pan },
            set: { pan = Self.formatPAN($0) }
        )
    }

    private func labeled(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color.white.opacity(0.62))
    }

    private func field(_ text: Binding<String>, placeholder: String, mono: Bool) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundStyle(Color.white.opacity(0.32)))
            .textFieldStyle(.plain)
            .font(mono ? KonumumFont.plate(16) : .system(size: 16, weight: .medium))
            .foregroundStyle(.white)
            .tint(KonumumTheme.neon)
            .padding(.horizontal, 14)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    }
            )
    }

    private func loadSavedCards() {
        if let data = savedCardsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([KonumumSavedCard].self, from: data) {
            savedCards = decoded
        } else {
            savedCards = []
        }
        autoSelectDefaultCard()
    }

    private func persistSavedCards() {
        if let data = try? JSONEncoder().encode(savedCards),
           let str = String(data: data, encoding: .utf8) {
            savedCardsJSON = str
        }
    }

    private func autoSelectDefaultCard() {
        let cards = methodCards
        if let def = cards.first(where: { $0.isDefault }) ?? cards.first {
            applySavedCard(def)
        } else {
            clearFormForNewCard()
        }
    }

    private func applySavedCard(_ card: KonumumSavedCard) {
        selectedCardId = card.id
        showingNewCardForm = false
        cardAlias = card.alias
        pan = Self.formatPAN(card.panDigits)
        holder = card.holder
        expiryMonth = card.expiryMonth
        expiryYear = card.expiryYear
        balanceVisible = method.isMealCard
        attempted = false
    }

    private func clearFormForNewCard() {
        selectedCardId = nil
        showingNewCardForm = true
        cardAlias = ""
        pan = ""
        holder = ""
        expiryMonth = ""
        expiryYear = ""
        cvv = ""
        otp = ""
        balanceVisible = false
        attempted = false
        saveFeedback = ""
    }

    private func saveCurrentCardToWallet() {
        guard canSaveCurrentCard else {
            attempted = true
            saveFeedback = ""
            return
        }
        let cleanDigits = panDigits
        let trimmedAlias = cardAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedAlias: String
        if !trimmedAlias.isEmpty {
            resolvedAlias = trimmedAlias
        } else if method.isMealCard {
            resolvedAlias = "\(method.title) •\(String(cleanDigits.suffix(4)))"
        } else {
            let brand = cleanDigits.hasPrefix("4") ? "Visa" : cleanDigits.hasPrefix("5") ? "Mastercard" : "Troy"
            resolvedAlias = "\(brand) •\(String(cleanDigits.suffix(4)))"
        }

        if let existingIdx = savedCards.firstIndex(where: { $0.methodRaw == method.rawValue && $0.panDigits == cleanDigits }) {
            savedCards[existingIdx].alias = resolvedAlias
            savedCards[existingIdx].holder = holder.trimmingCharacters(in: .whitespacesAndNewlines)
            savedCards[existingIdx].expiryMonth = expiryMonth
            savedCards[existingIdx].expiryYear = expiryYear
            selectedCardId = savedCards[existingIdx].id
        } else {
            let isFirstForMethod = !savedCards.contains(where: { $0.methodRaw == method.rawValue })
            let newCard = KonumumSavedCard(
                id: UUID().uuidString,
                methodRaw: method.rawValue,
                alias: resolvedAlias,
                holder: holder.trimmingCharacters(in: .whitespacesAndNewlines),
                panDigits: cleanDigits,
                expiryMonth: expiryMonth,
                expiryYear: expiryYear,
                isDefault: isFirstForMethod
            )
            savedCards.insert(newCard, at: 0)
            selectedCardId = newCard.id
        }
        persistSavedCards()
        saveFeedback = L("Kart kaydedildi! Kayıtlı kartlarınızdan tek dokunuşla seçebilirsiniz.", "Card saved! You can select it with one tap.")
    }

    private func deleteSavedCard(_ id: String) {
        let wasSelected = (selectedCardId == id)
        savedCards.removeAll { $0.id == id }
        let remainingForMethod = savedCards.indices.filter { savedCards[$0].methodRaw == method.rawValue }
        if !remainingForMethod.isEmpty && !remainingForMethod.contains(where: { savedCards[$0].isDefault }) {
            savedCards[remainingForMethod[0]].isDefault = true
        }
        persistSavedCards()
        if wasSelected {
            autoSelectDefaultCard()
        }
    }

    private func setDefaultSavedCard(_ id: String) {
        for idx in savedCards.indices where savedCards[idx].methodRaw == method.rawValue {
            savedCards[idx].isDefault = (savedCards[idx].id == id)
        }
        persistSavedCards()
        if let card = savedCards.first(where: { $0.id == id }) {
            applySavedCard(card)
        }
    }

    private func confirm() {
        attempted = true
        guard canPay else { return }
        otp = ""
        cvv = ""
        onComplete()
    }

    private static func formatPAN(_ raw: String) -> String {
        let digits = Array(raw.filter(\.isNumber).prefix(16))
        return stride(from: 0, to: digits.count, by: 4).map { start in
            String(digits[start..<min(start + 4, digits.count)])
        }.joined(separator: " ")
    }
}

#Preview {
    OrderPaymentView(profile: KonumumProfile(name: "Ada Yılmaz", plates: ["34 ABC 123"]))
        .environmentObject(KonumumDirectory())
        .preferredColorScheme(.dark)
}
