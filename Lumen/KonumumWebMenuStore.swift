import Foundation

struct KonumumDishVariation: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var priceDelta: Int
}

struct KonumumWebDish: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var price: Int
    var photo: String?
    var photoBg: String?
    var allergens: [String]?
    var kcal: Int?
    var variations: [KonumumDishVariation]?
    var soldOut: Bool?
    var category: String?
    var stock: Int?
}

struct KonumumWebOrder: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var restaurantId: String
    var driverName: String?
    var customer: String
    var plate: String
    var items: String
    var payment: String
    var latitude: Double?
    var longitude: Double?
    var meters: Int?
    var status: String?
    var total: Int?
    var source: String?
    var updatedAt: String?
    var lane: String?
    var stall: Int?
    var speaker: Int?
    var speakerMatched: Bool?
    var atDoor: Bool?
    var cancelReason: String?
}

struct KonumumWebCampaign: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var restaurantId: String?
    var branchTitle: String?
    var title: String
    var detail: String
    var code: String?
    var discountPercent: Int?
    var active: Bool?
}

struct KonumumVenuePatch: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var bayiKodu: String?
    var brandName: String?
    var branchTitle: String?
    var officialTitle: String?
    var email: String?
    var password: String?
    var phone: String?
    var taxNumber: String?
    var address: String?
    var iban: String?
    var cuisine: String?
    var hours: String?
    var open: Bool?
    var busy: String?
    var rating: Double?
    var ratingCount: Int?
    var logoMark: String?
    var logoBg: String?
    var logoFg: String?
    var mapLatitude: Double?
    var mapLongitude: Double?
    var menu: [KonumumWebDish]?
}

struct KonumumWebSnapshot: Sendable {
    var menus: [String: [KonumumWebDish]]
    var extras: [String: [KonumumWebDish]]
    var orders: [KonumumWebOrder]
    var campaigns: [KonumumWebCampaign]
    var venues: [KonumumVenuePatch]
    var linked: Bool
}

enum KonumumCloudEvent: Sendable {
    case snapshot(KonumumWebSnapshot)
    case order(KonumumWebOrder)
    case menus([String: [KonumumWebDish]])
    case campaigns([KonumumWebCampaign])
    case venues([KonumumVenuePatch])
}

enum KonumumWebBridge {
    // MARK: - Supabase Cloud Direct Credentials
    static let SUPABASE_PROJECT_ID = "hetcihydnkgbuglsuzcs"
    static let SUPABASE_URL = "https://hetcihydnkgbuglsuzcs.supabase.co"
    static let SUPABASE_ANON_KEY = "sb_publishable_Xh8V52jmvs1JFpKX7v8SuA_SFk1DA0Z"
    static let SUPABASE_SERVICE_ROLE_KEY = ""
    static var SUPABASE_ACTIVE_KEY: String {
        SUPABASE_SERVICE_ROLE_KEY.isEmpty ? SUPABASE_ANON_KEY : SUPABASE_SERVICE_ROLE_KEY
    }

    static var supabaseOrdersURL: URL {
        URL(string: "\(SUPABASE_URL)/rest/v1/orders?on_conflict=id")!
    }
    static var supabaseTrackingURL: URL {
        URL(string: "\(SUPABASE_URL)/rest/v1/live_tracking?on_conflict=order_id")!
    }
    static var supabaseStateURL: URL {
        URL(string: "\(SUPABASE_URL)/rest/v1/restaurant_state?on_conflict=key")!
    }
    static var supabaseRealtimeWSURL: URL {
        let encodedKey = SUPABASE_ACTIVE_KEY.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? SUPABASE_ACTIVE_KEY
        let wsBase = SUPABASE_URL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        return URL(string: "\(wsBase)/realtime/v1/websocket?apikey=\(encodedKey)&vsn=1.0.0")!
    }

    private static let fileFallback = URL(fileURLWithPath: "/Users/hamzaguler/Projects/Lumen/web/data/runtime.json")
    private static let seedFallback = URL(fileURLWithPath: "/Users/hamzaguler/Projects/Lumen/web/data/seed.json")

    private static func makeSupabaseRequest(url: URL, method: String = "POST", prefer: String? = "resolution=merge-duplicates,return=minimal") -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 3.5
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(SUPABASE_ACTIVE_KEY, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(SUPABASE_ACTIVE_KEY)", forHTTPHeaderField: "Authorization")
        if let prefer {
            req.setValue(prefer, forHTTPHeaderField: "Prefer")
        }
        return req
    }

    static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Int {
        let R = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) *
                sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(0.0, 1.0 - a)))
        return max(0, Int((R * c).rounded()))
    }

    static func pull() async -> KonumumWebSnapshot {
        if let cloudSnap = await fetchSupabaseSnapshot() {
            return cloudSnap
        }
        return readFile()
    }

    static func postOrder(_ order: KonumumWebOrder) async {
        struct SupabaseOrderRow: Encodable {
            var id: String
            var restaurant_id: String
            var driver_name: String
            var customer_name: String
            var plate: String
            var items: String
            var payment_method: String
            var total_amount: Int
            var order_status: String
            var cancel_reason: String
            var at_door: Bool
            var source: String
            var updated_at: String
        }
        struct SupabaseTrackingRow: Encodable {
            var order_id: String
            var restaurant_id: String
            var plate: String
            var latitude: Double
            var longitude: Double
            var distance_meters: Int
            var eta_seconds: Int
            var order_status: String
            var trigger_alarm: Bool
            var at_door: Bool
            var updated_at: String
        }

        let nowISO = ISO8601DateFormatter().string(from: Date())
        let meters = max(0, order.meters ?? 2400)
        let status = order.status ?? "iletildi"
        let lat = order.latitude ?? 40.9682
        let lon = order.longitude ?? 29.0748

        let orderRow = SupabaseOrderRow(
            id: order.id,
            restaurant_id: order.restaurantId,
            driver_name: order.driverName ?? order.customer,
            customer_name: order.customer,
            plate: order.plate,
            items: order.items,
            payment_method: order.payment,
            total_amount: order.total ?? 0,
            order_status: status,
            cancel_reason: order.cancelReason ?? "",
            at_door: meters == 0 || (order.atDoor ?? false),
            source: "ios-supabase",
            updated_at: nowISO
        )
        let trackingRow = SupabaseTrackingRow(
            order_id: order.id,
            restaurant_id: order.restaurantId,
            plate: order.plate,
            latitude: lat,
            longitude: lon,
            distance_meters: meters,
            eta_seconds: Int((Double(meters) / 8.33).rounded()),
            order_status: status,
            trigger_alarm: meters < 500,
            at_door: meters == 0,
            updated_at: nowISO
        )

        var req1 = makeSupabaseRequest(url: supabaseOrdersURL, method: "POST")
        req1.httpBody = try? JSONEncoder().encode([orderRow])
        _ = try? await URLSession.shared.data(for: req1)

        var req2 = makeSupabaseRequest(url: supabaseTrackingURL, method: "POST")
        req2.httpBody = try? JSONEncoder().encode([trackingRow])
        _ = try? await URLSession.shared.data(for: req2)

        upsertLocalOrder(order)
    }

    static func syncCustomerProfile(id: String, name: String, email: String, phone: String, plate: String, password: String) async {
        struct ProfileItem: Encodable {
            var id: String
            var name: String
            var email: String
            var phone: String
            var plate: String
            var kvkk: Bool
            var kvkkLoc: Bool
        }
        struct StateUpsertRow: Encodable {
            var key: String
            var payload: ProfileItem
            var updated_at: String
        }
        let row = StateUpsertRow(
            key: "customer_\(id)",
            payload: ProfileItem(id: id, name: name, email: email, phone: phone, plate: plate, kvkk: true, kvkkLoc: true),
            updated_at: ISO8601DateFormatter().string(from: Date())
        )
        var req = makeSupabaseRequest(url: supabaseStateURL, method: "POST")
        req.httpBody = try? JSONEncoder().encode([row])
        _ = try? await URLSession.shared.data(for: req)
    }

    static func deleteCustomerProfile(id: String, email: String, plate: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let encodedId = ("customer_" + id).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if !encodedId.isEmpty,
           let url = URL(string: "\(SUPABASE_URL)/rest/v1/restaurant_state?key=eq.\(encodedId)") {
            var req = makeSupabaseRequest(url: url, method: "DELETE", prefer: "return=minimal")
            req.httpBody = nil
            _ = try? await URLSession.shared.data(for: req)
        }
        if !trimmedEmail.isEmpty,
           let encodedEmail = ("__state_customer:" + trimmedEmail).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "\(SUPABASE_URL)/rest/v1/orders?id=eq.\(encodedEmail)") {
            var req = makeSupabaseRequest(url: url, method: "DELETE", prefer: "return=minimal")
            req.httpBody = nil
            _ = try? await URLSession.shared.data(for: req)
        }
        let trimmedPlate = plate.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPlate.isEmpty,
           let encodedPlate = trimmedPlate.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let trackUrl = URL(string: "\(SUPABASE_URL)/rest/v1/live_tracking?plate=eq.\(encodedPlate)") {
            var req = makeSupabaseRequest(url: trackUrl, method: "DELETE", prefer: "return=minimal")
            req.httpBody = nil
            _ = try? await URLSession.shared.data(for: req)
        }
    }

    static func patchStatus(id: String, status: String, cancelReason: String? = nil) async {
        struct StatusPatch: Encodable {
            var order_status: String
            var cancel_reason: String?
            var updated_at: String
        }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        if let url = URL(string: "\(SUPABASE_URL)/rest/v1/orders?id=eq.\(id)") {
            var req = makeSupabaseRequest(url: url, method: "PATCH")
            req.httpBody = try? JSONEncoder().encode(StatusPatch(order_status: status, cancel_reason: cancelReason, updated_at: nowISO))
            _ = try? await URLSession.shared.data(for: req)
        }
        if let trUrl = URL(string: "\(SUPABASE_URL)/rest/v1/live_tracking?order_id=eq.\(id)") {
            struct TrPatch: Encodable { var order_status: String; var updated_at: String }
            var req = makeSupabaseRequest(url: trUrl, method: "PATCH")
            req.httpBody = try? JSONEncoder().encode(TrPatch(order_status: status, updated_at: nowISO))
            _ = try? await URLSession.shared.data(for: req)
        }
        patchLocalOrder(id: id) { ord in
            ord.status = status
            if let cancelReason { ord.cancelReason = cancelReason }
            ord.updatedAt = nowISO
        }
    }

    static func patchDrive(id: String, action: String, speaker: Int = 0) async {
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let isDoor = (action == "door")
        if let url = URL(string: "\(SUPABASE_URL)/rest/v1/orders?id=eq.\(id)") {
            struct DrivePatch: Encodable {
                var at_door: Bool
                var order_status: String?
                var speaker: Int?
                var updated_at: String
            }
            var req = makeSupabaseRequest(url: url, method: "PATCH")
            req.httpBody = try? JSONEncoder().encode(
                DrivePatch(
                    at_door: isDoor,
                    order_status: isDoor ? "kapıda" : nil,
                    speaker: speaker > 0 ? speaker : nil,
                    updated_at: nowISO
                )
            )
            _ = try? await URLSession.shared.data(for: req)
        }
        patchLocalOrder(id: id) { ord in
            if isDoor {
                ord.atDoor = true
                ord.meters = 0
                ord.status = "kapıda"
            }
            if speaker > 0 {
                ord.speaker = speaker
                ord.speakerMatched = true
            }
            ord.updatedAt = nowISO
        }
    }

    static func pushLocation(
        id: String,
        restaurantId: String,
        plate: String,
        meters: Int,
        etaSeconds: Int? = nil,
        latitude: Double,
        longitude: Double,
        status: String? = nil
    ) async {
        struct LiveTrackingPatch: Encodable {
            var order_id: String
            var restaurant_id: String
            var plate: String
            var latitude: Double
            var longitude: Double
            var distance_meters: Int
            var eta_seconds: Int
            var order_status: String
            var trigger_alarm: Bool
            var at_door: Bool
            var updated_at: String
        }
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let clampedMeters = max(0, meters)
        let isAtDoor = clampedMeters <= 20
        let effectiveMeters = isAtDoor ? 0 : clampedMeters
        let resolvedStatus = status ?? (isAtDoor ? "kapıda" : "yolda")
        let triggerAlarm = effectiveMeters < 500
        let computedEta = etaSeconds ?? Int((Double(effectiveMeters) / 8.33).rounded())
        let payload = LiveTrackingPatch(
            order_id: id,
            restaurant_id: restaurantId,
            plate: plate,
            latitude: latitude,
            longitude: longitude,
            distance_meters: effectiveMeters,
            eta_seconds: max(0, computedEta),
            order_status: resolvedStatus,
            trigger_alarm: triggerAlarm,
            at_door: isAtDoor,
            updated_at: nowISO
        )

        var req = makeSupabaseRequest(url: supabaseTrackingURL, method: "POST")
        req.httpBody = try? JSONEncoder().encode([payload])
        _ = try? await URLSession.shared.data(for: req)

        if isAtDoor, let ordUrl = URL(string: "\(SUPABASE_URL)/rest/v1/orders?id=eq.\(id)") {
            struct OrdDoorPatch: Encodable {
                var at_door: Bool
                var order_status: String
                var updated_at: String
            }
            var oReq = makeSupabaseRequest(url: ordUrl, method: "PATCH")
            oReq.httpBody = try? JSONEncoder().encode(OrdDoorPatch(at_door: true, order_status: "kapıda", updated_at: nowISO))
            _ = try? await URLSession.shared.data(for: oReq)
        }

        patchLocalOrder(id: id) { ord in
            ord.meters = effectiveMeters
            ord.latitude = latitude
            ord.longitude = longitude
            if isAtDoor {
                ord.atDoor = true
                if ord.status != "teslim" && ord.status != "iptal" {
                    ord.status = "kapıda"
                }
            } else if let status {
                ord.status = status
            }
            ord.updatedAt = nowISO
        }
    }

    static func listen(onEvent: @escaping @Sendable (KonumumCloudEvent) -> Void) -> URLSessionWebSocketTask? {
        let task = URLSession.shared.webSocketTask(with: supabaseRealtimeWSURL)
        task.resume()
        let joinMsg: [String: Any] = [
            "topic": "realtime:konumum-kds-realtime",
            "event": "phx_join",
            "payload": [
                "config": [
                    "broadcast": ["self": true],
                    "postgres_changes": [
                        ["event": "*", "schema": "public", "table": "orders"],
                        ["event": "*", "schema": "public", "table": "live_tracking"],
                        ["event": "*", "schema": "public", "table": "restaurant_state"]
                    ]
                ]
            ],
            "ref": "1"
        ]
        if let data = try? JSONSerialization.data(withJSONObject: joinMsg),
           let str = String(data: data, encoding: .utf8) {
            task.send(.string(str)) { _ in }
        }
        receive(task, onEvent: onEvent)
        return task
    }

    private static func receive(_ task: URLSessionWebSocketTask, onEvent: @escaping @Sendable (KonumumCloudEvent) -> Void) {
        task.receive { result in
            switch result {
            case .success(.string(let text)):
                if let event = parse(text) { onEvent(event) }
                receive(task, onEvent: onEvent)
            case .success(.data(let data)):
                if let text = String(data: data, encoding: .utf8), let event = parse(text) { onEvent(event) }
                receive(task, onEvent: onEvent)
            default:
                break
            }
        }
    }

    private static func parse(_ text: String) -> KonumumCloudEvent? {
        guard let data = text.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        // Handle Supabase Realtime Phoenix postgres_changes frame
        if let payload = raw["payload"] as? [String: Any],
           let pgData = payload["data"] as? [String: Any],
           let table = pgData["table"] as? String,
           let record = pgData["record"] as? [String: Any] {
            if table == "orders" || table == "live_tracking" {
                let id = (record["id"] as? String) ?? (record["order_id"] as? String) ?? ""
                guard !id.isEmpty else { return nil }
                if id.hasPrefix("__state_") {
                    guard let rawItems = record["items"] as? String,
                          let itemData = rawItems.data(using: .utf8)
                    else { return nil }
                    let key = String(id.dropFirst("__state_".count))
                    let decoder = JSONDecoder()
                    if key == "menus", let mapped = try? decoder.decode([String: [KonumumWebDish]].self, from: itemData) {
                        return .menus(mapped)
                    }
                    if key == "campaigns", let mapped = try? decoder.decode([KonumumWebCampaign].self, from: itemData) {
                        return .campaigns(mapped)
                    }
                    if key == "profiles",
                       let profMap = try? JSONSerialization.jsonObject(with: itemData) as? [String: [String: Any]] {
                        var patches: [KonumumVenuePatch] = []
                        for (rid, dict) in profMap {
                            patches.append(
                                KonumumVenuePatch(
                                    id: (dict["id"] as? String) ?? rid,
                                    bayiKodu: dict["bayiKodu"] as? String,
                                    brandName: (dict["brandName"] as? String) ?? (dict["branchTitle"] as? String) ?? (dict["officialTitle"] as? String),
                                    branchTitle: (dict["branchTitle"] as? String) ?? (dict["officialTitle"] as? String),
                                    officialTitle: dict["officialTitle"] as? String,
                                    email: dict["email"] as? String,
                                    password: dict["password"] as? String,
                                    phone: dict["phone"] as? String,
                                    taxNumber: dict["taxNumber"] as? String,
                                    address: dict["address"] as? String,
                                    iban: dict["iban"] as? String,
                                    cuisine: dict["cuisine"] as? String,
                                    hours: dict["hours"] as? String,
                                    open: dict["open"] as? Bool,
                                    busy: dict["busy"] as? String,
                                    logoMark: dict["logoMark"] as? String,
                                    logoBg: dict["logoBg"] as? String,
                                    logoFg: dict["logoFg"] as? String,
                                    mapLatitude: (dict["latitude"] as? Double) ?? (dict["mapLatitude"] as? Double),
                                    mapLongitude: (dict["longitude"] as? Double) ?? (dict["mapLongitude"] as? Double)
                                )
                            )
                        }
                        return .venues(patches)
                    }
                    if key.hasPrefix("account:"),
                       let dict = try? JSONSerialization.jsonObject(with: itemData) as? [String: Any],
                       let rid = dict["id"] as? String, !rid.isEmpty {
                        let patch = KonumumVenuePatch(
                            id: rid,
                            bayiKodu: dict["bayiKodu"] as? String,
                            brandName: (dict["brandName"] as? String) ?? (dict["branchTitle"] as? String) ?? (dict["officialTitle"] as? String),
                            branchTitle: (dict["branchTitle"] as? String) ?? (dict["officialTitle"] as? String),
                            officialTitle: dict["officialTitle"] as? String,
                            email: dict["email"] as? String,
                            password: dict["password"] as? String,
                            phone: dict["phone"] as? String,
                            taxNumber: dict["taxNumber"] as? String,
                            address: dict["address"] as? String,
                            iban: dict["iban"] as? String,
                            cuisine: dict["cuisine"] as? String,
                            hours: dict["hours"] as? String,
                            open: dict["open"] as? Bool,
                            busy: dict["busy"] as? String,
                            logoMark: dict["logoMark"] as? String,
                            logoBg: dict["logoBg"] as? String,
                            logoFg: dict["logoFg"] as? String,
                            mapLatitude: (dict["latitude"] as? Double) ?? (dict["mapLatitude"] as? Double),
                            mapLongitude: (dict["longitude"] as? Double) ?? (dict["mapLongitude"] as? Double)
                        )
                        return .venues([patch])
                    }
                    return nil
                }
                guard (record["source"] as? String) != "system_state" else { return nil }
                let order = KonumumWebOrder(
                    id: id,
                    restaurantId: (record["restaurant_id"] as? String) ?? "mcd-kadikoy",
                    driverName: record["driver_name"] as? String,
                    customer: (record["customer_name"] as? String) ?? (record["driver_name"] as? String) ?? "Müşteri",
                    plate: (record["plate"] as? String) ?? "",
                    items: (record["items"] as? String) ?? "",
                    payment: (record["payment_method"] as? String) ?? "Kart",
                    latitude: record["latitude"] as? Double,
                    longitude: record["longitude"] as? Double,
                    meters: record["distance_meters"] as? Int,
                    status: record["order_status"] as? String,
                    total: record["total_amount"] as? Int,
                    source: "supabase-realtime",
                    updatedAt: record["updated_at"] as? String,
                    atDoor: record["at_door"] as? Bool,
                    cancelReason: record["cancel_reason"] as? String
                )
                return .order(order)
            }
        }

        if let type = raw["type"] as? String {
            let decoder = JSONDecoder()
            if type == "snapshot", let state = raw["state"] {
                guard let blob = try? JSONSerialization.data(withJSONObject: state),
                      let snap = decode(blob, linked: true)
                else { return nil }
                return .snapshot(snap)
            }
            if type == "order.upsert" || type == "order.door", let orderObj = raw["order"] {
                guard let blob = try? JSONSerialization.data(withJSONObject: orderObj),
                      let order = try? decoder.decode(KonumumWebOrder.self, from: blob)
                else { return nil }
                return .order(order)
            }
            if type == "menus", let menus = raw["menus"] {
                guard let blob = try? JSONSerialization.data(withJSONObject: menus),
                      let mapped = try? decoder.decode([String: [KonumumWebDish]].self, from: blob)
                else { return nil }
                return .menus(mapped)
            }
            if type == "campaigns", let campaigns = raw["campaigns"] {
                guard let blob = try? JSONSerialization.data(withJSONObject: campaigns),
                      let mapped = try? decoder.decode([KonumumWebCampaign].self, from: blob)
                else { return nil }
                return .campaigns(mapped)
            }
        }
        return nil
    }

    private static func fetchSupabaseSnapshot() async -> KonumumWebSnapshot? {
        guard let ordersURL = URL(string: "\(SUPABASE_URL)/rest/v1/orders?select=*&order=created_at.desc&limit=100"),
              let trackURL = URL(string: "\(SUPABASE_URL)/rest/v1/live_tracking?select=*"),
              let stateURL = URL(string: "\(SUPABASE_URL)/rest/v1/restaurant_state?select=*")
        else { return nil }

        let reqOrders = makeSupabaseRequest(url: ordersURL, method: "GET", prefer: nil)
        let reqTrack = makeSupabaseRequest(url: trackURL, method: "GET", prefer: nil)
        let reqState = makeSupabaseRequest(url: stateURL, method: "GET", prefer: nil)

        guard let (ordData, ordResp) = try? await URLSession.shared.data(for: reqOrders),
              let httpOrd = ordResp as? HTTPURLResponse,
              httpOrd.statusCode == 200,
              let ordRows = try? JSONSerialization.jsonObject(with: ordData) as? [[String: Any]]
        else { return nil }

        var trackMap: [String: [String: Any]] = [:]
        if let (trData, trResp) = try? await URLSession.shared.data(for: reqTrack),
           let httpTr = trResp as? HTTPURLResponse,
           httpTr.statusCode == 200,
           let trRows = try? JSONSerialization.jsonObject(with: trData) as? [[String: Any]] {
            for r in trRows {
                if let oid = r["order_id"] as? String { trackMap[oid] = r }
            }
        }

        let mappedOrders: [KonumumWebOrder] = ordRows.compactMap { row in
            guard let id = row["id"] as? String,
                  !id.hasPrefix("__state_"),
                  (row["source"] as? String) != "system_state",
                  (row["restaurant_id"] as? String) != "__system__"
            else { return nil }
            let tr = trackMap[id]
            return KonumumWebOrder(
                id: id,
                restaurantId: (row["restaurant_id"] as? String) ?? "mcd-kadikoy",
                driverName: row["driver_name"] as? String,
                customer: (row["customer_name"] as? String) ?? (row["driver_name"] as? String) ?? "Müşteri",
                plate: (row["plate"] as? String) ?? "",
                items: (row["items"] as? String) ?? "",
                payment: (row["payment_method"] as? String) ?? "Kart",
                latitude: tr?["latitude"] as? Double,
                longitude: tr?["longitude"] as? Double,
                meters: tr?["distance_meters"] as? Int,
                status: (row["order_status"] as? String) ?? (tr?["order_status"] as? String) ?? "iletildi",
                total: row["total_amount"] as? Int,
                source: "supabase",
                updatedAt: (tr?["updated_at"] as? String) ?? (row["updated_at"] as? String),
                lane: row["lane"] as? String,
                stall: row["stall"] as? Int,
                speaker: row["speaker"] as? Int,
                speakerMatched: row["speaker_matched"] as? Bool,
                atDoor: (tr?["at_door"] as? Bool) ?? (row["at_door"] as? Bool),
                cancelReason: row["cancel_reason"] as? String
            )
        }

        var fallback = readFile()
        fallback.orders = mappedOrders
        fallback.linked = true

        let decoder = JSONDecoder()

        func parseVenueDict(_ rid: String, _ dict: [String: Any]) -> KonumumVenuePatch {
            let menuArr = (dict["menu"] as? [[String: Any]]).flatMap { arr -> [KonumumWebDish]? in
                guard let d = try? JSONSerialization.data(withJSONObject: arr) else { return nil }
                return try? decoder.decode([KonumumWebDish].self, from: d)
            }
            return KonumumVenuePatch(
                id: (dict["id"] as? String) ?? rid,
                bayiKodu: dict["bayiKodu"] as? String,
                brandName: (dict["brandName"] as? String) ?? (dict["branchTitle"] as? String) ?? (dict["officialTitle"] as? String),
                branchTitle: (dict["branchTitle"] as? String) ?? (dict["officialTitle"] as? String),
                officialTitle: dict["officialTitle"] as? String,
                email: dict["email"] as? String,
                password: dict["password"] as? String,
                phone: dict["phone"] as? String,
                taxNumber: dict["taxNumber"] as? String,
                address: dict["address"] as? String,
                iban: dict["iban"] as? String,
                cuisine: dict["cuisine"] as? String,
                hours: dict["hours"] as? String,
                open: dict["open"] as? Bool,
                busy: dict["busy"] as? String,
                logoMark: dict["logoMark"] as? String,
                logoBg: dict["logoBg"] as? String,
                logoFg: dict["logoFg"] as? String,
                mapLatitude: (dict["latitude"] as? Double) ?? (dict["mapLatitude"] as? Double),
                mapLongitude: (dict["longitude"] as? Double) ?? (dict["mapLongitude"] as? Double),
                menu: menuArr
            )
        }

        func mergeVenuePatch(_ patch: KonumumVenuePatch) {
            if let menu = patch.menu, !menu.isEmpty, (fallback.menus[patch.id]?.isEmpty ?? true) {
                fallback.menus[patch.id] = menu
            }
            if let idx = fallback.venues.firstIndex(where: { $0.id == patch.id }) {
                if let v = patch.bayiKodu, !v.isEmpty { fallback.venues[idx].bayiKodu = v }
                if let v = patch.brandName, !v.isEmpty { fallback.venues[idx].brandName = v }
                if let v = patch.branchTitle, !v.isEmpty { fallback.venues[idx].branchTitle = v }
                if let v = patch.officialTitle, !v.isEmpty { fallback.venues[idx].officialTitle = v }
                if let v = patch.email, !v.isEmpty { fallback.venues[idx].email = v }
                if let v = patch.password, !v.isEmpty { fallback.venues[idx].password = v }
                if let v = patch.phone, !v.isEmpty { fallback.venues[idx].phone = v }
                if let v = patch.taxNumber, !v.isEmpty { fallback.venues[idx].taxNumber = v }
                if let v = patch.address, !v.isEmpty { fallback.venues[idx].address = v }
                if let v = patch.iban, !v.isEmpty { fallback.venues[idx].iban = v }
                if let v = patch.cuisine, !v.isEmpty { fallback.venues[idx].cuisine = v }
                if let v = patch.hours, !v.isEmpty { fallback.venues[idx].hours = v }
                if let v = patch.open { fallback.venues[idx].open = v }
                if let v = patch.busy, !v.isEmpty { fallback.venues[idx].busy = v }
                if let v = patch.logoMark, !v.isEmpty { fallback.venues[idx].logoMark = v }
                if let v = patch.logoBg, !v.isEmpty { fallback.venues[idx].logoBg = v }
                if let v = patch.logoFg, !v.isEmpty { fallback.venues[idx].logoFg = v }
                if let v = patch.mapLatitude { fallback.venues[idx].mapLatitude = v }
                if let v = patch.mapLongitude { fallback.venues[idx].mapLongitude = v }
            } else {
                fallback.venues.append(patch)
            }
        }

        // Parse system state rows mirrored inside public.orders (__state_...)
        for row in ordRows {
            guard let id = row["id"] as? String, id.hasPrefix("__state_"),
                  let rawItems = row["items"] as? String,
                  let data = rawItems.data(using: .utf8)
            else { continue }
            let key = String(id.dropFirst("__state_".count))
            if key == "menus", let decoded = try? decoder.decode([String: [KonumumWebDish]].self, from: data) {
                for (k, v) in decoded { fallback.menus[k] = v }
            } else if key == "menuExtras", let decoded = try? decoder.decode([String: [KonumumWebDish]].self, from: data) {
                for (k, v) in decoded { fallback.extras[k] = v }
            } else if key == "campaigns", let decoded = try? decoder.decode([KonumumWebCampaign].self, from: data) {
                fallback.campaigns = decoded
            } else if key == "profiles",
                      let profMap = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
                for (rid, dict) in profMap {
                    mergeVenuePatch(parseVenueDict(rid, dict))
                }
            } else if key.hasPrefix("account:"),
                      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rid = dict["id"] as? String, !rid.isEmpty {
                mergeVenuePatch(parseVenueDict(rid, dict))
            }
        }

        if let (stData, stResp) = try? await URLSession.shared.data(for: reqState),
           let httpSt = stResp as? HTTPURLResponse,
           httpSt.statusCode == 200,
           let stRows = try? JSONSerialization.jsonObject(with: stData) as? [[String: Any]] {
            for r in stRows {
                guard let key = r["key"] as? String, let payload = r["payload"] else { continue }
                if key == "menus",
                   let blob = try? JSONSerialization.data(withJSONObject: payload),
                   let decoded = try? decoder.decode([String: [KonumumWebDish]].self, from: blob) {
                    for (k, v) in decoded { fallback.menus[k] = v }
                } else if key == "menuExtras",
                          let blob = try? JSONSerialization.data(withJSONObject: payload),
                          let decoded = try? decoder.decode([String: [KonumumWebDish]].self, from: blob) {
                    for (k, v) in decoded { fallback.extras[k] = v }
                } else if key == "campaigns",
                          let blob = try? JSONSerialization.data(withJSONObject: payload),
                          let decoded = try? decoder.decode([KonumumWebCampaign].self, from: blob) {
                    fallback.campaigns = decoded
                } else if key == "profiles",
                          let profMap = payload as? [String: [String: Any]] {
                    for (rid, dict) in profMap {
                        mergeVenuePatch(parseVenueDict(rid, dict))
                    }
                } else if key.hasPrefix("account:"),
                          let dict = payload as? [String: Any],
                          let rid = dict["id"] as? String, !rid.isEmpty {
                    mergeVenuePatch(parseVenueDict(rid, dict))
                }
            }
        }
        return fallback
    }

    private static func upsertLocalOrder(_ order: KonumumWebOrder) {
        guard let data = try? Data(contentsOf: fileFallback),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }
        var orders = (json["orders"] as? [[String: Any]]) ?? []
        if let encoded = try? JSONEncoder().encode(order),
           let obj = try? JSONSerialization.jsonObject(with: encoded) as? [String: Any] {
            orders.removeAll { ($0["id"] as? String) == order.id }
            orders.insert(obj, at: 0)
            json["orders"] = orders
            if let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
                try? out.write(to: fileFallback, options: .atomic)
            }
        }
    }

    private static func patchLocalOrder(id: String, mutate: (inout KonumumWebOrder) -> Void) {
        guard let data = try? Data(contentsOf: fileFallback),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawOrders = json["orders"] as? [[String: Any]]
        else { return }
        var updatedOrders: [[String: Any]] = []
        for item in rawOrders {
            if (item["id"] as? String) == id,
               let itemData = try? JSONSerialization.data(withJSONObject: item),
               var decoded = try? JSONDecoder().decode(KonumumWebOrder.self, from: itemData) {
                mutate(&decoded)
                if let enc = try? JSONEncoder().encode(decoded),
                   let obj = try? JSONSerialization.jsonObject(with: enc) as? [String: Any] {
                    updatedOrders.append(obj)
                    continue
                }
            }
            updatedOrders.append(item)
        }
        json["orders"] = updatedOrders
        if let out = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted]) {
            try? out.write(to: fileFallback, options: .atomic)
        }
    }

    private static func readFile() -> KonumumWebSnapshot {
        guard let data = try? Data(contentsOf: fileFallback) else {
            return KonumumWebSnapshot(menus: [:], extras: [:], orders: [], campaigns: [], venues: [], linked: true)
        }
        var snap = decode(data, linked: true) ?? KonumumWebSnapshot(menus: [:], extras: [:], orders: [], campaigns: [], venues: [], linked: true)
        if let seedData = try? Data(contentsOf: seedFallback),
           let seedSnap = decode(seedData, linked: true),
           !seedSnap.venues.isEmpty {
            for v in seedSnap.venues where !snap.venues.contains(where: { $0.id == v.id }) {
                snap.venues.append(v)
            }
        }
        return snap
    }

    private static func decode(_ data: Data, linked: Bool) -> KonumumWebSnapshot? {
        struct ProfilePatch: Codable {
            var cuisine: String?
            var hours: String?
            var open: Bool?
            var busy: String?
            var logoMark: String?
            var logoBg: String?
            var logoFg: String?
        }
        struct Blob: Codable {
            var menus: [String: [KonumumWebDish]]?
            var menuExtras: [String: [KonumumWebDish]]?
            var orders: [KonumumWebOrder]?
            var campaigns: [KonumumWebCampaign]?
            var restaurants: [KonumumVenuePatch]?
            var profiles: [String: ProfilePatch]?
        }
        guard let blob = try? JSONDecoder().decode(Blob.self, from: data) else { return nil }
        var venueList = blob.restaurants ?? []
        if let profiles = blob.profiles {
            for (rid, prof) in profiles {
                if let idx = venueList.firstIndex(where: { $0.id == rid }) {
                    if let c = prof.cuisine { venueList[idx].cuisine = c }
                    if let h = prof.hours { venueList[idx].hours = h }
                    if let o = prof.open { venueList[idx].open = o }
                    if let b = prof.busy { venueList[idx].busy = b }
                    if let lm = prof.logoMark { venueList[idx].logoMark = lm }
                    if let lb = prof.logoBg { venueList[idx].logoBg = lb }
                    if let lf = prof.logoFg { venueList[idx].logoFg = lf }
                } else {
                    venueList.append(
                        KonumumVenuePatch(
                            id: rid,
                            cuisine: prof.cuisine,
                            hours: prof.hours,
                            open: prof.open,
                            busy: prof.busy,
                            logoMark: prof.logoMark,
                            logoBg: prof.logoBg,
                            logoFg: prof.logoFg
                        )
                    )
                }
            }
        }
        return KonumumWebSnapshot(
            menus: blob.menus ?? [:],
            extras: blob.menuExtras ?? [:],
            orders: blob.orders ?? [],
            campaigns: blob.campaigns ?? [],
            venues: venueList,
            linked: linked
        )
    }
}
