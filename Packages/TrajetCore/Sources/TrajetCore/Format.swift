import Foundation

public enum Fmt {
    static let months = ["janv.", "févr.", "mars", "avr.", "mai", "juin",
                         "juil.", "août", "sept.", "oct.", "nov.", "déc."]
    static let weekdays = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]
    static let narrowSpace = "\u{202F}"

    /// « 1 234 € »
    public static func euro(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        let digits = String(abs(rounded))
        var grouped = ""
        for (i, ch) in digits.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(narrowSpace) }
            grouped.append(ch)
        }
        return (rounded < 0 ? "-" : "") + String(grouped.reversed()) + narrowSpace + "€"
    }

    /// « 1 j 6 h », « 14 h 20 », « 45 min »
    public static func duration(_ minutes: Int) -> String {
        let m = max(0, minutes)
        let d = m / 1440
        let h = (m % 1440) / 60
        let r = m % 60
        if d > 0 { return h > 0 ? "\(d) j \(h) h" : "\(d) j" }
        if h > 0 { return r > 0 ? "\(h) h \(String(format: "%02d", r))" : "\(h) h" }
        return "\(r) min"
    }

    /// « 10 mai »
    public static func dayShort(_ d: Day) -> String { "\(d.day) \(months[d.month - 1])" }

    /// « lun. 10 mai 2027 »
    public static func dayLong(_ d: Day) -> String {
        "\(weekdays[d.weekday - 1]) \(d.day) \(months[d.month - 1]) \(d.year)"
    }

    /// « à l'instant », « il y a 3 h », « le 21 nov. »
    public static func age(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 120 { return "à l'instant" }
        if seconds < 3600 { return "il y a \(Int(seconds / 60)) min" }
        if seconds < 86_400 { return "il y a \(Int(seconds / 3600)) h" }
        return "le \(dayShort(Day(localDate: date)))"
    }

    /// « 08:35 »
    public static func clock(_ minuteOfDay: Int) -> String {
        let m = ((minuteOfDay % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", m / 60, m % 60)
    }
}
