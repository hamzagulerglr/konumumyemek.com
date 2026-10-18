import SwiftUI

struct RestaurantSellerDeskView: View {
    let restaurant: KonumumRestaurantAccount
    var onOpenKitchen: () -> Void

    @EnvironmentObject private var directory: KonumumDirectory

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(restaurant.branchTitle)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))

            reverseTrackBoard

            Button(action: onOpenKitchen) {
                Text("Mutfak Canlı Sipariş Ekranını Aç")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(KonumumTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(KonumumTheme.neon, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: KonumumTheme.neon.opacity(0.9), radius: 14)
            }
            .buttonStyle(KonumumPressStyle())

            RestaurantCompanyForm(restaurant: restaurant)
        }
    }

    private var reverseTrackBoard: some View {
        let route = directory.liveKitchenRoute
        return VStack(alignment: .leading, spacing: 12) {
            Text("Tersine Takip — Masaüstü Konsol")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            Text("Yaklaşan araç, plaka ve mesafe aynı veri akışından canlı akar.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))

            HStack(alignment: .top, spacing: 14) {
                SellerDeskMap(
                    progress: 1 - CGFloat(directory.liveMeters) / CGFloat(max(1, KonumumDirectory.approachStartMeters)),
                    plate: route.plate,
                    pinLatitude: restaurant.mapLatitude,
                    pinLongitude: restaurant.mapLongitude
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text(route.plate)
                        .font(KonumumFont.plate(20))
                        .tracking(2)
                        .foregroundStyle(KonumumTheme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(directory.liveMeters == 0 ? KonumumProximity.door.tint : KonumumTheme.neon, in: Capsule())
                    Text("Mutfak: \(directory.kitchenStatusText)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(directory.liveMeters == 0
                         ? "Mesafe: 0 Metre - Kapıda!"
                         : "Mesafe: \(directory.liveMeters) Metre")
                        .font(KonumumFont.plate(16))
                        .foregroundStyle(directory.liveMeters == 0 ? KonumumProximity.door.tint : .white)
                    Text("Tahmini: \(directory.liveSeconds) sn")
                        .font(KonumumFont.plate(14))
                        .foregroundStyle(Color.white.opacity(0.78))
                    if directory.customerCollectedNotice {
                        Text("Müşteri Siparişi Teslim Aldı")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(KonumumTheme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.22, green: 0.95, blue: 0.48), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                .frame(minWidth: 160, maxWidth: 240, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(KonumumTheme.neon.opacity(0.28), lineWidth: 1)
                }
        }
    }
}

private struct SellerDeskMap: View {
    var progress: CGFloat
    var plate: String
    var pinLatitude: Double
    var pinLongitude: Double

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(KonumumTheme.graphite))
            var grid = Path()
            stride(from: 0.0, through: size.width, by: 28).forEach { x in
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            stride(from: 0.0, through: size.height, by: 28).forEach { y in
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(.white.opacity(0.06)), lineWidth: 1)

            let route = Path { path in
                path.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.82))
                path.addQuadCurve(
                    to: CGPoint(x: size.width * 0.78, y: size.height * 0.22),
                    control: CGPoint(x: size.width * 0.48, y: size.height * 0.62)
                )
            }
            context.stroke(route, with: .color(KonumumTheme.neon.opacity(0.28)), style: StrokeStyle(lineWidth: 14, lineCap: .round))
            context.stroke(route, with: .color(KonumumTheme.neon), style: StrokeStyle(lineWidth: 4, lineCap: .round))

            let pin = CGPoint(
                x: size.width * pinClamp(CGFloat((pinLongitude - 36.25) / 0.16), 0.12, 0.88),
                y: size.height * (1 - pinClamp(CGFloat((pinLatitude - 41.24) / 0.10), 0.12, 0.88))
            )
            var drop = Path()
            drop.addEllipse(in: CGRect(x: pin.x - 7, y: pin.y - 18, width: 14, height: 14))
            context.fill(drop, with: .color(KonumumProximity.door.tint))

            let car = route.trimmedPath(from: 0, to: max(0.02, min(1, progress))).currentPoint ?? .zero
            context.fill(Path(roundedRect: CGRect(x: car.x - 8, y: car.y - 5, width: 16, height: 10), cornerRadius: 3), with: .color(KonumumTheme.neon))
            let plateText = context.resolve(Text(plate).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(KonumumTheme.ink))
            context.fill(Path(roundedRect: CGRect(x: car.x - 34, y: car.y - 22, width: 68, height: 14), cornerRadius: 4), with: .color(KonumumTheme.neon))
            context.draw(plateText, at: CGPoint(x: car.x, y: car.y - 15), anchor: .center)
        }
    }
}

struct RestaurantCompanyForm: View {
    let restaurant: KonumumRestaurantAccount
    @EnvironmentObject private var directory: KonumumDirectory

    @State private var officialTitle = ""
    @State private var branchTitle = ""
    @State private var email = ""
    @State private var password = ""
    @State private var phone = ""
    @State private var taxNumber = ""
    @State private var address = ""
    @State private var iban = ""
    @State private var latitude = 41.2867
    @State private var longitude = 36.3300
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Firma Bilgileri")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            Text("Vergi, IBAN, adres ve teslim pinini masaüstü panelden mühürleyin.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.62))

            field("Ticari Unvan", text: $officialTitle, prompt: "Şirket unvanı")
            field("Şube / Teslim Noktası", text: $branchTitle, prompt: "Şube adı")
            field("E-posta Adresi", text: $email, prompt: "restoran@konumumyemek.com")
            secret("Şifre", text: $password)
            field("Telefon", text: $phone, prompt: "0362 000 00 00")
            field("Vergi Numarası", text: $taxNumber, prompt: "1234567890")
            field("Adres", text: $address, prompt: "Mahalle, cadde, ilçe / Samsun")
            field("IBAN", text: $iban, prompt: "TR00 ACCT-000003 0000 00")

            Text("Haritadan Teslim Noktasını İşaretle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 6)

            BranchMapEditor(latitude: $latitude, longitude: $longitude)
                .frame(height: 220)

            Text(String(format: "Pin: %.4f, %.4f", latitude, longitude))
                .font(KonumumFont.plate(12))
                .foregroundStyle(Color.white.opacity(0.55))

            Button(action: save) {
                Text("Firma Bilgilerini Kaydet")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(KonumumTheme.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(KonumumTheme.neon, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(KonumumPressStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
        }
        .onAppear(perform: load)
        .alert("Kayıt Başarılı", isPresented: $saved) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text("Firma bilgileri konumumyemek.com restoran paneline kaydedildi.")
        }
    }

    private func load() {
        officialTitle = restaurant.officialTitle
        branchTitle = restaurant.branchTitle
        email = restaurant.email
        password = restaurant.password
        phone = restaurant.phone
        taxNumber = restaurant.taxNumber
        address = restaurant.address
        iban = restaurant.iban
        latitude = restaurant.mapLatitude
        longitude = restaurant.mapLongitude
    }

    private func save() {
        var next = restaurant
        next.officialTitle = officialTitle
        next.branchTitle = branchTitle
        next.email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        next.password = password
        next.phone = phone
        next.taxNumber = taxNumber.filter(\.isNumber)
        next.address = address
        next.iban = iban.uppercased()
        next.mapLatitude = latitude
        next.mapLongitude = longitude
        directory.updateRestaurantProfile(next)
        saved = true
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Color.white.opacity(0.32)))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .tint(KonumumTheme.neon)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(well())
        }
    }

    private func secret(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.62))
            SecureField("", text: text, prompt: Text("En az 6 karakter").foregroundStyle(Color.white.opacity(0.32)))
                .textContentType(.password)
                .font(KonumumFont.plate(15))
                .foregroundStyle(.white)
                .tint(KonumumTheme.neon)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(well())
        }
    }

    private func well() -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            }
    }
}

private struct BranchMapEditor: View {
    @Binding var latitude: Double
    @Binding var longitude: Double

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                KonumumTheme.graphite
                Canvas { context, canvasSize in
                    var grid = Path()
                    stride(from: 0.0, through: canvasSize.width, by: 24).forEach { x in
                        grid.move(to: CGPoint(x: x, y: 0))
                        grid.addLine(to: CGPoint(x: x, y: canvasSize.height))
                    }
                    stride(from: 0.0, through: canvasSize.height, by: 24).forEach { y in
                        grid.move(to: CGPoint(x: 0, y: y))
                        grid.addLine(to: CGPoint(x: canvasSize.width, y: y))
                    }
                    context.stroke(grid, with: .color(.white.opacity(0.07)), lineWidth: 1)
                    context.stroke(
                        Path(ellipseIn: CGRect(x: canvasSize.width * 0.18, y: canvasSize.height * 0.22, width: canvasSize.width * 0.64, height: canvasSize.height * 0.52)),
                        with: .color(KonumumTheme.neon.opacity(0.2)),
                        lineWidth: 2
                    )
                }
                let pin = CGPoint(
                    x: size.width * pinClamp(CGFloat((longitude - 36.25) / 0.16), 0.06, 0.94),
                    y: size.height * (1 - pinClamp(CGFloat((latitude - 41.24) / 0.10), 0.06, 0.94))
                )
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(KonumumProximity.door.tint)
                    .shadow(color: KonumumProximity.door.tint.opacity(0.8), radius: 8)
                    .position(pin)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { value in
                    let location = value.location
                    let nx = min(1, max(0, location.x / size.width))
                    let ny = min(1, max(0, location.y / size.height))
                    longitude = 36.25 + Double(nx) * 0.16
                    latitude = 41.24 + Double(1 - ny) * 0.10
                }
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(KonumumTheme.neon.opacity(0.35), lineWidth: 1)
        }
    }
}

private func pinClamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    min(max(value, lo), hi)
}
