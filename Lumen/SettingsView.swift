import SwiftUI

struct SettingsView: View {
    @Environment(FocusTimer.self) private var timer

    var body: some View {
        @Bindable var timer = timer
        Form {
            Section("Süreler") {
                Stepper(value: $timer.settings.focusMinutes, in: 5...90, step: 5) {
                    LabeledContent("Odak", value: "\(timer.settings.focusMinutes) dk")
                }
                Stepper(value: $timer.settings.shortBreakMinutes, in: 1...30, step: 1) {
                    LabeledContent("Kısa mola", value: "\(timer.settings.shortBreakMinutes) dk")
                }
                Stepper(value: $timer.settings.longBreakMinutes, in: 5...45, step: 5) {
                    LabeledContent("Uzun mola", value: "\(timer.settings.longBreakMinutes) dk")
                }
                Stepper(value: $timer.settings.sessionsUntilLongBreak, in: 2...8) {
                    LabeledContent("Uzun moladan önce", value: "\(timer.settings.sessionsUntilLongBreak) odak")
                }
            }

            Section("Davranış") {
                Toggle("Otomatik sonraki oturum", isOn: $timer.settings.autoStartNext)
                Toggle("Bitişte bildirim", isOn: $timer.settings.notifyOnComplete)
            }

            Section("Lumen") {
                LabeledContent("Platform", value: "macOS Sequoia 15+")
                LabeledContent("Dil", value: "Swift / SwiftUI")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
