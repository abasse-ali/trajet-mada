import Foundation

public struct DatePair: Hashable, Sendable {
    public let out: Day
    public let back: Day
    public var stay: Int { out.days(until: back) }

    public init(out: Day, back: Day) {
        self.out = out
        self.back = back
    }
}

public struct SearchParams: Sendable, Equatable, Codable {
    public var destinations: Set<PlaceID>
    /// Autorise l'arrivée par une ville et le retour par l'autre (Nosy Be / Antsiranana).
    public var allowOpenJaw: Bool
    public var periodStart: Day
    public var periodEnd: Day
    public var stayMin: Int
    public var stayMax: Int
    public var adults: Int
    public var modes: Set<Mode>
    public var includeUnverified: Bool

    public init(destinations: Set<PlaceID>, allowOpenJaw: Bool, periodStart: Day, periodEnd: Day,
                stayMin: Int, stayMax: Int, adults: Int, modes: Set<Mode>, includeUnverified: Bool) {
        self.destinations = destinations
        self.allowOpenJaw = allowOpenJaw
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.stayMin = stayMin
        self.stayMax = stayMax
        self.adults = adults
        self.modes = modes
        self.includeUnverified = includeUnverified
    }

    /// Mai à septembre de la prochaine saison, séjour de 28 à 30 jours, 1 adulte.
    public static func defaults(today: Day = Day(localDate: Date())) -> SearchParams {
        let year = today < Day(year: today.year, month: 5, day: 1) ? today.year : today.year + 1
        return SearchParams(destinations: [.diego, .nosyBe], allowOpenJaw: true,
                            periodStart: Day(year: year, month: 5, day: 1),
                            periodEnd: Day(year: year, month: 9, day: 30),
                            stayMin: 28, stayMax: 30, adults: 1,
                            modes: Set(Mode.filterable), includeUnverified: true)
    }

    /// Dernier jour possible pour partir de Madagascar (arrivée en France avant la fin de la période).
    public var lastReturnDay: Day { periodEnd.adding(days: -1) }

    /// Toutes les paires (départ, retour) respectant la période et la durée de séjour.
    public var datePairs: [DatePair] {
        var pairs: [DatePair] = []
        let low = max(1, min(stayMin, stayMax))
        let high = max(stayMin, stayMax)
        var day = periodStart
        let last = lastReturnDay
        while day <= last {
            for stay in low...high {
                let back = day.adding(days: stay)
                if back <= last { pairs.append(DatePair(out: day, back: back)) }
            }
            day = day.adding(days: 1)
        }
        return pairs
    }

    /// Mois couverts par la période (AAAA-MM).
    public var months: [String] {
        var result: [String] = []
        var y = periodStart.year
        var m = periodStart.month
        while (y, m) <= (periodEnd.year, periodEnd.month) {
            result.append(String(format: "%04d-%02d", y, m))
            m += 1
            if m > 12 { m = 1; y += 1 }
        }
        return result
    }

    public var summary: String {
        let dest = destinations.map { NetworkData.place($0).short }.sorted().joined(separator: " + ")
        return "\(dest), \(Fmt.dayShort(periodStart)) au \(Fmt.dayShort(periodEnd)), séjour \(stayMin)-\(stayMax) j, "
            + "\(adults) adulte(s), villes différentes : \(allowOpenJaw ? "oui" : "non"), "
            + "modes : \(modes.map(\.label).sorted().joined(separator: ", "))"
    }
}
