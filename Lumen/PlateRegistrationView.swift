import CoreText
import SwiftUI
import UIKit

enum KonumumTheme {
    static let graphite = Color(red: 11 / 255, green: 15 / 255, blue: 25 / 255)
    static let neon = Color(red: 0.227, green: 0.945, blue: 0.843)
    static let neonHot = Color(red: 0.82, green: 1.0, blue: 0.96)
    static let ink = Color(red: 11 / 255, green: 15 / 255, blue: 25 / 255)
    static let danger = Color(red: 1.0, green: 0.48, blue: 0.45)
}

private struct PopToHomeKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var popToHome: () -> Void {
        get { self[PopToHomeKey.self] }
        set { self[PopToHomeKey.self] = newValue }
    }
}

enum KonumumFont {
    static let family: String = {
        guard let url = Bundle.main.url(forResource: "JetBrainsMono-Medium", withExtension: "ttf") else {
            return "JetBrains Mono"
        }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
            let descriptor = descriptors.first,
            let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
        else {
            return "JetBrains Mono"
        }
        return name
    }()

    static func plate(_ size: CGFloat) -> Font {
        .custom(family, size: size)
    }
}

enum KonumumLanguage: String, CaseIterable {
    case tr = "tr"
    case en = "en"

    static var current: KonumumLanguage {
        let raw = UserDefaults.standard.string(forKey: KonumumMemberStore.language) ?? "tr"
        return KonumumLanguage(rawValue: raw) ?? .tr
    }

    static var isEN: Bool { current == .en }
}

func L(_ tr: String, _ en: String) -> String {
    KonumumLanguage.isEN ? en : tr
}

struct KonumumLangToggle: View {
    @AppStorage(KonumumMemberStore.language) private var lang = "tr"

    var body: some View {
        HStack(spacing: 0) {
            langChip("TR", code: "tr")
            langChip("EN", code: "en")
        }
        .padding(3)
        .background(Color.white.opacity(0.08), in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(KonumumTheme.neon.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dil seçimi / Language")
    }

    private func langChip(_ title: String, code: String) -> some View {
        let selected = lang == code
        return Button {
            withAnimation(.snappy(duration: 0.18)) {
                lang = code
            }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(0.6)
                .foregroundStyle(selected ? KonumumTheme.ink : Color.white.opacity(0.65))
                .frame(width: 30, height: 24)
                .background {
                    if selected {
                        Capsule().fill(KonumumTheme.neon)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

enum KonumumMemberStore {
    static let signedIn = "konumum.member.sessionOn"
    static let registered = "konumum.member.registered"
    static let landOnProfile = "konumum.member.landOnProfile"
    static let name = "konumum.member.name"
    static let email = "konumum.member.email"
    static let phone = "konumum.member.phone"
    static let password = "konumum.member.password"
    static let plate = "konumum.member.plate"
    static let kvkk = "konumum.member.kvkk"
    static let acikRiza = "konumum.member.acikRiza"
    static let language = "konumum.member.language"
    static let savedCards = "konumum.member.savedCards.v1"
}

struct KonumumProfile: Hashable {
    var name: String
    var email: String = ""
    var phone: String = ""
    var password: String = ""
    var plates: [String]
}

struct PlateRegistrationView: View {
    @EnvironmentObject private var directory: KonumumDirectory
    @AppStorage(KonumumMemberStore.language) private var lang = "tr"
    @AppStorage(KonumumMemberStore.signedIn) private var isSignedIn = false
    @AppStorage(KonumumMemberStore.registered) private var isRegistered = false
    @AppStorage(KonumumMemberStore.landOnProfile) private var landOnProfile = false
    @AppStorage(KonumumMemberStore.name) private var storedName = ""
    @AppStorage(KonumumMemberStore.email) private var storedEmail = ""
    @AppStorage(KonumumMemberStore.phone) private var storedPhone = ""
    @AppStorage(KonumumMemberStore.password) private var storedPassword = ""
    @AppStorage(KonumumMemberStore.plate) private var storedPlate = ""
    @AppStorage(KonumumMemberStore.kvkk) private var storedKvkk = false
    @AppStorage(KonumumMemberStore.acikRiza) private var storedAcikRiza = false

    @State private var showSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var fullName = ""
    @State private var phone = ""
    @State private var passwordAgain = ""
    @State private var plate = ""
    @State private var attempted = false
    @State private var loginFailed = false
    @State private var kvkkOk = false
    @State private var kvkkAydinlatma = false
    @State private var acikRiza = false
    @State private var showWebPanel = false
    @State private var showLegalSheet = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case email, password, name, phone, passwordAgain, plate
    }

    private var pickupGreen: Color {
        Color(red: 0.22, green: 0.95, blue: 0.48)
    }

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var emailLooksValid: Bool {
        trimmedEmail.contains("@") && trimmedEmail.contains(".")
    }

    private var nameIsValid: Bool {
        let parts = fullName.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ").filter { !$0.isEmpty }
        return parts.count >= 2 && parts.allSatisfy { $0.count >= 2 }
    }

    private var phoneIsValid: Bool {
        phone.filter(\.isNumber).count >= 10
    }

    private var passwordIsValid: Bool {
        password.count >= 6
    }

    private var passwordMatchOk: Bool {
        passwordIsValid && password == passwordAgain
    }

    private var plateIsValid: Bool {
        plate.range(
            of: #"^(0[1-9]|[1-7][0-9]|8[01]) [A-Z]{1,3} [0-9]{2,4}$"#,
            options: .regularExpression
        ) != nil
    }

    private var signUpConsentsOk: Bool { kvkkAydinlatma && acikRiza }

    private var signUpComplete: Bool {
        nameIsValid && emailLooksValid && phoneIsValid && passwordMatchOk && plateIsValid && signUpConsentsOk
    }

    var body: some View {
        welcomeBody
    }

    private var welcomeBody: some View {
        ZStack {
            KonumumTheme.graphite.ignoresSafeArea()

            RadialGradient(
                colors: [KonumumTheme.neon.opacity(0.22), KonumumTheme.neon.opacity(0.04), .clear],
                center: UnitPoint(x: 0.5, y: 0.08),
                startRadius: 8,
                endRadius: 280
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Spacer()
                    KonumumLangToggle()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                if showSignUp {
                    signUpForm
                } else {
                    loginCluster
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showWebPanel) {
            WebPanelView()
                .environmentObject(directory)
                .environment(\.popToHome, goHome)
        }
        .sheet(isPresented: $showLegalSheet) {
            legalSheetView
        }
        .onAppear { _ = KonumumFont.family }
    }

    private var loginCluster: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            VStack(spacing: 18) {
                brandHeader
                Text(L("E-posta adresinizle giriş yapın", "Sign in with your email address"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                loginField(
                    title: L("E-posta Adresi", "Email Address"),
                    prompt: "ornek@konumumyemek.com",
                    text: $email,
                    field: .email,
                    invalid: attempted && !emailLooksValid
                )
                .onSubmit { focus = .password }

                secretBox(
                    title: L("Şifre", "Password"),
                    prompt: L("Şifreniz", "Your password"),
                    text: $password,
                    field: .password,
                    invalid: attempted && password.isEmpty,
                    submit: .go,
                    onSubmit: signIn
                )

                kvkkConsent

                if attempted && !kvkkOk {
                    Text(L("Devam için KVKK açık rızası gerekli.", "Privacy & data consent is required to continue."))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KonumumTheme.danger)
                        .multilineTextAlignment(.center)
                } else if attempted && (!emailLooksValid || password.isEmpty) {
                    Text(L("Lütfen e-posta ve şifrenizi girin.", "Please enter your email and password."))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KonumumTheme.danger)
                        .multilineTextAlignment(.center)
                } else if loginFailed {
                    Text(L("E-posta veya şifre hatalı. Üye değilseniz Üye Ol’a dokunun.", "Invalid email or password. Tap Sign Up if you don't have an account."))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KonumumTheme.danger)
                        .multilineTextAlignment(.center)
                }

                HStack(spacing: 10) {
                    Button(action: signIn) {
                        Text(L("Giriş", "Sign In"))
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(KonumumTheme.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(pickupGreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: pickupGreen.opacity(0.85), radius: 12)
                    }
                    .buttonStyle(KonumumPressStyle())

                    Button(action: openSignUp) {
                        Text(L("Üye Ol", "Sign Up"))
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(KonumumTheme.neon)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(KonumumTheme.neon, lineWidth: 1.6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(KonumumTheme.neon.opacity(0.08))
                                    )
                            )
                            .shadow(color: KonumumTheme.neon.opacity(0.35), radius: 10)
                    }
                    .buttonStyle(KonumumPressStyle())
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 24)
        }
    }

    private var signUpForm: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Button {
                        attempted = false
                        showSignUp = false
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .bold))
                            Text(L("Giriş", "Sign In"))
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KonumumTheme.neon)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }

                brandHeader
                Text(L("Tersine Takip Dünyasına Kayıt Olun", "Register for Car Pickup & Live Approach"))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                loginField(
                    title: L("Adınız Soyadınız", "Full Name"),
                    prompt: L("Adınız Soyadınız", "First & Last Name"),
                    text: $fullName,
                    field: .name,
                    invalid: attempted && !nameIsValid,
                    keyboard: .default,
                    autocap: .words
                )
                .onSubmit { focus = .email }

                loginField(
                    title: L("E-posta Adresiniz", "Email Address"),
                    prompt: "ornek@konumumyemek.com",
                    text: $email,
                    field: .email,
                    invalid: attempted && !emailLooksValid
                )
                .onSubmit { focus = .phone }

                loginField(
                    title: L("Telefon Numaranız", "Phone Number"),
                    prompt: "0555 184 0055",
                    text: phoneBinding,
                    field: .phone,
                    invalid: attempted && !phoneIsValid,
                    keyboard: .phonePad,
                    autocap: .never
                )

                secretBox(
                    title: L("Şifre Oluşturun", "Create Password"),
                    prompt: L("Güvenli şifre", "At least 6 characters"),
                    text: $password,
                    field: .password,
                    invalid: attempted && !passwordIsValid,
                    submit: .next,
                    onSubmit: { focus = .passwordAgain }
                )

                secretBox(
                    title: L("Şifre Tekrar", "Confirm Password"),
                    prompt: L("Şifreyi tekrar yazın", "Re-enter password"),
                    text: $passwordAgain,
                    field: .passwordAgain,
                    invalid: attempted && !passwordMatchOk,
                    submit: .next,
                    onSubmit: { focus = .plate }
                )

                VStack(alignment: .leading, spacing: 6) {
                    Text(L("SABİT ARAÇ PLAKANIZ", "VEHICLE LICENSE PLATE"))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(Color.white.opacity(0.62))
                    TextField("", text: plateBinding, prompt: Text("34 KNM 55").foregroundStyle(Color.white.opacity(0.32)))
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.center)
                        .font(KonumumFont.plate(22))
                        .tracking(plate.isEmpty ? 0 : 4)
                        .foregroundStyle(.white)
                        .tint(KonumumTheme.neon)
                        .focused($focus, equals: .plate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.done)
                        .onSubmit(submitSignUp)
                        .padding(.horizontal, 18)
                        .frame(height: 76)
                        .background(well(active: focus == .plate, invalid: attempted && !plateIsValid))
                }

                signUpConsentTicks

                if attempted && !signUpConsentsOk {
                    Text(L("Üyelik için KVKK aydınlatma ve açık rıza onayları gerekli.", "Please accept both privacy and explicit consent checkboxes."))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KonumumTheme.danger)
                        .multilineTextAlignment(.center)
                } else if attempted && !signUpComplete {
                    Text(L("Lütfen tüm üyelik bilgilerini eksiksiz doldurun!", "Please fill in all registration fields accurately!"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KonumumTheme.danger)
                        .multilineTextAlignment(.center)
                }

                Button(action: submitSignUp) {
                    Text(L("KAYIT OL VE BAŞLAT", "SIGN UP & START"))
                        .font(.system(size: 18, weight: .heavy))
                        .foregroundStyle(KonumumTheme.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 58)
                        .background(pickupGreen, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: pickupGreen.opacity(0.9), radius: 14)
                }
                .buttonStyle(KonumumPressStyle())
                .opacity(signUpConsentsOk ? 1 : 0.55)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var brandHeader: some View {
        VStack(spacing: 12) {
            KonumumBrandMark(size: 84)
            Text("konumumyemek.com")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-0.4)
                .foregroundStyle(
                    LinearGradient(
                        colors: [KonumumTheme.neonHot, KonumumTheme.neon],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: KonumumTheme.neon.opacity(0.95), radius: 8)
                .shadow(color: KonumumTheme.neon.opacity(0.45), radius: 22)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func loginField(
        title: String,
        prompt: String,
        text: Binding<String>,
        field: Field,
        invalid: Bool,
        keyboard: UIKeyboardType = .emailAddress,
        autocap: TextInputAutocapitalization = .never
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.white.opacity(0.62))
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Color.white.opacity(0.32)))
                .textFieldStyle(.plain)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .tint(KonumumTheme.neon)
                .focused($focus, equals: field)
                .keyboardType(keyboard)
                .textInputAutocapitalization(autocap)
                .autocorrectionDisabled(field == .email || field == .phone)
                .submitLabel(.next)
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(well(active: focus == field, invalid: invalid))
        }
    }

    private func secretBox(
        title: String,
        prompt: String,
        text: Binding<String>,
        field: Field,
        invalid: Bool,
        submit: SubmitLabel,
        onSubmit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.white.opacity(0.62))
            SecureField("", text: text, prompt: Text(prompt).foregroundStyle(Color.white.opacity(0.32)))
                .textFieldStyle(.plain)
                .textContentType(field == .passwordAgain ? .newPassword : .password)
                .font(KonumumFont.plate(16))
                .foregroundStyle(.white)
                .tint(KonumumTheme.neon)
                .focused($focus, equals: field)
                .submitLabel(submit)
                .onSubmit(onSubmit)
                .padding(.horizontal, 18)
                .frame(height: 56)
                .background(well(active: focus == field, invalid: invalid))
        }
    }

    private func goHome() {
        showWebPanel = false
        focus = nil
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
    }

    private var kvkkConsent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $kvkkOk) {
                Text(L(
                    "KVKK aydınlatma ve açık rızayı okudum, kabul ediyorum. Plaka ve konum yalnızca teslim için işlenir.",
                    "I have read and accept the Privacy Notice & Explicit Consent. Plate and location are processed only for car pickup."
                ))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            }
            .tint(KonumumTheme.neon)
            Button {
                showLegalSheet = true
            } label: {
                Text(L("KVKK Aydınlatma ve Açık Rıza Metnini Oku", "Read Privacy Notice & Explicit Consent"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KonumumTheme.neon)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 4)
    }

    private var legalSheetView: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("KVKK Aydınlatma Metni", "Privacy Notice (KVKK)"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Text(L(
                        "konumumyemek.com veri sorumlusu sıfatıyla 6698 sayılı KVKK kapsamında ad-soyad, e-posta, telefon, araç plakası ve sipariş teslim anına kadar anlık konum verisini işler. Amaç: siparişin mutfağa iletilmesi ve paketin araç camından teslim edilmesidir. Teslim tamamlandığında konum paylaşımı otomatik olarak kapanır.",
                        "konumumyemek.com processes your full name, email, phone number, vehicle license plate, and live approach distance until order handoff under Turkish Personal Data Protection Law (KVKK No. 6698). Purpose: routing your order to the kitchen and handing the package through your car window. Live location stops automatically upon delivery."
                    ))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.82))

                    Text(L("Açık Rıza Metni", "Explicit Consent"))
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.top, 6)
                    Text(L(
                        "Plakamın restoran ekranında gösterilmesine, siparişimin mutfağa iletilmesine ve yaklaşım mesafemin (km/metre ve tahmini varış süresi) paket hazırlığı için takip edilmesine açık rıza veriyorum. Rızamı dilediğim zaman profil ekranından geri çekebilirim.",
                        "I explicitly consent to displaying my license plate on the restaurant kitchen screen, transmitting my order, and tracking my approach distance (km/meters and ETA) for meal preparation. I can withdraw my consent at any time from my profile."
                    ))
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.82))
                }
                .padding(24)
            }
            .background(KonumumTheme.graphite.ignoresSafeArea())
            .navigationTitle(L("KVKK & Açık Rıza", "Privacy & Consent"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L("Kapat", "Close")) {
                        showLegalSheet = false
                    }
                    .foregroundStyle(KonumumTheme.neon)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var signUpConsentTicks: some View {
        VStack(alignment: .leading, spacing: 12) {
            consentTick(
                isOn: $kvkkAydinlatma,
                title: L("KVKK aydınlatma metnini okudum, kabul ediyorum", "I have read and accept the Privacy Notice (KVKK)"),
                detail: L(
                    "6698 sayılı KVKK kapsamında e-posta, telefon, plaka ve teslim anına kadar konum drive-thru kimliği için işlenir. Teslimde konum kapanır.",
                    "Email, phone, license plate, and live location until handoff are processed for drive-thru identification. Location stops upon delivery."
                )
            )
            consentTick(
                isOn: $acikRiza,
                title: L("Açık rıza veriyorum", "I give my explicit consent"),
                detail: L(
                    "Plakamın restoran ekranında gösterilmesine, siparişimin mutfağa iletilmesine ve araç camından teslim edilmesine açık rıza veriyorum. Rızamı geri çekebilirim.",
                    "I consent to displaying my license plate on the restaurant screen and handing my order through the car window."
                )
            )
            Button {
                showLegalSheet = true
            } label: {
                Text(L("KVKK Aydınlatma ve Açık Rıza Metnini Oku", "Read Privacy Notice & Explicit Consent"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(KonumumTheme.neon)
                    .underline()
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private func consentTick(isOn: Binding<Bool>, title: String, detail: String) -> some View {
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

    private func signIn() {
        attempted = true
        loginFailed = false
        guard kvkkOk, emailLooksValid, !password.isEmpty else { return }
        focus = nil

        if directory.signInCustomer(identifier: trimmedEmail, password: password) {
            sealSession(from: directory.customerSession)
            storedKvkk = true
            enterApp(markRegistered: true)
            return
        }

        let storedMatch = storedEmail.lowercased() == trimmedEmail && storedPassword == password && !storedPassword.isEmpty
        if storedMatch {
            storedKvkk = true
            enterApp(markRegistered: isRegistered || !storedPlate.isEmpty)
            return
        }

        loginFailed = true
    }

    private func enterSimulation() {
        email = "musteri@konumumyemek.com"
        password = "konumum55"
        attempted = false
        loginFailed = false
    }

    private func openSignUp() {
        focus = .name
        attempted = false
        loginFailed = false
        if passwordAgain.isEmpty { passwordAgain = password }
        showSignUp = true
    }

    private func submitSignUp() {
        attempted = true
        guard signUpComplete else { return }
        focus = nil
        storedName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        storedEmail = trimmedEmail
        storedPhone = phone
        storedPassword = password
        storedPlate = plate
        storedKvkk = true
        storedAcikRiza = true
        _ = directory.registerMember(
            name: storedName,
            email: storedEmail,
            phone: phone,
            plate: plate,
            password: password
        )
        enterApp(markRegistered: true)
    }

    private func sealSession(from account: KonumumCustomerAccount?) {
        guard let account else { return }
        storedName = account.name
        storedEmail = account.email
        storedPhone = account.phone
        storedPassword = account.password
        storedPlate = account.plates.first ?? storedPlate
    }

    private func enterApp(markRegistered: Bool) {
        landOnProfile = false
        if markRegistered { isRegistered = true }
        isSignedIn = true
    }

    private var phoneBinding: Binding<String> {
        Binding(
            get: { phone },
            set: { phone = Self.formatPhone($0) }
        )
    }

    private var plateBinding: Binding<String> {
        Binding(
            get: { plate },
            set: { plate = Self.formatPlate($0) }
        )
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

    static func formatPlate(_ raw: String) -> String {
        let upper = raw.uppercased(with: Locale(identifier: "en_US_POSIX"))
        let characters = upper.filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        var city = ""
        var letters = ""
        var digits = ""
        var phase = 0

        for character in characters {
            if phase == 0 {
                if character.isNumber, city.count < 2 {
                    city.append(character)
                    if city.count == 2 { phase = 1 }
                } else if character.isLetter, !city.isEmpty {
                    phase = 1
                    if letters.count < 3 { letters.append(character) }
                }
            } else if phase == 1 {
                if character.isLetter, letters.count < 3 {
                    letters.append(character)
                } else if character.isNumber {
                    phase = 2
                    if digits.count < 4 { digits.append(character) }
                }
            } else if character.isNumber, digits.count < 4 {
                digits.append(character)
            }
        }

        return [city, letters, digits].filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func formatPhone(_ raw: String) -> String {
        let digits = raw.filter(\.isNumber)
        let clipped = String(digits.prefix(11))
        var result = ""
        for (index, character) in clipped.enumerated() {
            if index == 4 || index == 7 {
                result.append(" ")
            }
            result.append(character)
        }
        return result
    }
}

struct KonumumBrandMark: View {
    var size: CGFloat = 72

    var body: some View {
        Group {
            if let uiImage = UIImage(named: "KonumumLogo") ?? UIImage(named: "AppIcon60x60") {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "fork.knife.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(KonumumTheme.neon)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .shadow(color: KonumumTheme.neon.opacity(0.55), radius: 16)
        .accessibilityHidden(true)
    }
}

struct KonumumPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack {
        PlateRegistrationView()
    }
    .environmentObject(KonumumDirectory())
    .preferredColorScheme(.dark)
}
