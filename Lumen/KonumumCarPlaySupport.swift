import CarPlay
import SwiftUI
import UIKit

@MainActor
final class KonumumRuntime {
    static let shared = KonumumRuntime()
    let directory = KonumumDirectory()
}

final class KonumumAppDelegate: NSObject, UIApplicationDelegate {
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

    var body: some View {
        if let route = directory.liveRoute {
            SurucuNavigasyonCarPlayView(route: route, hostedOnCarPlay: true)
        } else {
            ZStack {
                KonumumTheme.graphite.ignoresSafeArea()
                VStack(spacing: 12) {
                    Text("konumumyemek.com")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(KonumumTheme.neon)
                    Text("Sipariş başladığında rota burada açılır.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .padding(24)
            }
        }
    }
}
