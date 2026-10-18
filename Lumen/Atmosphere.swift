import SwiftUI

struct LumenAtmosphere: View {
    let mode: SessionMode
    let progress: Double
    let running: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !running)) { timeline in
            mesh(at: timeline.date)
        }
        .ignoresSafeArea()
        .overlay {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.9), value: mode)
    }

    private func mesh(at date: Date) -> MeshGradient {
        let t = Float(date.timeIntervalSinceReferenceDate)
        let wave = sin(t / 4.2) * 0.07
        let lift = Float(progress) * 0.10
        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                .init(0, 0), .init(0.5, 0), .init(1, 0),
                .init(0, 0.5),
                .init(0.5 + wave, 0.48 + lift),
                .init(1, 0.5),
                .init(0, 1), .init(0.5, 1), .init(1, 1)
            ],
            colors: LumenTheme.meshColors(for: mode, running: running)
        )
    }
}
