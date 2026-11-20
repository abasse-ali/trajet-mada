import Foundation

/// Jour calendaire sans heure ni fuseau (évite les décalages de date).
public struct Day: Hashable, Comparable, Sendable, Codable {
    public let year: Int
    public let month: Int
    public let day: Int
    /// AAAA-MM-JJ
    public let key: String

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
        self.key = String(format: "%04d-%02d-%02d", year, month, day)
    }

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    var utcNoon: Date {
        Day.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    init(utcDate: Date) {
        let c = Day.utc.dateComponents([.year, .month, .day], from: utcDate)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Jour local d'une date choisie dans l'interface.
    public init(localDate: Date, calendar: Calendar = .current) {
        let c = calendar.dateComponents([.year, .month, .day], from: localDate)
        self.init(year: c.year!, month: c.month!, day: c.day!)
    }

    /// Date locale à midi (pour l'interface et les graphiques).
    public func localDate(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    /// Lit les 10 premiers caractères d'une date ISO (« 2027-05-10T09:35:00+02:00 »).
    public init?(isoPrefix: String) {
        let parts = isoPrefix.prefix(10).split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// Lit une date compacte « 20261118 » (format Navitia / API SNCF).
    public init?(compact: String) {
        let s = Array(compact.prefix(8))
        guard s.count == 8, let y = Int(String(s[0..<4])), let m = Int(String(s[4..<6])), let d = Int(String(s[6..<8])),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// AAAAMMJJ (API SNCF)
    public var compact: String { String(format: "%04d%02d%02d", year, month, day) }

    public func adding(days: Int) -> Day {
        Day(utcDate: Day.utc.date(byAdding: .day, value: days, to: utcNoon)!)
    }

    public func days(until other: Day) -> Int {
        Day.utc.dateComponents([.day], from: utcNoon, to: other.utcNoon).day!
    }

    /// 1 = dimanche … 7 = samedi
    public var weekday: Int { Day.utc.component(.weekday, from: utcNoon) }
    /// AAAA-MM
    public var monthKey: String { String(format: "%04d-%02d", year, month) }
    /// JJMM (Aviasales)
    public var ddmm: String { String(format: "%02d%02d", day, month) }
    /// JJ.MM.AAAA (FlixBus)
    public var dotted: String { String(format: "%02d.%02d.%04d", day, month, year) }
    /// AAMMJJ (Skyscanner)
    public var yymmdd: String { String(format: "%02d%02d%02d", year % 100, month, day) }

    public static func < (lhs: Day, rhs: Day) -> Bool { lhs.key < rhs.key }
}
