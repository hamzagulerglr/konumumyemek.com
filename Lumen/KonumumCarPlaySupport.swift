import AVFoundation
import CarPlay
import SwiftUI
import UIKit
import UserNotifications

@MainActor
final class KonumumRuntime {
    static let shared = KonumumRuntime()
    let directory = KonumumDirectory()
}

@MainActor
final class KonumumCarPlayNotifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = KonumumCarPlayNotifier()
    static let categoryId = "KONUMUM_ORDER_DRIVE_ACTIONS"
    static let actionAtDoorId = "KONUMUM_ACTION_AT_DOOR"
    static let actionCollectedId = "KONUMUM_ACTION_COLLECTED"

    private let synthesizer = AVSpeechSynthesizer()
    private var configured = false

    func configure() {
        guard !configured else { return }
        configured = true

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let atDoorAction = UNNotificationAction(
            identifier: Self.actionAtDoorId,
            title: "🚗 Kapıdayım",
            options: [.authenticationRequired]
        )
        let collectedAction = UNNotificationAction(
            identifier: Self.actionCollectedId,
            title: "✅ Yemeği Teslim Aldım",
            options: [.authenticationRequired]
        )

        let category = UNNotificationCategory(
            identifier: Self.categoryId,
            actions: [atDoorAction, collectedAction],
            intentIdentifiers: [],
            options: [.allowInCarPlay, .customDismissAction]
        )
        center.setNotificationCategories([category])

        center.requestAuthorization(options: [.alert, .sound, .badge, .carPlay]) { _, _ in }
    }

    func notifyDriver(
        title: String,
        body: String,
        orderId: String?,
        plate: String,
        speakText: String? = nil
    ) {
        configure()

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.categoryId
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        content.userInfo = [
            "orderId": orderId ?? "",
            "plate": plate
        ]

        let request = UNNotificationRequest(
            identifier: "konumum.drive.\(UUID().uuidString.prefix(8))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)

        if let voice = speakText, !voice.isEmpty {
            speakInCar(voice)
        }
    }

    private func speakInCar(_ text: String) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
        } catch {
            // Audio session fallback
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: KonumumLanguage.isEN ? "en-US" : "tr-TR")
        utterance.rate = 0.50
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let orderId = (userInfo["orderId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let plate = (userInfo["plate"] as? String) ?? "34 KNM 55"
        let actionId = response.actionIdentifier

        Task { @MainActor in
            let directory = KonumumRuntime.shared.directory
            let resolvedId = orderId ?? directory.liveDeliveryId ?? directory.deliveries.last(where: { $0.isOpen })?.id

            if actionId == Self.actionAtDoorId {
                if let id = resolvedId {
                    directory.checkInAtDoor(id: id)
                }
            } else if actionId == Self.actionCollectedId {
                directory.confirmCustomerCollected(deliveryId: resolvedId, plate: plate)
            }
            completionHandler()
        }
    }
}

final class KonumumAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            KonumumCarPlayNotifier.shared.configure()
        }
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if connectingSceneSession.role.rawValue == "CPTemplateApplicationSceneSessionRoleApplication" {
            let config = UISceneConfiguration(name: "CarPlay", sessionRole: connectingSceneSession.role)
            config.delegateClass = KonumumCarPlaySceneDelegate.self
            return config
        }
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}

final class KonumumCarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    var interfaceController: CPInterfaceController?
    private var mapTemplate: CPMapTemplate?
    private var host: UIHostingController<AnyView>?

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        self.interfaceController = interfaceController
        Task { @MainActor in
            KonumumRuntime.shared.directory.carPlayConnected = true
            self.mount(in: templateApplicationScene, interfaceController: interfaceController)
        }
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        Task { @MainActor in
            KonumumRuntime.shared.directory.carPlayConnected = false
        }
        self.interfaceController = nil
        mapTemplate = nil
        host = nil
    }

    @MainActor
    private func mount(in scene: CPTemplateApplicationScene, interfaceController: CPInterfaceController) {
        let directory = KonumumRuntime.shared.directory
        let map = CPMapTemplate()
        map.mapButtons = []
        map.automaticallyHidesNavigationBar = false
        mapTemplate = map
        interfaceController.setRootTemplate(map, animated: false)

        let root = AnyView(
            CarPlayDashboard()
                .environmentObject(directory)
        )
        let hosting = UIHostingController(rootView: root)
        hosting.view.backgroundColor = UIColor(KonumumTheme.graphite)
        host = hosting
        scene.carWindow.rootViewController = hosting
    }
}

private struct CarPlayDashboard: View {
    @EnvironmentObject private var directory: KonumumDirectory

    private var activeOrder: KonumumDelivery? {
        if let id = directory.liveDeliveryId,
           let match = directory.deliveries.first(where: { $0.id == id }) {
            return match
        }
        return directory.deliveries.last(where: { $0.isOpen })
    }

    var body: some View {
        ZStack {
            KonumumTheme.graphite.ignoresSafeArea()

            if let order = activeOrder {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text("CANLI SİPARİŞ DURUMU")
                                .font(.system(size: 11, weight: .heavy))
                                .tracking(1.4)
                                .foregroundStyle(KonumumTheme.ink)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(KonumumTheme.neon, in: Capsule())

                            Text(order.plate)
                                .font(KonumumFont.plate(14))
                                .foregroundStyle(.white)
                        }

                        Text(statusHeadline(for: order))
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(statusColor(for: order))
                            .lineLimit(2)

                        Text(directory.kitchenStatusText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.85))
                            .lineLimit(2)

                        Text("Mesafe: \(directory.liveMeters) m · Tahmini: \(directory.liveSeconds) sn")
                            .font(KonumumFont.plate(14))
                            .foregroundStyle(KonumumTheme.neon)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 10) {
                        Button {
                            directory.checkInAtDoor(id: order.id)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "car.fill")
                                Text("KAPIDAYIM")
                            }
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(KonumumTheme.ink)
                            .frame(width: 210, height: 54)
                            .background(Color(red: 1.0, green: 0.82, blue: 0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            directory.confirmCustomerCollected(deliveryId: order.id, plate: order.plate)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.seal.fill")
                                Text("TESLİM ALDIM")
                            }
                            .font(.system(size: 16, weight: .heavy))
                            .foregroundStyle(KonumumTheme.ink)
                            .frame(width: 210, height: 54)
                            .background(Color(red: 0.22, green: 0.95, blue: 0.48), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            } else if let route = directory.liveRoute {
                SurucuNavigasyonCarPlayView(route: route, hostedOnCarPlay: true)
            } else {
                VStack(spacing: 12) {
                    Text("konumumyemek.com")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(KonumumTheme.neon)
                    Text("Sipariş başladığında canlı mutfak durumu ve Kapıdayım / Teslim Aldım butonları burada açılır.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
        }
    }

    private func statusHeadline(for order: KonumumDelivery) -> String {
        if order.atDoor || directory.liveMeters == 0 {
            return "🚗 KAPIDA · Araç Camından Teslim"
        }
        switch order.kitchenStatus {
        case "kabul":
            return "👨‍🍳 SİPARİŞ MUTFAĞA ALINDI · Hazırlanıyor"
        case "hazir":
            return "🍔 SİPARİŞİNİZ HAZIR · Teslim Noktasına Yanaşın"
        case "yolda":
            return "🛣️ TESLİM NOKTASINA YAKLAŞIYORSUNUZ"
        case "iptal":
            return "⚠️ SİPARİŞ İPTAL EDİLDİ"
        default:
            return "📡 SİPARİŞ RESTORANA İLETİLDİ"
        }
    }

    private func statusColor(for order: KonumumDelivery) -> Color {
        if order.atDoor || directory.liveMeters == 0 {
            return Color(red: 0.22, green: 0.95, blue: 0.48)
        }
        switch order.kitchenStatus {
        case "hazir":
            return Color(red: 0.22, green: 0.95, blue: 0.48)
        case "kabul":
            return KonumumTheme.neon
        case "iptal":
            return KonumumTheme.danger
        default:
            return .white
        }
    }
}
