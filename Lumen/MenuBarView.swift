import SwiftUI

struct MenuBarView: View {
    @Environment(FocusTimer.self) private var timer

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: timer.mode.symbol)
                    .foregroundStyle(LumenTheme.glow(for: timer.mode))
                Text(timer.mode.title)
                    .font(.headline)
                Spacer()
            }

            Text(timer.displayTime)
                .font(.system(size: 32, weight: .light, design: .serif))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 8) {
                Button(timer.isRunning ? "Duraklat" : "Başlat") {
                    timer.toggle()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Sıfırla") { timer.reset() }
                Button("Atla") { timer.skip() }
                    .disabled(timer.phase == .idle)
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 248)
        .preferredColorScheme(.dark)
    }

    private var status: String {
        switch timer.phase {
        case .idle: return "Hazır"
        case .running: return "Akışta"
        case .paused: return "Duraklatıldı"
        }
    }
}
