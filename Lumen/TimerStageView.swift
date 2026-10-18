import SwiftUI

struct TimerStageView: View {
    @Environment(FocusTimer.self) private var timer

    var body: some View {
        ZStack {
            LumenAtmosphere(mode: timer.mode, progress: timer.progress, running: timer.isRunning)

            VStack(spacing: 28) {
                Spacer()

                Text(timer.mode.title.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(4.5)
                    .foregroundStyle(LumenTheme.glow(for: timer.mode).opacity(0.92))

                ZStack {
                    TimerRing(progress: timer.progress, tint: LumenTheme.glow(for: timer.mode), running: timer.isRunning)
                        .frame(width: 300, height: 300)

                    VStack(spacing: 8) {
                        Text(timer.displayTime)
                            .font(.system(size: 68, weight: .light, design: .serif))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                        Text(statusLabel)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .tracking(1.2)
                            .foregroundStyle(LumenTheme.mist)
                    }
                }

                HStack(spacing: 12) {
                    ControlButton(
                        title: timer.isRunning ? "Duraklat" : "Başlat",
                        symbol: timer.isRunning ? "pause.fill" : "play.fill",
                        prominent: true
                    ) {
                        timer.toggle()
                    }

                    ControlButton(title: "Sıfırla", symbol: "arrow.counterclockwise") {
                        timer.reset()
                    }

                    ControlButton(title: "Atla", symbol: "forward.end.fill") {
                        timer.skip()
                    }
                    .opacity(timer.phase == .idle ? 0.4 : 1)
                    .disabled(timer.phase == .idle)
                }

                Text("Boşluk başlatır  ·  ⌘R sıfırlar  ·  ⌘→ atlar")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.34))
                    .padding(.bottom, 10)

                Spacer()
            }
            .padding(40)
        }
        .frame(minWidth: 560, minHeight: 520)
    }

    private var statusLabel: String {
        switch timer.phase {
        case .idle: return "hazır"
        case .running: return "akışta"
        case .paused: return "duraklatıldı"
        }
    }
}

private struct ControlButton: View {
    let title: String
    let symbol: String
    var prominent: Bool = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .padding(.horizontal, prominent ? 24 : 16)
            .padding(.vertical, 11)
            .background(
                Capsule(style: .continuous)
                    .fill(prominent ? LumenTheme.amber : Color.white.opacity(hovering ? 0.12 : 0.07))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(prominent ? 0.18 : 0.08), lineWidth: 1)
            )
            .shadow(color: prominent ? LumenTheme.amber.opacity(0.28) : .clear, radius: 16, y: 6)
            .foregroundStyle(prominent ? Color.black.opacity(0.84) : Color.white.opacity(0.92))
            .scaleEffect(hovering ? 1.02 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
    }
}

private struct TimerRing: View {
    let progress: Double
    let tint: Color
    let running: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: 11)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    AngularGradient(
                        colors: [tint, LumenTheme.gold.opacity(0.85), tint.opacity(0.25)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 11, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(running ? 0.5 : 0.18), radius: running ? 18 : 8)
                .animation(.easeInOut(duration: 0.35), value: progress)
        }
    }
}
