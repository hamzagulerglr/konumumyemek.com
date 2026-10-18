import Foundation

enum SessionMode: String, Codable, CaseIterable, Identifiable {
    case focus
    case shortBreak
    case longBreak

    var id: String { rawValue }

    var title: String {
        switch self {
        case .focus: return "Odak"
        case .shortBreak: return "Kısa mola"
        case .longBreak: return "Uzun mola"
        }
    }

    var symbol: String {
        switch self {
        case .focus: return "circle.lefthalf.filled"
        case .shortBreak: return "cup.and.saucer"
        case .longBreak: return "leaf"
        }
    }
}

struct CompletedSession: Identifiable, Codable, Hashable {
    var id: UUID
    var mode: SessionMode
    var startedAt: Date
    var duration: TimeInterval
    var completed: Bool

    var minutes: Int { Int(duration / 60) }
}

struct TimerSettings: Codable, Equatable {
    var focusMinutes: Int
    var shortBreakMinutes: Int
    var longBreakMinutes: Int
    var sessionsUntilLongBreak: Int
    var autoStartNext: Bool
    var notifyOnComplete: Bool

    static let `default` = TimerSettings(
        focusMinutes: 25,
        shortBreakMinutes: 5,
        longBreakMinutes: 20,
        sessionsUntilLongBreak: 4,
        autoStartNext: false,
        notifyOnComplete: true
    )

    func duration(for mode: SessionMode) -> TimeInterval {
        switch mode {
        case .focus: return TimeInterval(focusMinutes * 60)
        case .shortBreak: return TimeInterval(shortBreakMinutes * 60)
        case .longBreak: return TimeInterval(longBreakMinutes * 60)
        }
    }
}

enum TimerPhase: Equatable {
    case idle
    case running
    case paused
}
