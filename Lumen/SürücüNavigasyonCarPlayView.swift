import SwiftUI
import UIKit

struct SurucuNavigasyonCarPlayView: View {
    let route: CarConsoleRoute
    var hostedOnCarPlay = false

    @EnvironmentObject private var directory: KonumumDirectory
    @Environment(\.dismiss) private var dismiss
    @State private var closing = false

    private var atDoor: Bool { directory.liveMeters <= 0 }
    private var progress: CGFloat {
        let start = CGFloat(KonumumDirectory.approachStartMeters)
        return 1 - CGFloat(directory.liveMeters) / max(1, start)
    }

    private var teslimNoktasi: String {
        if route.restaurantName.localizedCaseInsensitiveContains("McDonald") {
            return "Samsun McDonald's Drive-Thru (Teslim Noktası)"
        }
        return "\(route.destinationTitle) (Teslim Noktası)"
    }

    private var pickupGreen: Color {
        Color(red: 0.22, green: 0.95, blue: 0.48)
    }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width >= geo.size.height
            console(in: landscape ? geo.size : CGSize(width: geo.size.height, height: geo.size.width))
                .frame(
                    width: landscape ? geo.size.width : geo.size.height,
                    height: landscape ? geo.size.height : geo.size.width
                )
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
            if !hostedOnCarPlay {
                requestOrientation(.landscape)
            }
            if !directory.approachActive {
                directory.startLiveApproach()
            }
        }
        .onDisappear {
            if !hostedOnCarPlay {
                requestOrientation(.portrait)
            }
        }
    }

    private func console(in size: CGSize) -> some View {
        HStack(spacing: 0) {
            mapPane
                .frame(width: size.width * 0.65)
            infoPane
                .frame(width: size.width * 0.35)
        }
        .frame(width: size.width, height: size.height)
        .background(KonumumTheme.graphite)
        .animation(.easeInOut(duration: 0.28), value: directory.liveMeters)
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: atDoor)
    }

    private var mapPane: some View {
        ZStack {
            KonumumTheme.graphite
            LinearGradient(
                colors: [Color(red: 0.07, green: 0.10, blue: 0.16), KonumumTheme.graphite],
                startPoint: .top,
                endPoint: .bottom
            )

            DriverMapCanvas(
                progress: min(1, max(0, progress)),
                plate: route.plate,
                destinationTitle: teslimNoktasi
            )
            .padding(.top, 36)
            .padding(.horizontal, 18)
            .padding(.bottom, 18)

            VStack {
                HStack {
                    Text("CarPlay")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(KonumumTheme.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(KonumumTheme.neon.opacity(0.92), in: Capsule())
                    Text(hostedOnCarPlay ? "ARAÇ EKRANI" : "YATAY ÖN KONSOL")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(Color.white.opacity(0.45))
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }

    private var infoPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button {
                    directory.stopLiveApproach()
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
            .padding(.top, 22)

            Text("konumumyemek.com Navigasyon")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(KonumumTheme.neon)
                .shadow(color: KonumumTheme.neon.opacity(0.85), radius: 8)
                .padding(.top, 16)
                .minimumScaleFactor(0.7)
                .lineLimit(2)

            Text(teslimNoktasi)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.white)
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)

            Text(route.plate)
                .font(KonumumFont.plate(15))
                .tracking(2)
                .foregroundStyle(KonumumTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(KonumumTheme.neon, in: Capsule())
                .padding(.top, 10)

            liveReadout("Mutfak Durumu", value: directory.kitchenStatusText)
                .padding(.top, 22)

            if atDoor {
                Text("0 Metre - Teslim Noktasındasınız!")
                    .font(KonumumFont.plate(18))
                    .foregroundStyle(KonumumProximity.door.tint)
                    .shadow(color: KonumumProximity.door.tint.opacity(0.95), radius: 10)
                    .padding(.top, 16)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                liveReadout("Kalan Mesafe", value: "\(directory.liveMeters) Metre")
                    .padding(.top, 14)
                liveReadout("Tahmini Varış", value: "\(directory.liveSeconds) Saniye")
                    .padding(.top, 14)
            }

            Spacer(minLength: 12)

            if atDoor {
                Button(action: collectMeal) {
                    Text("YEMEĞİ TESLİM ALDIM")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(KonumumTheme.ink)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.7)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                        .background(pickupGreen, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: pickupGreen.opacity(0.95), radius: 16)
                        .shadow(color: pickupGreen.opacity(0.5), radius: 28, y: 4)
                }
                .buttonStyle(KonumumPressStyle())
                .disabled(closing)
                .opacity(closing ? 0.55 : 1)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.035))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(KonumumTheme.neon.opacity(0.28))
                .frame(width: 1)
        }
    }

    private func liveReadout(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(Color.white.opacity(0.55))
            Text("\(title): \(value)")
                .font(KonumumFont.plate(16))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(2)
                .shadow(color: KonumumTheme.neon.opacity(0.35), radius: 6)
        }
    }

    private func collectMeal() {
        guard !closing else { return }
        closing = true
        directory.confirmCustomerCollected(deliveryId: route.deliveryId, plate: route.plate)
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            directory.popToMenusHome()
        }
    }

    private func requestOrientation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }
}

private struct DriverMapCanvas: View {
    var progress: CGFloat
    var plate: String
    var destinationTitle: String

    var body: some View {
        Canvas { context, size in
            drawGrid(context: &context, size: size)

            let route = routePath(in: size)
            context.stroke(
                route,
                with: .color(KonumumTheme.neon.opacity(0.22)),
                style: StrokeStyle(lineWidth: 18, lineCap: .round, lineJoin: .round)
            )
            context.stroke(
                route,
                with: .color(KonumumTheme.neon),
                style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round)
            )

            let restaurant = CGPoint(x: size.width * 0.82, y: size.height * 0.18)
            drawRedPin(&context, at: restaurant)
            drawDestinationLabel(&context, title: destinationTitle, at: CGPoint(x: restaurant.x, y: restaurant.y - 44))

            let car = point(on: route, progress: min(1, max(0, progress)))
            drawCar(&context, at: car)
            drawPlateBadge(&context, plate: plate, at: CGPoint(x: car.x, y: car.y - 28))
        }
        .shadow(color: KonumumTheme.neon.opacity(0.28), radius: 16)
    }

    private func drawDestinationLabel(_ context: inout GraphicsContext, title: String, at origin: CGPoint) {
        let resolved = context.resolve(
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .foregroundColor(.white)
        )
        let textSize = resolved.measure(in: CGSize(width: 220, height: 36))
        let width = min(220, max(120, textSize.width + 16))
        let height = max(28, textSize.height + 10)
        let rect = CGRect(x: origin.x - width / 2, y: origin.y - height, width: width, height: height)
        context.fill(
            Path(roundedRect: rect, cornerRadius: 8),
            with: .color(Color(red: 0.08, green: 0.11, blue: 0.18).opacity(0.92))
        )
        context.stroke(
            Path(roundedRect: rect, cornerRadius: 8),
            with: .color(KonumumProximity.door.tint.opacity(0.7)),
            lineWidth: 1
        )
        context.draw(resolved, at: CGPoint(x: origin.x, y: origin.y - height / 2), anchor: .center)
    }

    private func drawPlateBadge(_ context: inout GraphicsContext, plate: String, at origin: CGPoint) {
        let resolved = context.resolve(
            Text(plate)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(KonumumTheme.ink)
        )
        let textSize = resolved.measure(in: CGSize(width: 220, height: 24))
        let width = max(72, textSize.width + 16)
        let height = max(18, textSize.height + 8)
        let rect = CGRect(x: origin.x - width / 2, y: origin.y - height, width: width, height: height)
        context.fill(Path(roundedRect: rect, cornerRadius: 6), with: .color(KonumumTheme.neon))
        context.draw(resolved, at: CGPoint(x: origin.x, y: origin.y - height / 2), anchor: .center)
    }

    private func drawRedPin(_ context: inout GraphicsContext, at origin: CGPoint) {
        var local = context
        local.translateBy(x: origin.x, y: origin.y)
        local.fill(
            Path(ellipseIn: CGRect(x: -18, y: -6, width: 36, height: 14)),
            with: .color(KonumumProximity.door.tint.opacity(0.28))
        )
        let drop = Path { path in
            path.move(to: CGPoint(x: 0, y: 16))
            path.addQuadCurve(to: CGPoint(x: -12, y: -6), control: CGPoint(x: -12, y: 6))
            path.addArc(
                center: CGPoint(x: 0, y: -8),
                radius: 12,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.addQuadCurve(to: CGPoint(x: 0, y: 16), control: CGPoint(x: 12, y: 6))
            path.closeSubpath()
        }
        local.fill(drop, with: .color(KonumumProximity.door.tint))
        local.stroke(drop, with: .color(.white.opacity(0.55)), lineWidth: 1.4)
        local.fill(Path(ellipseIn: CGRect(x: -5, y: -13, width: 10, height: 10)), with: .color(.white.opacity(0.92)))
    }

    private func drawCar(_ context: inout GraphicsContext, at origin: CGPoint) {
        var local = context
        local.translateBy(x: origin.x, y: origin.y)
        local.fill(Path(ellipseIn: CGRect(x: -16, y: -10, width: 32, height: 24)), with: .color(KonumumTheme.neon.opacity(0.22)))
        let body = Path(roundedRect: CGRect(x: -11, y: -7, width: 22, height: 12), cornerRadius: 3)
        local.fill(body, with: .color(KonumumTheme.neon))
        local.fill(Path(roundedRect: CGRect(x: -7, y: -5, width: 10, height: 6), cornerRadius: 1.5), with: .color(KonumumTheme.ink.opacity(0.55)))
        local.fill(Path(ellipseIn: CGRect(x: -9, y: 3, width: 5, height: 5)), with: .color(Color.white.opacity(0.85)))
        local.fill(Path(ellipseIn: CGRect(x: 4, y: 3, width: 5, height: 5)), with: .color(Color.white.opacity(0.85)))
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
}

#Preview {
    NavigationStack {
        SurucuNavigasyonCarPlayView(
            route: CarConsoleRoute(
                restaurantName: "McDonald's",
                destinationTitle: "McDonald's - Bulvar/Samsun Şubesi",
                plate: "34 KNM 55",
                paymentTitle: "Metropol Card",
                lines: [KitchenOrderLine(name: "Big Mac", quantity: 1, unitPrice: 215)]
            )
        )
    }
    .environmentObject(KonumumDirectory())
}
