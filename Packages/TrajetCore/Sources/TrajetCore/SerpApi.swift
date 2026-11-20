import Foundation

/// Google Flights en temps réel via SerpApi (250 recherches gratuites par mois).
public struct SerpApiClient: Sendable {
    public let key: String
    public let http: HTTPClient

    public init(key: String, http: HTTPClient) {
        self.key = key
        self.http = http
    }

    public struct Account: Sendable, Decodable {
        public let searchesPerMonth: Int?
        public let planSearchesLeft: Int?
        public let totalSearchesLeft: Int?
        public let thisMonthUsage: Int?
    }

    public struct FlightResult: Sendable {
        /// Prix total pour tous les voyageurs (€), nil si aucun vol.
        public let totalPrice: Double?
        public let detail: String
        public let googleFlightsURL: URL?
    }

    struct Response: Decodable {
        let bestFlights: [Option]?
        let otherFlights: [Option]?
        let priceInsights: Insights?
        let searchMetadata: Metadata?
        let error: String?

        struct Option: Decodable {
            let price: Double?
            let totalDuration: Int?
            let flights: [Segment]?
        }
        struct Segment: Decodable {
            let airline: String?
            let flightNumber: String?
            let departureAirport: Airport?
            let arrivalAirport: Airport?
        }
        struct Airport: Decodable {
            let id: String?
            let time: String?
        }
        struct Insights: Decodable {
            let lowestPrice: Double?
        }
        struct Metadata: Decodable {
            let googleFlightsUrl: String?
            let status: String?
        }
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    public static func parse(_ data: Data) throws -> FlightResult {
        let response = try decoder().decode(Response.self, from: data)
        let url = response.searchMetadata?.googleFlightsUrl.flatMap { URL(string: $0) }
        if let error = response.error {
            if error.localizedCaseInsensitiveContains("returned any results") {
                return FlightResult(totalPrice: nil, detail: "aucun vol trouvé par Google Flights", googleFlightsURL: url)
            }
            throw APIError.api(error)
        }
        let options = (response.bestFlights ?? []) + (response.otherFlights ?? [])
        let priced = options.filter { ($0.price ?? 0) > 0 }
        guard let best = priced.min(by: { ($0.price ?? .infinity) < ($1.price ?? .infinity) }) else {
            let lowest = response.priceInsights?.lowestPrice
            return FlightResult(totalPrice: lowest, detail: lowest == nil ? "aucun prix" : "prix le plus bas signalé",
                                googleFlightsURL: url)
        }
        return FlightResult(totalPrice: best.price, detail: describe(best), googleFlightsURL: url)
    }

    static func describe(_ option: Response.Option) -> String {
        let segments = option.flights ?? []
        var airlines: [String] = []
        for name in segments.compactMap(\.airline) where !airlines.contains(name) {
            airlines.append(name)
        }
        let route = ([segments.first?.departureAirport?.id] + segments.map { $0.arrivalAirport?.id })
            .compactMap { $0 }.joined(separator: "-")
        var parts: [String] = []
        if !airlines.isEmpty { parts.append(airlines.joined(separator: " + ")) }
        if !route.isEmpty { parts.append(route) }
        if let time = segments.first?.departureAirport?.time { parts.append("départ \(time)") }
        if let minutes = option.totalDuration { parts.append(Fmt.duration(minutes)) }
        return parts.joined(separator: " · ")
    }

    func search(_ items: [URLQueryItem], label: String) async throws -> FlightResult {
        var components = URLComponents(string: "https://serpapi.com/search.json")!
        components.queryItems = [
            URLQueryItem(name: "engine", value: "google_flights"),
            URLQueryItem(name: "hl", value: "fr"),
            URLQueryItem(name: "gl", value: "fr"),
            URLQueryItem(name: "currency", value: "EUR"),
            URLQueryItem(name: "deep_search", value: "true"),
            URLQueryItem(name: "api_key", value: key),
        ] + items
        let data = try await http.get(components.url!, label: label, timeout: 90)
        return try Self.parse(data)
    }

    public func roundTrip(from: AirportCode, to: AirportCode, out: Day, back: Day, adults: Int) async throws -> FlightResult {
        try await search([
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "departure_id", value: from.serpapi),
            URLQueryItem(name: "arrival_id", value: to.serpapi),
            URLQueryItem(name: "outbound_date", value: out.key),
            URLQueryItem(name: "return_date", value: back.key),
            URLQueryItem(name: "adults", value: String(adults)),
        ], label: "SerpApi AR \(from.code)-\(to.code) \(out.key)/\(back.key)")
    }

    public func oneWay(from: AirportCode, to: AirportCode, day: Day, adults: Int) async throws -> FlightResult {
        try await search([
            URLQueryItem(name: "type", value: "2"),
            URLQueryItem(name: "departure_id", value: from.serpapi),
            URLQueryItem(name: "arrival_id", value: to.serpapi),
            URLQueryItem(name: "outbound_date", value: day.key),
            URLQueryItem(name: "adults", value: String(adults)),
        ], label: "SerpApi aller \(from.code)-\(to.code) \(day.key)")
    }

    public func account() async throws -> Account {
        var components = URLComponents(string: "https://serpapi.com/account.json")!
        components.queryItems = [URLQueryItem(name: "api_key", value: key)]
        let data = try await http.get(components.url!, label: "SerpApi quota")
        return try Self.decoder().decode(Account.self, from: data)
    }
}
