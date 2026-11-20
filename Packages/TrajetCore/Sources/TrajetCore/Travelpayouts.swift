import Foundation

public enum APIError: LocalizedError {
    case api(String)
    case missingKey(String)

    public var errorDescription: String? {
        switch self {
        case .api(let message): return message
        case .missingKey(let name): return "Clé \(name) manquante (onglet Réglages)"
        }
    }
}

/// API Data d'Aviasales (Travelpayouts) : prix vus par les utilisateurs ces derniers jours.
public struct TravelpayoutsClient: Sendable {
    public let token: String
    public let http: HTTPClient

    public init(token: String, http: HTTPClient) {
        self.token = token
        self.http = http
    }

    public struct Ticket: Decodable, Sendable {
        public let price: Double?
        public let airline: String?
        public let flightNumber: String?
        public let departureAt: String?
        public let returnAt: String?
        public let transfers: Int?
        public let returnTransfers: Int?
        public let link: String?

        enum CodingKeys: String, CodingKey {
            case price, airline, flightNumber, departureAt, returnAt, transfers, returnTransfers, link
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            price = (try? c.decode(Double.self, forKey: .price)) ?? nil
            airline = (try? c.decode(String.self, forKey: .airline)) ?? nil
            if let text = try? c.decode(String.self, forKey: .flightNumber) {
                flightNumber = text
            } else if let number = try? c.decode(Int.self, forKey: .flightNumber) {
                flightNumber = String(number)
            } else {
                flightNumber = nil
            }
            departureAt = (try? c.decode(String.self, forKey: .departureAt)) ?? nil
            returnAt = (try? c.decode(String.self, forKey: .returnAt)) ?? nil
            transfers = (try? c.decode(Int.self, forKey: .transfers)) ?? nil
            returnTransfers = (try? c.decode(Int.self, forKey: .returnTransfers)) ?? nil
            link = (try? c.decode(String.self, forKey: .link)) ?? nil
        }
    }

    struct Response: Decodable {
        let success: Bool?
        let data: [Ticket]?
        let error: String?
    }

    public static func decode(_ data: Data) throws -> [Ticket] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)
        if response.success == false { throw APIError.api(response.error ?? "réponse Travelpayouts invalide") }
        return response.data ?? []
    }

    /// `returnMonth` nil = aller simple.
    public func prices(origin: String, destination: String, month: String, returnMonth: String?) async throws -> [Ticket] {
        var components = URLComponents(string: "https://api.travelpayouts.com/aviasales/v3/prices_for_dates")!
        var items = [
            URLQueryItem(name: "origin", value: origin),
            URLQueryItem(name: "destination", value: destination),
            URLQueryItem(name: "departure_at", value: month),
            URLQueryItem(name: "one_way", value: returnMonth == nil ? "true" : "false"),
            URLQueryItem(name: "direct", value: "false"),
            URLQueryItem(name: "currency", value: "eur"),
            URLQueryItem(name: "sorting", value: "price"),
            URLQueryItem(name: "limit", value: "1000"),
            URLQueryItem(name: "token", value: token),
        ]
        if let returnMonth { items.append(URLQueryItem(name: "return_at", value: returnMonth)) }
        components.queryItems = items
        let label = returnMonth == nil
            ? "Travelpayouts \(origin)-\(destination) aller \(month)"
            : "Travelpayouts \(origin)-\(destination) AR \(month)/\(returnMonth!)"
        let data = try await http.get(components.url!, label: label)
        return try Self.decode(data)
    }
}

public struct ScanTask: Sendable, Hashable {
    public let from: PlaceID
    public let to: PlaceID
    public let month: String
    public let returnMonth: String?
}

public struct ScanStats: Sendable {
    public var requests = 0
    public var failures = 0
    public var oneWayQuotes = 0
    public var roundTripQuotes = 0
    public var seconds = 0.0
    public var errors: [String] = []
    public var perRoute: [String: Int] = [:]

    public var summary: String {
        "Scan Travelpayouts : \(requests) requêtes, \(failures) échec(s), "
            + "\(oneWayQuotes) prix aller simple et \(roundTripQuotes) prix aller-retour en \(Int(seconds)) s"
    }

    public var details: String {
        let routes = perRoute.sorted { $0.key < $1.key }.map { "\($0.key) : \($0.value) prix" }.joined(separator: "\n")
        let errs = errors.prefix(20).joined(separator: "\n")
        return routes + (errs.isEmpty ? "" : "\n\nErreurs :\n" + errs)
    }
}

/// Parcourt tous les vols du réseau sur la période (allers simples et allers-retours).
public struct TravelpayoutsScanner: Sendable {
    public let client: TravelpayoutsClient

    public init(client: TravelpayoutsClient) {
        self.client = client
    }

    public static func plan(params: SearchParams, network: FilteredNetwork) -> [ScanTask] {
        let months = params.months
        var tasks: [ScanTask] = []
        for connection in network.connections where connection.options.contains(where: { $0.kind == .flight }) {
            guard NetworkData.place(connection.a).airport != nil, NetworkData.place(connection.b).airport != nil else { continue }
            for month in months {
                tasks.append(ScanTask(from: connection.a, to: connection.b, month: month, returnMonth: nil))
                tasks.append(ScanTask(from: connection.b, to: connection.a, month: month, returnMonth: nil))
            }
            for (i, month) in months.enumerated() {
                tasks.append(ScanTask(from: connection.a, to: connection.b, month: month, returnMonth: month))
                if i + 1 < months.count {
                    tasks.append(ScanTask(from: connection.a, to: connection.b, month: month, returnMonth: months[i + 1]))
                }
            }
        }
        return tasks
    }

    public func run(_ tasks: [ScanTask], into base: PriceBook,
                    progress: @escaping @Sendable (Int, Int) -> Void) async -> (PriceBook, ScanStats) {
        let started = Date()
        let limiter = RateLimiter(interval: 0.12)
        let client = self.client
        let counter = Counter()
        let total = tasks.count
        let outcomes: [ScanOutcome] = await boundedConcurrentMap(tasks, limit: 4) { task in
            await limiter.wait()
            let origin = NetworkData.place(task.from).airport!.code
            let destination = NetworkData.place(task.to).airport!.code
            var outcome: ScanOutcome
            do {
                let tickets = try await client.prices(origin: origin, destination: destination,
                                                      month: task.month, returnMonth: task.returnMonth)
                outcome = ScanOutcome(task: task, tickets: tickets, error: nil)
            } catch HTTPError.status(429, _) {
                // Trop de requêtes : une seconde tentative après 2 s.
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                do {
                    let tickets = try await client.prices(origin: origin, destination: destination,
                                                          month: task.month, returnMonth: task.returnMonth)
                    outcome = ScanOutcome(task: task, tickets: tickets, error: nil)
                } catch {
                    outcome = ScanOutcome(task: task, tickets: [], error: error.localizedDescription)
                }
            } catch {
                outcome = ScanOutcome(task: task, tickets: [], error: error.localizedDescription)
            }
            let done = await counter.increment()
            progress(done, total)
            return outcome
        }

        var book = base
        var stats = ScanStats()
        stats.requests = tasks.count
        let now = Date()
        for outcome in outcomes {
            let task = outcome.task
            let route = PriceBook.key(task.from, task.to)
            if let error = outcome.error {
                stats.failures += 1
                stats.errors.append("\(route) \(task.month)\(task.returnMonth.map { "/" + $0 } ?? "") : \(error)")
            } else {
                for ticket in outcome.tickets {
                    guard let price = ticket.price, price > 0,
                          let departure = ticket.departureAt.flatMap(Day.init(isoPrefix:)) else { continue }
                    let detail = Self.describe(ticket)
                    let link = ticket.link.flatMap { URL(string: "https://www.aviasales.com" + $0) }
                    let quote = Quote(price: price, source: .travelpayouts, carrier: ticket.airline,
                                      transfers: ticket.transfers, detail: detail, link: link, fetchedAt: now)
                    if task.returnMonth != nil {
                        guard let back = ticket.returnAt.flatMap(Day.init(isoPrefix:)) else { continue }
                        book.putRoundTrip(quote, from: task.from, to: task.to, out: departure, back: back)
                        stats.roundTripQuotes += 1
                    } else {
                        book.putOneWay(quote, from: task.from, to: task.to, day: departure)
                        stats.oneWayQuotes += 1
                    }
                    stats.perRoute[route, default: 0] += 1
                }
            }
        }
        book.lastScan = now
        stats.seconds = Date().timeIntervalSince(started)
        return (book, stats)
    }

    static func describe(_ t: TravelpayoutsClient.Ticket) -> String {
        var parts: [String] = []
        if let airline = t.airline { parts.append(airline + (t.flightNumber.map { " \($0)" } ?? "")) }
        if let transfers = t.transfers {
            parts.append(transfers == 0 ? "direct" : "\(transfers) escale\(transfers > 1 ? "s" : "")")
        }
        if let back = t.returnTransfers {
            parts.append("retour " + (back == 0 ? "direct" : "\(back) escale\(back > 1 ? "s" : "")"))
        }
        return parts.joined(separator: " · ")
    }
}

struct ScanOutcome: Sendable {
    let task: ScanTask
    let tickets: [TravelpayoutsClient.Ticket]
    let error: String?
}

actor Counter {
    private var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}
