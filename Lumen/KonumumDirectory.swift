import Foundation
import SwiftUI

enum MealCardBrand: String, CaseIterable, Identifiable, Hashable, Codable {
    case sodexo = "Sodexo"
    case multinet = "Multinet"
    case setcard = "Setcard"
    case metropol = "Metropol Card"
    case ticket = "Ticket Restaurant"
    case krediKarti = "Kredi Kartı"

    var id: String { rawValue }
}

struct KonumumReorderDraft: Equatable {
    var restaurantId: String
    var lines: [KitchenOrderLine]
}

struct KonumumRestaurantAccount: Identifiable, Hashable, Codable {
    var id: String
    var bayiKodu: String
    var kitchenPassword: String
    var brandName: String
    var branchTitle: String
    var officialTitle: String = ""
    var email: String = ""
    var password: String = "mutfak55"
    var phone: String = ""
    var taxNumber: String = ""
    var address: String = ""
    var iban: String = ""
    var mapLatitude: Double = 41.2867
    var mapLongitude: Double = 36.3300
    var cuisine: String = "Mutfak"
    var hours: String = "10:00-23:00"
    var isOpen: Bool = true
    var busyLevel: String = "mid"
    var rating: Double = 4.5
    var ratingCount: Int = 0
    var logoMark: String = ""
    var logoBg: String = "#3AF1D7"
    var logoFg: String = "#0B0F19"

    var isWithinOperatingHours: Bool {
        let parts = hours.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: CharacterSet(charactersIn: "-–"))
        guard parts.count == 2 else { return true }
        func parseMin(_ str: String) -> Int? {
            let comps = str.trimmingCharacters(in: .whitespaces).components(separatedBy: ":")
            guard comps.count == 2, let h = Int(comps[0]), let m = Int(comps[1]) else { return nil }
            return h * 60 + m
        }
        guard let openMin = parseMin(parts[0]), let closeMin = parseMin(parts[1]) else { return true }
        let cal = Calendar.current
        let now = Date()
        let curMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        if closeMin <= openMin {
            return curMin >= openMin || curMin < closeMin
        }
        return curMin >= openMin && curMin < closeMin
    }

    var effectiveOpen: Bool {
        isOpen && isWithinOperatingHours
    }
}

struct KonumumCustomerAccount: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var email: String
    var phone: String
    var password: String
    var plates: [String]
    var mealCards: [MealCardBrand]
}

struct KonumumDelivery: Identifiable, Hashable, Codable {
    var id: String
    var createdAt: Date
    var restaurantId: String
    var customerId: String
    var plate: String
    var payment: MealCardBrand
    var lines: [KitchenOrderLine]
    var delivered: Bool
    var kitchenStatus: String = "teslim"
    var lane: String = ""
    var stall: Int = 0
    var speaker: Int = 0
    var speakerMatched: Bool = false
    var atDoor: Bool = false
    var meters: Int = 1400
    var cancelReason: String = ""

    var total: Int { lines.reduce(0) { $0 + $1.lineTotal } }
    var isOpen: Bool { !["teslim", "iptal"].contains(kitchenStatus) }
}

@MainActor
final class KonumumDirectory: ObservableObject {
    @Published private(set) var restaurants: [KonumumRestaurantAccount]
    @Published private(set) var customers: [KonumumCustomerAccount]
    @Published private(set) var deliveries: [KonumumDelivery]

    @Published var restaurantSession: KonumumRestaurantAccount?
    @Published var customerSession: KonumumCustomerAccount?

    @Published var liveMeters: Int = 1400
    @Published var liveSeconds: Int = 140
    @Published var kitchenStatusText: String = "Siparişiniz Hazırlanıyor"
    @Published var customerCollectedNotice = false
    @Published var approachActive = false
    @Published var readyNotice = false
    @Published var kitchenBannerText: String?
    @Published var kitchenBannerKind: String = "info" // "prep", "ready", "cancel"
    @Published var pendingReorder: KonumumReorderDraft?
    @Published var webLinked = false
    @Published var webMenuExtras: [String: [KonumumWebDish]] = [:]
    @Published var webMenus: [String: [KonumumWebDish]] = [:]
    @Published var webCampaigns: [KonumumWebCampaign] = []
    @Published var liveDeliveryId: String?
    @Published var liveRoute: CarConsoleRoute?
    @Published var carPlayConnected = false
    private var webBridgeTask: Task<Void, Never>?
    private var cloudSocket: URLSessionWebSocketTask?

    /// Bound by the menus screen so nested CarPlay/kitchen can always pop to restaurant list.
    var popToMenusHome: () -> Void = {}

    private var approachTask: Task<Void, Never>?
    static let approachStartMeters = 1400
    static let approachStartSeconds = 140

    static func formatDistanceEta(meters: Int, seconds: Int) -> String {
        let isEN = KonumumLanguage.isEN
        if meters <= 0 {
            return isEN ? "0 m · AT DOOR (0s)" : "0 m · KAPIDA (0 sn)"
        }
        let kmPart = meters / 1000
        let mPart = meters % 1000
        let distText = kmPart > 0 ? "\(kmPart) km \(mPart) m" : "\(meters) m"
        let totalSec = max(1, seconds)
        let min = totalSec / 60
        let sec = totalSec % 60
        let etaText: String
        if isEN {
            etaText = min > 0
                ? (sec > 0 ? "\(min)m \(sec)s" : "\(min)m")
                : "\(sec)s"
        } else {
            etaText = min > 0
                ? (sec > 0 ? "\(min) dk \(sec) sn" : "\(min) dk")
                : "\(sec) sn"
        }
        return "\(distText) (\(etaText))"
    }

    init() {
        let mcdonalds = KonumumRestaurantAccount(
            id: "mcd-samsun",
            bayiKodu: "SAMSUN-01",
            kitchenPassword: "mutfak55",
            brandName: "McDonald's",
            branchTitle: "McDonald's - Bulvar/Samsun Şubesi",
            officialTitle: "McDonald's Restoranları Gıda Ticaret A.Ş. Samsun Şubesi",
            email: "mcd@konumumyemek.com",
            password: "mutfak55",
            phone: "0362 000 00 01",
            taxNumber: "1234567890",
            address: "Atatürk Bulvarı No:18 İlkadım / Samsun",
            iban: "TR33 0006 1005 1978 6457 8413 26",
            mapLatitude: 41.2867,
            mapLongitude: 36.3300
        )
        let demoCustomer = KonumumCustomerAccount(
            id: "cust-demo",
            name: "Ahmet Yılmaz",
            email: "musteri@konumumyemek.com",
            phone: "0532 100 55 00",
            password: "konumum55",
            plates: ["34 KNM 55"],
            mealCards: [.sodexo, .metropol, .multinet]
        )
        let calendar = Calendar.current
        let today = Date()
        func stamp(_ hour: Int, _ minute: Int) -> Date {
            var parts = calendar.dateComponents([.year, .month, .day], from: today)
            parts.hour = hour
            parts.minute = minute
            return calendar.date(from: parts) ?? today
        }

        restaurants = [
            mcdonalds,
            KonumumRestaurantAccount(
                id: "bk-samsun", bayiKodu: "SAMSUN-02", kitchenPassword: "mutfak55",
                brandName: "Burger King", branchTitle: "Burger King - Piazza/Samsun Şubesi",
                officialTitle: "Burger King Restoranları Piazza Samsun Şubesi",
                email: "bk@konumumyemek.com", password: "mutfak55", phone: "0362 000 00 02",
                taxNumber: "2234567890", address: "Piazza AVM, Atakum / Samsun",
                iban: "TR44 0006 1005 1978 6457 8413 27", mapLatitude: 41.3220, mapLongitude: 36.2910
            ),
            KonumumRestaurantAccount(
                id: "kfc-samsun", bayiKodu: "SAMSUN-03", kitchenPassword: "mutfak55",
                brandName: "KFC", branchTitle: "KFC - Atakum/Samsun Şubesi",
                officialTitle: "KFC Atakum Gıda Ticaret Ltd. Şti.",
                email: "kfc@konumumyemek.com", password: "mutfak55", phone: "0362 000 00 03",
                taxNumber: "3234567890", address: "Atatürk Bulvarı Atakum / Samsun",
                iban: "TR55 0006 1005 1978 6457 8413 28", mapLatitude: 41.3305, mapLongitude: 36.2864
            ),
            KonumumRestaurantAccount(
                id: "yusuf-samsun", bayiKodu: "SAMSUN-04", kitchenPassword: "mutfak55",
                brandName: "Köfteci Yusuf", branchTitle: "Köfteci Yusuf - İlkadım/Samsun Şubesi",
                officialTitle: "Köfteci Yusuf İlkadım Şubesi",
                email: "yusuf@konumumyemek.com", password: "mutfak55", phone: "0362 000 00 04",
                taxNumber: "4234567890", address: "İstiklal Caddesi İlkadım / Samsun",
                iban: "TR66 0006 1005 1978 6457 8413 29", mapLatitude: 41.2860, mapLongitude: 36.3360
            ),
            KonumumRestaurantAccount(
                id: "adiyorem-samsun", bayiKodu: "SAMSUN-05", kitchenPassword: "mutfak55",
                brandName: "Adıyörem Çiğ Köfte", branchTitle: "Adıyörem Çiğ Köfte - İlkadım/Samsun",
                officialTitle: "Adıyörem Çiğ Köfte İlkadım",
                email: "adiyorem@konumumyemek.com", password: "mutfak55", phone: "0362 000 00 05",
                taxNumber: "5234567890", address: "Kale Mah. İlkadım / Samsun",
                iban: "TR77 0006 1005 1978 6457 8413 30", mapLatitude: 41.2922, mapLongitude: 36.3312
            ),
            KonumumRestaurantAccount(
                id: "calikusu-samsun", bayiKodu: "SAMSUN-06", kitchenPassword: "mutfak55",
                brandName: "Çalıkuşu Döner", branchTitle: "Çalıkuşu Döner - Atakum/Samsun",
                officialTitle: "Çalıkuşu Döner Atakum",
                email: "calikusu@konumumyemek.com", password: "mutfak55", phone: "0362 000 00 06",
                taxNumber: "6234567890", address: "Cumhuriyet Mah. Atakum / Samsun",
                iban: "TR88 0006 1005 1978 6457 8413 31", mapLatitude: 41.3278, mapLongitude: 36.2788
            ),
            KonumumRestaurantAccount(
                id: "haci-samsun", bayiKodu: "SAMSUN-07", kitchenPassword: "mutfak55",
                brandName: "Hacı Döner", branchTitle: "Hacı Döner - Bulvar/Samsun",
                officialTitle: "Hacı Döner Bulvar Şubesi",
                email: "haci@konumumyemek.com", password: "mutfak55", phone: "0362 000 00 07",
                taxNumber: "7234567890", address: "Atatürk Bulvarı İlkadım / Samsun",
                iban: "TR99 0006 1005 1978 6457 8413 32", mapLatitude: 41.2804, mapLongitude: 36.3348
            ),
            KonumumRestaurantAccount(
                id: "pizza-samsun", bayiKodu: "SAMSUN-08", kitchenPassword: "mutfak55",
                brandName: "Pizzacılar", branchTitle: "Pizzacılar - Piazza/Samsun",
                officialTitle: "Pizzacılar Piazza Samsun",
                email: "pizza@konumumyemek.com", password: "mutfak55", phone: "0362 000 00 08",
                taxNumber: "8234567890", address: "Piazza AVM yeme-içme katı, Atakum / Samsun",
                iban: "TR11 0006 1005 1978 6457 8413 33", mapLatitude: 41.3196, mapLongitude: 36.2944
            ),
            KonumumRestaurantAccount(
                id: "simit-samsun", bayiKodu: "SAMSUN-09", kitchenPassword: "mutfak55",
                brandName: "Simitçiler", branchTitle: "Simitçiler - Çarşı/Samsun",
                officialTitle: "Simitçiler Çarşı Samsun",
                email: "simit@konumumyemek.com", password: "mutfak55", phone: "0362 000 00 09",
                taxNumber: "9234567890", address: "Çarşı Mah. İlkadım / Samsun",
                iban: "TR22 0006 1005 1978 6457 8413 34", mapLatitude: 41.2888, mapLongitude: 36.3402
            )
        ]
        customers = [demoCustomer]
        deliveries = []
        restaurants = restaurants.map(Self.seededVenue)
    }

    private static func seededVenue(_ row: KonumumRestaurantAccount) -> KonumumRestaurantAccount {
        var next = row
        switch row.id {
        case "mcd-samsun":
            next.cuisine = "Burger"; next.hours = "08:00-02:00"; next.rating = 4.6; next.ratingCount = 2340
            next.logoMark = "M"; next.logoBg = "#dc1420"; next.logoFg = "#ffc70a"
        case "bk-samsun":
            next.cuisine = "Burger"; next.hours = "10:00-00:00"; next.rating = 4.4; next.ratingCount = 1890
            next.logoMark = "BK"; next.logoBg = "#d61c24"; next.logoFg = "#ffffff"
        case "kfc-samsun":
            next.cuisine = "Tavuk"; next.hours = "10:00-23:00"; next.rating = 4.5; next.ratingCount = 1560
            next.logoMark = "KFC"; next.logoBg = "#e3002b"; next.logoFg = "#ffffff"
        case "yusuf-samsun":
            next.cuisine = "Köfte"; next.hours = "10:00-22:00"; next.rating = 4.7; next.ratingCount = 980
            next.logoMark = "KY"; next.logoBg = "#8c121a"; next.logoFg = "#ffffff"
        case "adiyorem-samsun":
            next.cuisine = "Çiğ Köfte"; next.hours = "10:00-22:00"; next.rating = 4.5; next.ratingCount = 640
            next.logoMark = "AÇ"; next.logoBg = "#b81f1a"; next.logoFg = "#ff9e2e"
        case "calikusu-samsun":
            next.cuisine = "Döner"; next.hours = "11:00-23:00"; next.rating = 4.3; next.ratingCount = 420
            next.logoMark = "Ç"; next.logoBg = "#c45a12"; next.logoFg = "#ffffff"
        case "haci-samsun":
            next.cuisine = "Döner"; next.hours = "10:00-22:00"; next.rating = 4.4; next.ratingCount = 510
            next.logoMark = "HD"; next.logoBg = "#1f7a3a"; next.logoFg = "#ffffff"
        case "pizza-samsun":
            next.cuisine = "Pizza"; next.hours = "12:00-02:00"; next.rating = 4.2; next.ratingCount = 380
            next.logoMark = "P"; next.logoBg = "#e23c3c"; next.logoFg = "#ffd54a"
        case "simit-samsun":
            next.cuisine = "Fırın"; next.hours = "06:30-21:00"; next.rating = 4.8; next.ratingCount = 2100
            next.logoMark = "S"; next.logoBg = "#b8862b"; next.logoFg = "#ffffff"
        default:
            break
        }
        return next
    }

    func applyVenues(_ patches: [KonumumVenuePatch]) {
        guard !patches.isEmpty else { return }
        let staticIds = Set([
            "mcd-samsun", "bk-samsun", "kfc-samsun", "yusuf-samsun",
            "adiyorem-samsun", "calikusu-samsun", "haci-samsun",
            "pizza-samsun", "simit-samsun"
        ])
        let incomingIds = Set(patches.map(\.id))
        restaurants.removeAll { row in
            !staticIds.contains(row.id) && !incomingIds.contains(row.id)
        }
        restaurants = restaurants.map { row in
            guard let patch = patches.first(where: { $0.id == row.id }) else { return row }
            var next = row
            if let value = patch.bayiKodu, !value.isEmpty { next.bayiKodu = value }
            if let value = patch.brandName, !value.isEmpty { next.brandName = value }
            if let value = patch.branchTitle, !value.isEmpty { next.branchTitle = value }
            if let value = patch.officialTitle, !value.isEmpty { next.officialTitle = value }
            if let value = patch.email, !value.isEmpty { next.email = value }
            if let value = patch.password, !value.isEmpty {
                next.password = value
                next.kitchenPassword = value
            }
            if let value = patch.phone, !value.isEmpty { next.phone = value }
            if let value = patch.taxNumber, !value.isEmpty { next.taxNumber = value }
            if let value = patch.address, !value.isEmpty { next.address = value }
            if let value = patch.iban, !value.isEmpty { next.iban = value }
            if let value = patch.cuisine, !value.isEmpty { next.cuisine = value }
            if let value = patch.hours, !value.isEmpty { next.hours = value }
            if let value = patch.open { next.isOpen = value }
            if let value = patch.busy, !value.isEmpty { next.busyLevel = value }
            if let value = patch.rating { next.rating = value }
            if let value = patch.ratingCount { next.ratingCount = value }
            if let value = patch.logoMark, !value.isEmpty { next.logoMark = value }
            if let value = patch.logoBg, !value.isEmpty { next.logoBg = value }
            if let value = patch.logoFg, !value.isEmpty { next.logoFg = value }
            if let value = patch.mapLatitude { next.mapLatitude = value }
            if let value = patch.mapLongitude { next.mapLongitude = value }
            return next
        }
        // Append newly registered cloud restaurants (e.g. glrhmz / hmzglr-9822) not in static seed
        for patch in patches where !restaurants.contains(where: { $0.id == patch.id }) {
            let title = patch.brandName ?? patch.branchTitle ?? patch.officialTitle ?? patch.id
            guard !title.isEmpty else { continue }
            let account = KonumumRestaurantAccount(
                id: patch.id,
                bayiKodu: patch.bayiKodu ?? "BY-\(patch.id.suffix(4).uppercased())",
                kitchenPassword: patch.password ?? "mutfak55",
                brandName: title,
                branchTitle: patch.branchTitle ?? title,
                officialTitle: patch.officialTitle ?? title,
                email: patch.email ?? "",
                password: patch.password ?? "mutfak55",
                phone: patch.phone ?? "",
                taxNumber: patch.taxNumber ?? "",
                address: patch.address ?? "Samsun",
                iban: patch.iban ?? "",
                mapLatitude: patch.mapLatitude ?? 41.3320,
                mapLongitude: patch.mapLongitude ?? 36.2730,
                cuisine: patch.cuisine ?? "Restoran & Mutfak",
                hours: patch.hours ?? "09:00-23:00",
                isOpen: patch.open ?? true,
                busyLevel: patch.busy ?? "low",
                rating: patch.rating ?? 5.0,
                ratingCount: patch.ratingCount ?? 1,
                logoMark: patch.logoMark ?? String(title.prefix(2)).uppercased(),
                logoBg: patch.logoBg ?? "#3AF1D7",
                logoFg: patch.logoFg ?? "#0B0F19"
            )
            restaurants.insert(account, at: 0)
        }
        if var session = restaurantSession, let patch = patches.first(where: { $0.id == session.id }) {
            if let value = patch.cuisine, !value.isEmpty { session.cuisine = value }
            if let value = patch.hours, !value.isEmpty { session.hours = value }
            if let value = patch.open { session.isOpen = value }
            if let value = patch.busy, !value.isEmpty { session.busyLevel = value }
            if let value = patch.logoMark, !value.isEmpty { session.logoMark = value }
            if let value = patch.logoBg, !value.isEmpty { session.logoBg = value }
            if let value = patch.logoFg, !value.isEmpty { session.logoFg = value }
            restaurantSession = session
        }
    }

    func startWebBridge() {
        guard webBridgeTask == nil else { return }
        cloudSocket = KonumumWebBridge.listen { [weak self] event in
            Task { @MainActor in
                self?.applyCloud(event)
            }
        }
        webBridgeTask = Task { @MainActor [weak self] in
            await self?.refreshFromWeb()
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                await self.refreshFromWeb()
            }
        }
    }

    func dishes(for restaurantId: String) -> [KonumumWebDish] {
        if let cloud = webMenus[restaurantId], !cloud.isEmpty { return cloud }
        return webMenuExtras[restaurantId] ?? []
    }

    func cloudMenu(for restaurantId: String) -> [KonumumWebDish]? {
        let rows = webMenus[restaurantId]
        return (rows?.isEmpty == false) ? rows : nil
    }

    private func applyCloud(_ event: KonumumCloudEvent) {
        webLinked = true
        switch event {
        case .snapshot(let snap):
            applySnapshot(snap)
        case .order(let order):
            absorbWebOrders([order])
        case .menus(let menus):
            webMenus = menus
        case .campaigns(let campaigns):
            webCampaigns = campaigns.filter { $0.active ?? true }
        case .venues(let venues):
            applyVenues(venues)
        }
    }

    private func applySnapshot(_ snap: KonumumWebSnapshot) {
        webLinked = snap.linked
        webMenus = snap.menus
        webMenuExtras = snap.extras
        webCampaigns = snap.campaigns.filter { $0.active ?? true }
        absorbWebOrders(snap.orders)
        applyVenues(snap.venues)
    }

    private func refreshFromWeb() async {
        applySnapshot(await KonumumWebBridge.pull())
    }

    private func absorbWebOrders(_ rows: [KonumumWebOrder]) {
        for row in rows {
            let status = row.status ?? "iletildi"
            if let index = deliveries.firstIndex(where: { $0.id == row.id }) {
                let prevStatus = deliveries[index].kitchenStatus
                deliveries[index].kitchenStatus = status
                deliveries[index].delivered = status == "teslim"
                if let reason = row.cancelReason, !reason.isEmpty {
                    deliveries[index].cancelReason = reason
                }
                if status != prevStatus && isOwnOrder(deliveries[index]) {
                    let isEN = KonumumLanguage.isEN
                    if status == "kabul" {
                        kitchenBannerKind = "prep"
                        kitchenBannerText = isEN
                            ? "👨‍🍳 Kitchen accepted your order · Now preparing!"
                            : "👨‍🍳 Siparişiniz mutfağa alındı · Hazırlanıyor!"
                        kitchenStatusText = isEN ? "Preparing Your Order" : "Siparişiniz Hazırlanıyor"
                    } else if status == "hazir" {
                        readyNotice = true
                        kitchenBannerKind = "ready"
                        kitchenBannerText = isEN
                            ? "🍔 Your order is ready! Please approach the pickup window."
                            : "🍔 Siparişiniz hazır! Lütfen teslim penceresine yanaşın."
                        kitchenStatusText = isEN
                            ? "Order Ready · Waiting at Pickup Window"
                            : "Paketiniz Hazır · Teslim Penceresinde Bekleniyor"
                    } else if status == "iptal" {
                        let reasonText = deliveries[index].cancelReason.isEmpty
                            ? (isEN ? "Canceled by restaurant" : "Restoran tarafından iptal edildi")
                            : deliveries[index].cancelReason
                        kitchenBannerKind = "cancel"
                        kitchenBannerText = isEN
                            ? "⚠️ Order Canceled: \(reasonText)"
                            : "⚠️ Sipariş İptal Edildi: \(reasonText)"
                    } else if status == "teslim" {
                        kitchenBannerKind = "ready"
                        kitchenBannerText = isEN
                            ? "✅ Order handed through car window · Enjoy!"
                            : "✅ Paketiniz araç camından teslim edildi · Afiyet olsun!"
                    }
                }
                if let lane = row.lane { deliveries[index].lane = lane }
                if let stall = row.stall { deliveries[index].stall = stall }
                if let speaker = row.speaker { deliveries[index].speaker = speaker }
                if let matched = row.speakerMatched { deliveries[index].speakerMatched = matched }
                if let door = row.atDoor { deliveries[index].atDoor = door }
                if let m = row.meters {
                    if liveDeliveryId == row.id && approachActive {
                        deliveries[index].meters = liveMeters
                    } else {
                        deliveries[index].meters = m
                        if liveDeliveryId == row.id {
                            liveMeters = m
                            let ratio = Double(m) / Double(Self.approachStartMeters)
                            liveSeconds = max(0, Int((ratio * Double(Self.approachStartSeconds)).rounded()))
                        }
                    }
                }
                if ["iptal", "teslim"].contains(status), liveDeliveryId == row.id {
                    readyNotice = false
                    stopLiveApproach()
                    liveDeliveryId = nil
                }
                continue
            }
            let customer = customers.first { $0.name == row.customer || $0.plates.contains(row.plate) }
            let pay = MealCardBrand.allCases.first { $0.rawValue == row.payment } ?? .metropol
            deliveries.insert(
                KonumumDelivery(
                    id: row.id,
                    createdAt: Date(),
                    restaurantId: row.restaurantId,
                    customerId: customer?.id ?? "web-cust",
                    plate: row.plate,
                    payment: pay,
                    lines: [KitchenOrderLine(name: row.items, quantity: 1, unitPrice: row.total ?? 0)],
                    delivered: status == "teslim",
                    kitchenStatus: status,
                    lane: row.lane ?? "",
                    stall: row.stall ?? 0,
                    speaker: row.speaker ?? 0,
                    speakerMatched: row.speakerMatched ?? false,
                    atDoor: row.atDoor ?? false,
                    meters: row.meters ?? Self.approachStartMeters,
                    cancelReason: row.cancelReason ?? ""
                ),
                at: 0
            )
        }
    }

    private func isOwnOrder(_ order: KonumumDelivery) -> Bool {
        if let customer = customerSession {
            return order.customerId == customer.id || customer.plates.contains(order.plate)
        }
        return liveDeliveryId == order.id
    }

    var liveKitchenRoute: CarConsoleRoute {
        let live = deliveries.last(where: { !$0.delivered }) ?? deliveries.last
        let restaurant = restaurants.first(where: { $0.id == live?.restaurantId }) ?? restaurants[0]
        return CarConsoleRoute(
            deliveryId: live?.id,
            restaurantName: restaurant.brandName,
            destinationTitle: restaurant.branchTitle,
            plate: live?.plate ?? "34 KNM 55",
            paymentTitle: live?.payment.rawValue ?? "Metropol Card",
            lines: live?.lines ?? [KitchenOrderLine(name: "Big Mac", quantity: 1, unitPrice: 215)]
        )
    }

    func restaurantDeliveries(for account: KonumumRestaurantAccount) -> [KonumumDelivery] {
        deliveries.filter { $0.restaurantId == account.id }
    }

    func todayDeliveredCount(for account: KonumumRestaurantAccount) -> Int {
        restaurantDeliveries(for: account).filter(\.delivered).count
    }

    func todayRevenue(for account: KonumumRestaurantAccount) -> Int {
        restaurantDeliveries(for: account).filter(\.delivered).reduce(0) { $0 + $1.total }
    }

    func revenueByBrand(for account: KonumumRestaurantAccount) -> [(MealCardBrand, Int)] {
        var bucket: [MealCardBrand: Int] = [:]
        for delivery in restaurantDeliveries(for: account) where delivery.delivered {
            bucket[delivery.payment, default: 0] += delivery.total
        }
        return [MealCardBrand.sodexo, .metropol, .multinet, .setcard, .ticket, .krediKarti].map { brand in
            (brand, bucket[brand] ?? 0)
        }
    }

    @discardableResult
    func recordOrder(
        plate: String,
        restaurantName: String,
        payment: MealCardBrand,
        lines: [KitchenOrderLine]
    ) -> String {
        let restaurant = restaurants.first { $0.brandName == restaurantName } ?? restaurants[0]
        let customer = customers.first { $0.plates.contains(plate) }
        let id = "live-\(UUID().uuidString.prefix(8))"
        let loc = KonumumLocation.shared
        let initialMeters: Int
        let initialPoint: (Double, Double)
        if let gps = loc.lastCoordinate {
            let rawDist = loc.distanceMeters(latitude: restaurant.mapLatitude, longitude: restaurant.mapLongitude)
            initialMeters = rawDist <= 20 ? 0 : rawDist
            initialPoint = (gps.latitude, gps.longitude)
        } else {
            initialMeters = Self.approachStartMeters
            initialPoint = Self.coords(restaurant: restaurant, meters: Self.approachStartMeters)
        }
        deliveries.append(
            KonumumDelivery(
                id: id,
                createdAt: Date(),
                restaurantId: restaurant.id,
                customerId: customer?.id ?? "walkin",
                plate: plate,
                payment: payment,
                lines: lines,
                delivered: false,
                kitchenStatus: "iletildi",
                atDoor: initialMeters == 0,
                meters: initialMeters
            )
        )
        liveDeliveryId = id
        readyNotice = false
        kitchenStatusText = "Restoran takibi başladı · Aracınız izleniyor"
        let web = KonumumWebOrder(
            id: id,
            restaurantId: restaurant.id,
            driverName: customer?.name ?? plate,
            customer: customer?.name ?? plate,
            plate: plate,
            items: lines.map(\.label).joined(separator: ", "),
            payment: payment.rawValue,
            latitude: initialPoint.0,
            longitude: initialPoint.1,
            meters: initialMeters,
            status: "iletildi",
            total: lines.reduce(0) { $0 + $1.lineTotal },
            source: "ios",
            updatedAt: nil
        )
        Task { await KonumumWebBridge.postOrder(web) }
        beginCustomerTrip(
            CarConsoleRoute(
                deliveryId: id,
                restaurantName: restaurant.brandName,
                destinationTitle: restaurant.branchTitle,
                plate: plate,
                paymentTitle: payment.rawValue,
                lines: lines
            )
        )
        return id
    }

    static func coords(restaurant: KonumumRestaurantAccount, meters: Int) -> (Double, Double) {
        let progress = 1 - (Double(max(0, min(approachStartMeters, meters))) / Double(approachStartMeters))
        let startLat = restaurant.mapLatitude - 0.00126
        let startLng = restaurant.mapLongitude - 0.00126
        return (
            startLat + (restaurant.mapLatitude - startLat) * progress,
            startLng + (restaurant.mapLongitude - startLng) * progress
        )
    }

    private func pushLiveLocation() {
        guard let id = liveDeliveryId else { return }
        let delivery = deliveries.last(where: { $0.id == id })
        let restaurant = restaurants.first(where: { account in
            delivery?.restaurantId == account.id
        }) ?? restaurants[0]
        let plate = delivery?.plate ?? customerSession?.plates.first ?? "34 KNM 55"
        let loc = KonumumLocation.shared
        let point: (Double, Double)
        if let gps = loc.lastCoordinate {
            let rawDist = loc.distanceMeters(latitude: restaurant.mapLatitude, longitude: restaurant.mapLongitude)
            liveMeters = rawDist <= 20 ? 0 : rawDist
            let speed = loc.lastSpeedMps > 1.5 ? loc.lastSpeedMps : 8.33
            liveSeconds = liveMeters == 0 ? 0 : max(1, Int((Double(liveMeters) / speed).rounded()))
            point = (gps.latitude, gps.longitude)
        } else {
            point = Self.coords(restaurant: restaurant, meters: liveMeters)
        }
        if let index = deliveries.firstIndex(where: { $0.id == id }) {
            deliveries[index].meters = liveMeters
            if liveMeters == 0 {
                deliveries[index].atDoor = true
            }
        }
        let currentMeters = liveMeters
        let currentEta = liveSeconds
        let currentStatus = deliveries.first(where: { $0.id == id })?.kitchenStatus
        Task {
            await KonumumWebBridge.pushLocation(
                id: id,
                restaurantId: restaurant.id,
                plate: plate,
                meters: currentMeters,
                etaSeconds: currentEta,
                latitude: point.0,
                longitude: point.1,
                status: currentStatus
            )
        }
    }

    func setKitchenStatus(id: String, status: String, cancelReason: String? = nil) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }) else { return }
        deliveries[index].kitchenStatus = status
        deliveries[index].delivered = status == "teslim"
        if let cancelReason, !cancelReason.isEmpty {
            deliveries[index].cancelReason = cancelReason
        }
        Task { await KonumumWebBridge.patchStatus(id: id, status: status, cancelReason: cancelReason) }
        readyNotice = false
        if ["iptal", "teslim"].contains(status) {
            if liveDeliveryId == id {
                stopLiveApproach()
                liveDeliveryId = nil
            }
        }
    }

    func cancelOrder(id: String, reason: String = "Müşteri tarafından iptal edildi") {
        if let index = deliveries.firstIndex(where: { $0.id == id }) {
            deliveries[index].cancelReason = reason
        }
        setKitchenStatus(id: id, status: "iptal", cancelReason: reason)
    }

    func startPickup(id: String) {
        guard let delivery = deliveries.first(where: { $0.id == id }) else { return }
        let restaurant = restaurants.first(where: { $0.id == delivery.restaurantId }) ?? restaurants[0]
        setKitchenStatus(id: id, status: "yolda")
        readyNotice = false
        beginCustomerTrip(
            CarConsoleRoute(
                deliveryId: id,
                restaurantName: restaurant.brandName,
                destinationTitle: restaurant.branchTitle,
                plate: delivery.plate,
                paymentTitle: delivery.payment.rawValue,
                lines: delivery.lines
            )
        )
    }

    func reorder(_ delivery: KonumumDelivery) {
        pendingReorder = KonumumReorderDraft(restaurantId: delivery.restaurantId, lines: delivery.lines)
    }

    private func nextSpeaker(for restaurantId: String, excluding id: String) -> Int {
        let used = Set(
            deliveries
                .filter { $0.restaurantId == restaurantId && $0.id != id && $0.isOpen && $0.speaker > 0 }
                .map(\.speaker)
        )
        return used.contains(1) ? 2 : 1
    }

    func checkInAtSpeaker(id: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }) else { return }
        let speaker = nextSpeaker(for: deliveries[index].restaurantId, excluding: id)
        deliveries[index].speaker = speaker
        deliveries[index].lane = speaker == 1 ? "A" : "B"
        deliveries[index].speakerMatched = false
        deliveries[index].atDoor = false
        if ["hazir", "iletildi", "kabul"].contains(deliveries[index].kitchenStatus) {
            deliveries[index].kitchenStatus = "yolda"
        }
        kitchenStatusText = "Hoparlör \(speaker) · Şerit \(deliveries[index].lane)"
        Task { await KonumumWebBridge.patchDrive(id: id, action: "speaker") }
    }

    func confirmSpeakerMatch(id: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }) else { return }
        if deliveries[index].speaker == 0 {
            let speaker = nextSpeaker(for: deliveries[index].restaurantId, excluding: id)
            deliveries[index].speaker = speaker
            deliveries[index].lane = speaker == 1 ? "A" : "B"
        }
        deliveries[index].speakerMatched = true
        deliveries[index].stall = deliveries[index].speaker
        kitchenStatusText = "Hoparlör eşleşti · \(deliveries[index].plate)"
        Task { await KonumumWebBridge.patchDrive(id: id, action: "match") }
    }

    func checkInAtDoor(id: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }) else { return }
        deliveries[index].atDoor = true
        deliveries[index].kitchenStatus = "kapıda"
        liveMeters = 0
        kitchenStatusText = "Kapıda · Paketiniz araç camından teslim ediliyor"
        Task { await KonumumWebBridge.patchDrive(id: id, action: "door") }
    }

    func markDelivered(id: String) {
        guard let index = deliveries.firstIndex(where: { $0.id == id }) else { return }
        deliveries[index].delivered = true
        deliveries[index].kitchenStatus = "teslim"
        readyNotice = false
        if liveDeliveryId == id {
            stopLiveApproach()
            liveDeliveryId = nil
        }
        Task { await KonumumWebBridge.patchStatus(id: id, status: "teslim") }
    }

    func markDelivered(plate: String) {
        guard let index = deliveries.lastIndex(where: { !$0.delivered && $0.plate == plate }) else { return }
        deliveries[index].delivered = true
        deliveries[index].kitchenStatus = "teslim"
        readyNotice = false
        if liveDeliveryId == deliveries[index].id {
            stopLiveApproach()
            liveDeliveryId = nil
        }
        Task { await KonumumWebBridge.patchStatus(id: deliveries[index].id, status: "teslim") }
    }

    func startLiveApproach() {
        approachTask?.cancel()
        if KonumumLocation.shared.lastCoordinate == nil {
            liveMeters = Self.approachStartMeters
            liveSeconds = Self.approachStartSeconds
        }
        kitchenStatusText = "Siparişiniz Hazırlanıyor"
        customerCollectedNotice = false
        readyNotice = false
        approachActive = true
        KonumumLocation.shared.onLocationUpdate = { [weak self] _, _ in
            guard let self, self.approachActive else { return }
            self.pushLiveLocation()
            if self.liveMeters == 0 {
                self.kitchenStatusText = "Teslim Noktasında"
                KonumumLocation.shared.stop()
            }
        }
        pushLiveLocation()
        approachTask = Task { @MainActor in
            while !Task.isCancelled && liveMeters > 0 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                if KonumumLocation.shared.lastCoordinate == nil {
                    liveMeters = max(0, liveMeters - 15)
                    let ratio = Double(liveMeters) / Double(Self.approachStartMeters)
                    liveSeconds = max(0, Int((ratio * Double(Self.approachStartSeconds)).rounded()))
                }
                pushLiveLocation()
                if liveMeters == 0 {
                    kitchenStatusText = "Teslim Noktasında"
                    KonumumLocation.shared.stop()
                }
            }
        }
    }

    func beginCustomerTrip(_ route: CarConsoleRoute) {
        liveRoute = route
        KonumumLocation.shared.prepareForOrder()
        startLiveApproach()
    }

    func confirmCustomerCollected(deliveryId: String?, plate: String) {
        approachTask?.cancel()
        liveMeters = 0
        liveSeconds = 0
        kitchenStatusText = "Müşteri Siparişi Teslim Aldı"
        customerCollectedNotice = true
        approachActive = false
        liveRoute = nil
        KonumumLocation.shared.stop()
        if let deliveryId {
            markDelivered(id: deliveryId)
        } else {
            markDelivered(plate: plate)
        }
    }

    func stopLiveApproach() {
        approachTask?.cancel()
        approachTask = nil
        approachActive = false
        customerCollectedNotice = false
        kitchenStatusText = "Siparişiniz Hazırlanıyor"
        liveMeters = Self.approachStartMeters
        liveSeconds = Self.approachStartSeconds
        liveRoute = nil
        KonumumLocation.shared.stop()
    }

    func customerOrders(for account: KonumumCustomerAccount) -> [KonumumDelivery] {
        deliveries
            .filter { $0.customerId == account.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func memberOrders(plate: String, customerId: String?) -> [KonumumDelivery] {
        deliveries
            .filter { order in
                order.plate == plate || (customerId.map { order.customerId == $0 } ?? false)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func registerMember(name: String, email: String, phone: String, plate: String, password: String) -> KonumumCustomerAccount {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = customers.firstIndex(where: {
            $0.email.lowercased() == trimmedEmail || $0.plates.contains(plate)
        }) {
            customers[index].name = trimmedName
            customers[index].email = trimmedEmail
            customers[index].phone = trimmedPhone
            customers[index].password = pin
            if !customers[index].plates.contains(plate) {
                customers[index].plates.insert(plate, at: 0)
            }
            customerSession = customers[index]
            let acc = customers[index]
            Task {
                await KonumumWebBridge.syncCustomerProfile(
                    id: acc.id, name: trimmedName, email: trimmedEmail, phone: trimmedPhone, plate: plate, password: pin
                )
            }
            return acc
        }
        let account = KonumumCustomerAccount(
            id: "cust-\(UUID().uuidString.prefix(8))",
            name: trimmedName,
            email: trimmedEmail,
            phone: trimmedPhone,
            password: pin,
            plates: [plate],
            mealCards: [.metropol]
        )
        customers.append(account)
        customerSession = account
        Task {
            await KonumumWebBridge.syncCustomerProfile(
                id: account.id, name: trimmedName, email: trimmedEmail, phone: trimmedPhone, plate: plate, password: pin
            )
        }
        return account
    }

    func signInRestaurant(bayi: String, password: String) -> Bool {
        let key = bayi.trimmingCharacters(in: .whitespacesAndNewlines)
        let pin = password.trimmingCharacters(in: .whitespacesAndNewlines)
        let emailKey = key.lowercased()
        let bayiKey = key.uppercased()
        guard let match = restaurants.first(where: { account in
            let pinOk = account.kitchenPassword == pin || account.password == pin
            return pinOk && (
                account.bayiKodu.uppercased() == bayiKey ||
                account.email.lowercased() == emailKey
            )
        }) else { return false }
        restaurantSession = match
        return true
    }

    func updateRestaurantProfile(_ account: KonumumRestaurantAccount) {
        guard let index = restaurants.firstIndex(where: { $0.id == account.id }) else { return }
        restaurants[index] = account
        if restaurantSession?.id == account.id {
            restaurantSession = account
        }
    }

    func signInCustomer(identifier: String, password: String) -> Bool {
        let key = identifier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pin = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = customers.first(where: { account in
            account.password == pin && (
                account.email.lowercased() == key ||
                account.phone.filter(\.isNumber) == key.filter(\.isNumber) ||
                account.phone.lowercased() == key
            )
        }) else { return false }
        customerSession = match
        return true
    }

    func signOutRestaurant() { restaurantSession = nil }
    func signOutCustomer() { customerSession = nil }

    func deleteCustomerAccount(email: String, plate: String) {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedPlate = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentId = customerSession?.id ?? customers.first(where: {
            $0.email.lowercased() == trimmedEmail || $0.plates.contains(trimmedPlate)
        })?.id ?? "unknown"

        stopLiveApproach()
        liveDeliveryId = nil
        readyNotice = false

        customers.removeAll { account in
            account.id == currentId ||
            (!trimmedEmail.isEmpty && account.email.lowercased() == trimmedEmail) ||
            (!trimmedPlate.isEmpty && account.plates.contains(trimmedPlate))
        }
        deliveries.removeAll { order in
            order.customerId == currentId ||
            (!trimmedPlate.isEmpty && order.plate == trimmedPlate)
        }
        customerSession = nil

        Task {
            await KonumumWebBridge.deleteCustomerProfile(id: currentId, email: trimmedEmail, plate: trimmedPlate)
        }
    }
}
