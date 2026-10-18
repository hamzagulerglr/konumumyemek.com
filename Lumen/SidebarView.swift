import SwiftUI

struct SidebarView: View {
    @Environment(FocusTimer.self) private var timer

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("LUMEN")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .tracking(3.4)
                    .foregroundStyle(LumenTheme.amber)
                Text("Bugünün ritmi")
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
            }
            .padding(.top, 22)

            HStack(spacing: 10) {
                StatCard(title: "Odak", value: "\(timer.todayFocusCount)")
                StatCard(title: "Dakika", value: "\(timer.todayMinutes)")
            }

            VStack(spacing: 8) {
                ForEach(SessionMode.allCases) { mode in
                    Button {
                        timer.select(mode)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: mode.symbol)
                                .frame(width: 18)
                            Text(mode.title)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text(minutesLabel(for: mode))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.42))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(timer.mode == mode ? LumenTheme.glow(for: mode).opacity(0.16) : LumenTheme.panel)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(
                                    timer.mode == mode ? LumenTheme.glow(for: mode).opacity(0.5) : Color.white.opacity(0.05),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(timer.mode == mode ? LumenTheme.glow(for: mode) : Color.white.opacity(0.86))
                    .disabled(timer.isRunning && timer.mode != mode)
                }
            }

            Text("Geçmiş")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .padding(.top, 6)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if timer.sessions.isEmpty {
                        Text("Henüz oturum yok. İlk odağı başlatın.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.vertical, 8)
                    } else {
                        ForEach(timer.sessions.prefix(24)) { session in
                            HistoryRow(session: session)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.28))
                .ignoresSafeArea()
        }
    }

    private func minutesLabel(for mode: SessionMode) -> String {
        "\(Int(timer.settings.duration(for: mode) / 60)) dk"
    }
}

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.42))
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(LumenTheme.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct HistoryRow: View {
    let session: CompletedSession

    var body: some View {
        HStack {
            Image(systemName: session.mode.symbol)
                .foregroundStyle(LumenTheme.glow(for: session.mode))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.mode.title)
                    .font(.system(size: 13, weight: .medium))
                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Text(session.completed ? "\(session.minutes) dk" : "yarım")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .foregroundStyle(.white.opacity(0.88))
        .padding(.vertical, 4)
    }
}
