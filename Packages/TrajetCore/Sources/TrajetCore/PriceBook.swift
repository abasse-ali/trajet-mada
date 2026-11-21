import Foundation

public enum QuoteSource: String, Codable, Sendable {
    case travelpayouts
    case serpapi
    case flixbus
    case sncf

    /// Prix vérifié à l'instant (et non tiré d'un cache ou d'une grille).
    public var isLive: Bool { self == .serpapi || self == .flixbus }

    public var label: String {
        switch self {
        case .travelpayouts: return "Aviasales (prix vus récemment)"
        case .serpapi: return "Google Flights"
        case .flixbus: return "FlixBus"
        case .sncf: return "SNCF open data"
        }
    }
}

public struct Quote: Codable, Sendable {
    /// Prix par personne (€).
    public let price: Double
    public let source: QuoteSource
    public let carrier: String?
    public let transfers: Int?
    public let detail: String?
    public let link: URL?
    public let fetchedAt: Date

    public init(price: Double, source: QuoteSource, carrier: String? = nil, transfers: Int? = nil,
                detail: String? = nil, link: URL? = nil, fetchedAt: Date = Date()) {
        self.price = price
        self.source = source
        self.carrier = carrier
        self.transfers = transfers
        self.detail = detail
        self.link = link
        self.fetchedAt = fetchedAt
    }
}

/// Tous les prix récupérés, par trajet orienté (« PAR>TNR ») puis par jour ou paire de jours.
public struct PriceBook: Codable, Sendable {
    public var oneWay: [String: [String: Quote]] = [:]
    /// Clé de second niveau : « AAAA-MM-JJ|AAAA-MM-JJ » (aller|retour).
    public var roundTrip: [String: [String: Quote]] = [:]
    public var bus: [String: [String: Quote]] = [:]
    /// Grilles officielles SNCF par identifiant d'option (« tgv », « ouigo », « intercites-nuit »).
    public var trainGrid: [String: FareRange] = [:]
    public var lastScan: Date?

    public init() {}

    enum CodingKeys: String, CodingKey {
        case oneWay, roundTrip, bus, trainGrid, lastScan
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        oneWay = try c.decodeIfPresent([String: [String: Quote]].self, forKey: .oneWay) ?? [:]
        roundTrip = try c.decodeIfPresent([String: [String: Quote]].self, forKey: .roundTrip) ?? [:]
        bus = try c.decodeIfPresent([String: [String: Quote]].self, forKey: .bus) ?? [:]
        trainGrid = try c.decodeIfPresent([String: FareRange].self, forKey: .trainGrid) ?? [:]
        lastScan = try c.decodeIfPresent(Date.self, forKey: .lastScan)
    }

    public static func key(_ from: PlaceID, _ to: PlaceID) -> String { "\(from.rawValue)>\(to.rawValue)" }
    public static func pairKey(_ out: Day, _ back: Day) -> String { "\(out.key)|\(back.key)" }

    public var isEmpty: Bool { oneWay.isEmpty && roundTrip.isEmpty && bus.isEmpty }

    public var counts: (oneWay: Int, roundTrip: Int, bus: Int) {
        (oneWay.values.reduce(0) { $0 + $1.count },
         roundTrip.values.reduce(0) { $0 + $1.count },
         bus.values.reduce(0) { $0 + $1.count })
    }

    /// Règles de remplacement :
    /// - un prix vérifié (Google Flights, FlixBus) l'emporte sur un prix en cache, sauf s'il a plus de 2 jours de retard ;
    /// - entre deux prix de même nature, le plus récent l'emporte ;
    /// - dans un même relevé (moins d'une heure d'écart), on garde le moins cher.
    public mutating func put(_ quote: Quote, in store: WritableKeyPath<PriceBook, [String: [String: Quote]]>,
                             key: String, sub: String) {
        if let current = self[keyPath: store][key]?[sub] {
            let newer = quote.fetchedAt.timeIntervalSince(current.fetchedAt)
            if quote.source.isLive != current.source.isLive {
                if current.source.isLive && newer < 172_800 { return }
                if !current.source.isLive && newer < -172_800 { return }
            } else if abs(newer) < 3600 {
                if current.price <= quote.price { return }
            } else if newer < 0 {
                return
            }
        }
        self[keyPath: store][key, default: [:]][sub] = quote
    }

    public mutating func putOneWay(_ quote: Quote, from: PlaceID, to: PlaceID, day: Day) {
        put(quote, in: \.oneWay, key: Self.key(from, to), sub: day.key)
    }

    public mutating func putRoundTrip(_ quote: Quote, from: PlaceID, to: PlaceID, out: Day, back: Day) {
        put(quote, in: \.roundTrip, key: Self.key(from, to), sub: Self.pairKey(out, back))
    }

    public mutating func putBus(_ quote: Quote, from: PlaceID, to: PlaceID, day: Day) {
        put(quote, in: \.bus, key: Self.key(from, to), sub: day.key)
    }

    /// Prix médian observé par trajet et par mois (« PAR>TNR#2027-05 ») et par trajet.
    /// Sert d'estimation réaliste les jours sans prix connu. Un aller-retour réel compte pour
    /// moitié dans chaque sens (965 € Paris ⇄ Nosy Be donne environ 483 € par trajet).
    public func calibration() -> [String: Double] {
        var buckets: [String: [Double]] = [:]
        for (route, days) in oneWay {
            for (day, quote) in days where quote.price > 0 {
                buckets["\(route)#\(day.prefix(7))", default: []].append(quote.price)
                buckets[route, default: []].append(quote.price)
            }
        }
        for (route, pairs) in roundTrip {
            let ends = route.split(separator: ">").map(String.init)
            guard ends.count == 2 else { continue }
            let reverse = "\(ends[1])>\(ends[0])"
            for (pair, quote) in pairs where quote.price > 0 {
                let days = pair.split(separator: "|").map(String.init)
                guard days.count == 2 else { continue }
                let half = quote.price / 2
                buckets["\(route)#\(days[0].prefix(7))", default: []].append(half)
                buckets["\(reverse)#\(days[1].prefix(7))", default: []].append(half)
                buckets[route, default: []].append(half)
                buckets[reverse, default: []].append(half)
            }
        }
        return buckets.mapValues { values in
            let sorted = values.sorted()
            return sorted[sorted.count / 2]
        }
    }
}
