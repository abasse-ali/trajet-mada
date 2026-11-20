import Foundation
import Observation

public enum LogLevel: String, Codable, Sendable, CaseIterable, Identifiable {
    case debug
    case info
    case warning
    case error

    public var id: String { rawValue }
    public var rank: Int {
        switch self {
        case .debug: return 0
        case .info: return 1
        case .warning: return 2
        case .error: return 3
        }
    }
    public var label: String {
        switch self {
        case .debug: return "Détail"
        case .info: return "Info"
        case .warning: return "Alerte"
        case .error: return "Erreur"
        }
    }
}

public enum LogCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case app
    case api
    case scan
    case engine

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .app: return "App"
        case .api: return "API"
        case .scan: return "Scan"
        case .engine: return "Calcul"
        }
    }
}

public struct LogEntry: Codable, Sendable, Identifiable {
    public let id: UUID
    public let date: Date
    public let level: LogLevel
    public let category: LogCategory
    public let message: String
    public let details: String?
}

/// Journal de l'app : en mémoire pour l'interface et sur disque (JSON par ligne).
@Observable
@MainActor
public final class LogStore {
    public private(set) var entries: [LogEntry] = []
    private let fileURL: URL?
    private let maxEntries = 3000

    public init(fileURL: URL? = LogStore.defaultFileURL()) {
        self.fileURL = fileURL
        if let url = fileURL, let text = try? String(contentsOf: url, encoding: .utf8) {
            let decoder = Self.decoder()
            let loaded = text.split(separator: "\n").compactMap { line in
                try? decoder.decode(LogEntry.self, from: Data(line.utf8))
            }
            entries = Array(loaded.suffix(maxEntries))
        }
    }

    public nonisolated static func defaultFileURL() -> URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("journal.jsonl")
    }

    nonisolated static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    nonisolated static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    // MARK: - Écriture (appelable depuis n'importe quel fil)

    public nonisolated func log(_ level: LogLevel, _ category: LogCategory, _ message: String, details: String? = nil) {
        let entry = LogEntry(id: UUID(), date: Date(), level: level, category: category, message: message, details: details)
        Task { @MainActor in self.append(entry) }
    }

    public nonisolated func debug(_ category: LogCategory, _ message: String, details: String? = nil) {
        log(.debug, category, message, details: details)
    }

    public nonisolated func info(_ category: LogCategory, _ message: String, details: String? = nil) {
        log(.info, category, message, details: details)
    }

    public nonisolated func warning(_ category: LogCategory, _ message: String, details: String? = nil) {
        log(.warning, category, message, details: details)
    }

    public nonisolated func error(_ category: LogCategory, _ message: String, details: String? = nil) {
        log(.error, category, message, details: details)
    }

    func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries + 300 {
            entries.removeFirst(entries.count - maxEntries)
            rewriteFile()
        } else {
            appendToFile(entry)
        }
    }

    private func appendToFile(_ entry: LogEntry) {
        guard let url = fileURL, var data = try? Self.encoder().encode(entry) else { return }
        data.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func rewriteFile() {
        guard let url = fileURL else { return }
        let encoder = Self.encoder()
        var data = Data()
        for entry in entries {
            if let line = try? encoder.encode(entry) {
                data.append(line)
                data.append(0x0A)
            }
        }
        try? data.write(to: url, options: .atomic)
    }

    public func clear() {
        entries.removeAll()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        info(.app, "Journal effacé")
    }

    public var errorCount: Int { entries.filter { $0.level == .error }.count }

    /// Texte lisible pour partager ou copier le journal.
    public func exportText(_ list: [LogEntry]? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return (list ?? entries).map { entry in
            var line = "\(formatter.string(from: entry.date)) [\(entry.level.label.uppercased())] [\(entry.category.label)] \(entry.message)"
            if let details = entry.details, !details.isEmpty {
                line += "\n    " + details.replacingOccurrences(of: "\n", with: "\n    ")
            }
            return line
        }.joined(separator: "\n")
    }
}
