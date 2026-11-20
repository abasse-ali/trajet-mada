import Foundation

public enum HTTPError: LocalizedError {
    case status(Int, String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .status(let code, let body):
            return "HTTP \(code)" + (body.isEmpty ? "" : " : \(body.prefix(160))")
        case .invalidResponse:
            return "RÃ©ponse invalide"
        }
    }
}

/// Masque les clÃ©s d'API dans les URL Ã©crites au journal.
public enum Redact {
    static let secretNames: Set<String> = ["token", "api_key", "apikey", "key"]

    public static func url(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        components.queryItems = components.queryItems?.map { item in
            secretNames.contains(item.name.lowercased()) ? URLQueryItem(name: item.name, value: "***") : item
        }
        return components.url?.absoluteString ?? url.absoluteString
    }
}

/// Client HTTP qui journalise chaque requÃªte (URL sans clÃ©, code, durÃ©e, taille).
public struct HTTPClient: Sendable {
    public let log: LogStore
    public let session: URLSession

    public init(log: LogStore, session: URLSession = .shared) {
        self.log = log
        self.session = session
    }

    public func get(_ url: URL, label: String, timeout: TimeInterval = 30,
                    headers: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let started = Date()
        do {
            let (data, response) = try await session.data(for: request)
            let millis = Int(Date().timeIntervalSince(started) * 1000)
            guard let http = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
                log.error(.api, "\(label) : HTTP \(http.statusCode) (\(millis) ms)", details: "\(Redact.url(url))\n\(body)")
                throw HTTPError.status(http.statusCode, body)
            }
            log.debug(.api, "\(label) : \(http.statusCode), \(millis) ms, \(data.count) octets", details: Redact.url(url))
            return data
        } catch let error as HTTPError {
            throw error
        } catch {
            let millis = Int(Date().timeIntervalSince(started) * 1000)
            log.error(.api, "\(label) : Ã©chec aprÃ¨s \(millis) ms", details: "\(Redact.url(url))\n\(error.localizedDescription)")
            throw error
        }
    }
}

/// Espace les requÃªtes pour respecter les limites des API.
public actor RateLimiter {
    private var nextSlot = Date.distantPast
    private let interval: TimeInterval

    public init(interval: TimeInterval) {
        self.interval = interval
    }

    public func wait() async {
        let now = Date()
        let slot = max(now, nextSlot)
        nextSlot = slot.addingTimeInterval(interval)
        let delay = slot.timeIntervalSince(now)
        if delay > 0 {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
    }
}

/// ExÃ©cute `transform` sur chaque Ã©lÃ©ment avec au plus `limit` tÃ¢ches en parallÃ¨le.
public func boundedConcurrentMap<T: Sendable, R: Sendable>(
    _ items: [T], limit: Int, _ transform: @escaping @Sendable (T) async -> R
) async -> [R] {
    guard !items.isEmpty else { return [] }
    return await withTaskGroup(of: (Int, R).self, returning: [R].self) { group in
        var results = [R?](repeating: nil, count: items.count)
        var next = 0
        while next < min(max(1, limit), items.count) {
            let index = next
            let item = items[index]
            group.addTask { let value = await transform(item); return (index, value) }
            next += 1
        }
        while let finished = await group.next() {
            results[finished.0] = finished.1
            if next < items.count {
                let index = next
                let item = items[index]
                group.addTask { let value = await transform(item); return (index, value) }
                next += 1
            }
        }
        return results.compactMap { $0 }
    }
}
