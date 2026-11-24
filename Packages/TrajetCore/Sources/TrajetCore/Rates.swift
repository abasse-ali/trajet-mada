import Foundation

/// Taux de change réel euro/ariary (open.er-api.com, gratuit, sans clé, mis à jour chaque jour).
public struct ExchangeRateClient: Sendable {
    public let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    struct Response: Decodable {
        let result: String?
        let timeLastUpdateUnix: Double?
        let rates: [String: Double]?
    }

    /// (ariary pour 1 euro, date de mise à jour du taux)
    public static func parse(_ data: Data) throws -> (rate: Double, date: Date) {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)
        guard response.result == "success", let rate = response.rates?["MGA"], rate > 0 else {
            throw APIError.api("taux euro/ariary indisponible")
        }
        return (rate, response.timeLastUpdateUnix.map { Date(timeIntervalSince1970: $0) } ?? Date())
    }

    public func euroToAriary() async throws -> (rate: Double, date: Date) {
        let data = try await http.get(URL(string: "https://open.er-api.com/v6/latest/EUR")!, label: "Taux de change euro/ariary")
        return try Self.parse(data)
    }
}

extension Collector {
    /// Enregistre les prix d'un calendrier Google Flights dans le carnet de prix. Renvoie le nombre de prix.
    @discardableResult
    public static func store(_ prices: [SerpApiClient.CalendarPrice], for job: CalendarJob, adults: Int,
                             into book: inout PriceBook, at date: Date = Date()) -> Int {
        var count = 0
        let perPerson = Double(max(1, adults))
        for entry in prices {
            let quote = Quote(price: entry.price / perPerson, source: .serpapi, detail: "Google Flights, calendrier des prix",
                              link: nil, fetchedAt: date)
            if job.stay != nil {
                guard let back = entry.back else { continue }
                book.putRoundTrip(quote, from: job.from, to: job.to, out: entry.out, back: back)
            } else {
                book.putOneWay(quote, from: job.from, to: job.to, day: entry.out)
            }
            count += 1
        }
        book.markCalendar(job.key, at: date)
        return count
    }
}
