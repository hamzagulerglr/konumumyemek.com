import Foundation
import UserNotifications

@MainActor
@Observable
final class FocusTimer {
    var mode: SessionMode = .focus
    var phase: TimerPhase = .idle
    var remaining: TimeInterval
    var total: TimeInterval
    var sessions: [CompletedSession] = []
    var settings: TimerSettings {
        didSet {
            persistSettings()
            if phase == .idle {
                resetClock()
            }
        }
    }

    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var sessionStart: Date?
    @ObservationIgnored private var completedFocusCount = 0
    @ObservationIgnored private let store = SessionStore()
    @ObservationIgnored private let settingsKey = "lumen.settings.v1"

    init() {
        let loaded: TimerSettings
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(TimerSettings.self, from: data) {
            loaded = decoded
        } else {
            loaded = .default
        }
        let duration = loaded.duration(for: .focus)
        remaining = duration
        total = duration
        settings = loaded
        sessions = store.load()
        completedFocusCount = Self.focusCount(in: sessions, on: .now)
    }

    var progress: Double {
        guard total > 0 else { return 0 }
        return 1 - (remaining / total)
    }

    var displayTime: String {
        let seconds = max(0, Int(remaining.rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var todayMinutes: Int {
        sessions
            .filter { Calendar.current.isDateInToday($0.startedAt) && $0.mode == .focus && $0.completed }
            .reduce(0) { $0 + $1.minutes }
    }

    var todayFocusCount: Int {
        sessions.filter { Calendar.current.isDateInToday($0.startedAt) && $0.mode == .focus && $0.completed }.count
    }

    var isRunning: Bool { phase == .running }

    func select(_ newMode: SessionMode) {
        guard phase != .running else { return }
        mode = newMode
        resetClock()
        phase = .idle
    }

    func toggle() {
        switch phase {
        case .idle, .paused:
            start()
        case .running:
            pause()
        }
    }

    func start() {
        if phase == .idle {
            sessionStart = Date()
            remaining = settings.duration(for: mode)
            total = remaining
        }
        phase = .running
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        if let ticker {
            RunLoop.main.add(ticker, forMode: .common)
        }
    }

    func pause() {
        ticker?.invalidate()
        ticker = nil
        phase = .paused
    }

    func skip() {
        guard phase != .idle else { return }
        finish(completed: false)
    }

    func reset() {
        ticker?.invalidate()
        ticker = nil
        phase = .idle
        sessionStart = nil
        resetClock()
    }

    func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 {
            remaining = 0
            finish(completed: true)
        }
    }

    private func finish(completed: Bool) {
        ticker?.invalidate()
        ticker = nil
        let started = sessionStart ?? Date()
        let elapsed = settings.duration(for: mode) - remaining
        let record = CompletedSession(
            id: UUID(),
            mode: mode,
            startedAt: started,
            duration: max(elapsed, completed ? settings.duration(for: mode) : elapsed),
            completed: completed
        )
        sessions.insert(record, at: 0)
        if sessions.count > 200 {
            sessions = Array(sessions.prefix(200))
        }
        store.save(sessions)

        if completed && mode == .focus {
            completedFocusCount += 1
        }

        if completed && settings.notifyOnComplete {
            notifyCompletion()
        }

        let next = nextMode(afterCompleted: completed)
        mode = next
        phase = .idle
        sessionStart = nil
        resetClock()

        if completed && settings.autoStartNext {
            start()
        }
    }

    private func nextMode(afterCompleted completed: Bool) -> SessionMode {
        guard completed else { return mode }
        switch mode {
        case .focus:
            if completedFocusCount > 0, completedFocusCount % settings.sessionsUntilLongBreak == 0 {
                return .longBreak
            }
            return .shortBreak
        case .shortBreak, .longBreak:
            return .focus
        }
    }

    private func resetClock() {
        total = settings.duration(for: mode)
        remaining = total
    }

    private func persistSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func notifyCompletion() {
        let content = UNMutableNotificationContent()
        content.title = "\(mode.title) bitti"
        content.body = "Lumen sıradaki ritme hazır."
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    private static func focusCount(in sessions: [CompletedSession], on date: Date) -> Int {
        sessions.filter {
            Calendar.current.isDate($0.startedAt, inSameDayAs: date) && $0.mode == .focus && $0.completed
        }.count
    }
}
