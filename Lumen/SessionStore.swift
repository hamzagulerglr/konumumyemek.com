import Foundation

@MainActor
final class SessionStore {
    private let fileURL: URL
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lumen", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        fileURL = folder.appendingPathComponent("sessions.json")
    }

    func load() -> [CompletedSession] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? decoder.decode([CompletedSession].self, from: data)) ?? []
    }

    func save(_ sessions: [CompletedSession]) {
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
