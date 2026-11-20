import Foundation

public struct BookingLink: Sendable, Identifiable, Hashable {
    public var id: String { label + "|" + url.absoluteString }
    public let label: String
    public let url: URL
    /// Le site s'ouvre directement sur la recherche, dates et lieux remplis.
    public let prefilled: Bool
}

/// Liens de réservation préremplis (lieux, dates, voyageurs) pour chaque transporteur.
public enum LinkBuilder {
    public static func links(for option: TransportOption, from: PlaceID, to: PlaceID, day: Day,
                             returnDay: Day? = nil, adults: Int = 1) -> [BookingLink] {
        let origin = NetworkData.place(from)
        let destination = NetworkData.place(to)
        var result: [BookingLink] = []
        for kind in option.links {
            switch kind {
            case .flightComparators:
                guard let a = origin.airport, let b = destination.airport else { continue }
                result += flightLinks(from: a, to: b, out: day, back: returnDay, adults: adults)
            case .flixbus:
                if let f = origin.flixbusCityID, let t = destination.flixbusCityID,
                   let url = flixbusURL(fromCity: f, toCity: t, day: day, adults: adults) {
                    result.append(BookingLink(label: "FlixBus", url: url, prefilled: true))
                }
            case .blablacar:
                if let url = blablacarURL(from: origin.cityName, to: destination.cityName, day: day, seats: adults) {
                    result.append(BookingLink(label: "BlaBlaCar", url: url, prefilled: true))
                }
            case .sncfConnect:
                result.append(BookingLink(label: "SNCF Connect", url: URL(string: "https://www.sncf-connect.com/")!, prefilled: false))
            case .trainline:
                result.append(BookingLink(label: "Trainline", url: URL(string: "https://www.thetrainline.com/fr")!, prefilled: false))
            case .ouigo:
                result.append(BookingLink(label: "OUIGO", url: URL(string: "https://www.ouigo.com/")!, prefilled: false))
            case .website(let label, let address):
                if let url = URL(string: address) { result.append(BookingLink(label: label, url: url, prefilled: false)) }
            case .search(let label, let query):
                if let url = googleSearchURL(query) { result.append(BookingLink(label: label, url: url, prefilled: false)) }
            }
        }
        return result
    }

    public static func flightLinks(from a: AirportCode, to b: AirportCode, out: Day, back: Day?, adults: Int) -> [BookingLink] {
        [
            BookingLink(label: "Google Flights", url: googleFlightsURL(from: a, to: b, out: out, back: back), prefilled: true),
            BookingLink(label: "Skyscanner", url: skyscannerURL(from: a, to: b, out: out, back: back, adults: adults), prefilled: true),
            BookingLink(label: "Kayak", url: kayakURL(from: a, to: b, out: out, back: back, adults: adults), prefilled: true),
            BookingLink(label: "Aviasales", url: aviasalesURL(from: a, to: b, out: out, back: back, adults: adults), prefilled: true),
        ]
    }

    public static func googleFlightsURL(from a: AirportCode, to b: AirportCode, out: Day, back: Day?) -> URL {
        var query = "Flights from \(a.code) to \(b.code) on \(out.key)"
        if let back { query += " through \(back.key)" } else { query += " one way" }
        var components = URLComponents(string: "https://www.google.com/travel/flights")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "curr", value: "EUR"),
            URLQueryItem(name: "hl", value: "fr"),
        ]
        return components.url!
    }

    public static func skyscannerURL(from a: AirportCode, to b: AirportCode, out: Day, back: Day?, adults: Int) -> URL {
        var path = "https://www.skyscanner.fr/transport/vols/\(a.skyscanner)/\(b.skyscanner)/\(out.yymmdd)/"
        if let back { path += "\(back.yymmdd)/" }
        path += "?adultsv2=\(adults)&cabinclass=economy&rtn=\(back == nil ? 0 : 1)"
        return URL(string: path)!
    }

    public static func kayakURL(from a: AirportCode, to b: AirportCode, out: Day, back: Day?, adults: Int) -> URL {
        var path = "https://www.kayak.fr/flights/\(a.code)-\(b.code)/\(out.key)"
        if let back { path += "/\(back.key)" }
        if adults > 1 { path += "/\(adults)adults" }
        path += "?sort=price_a"
        return URL(string: path)!
    }

    /// Billet multi-destinations (arrivée et retour par des villes différentes).
    public static func kayakMultiCityURL(legs: [(AirportCode, AirportCode, Day)], adults: Int) -> URL {
        var path = "https://www.kayak.fr/flights"
        for leg in legs { path += "/\(leg.0.code)-\(leg.1.code)/\(leg.2.key)" }
        if adults > 1 { path += "/\(adults)adults" }
        path += "?sort=price_a"
        return URL(string: path)!
    }

    public static func aviasalesURL(from a: AirportCode, to b: AirportCode, out: Day, back: Day?, adults: Int) -> URL {
        var code = "\(a.code)\(out.ddmm)\(b.code)"
        if let back { code += back.ddmm }
        code += String(adults)
        return URL(string: "https://www.aviasales.fr/search/\(code)")!
    }

    public static func flixbusURL(fromCity: String, toCity: String, day: Day, adults: Int) -> URL? {
        var components = URLComponents(string: "https://shop.flixbus.fr/search")!
        components.queryItems = [
            URLQueryItem(name: "departureCity", value: fromCity),
            URLQueryItem(name: "arrivalCity", value: toCity),
            URLQueryItem(name: "rideDate", value: day.dotted),
            URLQueryItem(name: "adult", value: String(adults)),
            URLQueryItem(name: "_locale", value: "fr"),
        ]
        return components.url
    }

    public static func blablacarURL(from: String, to: String, day: Day, seats: Int) -> URL? {
        var components = URLComponents(string: "https://www.blablacar.fr/search")!
        components.queryItems = [
            URLQueryItem(name: "fn", value: from),
            URLQueryItem(name: "tn", value: to),
            URLQueryItem(name: "db", value: day.key),
            URLQueryItem(name: "seats", value: String(seats)),
        ]
        return components.url
    }

    public static func googleSearchURL(_ query: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url
    }
}
