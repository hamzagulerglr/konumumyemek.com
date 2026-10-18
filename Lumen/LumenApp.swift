import SwiftUI

@main
struct LumenApp: App {
    @UIApplicationDelegateAdaptor(KonumumAppDelegate.self) private var appDelegate
    @StateObject private var directory = KonumumRuntime.shared.directory
    @AppStorage(KonumumMemberStore.signedIn) private var isSignedIn = false
    @AppStorage(KonumumMemberStore.name) private var memberName = ""
    @AppStorage(KonumumMemberStore.email) private var memberEmail = ""
    @AppStorage(KonumumMemberStore.phone) private var memberPhone = ""
    @AppStorage(KonumumMemberStore.password) private var memberPassword = ""
    @AppStorage(KonumumMemberStore.plate) private var memberPlate = ""

    var body: some Scene {
        WindowGroup {
            Group {
                if isSignedIn {
                    NavigationStack {
                        OrderPaymentView(profile: liveProfile)
                    }
                } else {
                    PlateRegistrationView()
                }
            }
            .environmentObject(directory)
            .background(KonumumTheme.graphite.ignoresSafeArea())
            .preferredColorScheme(.dark)
            .onAppear {
                directory.startWebBridge()
                hydrateIfNeeded()
            }
            .onChange(of: isSignedIn) { _, signed in
                if signed { hydrateIfNeeded() }
            }
        }
    }

    private var liveProfile: KonumumProfile {
        KonumumProfile(
            name: memberName,
            email: memberEmail,
            phone: memberPhone,
            password: memberPassword,
            plates: [memberPlate].filter { !$0.isEmpty }
        )
    }

    private func hydrateIfNeeded() {
        guard isSignedIn else { return }
        _ = KonumumFont.family
        if !memberEmail.isEmpty, !memberPassword.isEmpty {
            _ = directory.signInCustomer(identifier: memberEmail, password: memberPassword)
        }
        if directory.customerSession == nil, !memberPlate.isEmpty {
            _ = directory.registerMember(
                name: memberName,
                email: memberEmail,
                phone: memberPhone,
                plate: memberPlate,
                password: memberPassword
            )
        }
    }
}
