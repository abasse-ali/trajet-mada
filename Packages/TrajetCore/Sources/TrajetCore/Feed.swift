import Foundation

/// Données publiées chaque jour par le serveur (script server/trajetmada_update.py).
public struct DataFeed: Decodable, Sendable {
    public let version: Int
    public let generatedAt: String
    public let period: Period?
    public let oneWay: [Entry]?
    public let roundTrip: [Entry]?
    public let bus: [Entry]?
    public let trainGrid: [String: FareRange]?
    public let schedules: [ScheduleEntry]?
    public let sncfWindow: Period?
    public let stats: [String: Int]?

    public struct Period: Decodable, Sendable {
        public let start: String
        public let end: String
    }

    /// Prix d'un trajet : `day` pour un aller simple, `out` et `back` pour un aller-retour.
    public struct Entry: Decodable, Sendable {
        public let from: String
        public let to: String
        public let day: String?
        public let out: String?
        public let back: String?
        public let price: Double
        public let source: String
        public let carrier: String?
        public let transfers: Int?
        public let detail: String?
        public let link: String?
        public let fetchedAt: String?
    }

    public struct ScheduleEntry: Decodable, Sendable {
        public let from: String
        public let to: String
        public let day: String?
        /// 1 = dimanche … 7 = samedi
        public let weekday: Int
        public let referenceDay: String
        public let exact: Bool
        public let journeys: [JourneyEntry]
    }

    public struct JourneyEntry: Decodable, Sendable {
        public let departure: String
        public let arrival: String
        public let arrivalDayOffset: Int
        public let durationMin: Int
        public let transfers: Int
        public let trains: [String]
        public let modes: [String]
        public let fare: Double?
    }
}

public struct FeedSchedules: Sendable {
    /// Horaires d'un jour précis, clé « TLS_V>PAR_G>2027-05-10 ».
    public var exact: [String: TrainSchedule] = [:]
    /// Horaires types par jour de semaine, clé « TLS_V>PAR_G#2 ».
    public var typical: [String: TrainSchedule] = [:]

    public init() {}

    /// Horaires pour une étape : jour exact s'il est connu, sinon horaires types du même jour de semaine.
    public func schedule(from: PlaceID, to: PlaceID, day: Day) -> TrainSchedule? {
        if let exact = exact["\(from.rawValue)>\(to.rawValue)>\(day.key)"] { return exact }
        guard let typical = typical["\(from.rawValue)>\(to.rawValue)#\(day.weekday)"] else { return nil }
        return TrainSchedule(day: day, referenceDay: typical.referenceDay, exact: false, journeys: typical.journeys)
    }

    public var isEmpty: Bool { exact.isEmpty && typical.isEmpty }
}

public enum FeedReader {
    public static func decode(_ data: Data) throws -> DataFeed {
        let feed = try JSONDecoder().decode(DataFeed.self, from: data)
        guard feed.version == 1 else { throw APIError.api("format de données \(feed.version) non pris en charge") }
        return feed
    }

    static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    public static func generatedDate(_ feed: DataFeed) -> Date? { date(feed.generatedAt) }

    /// Ajoute les prix du serveur au carnet de prix (les prix plus récents ou vérifiés l'emportent).
    public static func merge(_ feed: DataFeed, into base: PriceBook) -> (book: PriceBook, added: Int) {
        var book = base
        var added = 0
        let fallbackDate = generatedDate(feed) ?? Date()

        func quote(_ e: DataFeed.Entry) -> Quote {
            Quote(price: e.price, source: QuoteSource(rawValue: e.source) ?? .travelpayouts, carrier: e.carrier,
                  transfers: e.transfers, detail: e.detail, link: e.link.flatMap { URL(string: $0) },
                  fetchedAt: date(e.fetchedAt) ?? fallbackDate)
        }

        for e in feed.oneWay ?? [] {
            guard let from = PlaceID(rawValue: e.from), let to = PlaceID(rawValue: e.to),
                  let day = e.day.flatMap(Day.init(isoPrefix:)), e.price > 0 else { continue }
            book.putOneWay(quote(e), from: from, to: to, day: day)
            added += 1
        }
        for e in feed.roundTrip ?? [] {
            guard let from = PlaceID(rawValue: e.from), let to = PlaceID(rawValue: e.to),
                  let out = e.out.flatMap(Day.init(isoPrefix:)), let back = e.back.flatMap(Day.init(isoPrefix:)),
                  e.price > 0 else { continue }
            book.putRoundTrip(quote(e), from: from, to: to, out: out, back: back)
            added += 1
        }
        for e in feed.bus ?? [] {
            guard let from = PlaceID(rawValue: e.from), let to = PlaceID(rawValue: e.to),
                  let day = e.day.flatMap(Day.init(isoPrefix:)), e.price > 0 else { continue }
            book.putBus(quote(e), from: from, to: to, day: day)
            added += 1
        }
        if let grid = feed.trainGrid, !grid.isEmpty {
            book.trainGrid = grid
        }
        return (book, added)
    }

    public static func schedules(_ feed: DataFeed) -> FeedSchedules {
        var result = FeedSchedules()
        for entry in feed.schedules ?? [] {
            guard let reference = Day(isoPrefix: entry.referenceDay) else { continue }
            let journeys = entry.journeys.map { j in
                TrainJourney(departure: j.departure, arrival: j.arrival, arrivalDayOffset: j.arrivalDayOffset,
                             durationMin: j.durationMin, transfers: j.transfers, trains: j.trains, modes: j.modes,
                             fare: j.fare)
            }
            if entry.exact, let day = entry.day.flatMap(Day.init(isoPrefix:)) {
                result.exact["\(entry.from)>\(entry.to)>\(day.key)"] =
                    TrainSchedule(day: day, referenceDay: reference, exact: true, journeys: journeys)
            } else {
                result.typical["\(entry.from)>\(entry.to)#\(entry.weekday)"] =
                    TrainSchedule(day: reference, referenceDay: reference, exact: false, journeys: journeys)
            }
        }
        return result
    }
}
