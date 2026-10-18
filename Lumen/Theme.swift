import SwiftUI

enum LumenTheme {
    static let amber = Color(red: 0.96, green: 0.74, blue: 0.38)
    static let gold = Color(red: 1.0, green: 0.88, blue: 0.62)
    static let ink = Color(red: 0.055, green: 0.055, blue: 0.06)
    static let mist = Color.white.opacity(0.58)
    static let panel = Color.white.opacity(0.045)

    static func glow(for mode: SessionMode) -> Color {
        switch mode {
        case .focus: return amber
        case .shortBreak: return Color(red: 0.55, green: 0.80, blue: 0.86)
        case .longBreak: return Color(red: 0.70, green: 0.64, blue: 0.94)
        }
    }

    static func meshColors(for mode: SessionMode, running: Bool) -> [Color] {
        let accent = glow(for: mode).opacity(running ? 0.62 : 0.28)
        let warm = Color(red: 0.12, green: 0.09, blue: 0.055)
        let cool = Color(red: 0.06, green: 0.07, blue: 0.09)
        return [
            ink, warm, cool,
            warm, accent, cool,
            Color(red: 0.03, green: 0.03, blue: 0.04),
            warm.opacity(0.8),
            ink
        ]
    }
}
