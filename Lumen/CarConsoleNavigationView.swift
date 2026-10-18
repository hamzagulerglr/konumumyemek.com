import SwiftUI

enum KonumumProximity: Hashable {
    case far
    case mid
    case door

    init(meters: Int) {
        if meters >= 1000 { self = .far }
        else if meters >= 500 { self = .mid }
        else { self = .door }
    }

    var tint: Color {
        switch self {
        case .far: KonumumTheme.neon
        case .mid: Color(red: 1.0, green: 0.82, blue: 0.16)
        case .door: Color(red: 1.0, green: 0.26, blue: 0.32)
        }
    }

    var label: String {
        switch self {
        case .far: "Yeni Sipariş · Yeşil"
        case .mid: "Orta Mesafe · Sarı"
        case .door: "Kapıda · Kırmızı"
        }
    }
}

struct CarConsoleRoute: Hashable {
    var deliveryId: String? = nil
    var restaurantName: String
    var destinationTitle: String
    var plate: String
    var paymentTitle: String
    var lines: [KitchenOrderLine]
}

struct CarConsoleNavigationView: View {
    let route: CarConsoleRoute

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var directory: KonumumDirectory
    @State private var meters = 1400
    @State private var seconds = 140
    @State private var kitchenWake = false

    private var approaching: Bool { meters <= 100 }
    private var progress: CGFloat {
        1 - CGFloat(meters) / 1400
    }
    private var proximity: KonumumProximity { KonumumProximity(meters: meters) }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width >= geo.size.height
            console
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
        .onDisappear {
            requestOrientation(.portrait)
        }
        .task {
            while !Task.isCancelled && meters > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                meters = max(0, meters - 10)
                seconds = max(0, Int((Double(meters) / 10.0).rounded()))
            }
        }
        .onChange(of: approaching) { _, isNear in
            guard isNear else { return }
            Task {
                try? await Task.sleep(nanoseconds: 900_000_000)
                kitchenWake = true
            }
        }
        .navigationDestination(isPresented: $kitchenWake) {
            RestaurantKitchenView(route: route, onCloseOrder: {
                directory.popToMenusHome()
            })
            .environment(\.popToHome, { directory.popToMenusHome() })
            .environmentObject(directory)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var console: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                mapPane
                    .frame(maxWidth: .infinity)
                infoPane
                    .frame(width: 340)
            }

            if approaching {
                approachBanner
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
            }
        }
        .background(KonumumTheme.graphite)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: approaching)
        .animation(.easeInOut(duration: 0.28), value: proximity)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(alignment: .top) {
            standardBar
        }
    }

    private var standardBar: some View {
        HStack(spacing: 10) {
            standardChip("CarPlay")
            standardChip("Android Auto")
            Spacer()
            Text("YATAY KONSOL")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func standardChip(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(KonumumTheme.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(KonumumTheme.neon.opacity(0.92), in: Capsule())
    }

    private var mapPane: some View {
        ZStack {
            KonumumTheme.graphite
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.10, blue: 0.16), KonumumTheme.graphite],
                startPoint: .top,
                endPoint: .bottom
            )

            ConsoleMapCanvas(progress: progress, plate: route.plate, tint: proximity.tint)
                .padding(.top, 28)
                .padding(.horizontal, 18)
                .padding(.bottom, approaching ? 92 : 18)
                .animation(.easeInOut(duration: 0.28), value: proximity)

            VStack {
                Spacer()
                HStack {
                    FriendlyCompassBadge()
                    Spacer()
                }
                .padding(16)
            }
            .allowsHitTesting(false)
        }
    }

    private var infoPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .bold))
                        Text("Sipariş")
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KonumumTheme.neon)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 28)

            Text("konumumyemek.com Navigasyon")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(KonumumTheme.neon)
                .shadow(color: KonumumTheme.neon.opacity(0.85), radius: 8)
                .padding(.top, 18)
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(route.destinationTitle)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.top, 16)
                .fixedSize(horizontal: false, vertical: true)

            Text(route.plate)
                .font(KonumumFont.plate(16))
                .tracking(2)
                .foregroundStyle(KonumumTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(proximity.tint, in: Capsule())
                .shadow(color: proximity.tint.opacity(0.7), radius: 8)
                .padding(.top, 12)

            Text(proximity.label)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(proximity.tint)
                .shadow(color: proximity.tint.opacity(0.8), radius: 6)
                .padding(.top, 8)

            Spacer(minLength: 16)

            Text("Mesafe: \(meters) Metre")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Text("Tahmini Süre: \(durationLabel)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
                .padding(.top, 6)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, approaching ? 100 : 20)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.035))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(KonumumTheme.neon.opacity(0.28))
                .frame(width: 1)
        }
    }

    private var durationLabel: String {
        if seconds >= 60 {
            let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
            return "\(minutes) Dakika"
        }
        if seconds == 0 {
            return "Varış"
        }
        return "\(seconds) Saniye"
    }

    private var approachBanner: some View {
        Text("\(route.restaurantName) Kapısına Yaklaştınız. Mutfak Paneli Aracınızı Tanıdı, Siparişiniz Kapıya Getiriliyor. Lütfen Arabanızdan İnmeyin!")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(KonumumTheme.ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(KonumumProximity.door.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: KonumumProximity.door.tint.opacity(1), radius: 16)
            .shadow(color: KonumumProximity.door.tint.opacity(0.55), radius: 28)
    }

    private func requestOrientation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

private struct FriendlyCompassBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.07))
            Circle()
                .strokeBorder(KonumumTheme.neon.opacity(0.55), lineWidth: 1.2)
            Image(systemName: "fork.knife")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(KonumumTheme.neon)
        }
        .frame(width: 46, height: 46)
        .shadow(color: KonumumTheme.neon.opacity(0.55), radius: 10)
    }
}

private struct ConsoleMapCanvas: View {
    var progress: CGFloat
    var plate: String
    var tint: Color

    var body: some View {
        Canvas { context, size in
            drawGrid(context: &context, size: size)

            let route = routePath(in: size)
            var glow = context
            glow.stroke(
                route,
                with: .color(tint.opacity(0.24)),
                style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                route,
                with: .color(tint),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )

            let restaurant = CGPoint(x: size.width * 0.82, y: size.height * 0.18)
            drawBrandPin(&context, at: restaurant, scale: 1.15, tint: KonumumTheme.neon)

            let car = point(on: route, progress: min(1, max(0, progress)))
            drawBrandPin(&context, at: car, scale: 1.0, tint: tint)
            drawPlateBadge(&context, plate: plate, at: CGPoint(x: car.x, y: car.y - 34), tint: tint)
        }
        .shadow(color: tint.opacity(0.35), radius: 16)
    }

    private func drawPlateBadge(_ context: inout GraphicsContext, plate: String, at origin: CGPoint, tint: Color) {
        let resolved = context.resolve(
            Text(plate)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(KonumumTheme.ink)
        )
        let textSize = resolved.measure(in: CGSize(width: 220, height: 24))
        let width = max(72, textSize.width + 16)
        let height = max(18, textSize.height + 8)
        let rect = CGRect(x: origin.x - width / 2, y: origin.y - height, width: width, height: height)
        context.fill(Path(ellipseIn: rect.insetBy(dx: -8, dy: -6)), with: .color(tint.opacity(0.28)))
        context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(tint))
        context.stroke(Path(roundedRect: rect, cornerRadius: 6), with: .color(.white.opacity(0.4)), lineWidth: 0.8)
        context.draw(resolved, at: CGPoint(x: origin.x, y: origin.y - height / 2), anchor: .center)
    }

    private func drawBrandPin(_ context: inout GraphicsContext, at origin: CGPoint, scale: CGFloat, tint: Color) {
        var local = context
        local.translateBy(x: origin.x, y: origin.y)
        local.scaleBy(x: scale, y: scale)

        local.fill(
            Path(ellipseIn: CGRect(x: -24, y: -38, width: 48, height: 52)),
            with: .color(tint.opacity(0.22))
        )

        let drop = Path { path in
            path.move(to: CGPoint(x: 0, y: 20))
            path.addCurve(
                to: CGPoint(x: -16, y: -10),
                control1: CGPoint(x: -2, y: 8),
                control2: CGPoint(x: -16, y: 4)
            )
            path.addArc(
                center: CGPoint(x: 0, y: -12),
                radius: 16,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.addCurve(
                to: CGPoint(x: 0, y: 20),
                control1: CGPoint(x: 16, y: 4),
                control2: CGPoint(x: 2, y: 8)
            )
            path.closeSubpath()
        }
        local.fill(drop, with: .color(tint))
        local.stroke(drop, with: .color(.white.opacity(0.42)), lineWidth: 1.6)

        let ring = Path(ellipseIn: CGRect(x: -11.5, y: -23.5, width: 23, height: 23))
        local.stroke(ring, with: .color(tint.opacity(0.95)), lineWidth: 2.4)
        // Inner well: dark navy, never pure black.
        local.fill(
            Path(ellipseIn: CGRect(x: -9.5, y: -21.5, width: 19, height: 19)),
            with: .color(Color(red: 22 / 255, green: 32 / 255, blue: 48 / 255))
        )

        var bowl = Path()
        bowl.addEllipse(in: CGRect(x: -6.6, y: -16.2, width: 13.2, height: 4.2))
        bowl.move(to: CGPoint(x: -6.4, y: -14.4))
        bowl.addQuadCurve(to: CGPoint(x: 6.4, y: -14.4), control: CGPoint(x: 0, y: -7.2))
        local.fill(bowl, with: .color(.white))
        local.stroke(
            Path(ellipseIn: CGRect(x: -6.6, y: -16.4, width: 13.2, height: 4.4)),
            with: .color(.white),
            lineWidth: 1.15
        )

        var noodles = Path()
        noodles.move(to: CGPoint(x: -3.2, y: -14.8))
        noodles.addQuadCurve(to: CGPoint(x: 1.8, y: -12.6), control: CGPoint(x: -1.4, y: -12.2))
        noodles.move(to: CGPoint(x: -1.6, y: -15.2))
        noodles.addQuadCurve(to: CGPoint(x: 3.4, y: -13.0), control: CGPoint(x: 0.6, y: -12.4))
        local.stroke(noodles, with: .color(.white.opacity(0.92)), style: StrokeStyle(lineWidth: 0.9, lineCap: .round))

        var steam = Path()
        steam.move(to: CGPoint(x: -2.6, y: -18))
        steam.addQuadCurve(to: CGPoint(x: -2.4, y: -25.5), control: CGPoint(x: -5, y: -21.5))
        steam.move(to: CGPoint(x: 0.2, y: -18.4))
        steam.addQuadCurve(to: CGPoint(x: 0.4, y: -26.8), control: CGPoint(x: 2.6, y: -22))
        steam.move(to: CGPoint(x: 3.0, y: -18))
        steam.addQuadCurve(to: CGPoint(x: 3.2, y: -24.8), control: CGPoint(x: 5.4, y: -21))
        local.stroke(steam, with: .color(.white), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))

        var fork = Path()
        fork.move(to: CGPoint(x: 5.2, y: -14.6))
        fork.addLine(to: CGPoint(x: 9.4, y: -22.8))
        fork.move(to: CGPoint(x: 8.2, y: -23.4))
        fork.addLine(to: CGPoint(x: 10.6, y: -22.2))
        fork.move(to: CGPoint(x: 9.0, y: -24.2))
        fork.addLine(to: CGPoint(x: 9.8, y: -21.4))
        local.stroke(fork, with: .color(.white), style: StrokeStyle(lineWidth: 1.15, lineCap: .round, lineJoin: .round))
    }

    private func drawGrid(context: inout GraphicsContext, size: CGSize) {
        var grid = Path()
        let step: CGFloat = 36
        var x: CGFloat = 0
        while x < size.width {
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
            x += step
        }
        var y: CGFloat = 0
        while y < size.height {
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
            y += step
        }
        context.stroke(grid, with: .color(Color.white.opacity(0.05)), lineWidth: 1)

        var roads = Path()
        roads.move(to: CGPoint(x: 0, y: size.height * 0.62))
        roads.addLine(to: CGPoint(x: size.width, y: size.height * 0.38))
        roads.move(to: CGPoint(x: size.width * 0.22, y: size.height))
        roads.addLine(to: CGPoint(x: size.width * 0.72, y: 0))
        context.stroke(roads, with: .color(Color.white.opacity(0.10)), style: StrokeStyle(lineWidth: 10, lineCap: .round))
    }

    private func routePath(in size: CGSize) -> Path {
        Path { path in
            path.move(to: CGPoint(x: size.width * 0.12, y: size.height * 0.86))
            path.addCurve(
                to: CGPoint(x: size.width * 0.48, y: size.height * 0.52),
                control1: CGPoint(x: size.width * 0.18, y: size.height * 0.68),
                control2: CGPoint(x: size.width * 0.32, y: size.height * 0.58)
            )
            path.addCurve(
                to: CGPoint(x: size.width * 0.82, y: size.height * 0.18),
                control1: CGPoint(x: size.width * 0.64, y: size.height * 0.46),
                control2: CGPoint(x: size.width * 0.70, y: size.height * 0.24)
            )
        }
    }

    private func point(on path: Path, progress: CGFloat) -> CGPoint {
        let trimmed = path.trimmedPath(from: 0, to: max(0.001, progress))
        return trimmed.currentPoint ?? .zero
    }

    private func heading(on path: Path, progress: CGFloat) -> Angle {
        let a = point(on: path, progress: max(0, progress - 0.02))
        let b = point(on: path, progress: min(1, progress + 0.02))
        return .radians(atan2(b.y - a.y, b.x - a.x) + .pi / 2)
    }
}

#Preview {
    CarConsoleNavigationView(
        route: CarConsoleRoute(
            restaurantName: "McDonald's",
            destinationTitle: "McDonald's - Bulvar/Samsun Şubesi",
            plate: "34 KNM 55",
            paymentTitle: "Metropol Card",
            lines: [
                KitchenOrderLine(name: "Big Mac", quantity: 1, unitPrice: 215)
            ]
        )
    )
    .environmentObject(KonumumDirectory())
}
