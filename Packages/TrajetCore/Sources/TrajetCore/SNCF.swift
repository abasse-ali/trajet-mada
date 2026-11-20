import Foundation

// MARK: - Grille officielle des prix (open data SNCF, sans clé)

/// Fourchette officielle d'un tarif SNCF (2nde classe, tarif normal).
public struct FareRange: Codable, Sendable, Hashable {
    public let min: Double
    public let max: Double
    public let source: String

    public init(min: Double, max: Double, source: String) {
        self.min = min
        self.max = max
        self.source = source
    }

    /// Prix retenu pour le classement : le premier quart de la fourchette (billet pris à l'ouverture des ventes).
    public var likely: Double { (min + (max - min) * 0.25).rounded() }

    public var summary: String { "grille officielle SNCF : \(Fmt.euro(min)) à \(Fmt.euro(max)) en 2nde, tarif normal" }
}

/// Lit les grilles « tarifs-tgv-inoui-ouigo » et « tarifs-intercites » de ressources.data.sncf.com.
public struct SNCFFareClient: Sendable {
    public let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    static let tgvURL = "https://ressources.data.sncf.com/api/explore/v2.1/catalog/datasets/tarifs-tgv-inoui-ouigo/records"
    static let intercitesURL = "https://ressources.data.sncf.com/api/explore/v2.1/catalog/datasets/tarifs-intercites/records"
    static let toulouseUIC = "87611004"

    struct TGVResponse: Decodable {
        let results: [Record]?
        struct Record: Decodable {
            let transporteur: String?
            let gareOrigine: String?
            let gareDestination: String?
            let prixMinimum: Double?
            let prixMaximum: Double?
        }
    }

    struct IntercitesResponse: Decodable {
        let results: [Record]?
        struct Record: Decodable {
            let transporteur: String?
            let origine: String?
            let destination: String?
            let prixMin: Double?
            let prixMax: Double?
        }
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Fourchettes TGV INOUI et OUIGO entre Toulouse et Paris, par identifiant d'option (« tgv », « ouigo »).
    public static func parseTGV(_ data: Data) throws -> [String: FareRange] {
        let records = try decoder().decode(TGVResponse.self, from: data).results ?? []
        var result: [String: FareRange] = [:]
        for (optionID, carrier) in [("tgv", "TGV INOUI"), ("ouigo", "OUIGO")] {
            let rows = records.filter { $0.transporteur == carrier && $0.prixMinimum != nil && $0.prixMaximum != nil }
            // Les trains de Toulouse arrivent à Montparnasse : on privilégie ces lignes de la grille.
            let montparnasse = rows.filter {
                ($0.gareOrigine ?? "").contains("MONTPARNASSE") || ($0.gareDestination ?? "").contains("MONTPARNASSE")
            }
            let chosen = montparnasse.isEmpty ? rows : montparnasse
            guard let low = chosen.compactMap(\.prixMinimum).min(),
                  let high = chosen.compactMap(\.prixMaximum).max() else { continue }
            result[optionID] = FareRange(min: low, max: high, source: "open data SNCF (tarifs TGV INOUI et OUIGO)")
        }
        return result
    }

    public static func parseIntercites(_ data: Data) throws -> FareRange? {
        let records = try decoder().decode(IntercitesResponse.self, from: data).results ?? []
        guard let low = records.compactMap(\.prixMin).min(), let high = records.compactMap(\.prixMax).max() else { return nil }
        return FareRange(min: low, max: high, source: "open data SNCF (tarifs Intercités, couchette)")
    }

    static func recordsURL(_ base: String, where clause: String) -> URL {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = clause.addingPercentEncoding(withAllowedCharacters: allowed) ?? clause
        return URL(string: "\(base)?where=\(encoded)&limit=50")!
    }

    /// Fourchettes Toulouse ⇄ Paris pour les options « tgv », « ouigo » et « intercites-nuit ».
    public func fetchToulouseParis() async -> [String: FareRange] {
        var result: [String: FareRange] = [:]
        let tgvClause = "classe=\"2\" and profil_tarifaire=\"Tarif Normal\" and "
            + "((gare_origine_code_uic=\"\(Self.toulouseUIC)\" and startswith(gare_destination, \"PARIS\")) or "
            + "(gare_destination_code_uic=\"\(Self.toulouseUIC)\" and startswith(gare_origine, \"PARIS\")))"
        do {
            let data = try await http.get(Self.recordsURL(Self.tgvURL, where: tgvClause), label: "Grille SNCF TGV/OUIGO Toulouse-Paris")
            result.merge(try Self.parseTGV(data)) { _, new in new }
        } catch {
            http.log.warning(.api, "Grille SNCF TGV/OUIGO indisponible : \(error.localizedDescription)")
        }
        let nightClause = "classe=\"2\" and profil_tarifaire=\"Tarif Normal\" and type_place=\"couchette\" and "
            + "(origine_uic8=\"\(Self.toulouseUIC)\" or destination_uic8=\"\(Self.toulouseUIC)\") and "
            + "(startswith(origine, \"PARIS\") or startswith(destination, \"PARIS\"))"
        do {
            let data = try await http.get(Self.recordsURL(Self.intercitesURL, where: nightClause), label: "Grille SNCF Intercités de nuit")
            if let range = try Self.parseIntercites(data) { result["intercites-nuit"] = range }
        } catch {
            http.log.warning(.api, "Grille SNCF Intercités indisponible : \(error.localizedDescription)")
        }
        return result
    }
}

// MARK: - Horaires réels (api.sncf.com, clé personnelle)

public struct TrainJourney: Sendable, Identifiable, Hashable {
    public var id: String { "\(departure)-\(arrival)-\(trains.joined(separator: "+"))" }
    /// « 06:10 »
    public let departure: String
    /// « 11:03 »
    public let arrival: String
    /// 1 si l'arrivée a lieu le lendemain.
    public let arrivalDayOffset: Int
    public let durationMin: Int
    public let transfers: Int
    /// « TGV INOUI 8502 »
    public let trains: [String]
    /// Modes commerciaux (« TGV INOUI », « Intercités de nuit »…).
    public let modes: [String]
    /// Prix renvoyé par l'API (rarement disponible).
    public let fare: Double?
}

public struct SNCFWindow: Sendable, Codable, Equatable {
    public let start: Day
    public let end: Day
}

public struct TrainSchedule: Sendable {
    /// Jour du trajet.
    public let day: Day
    /// Jour réellement interrogé (le même si les horaires sont publiés).
    public let referenceDay: Day
    public let exact: Bool
    public let journeys: [TrainJourney]

    public init(day: Day, referenceDay: Day, exact: Bool, journeys: [TrainJourney]) {
        self.day = day
        self.referenceDay = referenceDay
        self.exact = exact
        self.journeys = journeys
    }
}

public struct SNCFClient: Sendable {
    public let key: String
    public let http: HTTPClient

    public init(key: String, http: HTTPClient) {
        self.key = key
        self.http = http
    }

    static let base = "https://api.sncf.com/v1/coverage/sncf"

    /// Authentification HTTP Basic : la clé comme nom d'utilisateur, mot de passe vide.
    var headers: [String: String] {
        ["Authorization": "Basic " + Data("\(key):".utf8).base64EncodedString()]
    }

    struct CoverageResponse: Decodable {
        let regions: [Region]?
        struct Region: Decodable {
            let startProductionDate: String?
            let endProductionDate: String?
        }
    }

    struct JourneysResponse: Decodable {
        let journeys: [Journey]?
        let error: NavitiaError?

        struct Journey: Decodable {
            let departureDateTime: String?
            let arrivalDateTime: String?
            let duration: Int?
            let nbTransfers: Int?
            let sections: [Section]?
            let fare: Fare?
        }
        struct Section: Decodable {
            let type: String?
            let displayInformations: Display?
        }
        struct Display: Decodable {
            let commercialMode: String?
            let headsign: String?
        }
        struct Fare: Decodable {
            let found: Bool?
            let total: Total?
        }
        struct Total: Decodable {
            let value: String?
        }
        struct NavitiaError: Decodable {
            let id: String?
            let message: String?
        }
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    public static func parseWindow(_ data: Data) throws -> SNCFWindow {
        let response = try decoder().decode(CoverageResponse.self, from: data)
        guard let region = response.regions?.first,
              let start = region.startProductionDate.flatMap(Day.init(compact:)),
              let end = region.endProductionDate.flatMap(Day.init(compact:)) else {
            throw APIError.api("période des horaires SNCF illisible")
        }
        return SNCFWindow(start: start, end: end)
    }

    public static func parseJourneys(_ data: Data) throws -> [TrainJourney] {
        let response = try decoder().decode(JourneysResponse.self, from: data)
        if let error = response.error {
            if error.id == "no_solution" { return [] }
            throw APIError.api(error.message ?? error.id ?? "erreur API SNCF")
        }
        var seen = Set<String>()
        var result: [TrainJourney] = []
        for journey in response.journeys ?? [] {
            guard let dep = journey.departureDateTime, let arr = journey.arrivalDateTime,
                  dep.count >= 13, arr.count >= 13 else { continue }
            let sections = (journey.sections ?? []).filter { $0.type == "public_transport" }
            let trains = sections.compactMap { section -> String? in
                guard let info = section.displayInformations else { return nil }
                return [info.commercialMode, info.headsign].compactMap { $0 }.joined(separator: " ")
            }
            var offset = 0
            if let d1 = Day(compact: dep), let d2 = Day(compact: arr) { offset = d1.days(until: d2) }
            var fare: Double?
            if journey.fare?.found == true, let value = journey.fare?.total?.value, let price = Double(value), price > 0 {
                fare = price
            }
            let item = TrainJourney(
                departure: clock(dep), arrival: clock(arr), arrivalDayOffset: offset,
                durationMin: (journey.duration ?? 0) / 60, transfers: journey.nbTransfers ?? 0,
                trains: trains, modes: sections.compactMap { $0.displayInformations?.commercialMode }, fare: fare)
            if seen.insert(item.id).inserted { result.append(item) }
        }
        return result.sorted { $0.departure < $1.departure }
    }

    /// « 20261201T061000 » vers « 06:10 »
    static func clock(_ stamp: String) -> String {
        let chars = Array(stamp)
        guard chars.count >= 13 else { return "" }
        return String(chars[9..<11]) + ":" + String(chars[11..<13])
    }

    /// Jour à interroger : le jour même s'il est publié, sinon le même jour de la semaine dans la période publiée.
    public static func referenceDay(for day: Day, window: SNCFWindow, today: Day) -> (day: Day, exact: Bool) {
        if day >= window.start && day <= window.end { return (day, true) }
        var cursor = max(window.start, today.adding(days: 1))
        while cursor <= window.end {
            if cursor.weekday == day.weekday { return (cursor, false) }
            cursor = cursor.adding(days: 1)
        }
        return (max(window.start, today), false)
    }

    public func window() async throws -> SNCFWindow {
        let data = try await http.get(URL(string: Self.base)!, label: "SNCF période des horaires", headers: headers)
        return try Self.parseWindow(data)
    }

    public func journeys(from: String, to: String, day: Day, label: String) async throws -> [TrainJourney] {
        var components = URLComponents(string: Self.base + "/journeys")!
        components.queryItems = [
            URLQueryItem(name: "from", value: from),
            URLQueryItem(name: "to", value: to),
            URLQueryItem(name: "datetime", value: "\(day.compact)T050000"),
            URLQueryItem(name: "count", value: "20"),
            URLQueryItem(name: "min_nb_journeys", value: "12"),
            URLQueryItem(name: "data_freshness", value: "base_schedule"),
        ]
        let data = try await http.get(components.url!, label: label, headers: headers)
        return try Self.parseJourneys(data)
    }
}
