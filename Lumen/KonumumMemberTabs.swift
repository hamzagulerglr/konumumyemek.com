import SwiftUI
import UIKit

enum KonumumMemberTab: Hashable {
    case home
    case orders
    case campaigns
    case profile
}

struct SiparislerimView: View {
    let profile: KonumumProfile
    @EnvironmentObject private var directory: KonumumDirectory
    @AppStorage(KonumumMemberStore.language) private var lang = "tr"

    private var plate: String { profile.plates.first ?? "34 KNM 55" }
    private var orders: [KonumumDelivery] {
        directory.memberOrders(plate: plate, customerId: directory.customerSession?.id)
    }
    private var active: [KonumumDelivery] { orders.filter(\.isOpen) }
    private var past: [KonumumDelivery] { orders.filter { !$0.isOpen } }

    private var stamp: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: lang == "en" ? "en_US" : "tr_TR")
        formatter.dateFormat = "dd MMM HH:mm"
        return formatter
    }

    var body: some View {
        ZStack {
            KonumumTheme.graphite.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center) {
                        Text(L("Siparişlerim", "My Orders"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        KonumumLangToggle()
                    }
                    .padding(.top, 12)

                    Text(plate)
                        .font(KonumumFont.plate(14))
                        .foregroundStyle(Color.white.opacity(0.62))

                    if let bannerText = directory.kitchenBannerText {
                        HStack(alignment: .center, spacing: 10) {
                            Text(bannerText)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(directory.kitchenBannerKind == "ready" ? KonumumTheme.ink : .white)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button {
                                directory.kitchenBannerText = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle((directory.kitchenBannerKind == "ready" ? KonumumTheme.ink : Color.white).opacity(0.75))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(14)
                        .background(
                            directory.kitchenBannerKind == "cancel"
                            ? KonumumTheme.danger
                            : directory.kitchenBannerKind == "ready"
                            ? Color(red: 0.22, green: 0.95, blue: 0.48)
                            : Color(red: 0.14, green: 0.22, blue: 0.34),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(
                                    directory.kitchenBannerKind == "prep" ? KonumumTheme.neon.opacity(0.65) : .clear,
                                    lineWidth: 1
                                )
                        }
                    }

                    section(L("Aktif Sipariş", "Active Order")) {
                        if active.isEmpty && !directory.approachActive {
                            emptyRow(L("Şu an açık sipariş yok", "No active orders right now"))
                        } else {
                            if directory.approachActive {
                                liveTrackCard
                            }
                            ForEach(active) { order in
                                orderCard(order, live: true)
                            }
                        }
                    }

                    section(L("Geçmiş Siparişler", "Past Orders")) {
                        if past.isEmpty {
                            emptyRow(L("Henüz tamamlanan sipariş yok", "No completed orders yet"))
                        } else {
                            ForEach(past) { order in
                                orderCard(order, live: false)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }

    private var readyBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HAZIR BİLDİRİMİ")
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(KonumumTheme.ink)
            Text("Siparişiniz hazır. Gişeden teslim için yola çıkabilirsiniz.")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(KonumumTheme.ink)
            if let id = directory.liveDeliveryId {
                Button {
                    directory.startPickup(id: id)
                } label: {
                    Text("Yola Çık")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(KonumumTheme.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(KonumumPressStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.22, green: 0.95, blue: 0.48), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var liveTrackCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("CANLI TAKİP", "LIVE TRACKING"))
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(KonumumTheme.neon)
            Text(localizedKitchenStatusText(directory.kitchenStatusText))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
            Text("\(L("Kalan Mesafe", "Distance")): \(KonumumDirectory.formatDistanceEta(meters: directory.liveMeters, seconds: directory.liveSeconds))")
                .font(KonumumFont.plate(15))
                .foregroundStyle(directory.liveMeters == 0 ? KonumumProximity.door.tint : .white)
            if let live = orders.first(where: { $0.id == directory.liveDeliveryId }) ?? active.first {
                driveIdentity(live)
                driveButtons(live)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card(glow: true))
    }

    private func localizedKitchenStatusText(_ raw: String) -> String {
        guard KonumumLanguage.isEN else { return raw }
        if raw.contains("Kapıda") { return "At Pickup Window · Handing Through Car Window" }
        if raw.contains("Hazırlanıyor") { return "Preparing Your Order" }
        if raw.contains("Teslim") { return "Order Delivered" }
        return raw
    }

    private func driveIdentity(_ order: KonumumDelivery) -> some View {
        let m = directory.liveDeliveryId == order.id ? directory.liveMeters : order.meters
        let sec = directory.liveDeliveryId == order.id
            ? directory.liveSeconds
            : max(0, Int((Double(m) / Double(KonumumDirectory.approachStartMeters) * Double(KonumumDirectory.approachStartSeconds)).rounded()))
        return Group {
            if order.atDoor || m == 0 {
                Text(L("Kapı önünde · Paketiniz araç camından teslim edilir", "At pickup window · Handed through your car window"))
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(KonumumProximity.door.tint)
            } else if order.isOpen {
                Text(L(
                    "Restoran takibinde · Plaka \(order.plate) · \(KonumumDirectory.formatDistanceEta(meters: m, seconds: sec))",
                    "Live tracked · Plate \(order.plate) · \(KonumumDirectory.formatDistanceEta(meters: m, seconds: sec))"
                ))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KonumumTheme.neon)
            }
        }
    }

    @ViewBuilder
    private func driveButtons(_ order: KonumumDelivery) -> some View {
        let rest = directory.restaurants.first(where: { $0.id == order.restaurantId })
        HStack(spacing: 8) {
            if order.isOpen {
                Button {
                    let lat = rest?.mapLatitude ?? 41.2867
                    let lon = rest?.mapLongitude ?? 36.3300
                    let name = (rest?.branchTitle ?? "Restoran").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Restoran"
                    if let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lon)&dirflg=d&q=\(name)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill")
                        Text(L("CarPlay Rota", "CarPlay Route"))
                    }
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(KonumumTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(KonumumTheme.neon, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            if order.isOpen, !order.atDoor {
                Button(L("Kapıdayım", "I'm Here")) { directory.checkInAtDoor(id: order.id) }
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(KonumumTheme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(KonumumProximity.door.tint, in: Capsule())
            }
        }
    }

    private func orderCard(_ order: KonumumDelivery, live: Bool) -> some View {
        let restaurant = directory.restaurants.first(where: { $0.id == order.restaurantId })
        let status = order.kitchenStatus
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(restaurant?.brandName ?? "Restoran")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text(statusLabel(status))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(KonumumTheme.ink)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusTint(status), in: Capsule())
            }
            Text(order.lines.map(\.label).joined(separator: "\n"))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.78))
            if status == "iptal", !order.cancelReason.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text("\(L("İptal / Red Nedeni", "Reason")): \(order.cancelReason)")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(KonumumTheme.danger)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(KonumumTheme.danger.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            driveIdentity(order)
            HStack(spacing: 6) {
                ForEach(["iletildi", "kabul", "hazir", "yolda", "teslim"], id: \.self) { step in
                    Circle()
                        .fill(stepActive(status, step) ? KonumumTheme.neon : Color.white.opacity(0.18))
                        .frame(width: 7, height: 7)
                    Text(shortStep(step))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(stepActive(status, step) ? KonumumTheme.neon : Color.white.opacity(0.35))
                }
            }
            HStack {
                Text(stamp.string(from: order.createdAt))
                Spacer()
                Text(order.payment.rawValue)
                Text("₺\(order.total)")
                    .font(KonumumFont.plate(14))
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.55))
            HStack(spacing: 8) {
                if ["iletildi", "kabul"].contains(status) {
                    Button(L("İptal", "Cancel")) { directory.cancelOrder(id: order.id) }
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(KonumumTheme.danger)
                }
                driveButtons(order)
                if !order.isOpen {
                    Button(L("Yeniden sipariş", "Reorder")) { directory.reorder(order) }
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(KonumumTheme.neon)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(card(glow: live && order.isOpen))
    }

    private func statusLabel(_ status: String) -> String {
        switch status {
        case "iletildi": L("İLETİLDİ", "SENT")
        case "kabul": L("KABUL", "ACCEPTED")
        case "hazir": L("HAZIR", "READY")
        case "yolda": L("YOLDA", "ON ROUTE")
        case "kapıda", "kapida": L("KAPIDA", "AT DOOR")
        case "iptal": L("İPTAL", "CANCELED")
        default: L("TESLİM", "DELIVERED")
        }
    }

    private func statusTint(_ status: String) -> Color {
        switch status {
        case "iptal": KonumumTheme.danger
        case "hazir", "teslim": Color(red: 0.22, green: 0.95, blue: 0.48)
        default: KonumumTheme.neon
        }
    }

    private func shortStep(_ step: String) -> String {
        switch step {
        case "iletildi": L("İlet", "Sent")
        case "kabul": L("Kabul", "Prep")
        case "hazir": L("Hazır", "Ready")
        case "yolda": L("Yolda", "Route")
        default: L("Teslim", "Done")
        }
    }

    private func stepActive(_ status: String, _ step: String) -> Bool {
        let order = ["iletildi", "kabul", "hazir", "yolda", "teslim"]
        let current = status == "kapıda" || status == "kapida" ? "yolda" : status
        guard let now = order.firstIndex(of: current), let at = order.firstIndex(of: step) else { return false }
        return at <= now
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            content()
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(card(glow: false))
    }

    private func card(glow: Bool) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.045))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(glow ? KonumumTheme.neon.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 1)
            }
    }
}

struct KampanyalarView: View {
    @EnvironmentObject private var directory: KonumumDirectory
    @AppStorage(KonumumMemberStore.language) private var lang = "tr"

    private var campaigns: [(title: String, detail: String, code: String)] {
        [
            ("McDonald's Drive-Thru", L("%20 konumumyemek indirimi", "20% konumumyemek discount"), "KONUMUM20"),
            ("Köfteci Yusuf", L("İkinci menüde %15 indirim", "15% off on your second menu"), "YUSUF15"),
            ("KFC Samsun", L("Kova menüde 40 TL indirim", "40 TL off on bucket meals"), "MUTFAK40"),
            ("Metropol Card", L("Drive-Thru teslimatta 2 kat puan", "2x points on car pickup orders"), "METROPOL2X"),
            ("Metropol Card", L("İlk arabadan teslimatta 50 TL", "50 TL bonus on first car pickup"), "METRO50")
        ]
    }

    var body: some View {
        ZStack {
            KonumumTheme.graphite.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .center) {
                        Text(L("Kampanyalar", "Campaigns"))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        KonumumLangToggle()
                    }
                    .padding(.top, 12)
                    Text(L("konumumyemek.com özel restoran kodları ve Metropol Card", "Exclusive restaurant promo codes and Metropol Card offers"))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.62))

                    ForEach(directory.webCampaigns) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            if let branch = item.branchTitle, !branch.isEmpty {
                                Text(branch.uppercased())
                                    .font(.system(size: 11, weight: .heavy))
                                    .tracking(0.8)
                                    .foregroundStyle(KonumumTheme.neon)
                            }
                            Text(item.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(item.detail)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.72))
                            Text(item.code ?? "KONUMUM20")
                                .font(KonumumFont.plate(16))
                                .foregroundStyle(KonumumTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(KonumumTheme.neon, in: Capsule())
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.045))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(KonumumTheme.neon.opacity(0.28), lineWidth: 1)
                                }
                        }
                    }

                    ForEach(Array(campaigns.enumerated()), id: \.offset) { _, item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                            Text(item.detail)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.white.opacity(0.72))
                            Text(item.code)
                                .font(KonumumFont.plate(16))
                                .foregroundStyle(KonumumTheme.ink)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(KonumumTheme.neon, in: Capsule())
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.white.opacity(0.045))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(KonumumTheme.neon.opacity(0.28), lineWidth: 1)
                                }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
    }
}

struct UyelikProfilView: View {
    let profile: KonumumProfile
    @EnvironmentObject private var directory: KonumumDirectory
    @AppStorage(KonumumMemberStore.language) private var lang = "tr"
    @AppStorage(KonumumMemberStore.signedIn) private var isSignedIn = false
    @AppStorage(KonumumMemberStore.registered) private var isRegistered = false
    @AppStorage(KonumumMemberStore.name) private var storedName = ""
    @AppStorage(KonumumMemberStore.email) private var storedEmail = ""
    @AppStorage(KonumumMemberStore.phone) private var storedPhone = ""
    @AppStorage(KonumumMemberStore.password) private var storedPassword = ""
    @AppStorage(KonumumMemberStore.plate) private var storedPlate = ""
    @AppStorage(KonumumMemberStore.kvkk) private var storedKvkk = false
    @AppStorage(KonumumMemberStore.acikRiza) private var storedAcikRiza = false
    @FocusState private var focus: Field?
    @State private var fullName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var plate = ""
    @State private var password = ""
    @State private var attempted = false
    @State private var saved = false
    @State private var showDeleteConfirm = false
    @State private var kvkkOk = false
    @State private var acikRizaOk = false

    private enum Field: Hashable {
        case name, email, phone, plate, password
    }

    private var initials: String {
        let parts = fullName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init)
        return letters.joined().uppercased()
    }

    private var nameOk: Bool {
        let parts = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return parts.count >= 2
    }

    private var emailOk: Bool {
        email.contains("@") && email.contains(".")
    }

    private var phoneOk: Bool {
        phone.filter(\.isNumber).count >= 10
    }

    private var plateOk: Bool {
        plate.range(
            of: #"^(0[1-9]|[1-7][0-9]|8[01]) [A-Z]{1,3} [0-9]{2,4}$"#,
            options: .regularExpression
        ) != nil
    }

    private var passwordOk: Bool {
        password.count >= 6
    }

    private var profileComplete: Bool {
        nameOk && emailOk && phoneOk && plateOk && passwordOk && kvkkOk && acikRizaOk
    }

    var body: some View {
        ZStack {
            KonumumTheme.graphite.ignoresSafeArea()
            RadialGradient(
                colors: [KonumumTheme.neon.opacity(0.16), .clear],
                center: UnitPoint(x: 0.5, y: 0.08),
                startRadius: 8,
                endRadius: 240
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Spacer()
                        KonumumLangToggle()
                    }
                    .padding(.top, 12)

                    ZStack {
                        Circle()
                            .fill(KonumumTheme.neon.opacity(0.18))
                            .frame(width: 108, height: 108)
                        Circle()
                            .strokeBorder(KonumumTheme.neon, lineWidth: 2)
                            .frame(width: 108, height: 108)
                            .shadow(color: KonumumTheme.neon.opacity(0.7), radius: 14)
                        if initials.isEmpty {
                            Image(systemName: "person.fill")
                                .font(.system(size: 38, weight: .bold))
                                .foregroundStyle(KonumumTheme.neon)
                        } else {
                            Text(initials)
                                .font(.system(size: 32, weight: .bold))
                                .foregroundStyle(KonumumTheme.neon)
                        }
                    }
                    .padding(.top, 4)

                    Text(L("Profil", "Profile"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)

                    field(L("Ad Soyad", "Full Name"), text: $fullName, prompt: L("Adınız Soyadınız", "First & Last Name"), field: .name, invalid: attempted && !nameOk)
                    field(L("Mail Adresi", "Email Address"), text: $email, prompt: "ornek@konumumyemek.com", field: .email, invalid: attempted && !emailOk, keyboard: .emailAddress)
                    field(L("Telefon Numarası", "Phone Number"), text: phoneBinding, prompt: "0555 184 0055", field: .phone, invalid: attempted && !phoneOk, keyboard: .phonePad)
                    plateField
                    secretField(L("Şifre", "Password"), text: $password, field: .password, invalid: attempted && !passwordOk)

                    profileConsentTick(
                        isOn: $kvkkOk,
                        title: L("KVKK aydınlatma metnini okudum, kabul ediyorum", "I have read and accept the Privacy Notice (KVKK)"),
                        detail: L(
                            "E-posta, telefon, plaka ve teslim konumu drive-thru kimliği için işlenir. Teslimde konum kapanır.",
                            "Email, phone, license plate, and pickup location are processed for drive-thru identification. Location stops upon delivery."
                        )
                    )
                    profileConsentTick(
                        isOn: $acikRizaOk,
                        title: L("Açık rıza veriyorum", "I give my explicit consent"),
                        detail: L(
                            "Plakamın restoran ekranında gösterilmesine, siparişimin mutfağa iletilmesine ve araç camından teslim edilmesine açık rıza veriyorum.",
                            "I consent to displaying my license plate on the restaurant screen and handing my order through the car window."
                        )
                    )

                    if attempted && !profileComplete {
                        Text(L("Lütfen tüm üyelik bilgilerini eksiksiz doldurun!", "Please complete all profile fields accurately!"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(KonumumTheme.danger)
                    }

                    Button(action: save) {
                        Text(L("Bilgilerimi Güncelle", "Update My Profile"))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(KonumumTheme.ink)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(KonumumTheme.neon, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: KonumumTheme.neon.opacity(0.9), radius: 14)
                    }
                    .buttonStyle(KonumumPressStyle())
                    .padding(.top, 8)

                    Button(action: signOut) {
                        Text(L("Çıkış Yap", "Sign Out"))
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .overlay {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.28), lineWidth: 1.4)
                            }
                    }
                    .buttonStyle(KonumumPressStyle())

                    Button {
                        showDeleteConfirm = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text(L("Hesabımı ve Verilerimi Kalıcı Olarak Sil", "Permanently Delete My Account & Data"))
                                .font(.system(size: 15, weight: .bold))
                                .multilineTextAlignment(.center)
                        }
                        .foregroundStyle(KonumumTheme.danger)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(KonumumTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(KonumumTheme.danger.opacity(0.85), lineWidth: 1.4)
                        }
                    }
                    .buttonStyle(KonumumPressStyle())
                    .padding(.bottom, 28)
                }
                .padding(.horizontal, 24)
            }
        }
        .onAppear(perform: prefill)
        .alert(L("Kayıt Başarılı", "Saved Successfully"), isPresented: $saved) {
            Button(L("Tamam", "OK"), role: .cancel) {}
        } message: {
            Text(L("Mail, telefon ve plaka bilgileriniz güncellendi.", "Your email, phone, and license plate have been updated."))
        }
        .confirmationDialog(
            L("Hesabınızı Kalıcı Olarak Silmek İstiyor Musunuz?", "Permanently Delete Your Account?"),
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button(L("Hesabımı Kalıcı Olarak Sil", "Delete My Account Permanently"), role: .destructive) {
                deleteAccountPermanently()
            }
            Button(L("Vazgeç", "Cancel"), role: .cancel) {}
        } message: {
            Text(
                L(
                    "Üyelik bilgileriniz, kayıtlı plakanız ve aktif konum izleme verileriniz cihazdan ve bulut sunucularımızdan kalıcı olarak silinecektir. Bu işlem geri alınamaz.",
                    "Your profile information, registered license plate, and active location tracking data will be permanently deleted from this device and our cloud servers. This action cannot be undone."
                )
            )
        }
    }

    private var plateField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Araç Plakası", "Vehicle License Plate"))
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.62))
            TextField("", text: plateBinding, prompt: Text("34 KNM 55").foregroundStyle(Color.white.opacity(0.32)))
                .textFieldStyle(.plain)
                .font(KonumumFont.plate(18))
                .foregroundStyle(.white)
                .tint(KonumumTheme.neon)
                .focused($focus, equals: .plate)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(well(active: focus == .plate, invalid: attempted && !plateOk))
        }
    }

    private func field(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        field: Field,
        invalid: Bool,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.62))
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Color.white.opacity(0.32)))
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .tint(KonumumTheme.neon)
                .focused($focus, equals: field)
                .keyboardType(keyboard)
                .textInputAutocapitalization(field == .email ? .never : .words)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(well(active: focus == field, invalid: invalid))
        }
    }

    private func secretField(_ title: String, text: Binding<String>, field: Field, invalid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Color.white.opacity(0.62))
            SecureField("", text: text, prompt: Text("En az 6 karakter").foregroundStyle(Color.white.opacity(0.32)))
                .textContentType(.newPassword)
                .font(KonumumFont.plate(16))
                .foregroundStyle(.white)
                .tint(KonumumTheme.neon)
                .focused($focus, equals: field)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(well(active: focus == field, invalid: invalid))
        }
    }

    private var plateBinding: Binding<String> {
        Binding(
            get: { plate },
            set: { plate = PlateRegistrationView.formatPlate($0) }
        )
    }

    private var phoneBinding: Binding<String> {
        Binding(
            get: { phone },
            set: { phone = PlateRegistrationView.formatPhone($0) }
        )
    }

    private func prefill() {
        fullName = storedName.isEmpty ? profile.name : storedName
        email = storedEmail.isEmpty ? profile.email : storedEmail
        phone = storedPhone.isEmpty ? profile.phone : storedPhone
        plate = storedPlate.isEmpty ? (profile.plates.first ?? "") : storedPlate
        if password.isEmpty {
            password = storedPassword.isEmpty ? profile.password : storedPassword
        }
        if let member = directory.customerSession {
            if fullName.isEmpty { fullName = member.name }
            if email.isEmpty { email = member.email }
            if phone.isEmpty { phone = member.phone }
            if plate.isEmpty { plate = member.plates.first ?? "" }
        }
        kvkkOk = storedKvkk
        acikRizaOk = storedAcikRiza
    }

    private func profileConsentTick(isOn: Binding<Bool>, title: String, detail: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? KonumumTheme.neon : Color.white.opacity(0.35))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    Text(detail)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func save() {
        attempted = true
        guard profileComplete else { return }
        focus = nil
        storedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        storedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        storedPhone = phone
        storedPassword = password
        storedPlate = plate
        storedKvkk = true
        storedAcikRiza = true
        isRegistered = true
        _ = directory.registerMember(name: fullName, email: email, phone: phone, plate: plate, password: password)
        saved = true
    }

    private func signOut() {
        directory.signOutCustomer()
        isSignedIn = false
    }

    private func deleteAccountPermanently() {
        let currentEmail = email.isEmpty ? storedEmail : email
        let currentPlate = plate.isEmpty ? storedPlate : plate
        directory.deleteCustomerAccount(email: currentEmail, plate: currentPlate)
        storedName = ""
        storedEmail = ""
        storedPhone = ""
        storedPassword = ""
        storedPlate = ""
        storedKvkk = false
        storedAcikRiza = false
        UserDefaults.standard.removeObject(forKey: KonumumMemberStore.savedCards)
        isRegistered = false
        isSignedIn = false
    }

    private func well(active: Bool, invalid: Bool) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.white.opacity(0.045))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        invalid ? KonumumTheme.danger : (active ? KonumumTheme.neon : Color.white.opacity(0.14)),
                        lineWidth: active ? 1.5 : 1
                    )
            }
            .shadow(color: active && !invalid ? KonumumTheme.neon.opacity(0.22) : .clear, radius: 16)
    }
}

struct KonumumBottomBar: View {
    @Binding var selection: KonumumMemberTab
    var onHome: () -> Void
    @AppStorage(KonumumMemberStore.language) private var lang = "tr"

    var body: some View {
        HStack(spacing: 0) {
            tab(.home, "house.fill", L("Ana Sayfa", "Home"))
            tab(.orders, "bag.fill", L("Siparişlerim", "My Orders"))
            tab(.campaigns, "tag.fill", L("Kampanyalar", "Campaigns"))
            tab(.profile, "person.fill", L("Profil", "Profile"))
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(KonumumTheme.graphite.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(KonumumTheme.neon.opacity(0.22))
                .frame(height: 1)
        }
    }

    private func tab(_ item: KonumumMemberTab, _ icon: String, _ title: String) -> some View {
        let selected = selection == item
        return Button {
            if item == .home {
                onHome()
            } else {
                selection = item
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected ? KonumumTheme.neon : Color.white.opacity(0.45))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
