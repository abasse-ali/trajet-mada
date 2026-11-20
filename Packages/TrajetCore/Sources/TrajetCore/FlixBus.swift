import Foundation

/// Prix FlixBus réels via l'API publique utilisée par leur site (sans clé).
public struct FlixBusClient: Sendable {
    public let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    struct Response: Decodable {
        let trips: [Trip]?
    }
    struct Trip: Decodable {
        let results: [String: Ride]?
    }
    struct Ride: Decodable {
        let status: String?
        let price: Price?
        let departure: Point?
        let arrival: Point?
        let available: Available?
    }
    struct Price: Decodable {
        let total: Double?
    }
    struct Point: Decodable {
        let date: String?
    }
    struct Available: Decodable {
        let seats: Int?
    }

    public struct Offer: Sendable {
        /// Prix total pour tous les voyageurs (€).
        public let total: Double
        public let departure: String?
        public let arrival: String?
        public let seats: Int?
    }

    /// Trajet disponible le moins cher.
    public static func cheapest(_ data: Data) throws -> Offer? {
        let response = try JSONDecoder().decode(Response.self, from: data)
        let rides = (response.trips ?? []).flatMap { ($0.results ?? [:]).values }
        let available = rides.filter { ($0.status ?? "available") == "available" && ($0.price?.total ?? 0) > 0 }
        guard let best = available.min(by: { ($0.price?.total ?? .infinity) < ($1.price?.total ?? .infinity) }),
              let total = best.price?.total else { return nil }
        return Offer(total: total, departure: best.departure?.date, arrival: best.arrival?.date, seats: best.available?.seats)
    }

    public func quote(from: PlaceID, to: PlaceID, day: Day, adults: Int) async throws -> Quote? {
        guard let fromID = NetworkData.place(from).flixbusCityID,
              let toID = NetworkData.place(to).flixbusCityID else { return nil }
        var components = URLComponents(string: "https://global.api.flixbus.com/search/service/v4/search")!
        components.queryItems = [
            URLQueryItem(name: "from_city_id", value: fromID),
            URLQueryItem(name: "to_city_id", value: toID),
            URLQueryItem(name: "departure_date", value: day.dotted),
            URLQueryItem(name: "products", value: "{\"adult\":\(adults)}"),
            URLQueryItem(name: "currency", value: "EUR"),
            URLQueryItem(name: "locale", value: "fr"),
            URLQueryItem(name: "search_by", value: "cities"),
            URLQueryItem(name: "include_after_midnight_rides", value: "1"),
        ]
        let label = "FlixBus \(NetworkData.place(from).short)-\(NetworkData.place(to).short) \(day.key)"
        let data = try await http.get(components.url!, label: label)
        guard let offer = try Self.cheapest(data) else { return nil }
        var parts: [String] = []
        if let dep = offer.departure { parts.append("départ " + String(dep.dropFirst(11).prefix(5))) }
        if let arr = offer.arrival { parts.append("arrivée " + String(arr.dropFirst(11).prefix(5))) }
        if let seats = offer.seats { parts.append("\(seats) places") }
        return Quote(price: offer.total / Double(max(1, adults)), source: .flixbus, carrier: "FlixBus",
                     transfers: nil, detail: parts.joined(separator: " · "),
                     link: LinkBuilder.flixbusURL(fromCity: fromID, toCity: toID, day: day, adults: adults))
    }
}
