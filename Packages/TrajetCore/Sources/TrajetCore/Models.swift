import Foundation

public enum Mode: String, CaseIterable, Codable, Sendable, Identifiable {
    case avion
    case train
    case bus
    case covoiturage
    case bateau
    case taxiBrousse = "taxi-brousse"
    case voiture
    case local

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .avion: return "Avion"
        case .train: return "Train"
        case .bus: return "Bus"
        case .covoiturage: return "Covoiturage"
        case .bateau: return "Bateau"
        case .taxiBrousse: return "Taxi-brousse"
        case .voiture: return "Taxi privé"
        case .local: return "Transport urbain"
        }
    }

    /// Nom de l'icône SVG dans le catalogue d'assets.
    public var iconName: String { "mode.\(rawValue)" }

    public static let filterable: [Mode] = [.avion, .train, .bus, .covoiturage, .bateau, .taxiBrousse, .voiture]
}

public enum PlaceID: String, CaseIterable, Codable, Sendable, Hashable {
    case toulouse = "TLS_V"
    case toulouseAirport = "TLS"
    case parisStations = "PAR_G"
    case parisAirports = "PAR"
    case milan = "MIL"
    case reunion = "RUN"
    case mayotte = "DZA"
    case johannesburg = "JNB"
    case tana = "TNR"
    case ankify = "ANK"
    case nosyBe = "NOS"
    case diego = "DIE"
}

/// Codes à utiliser pour chaque service de prix ou de réservation.
public struct AirportCode: Sendable, Hashable {
    /// Code ville ou aéroport pour Travelpayouts, Google Flights (texte), Kayak, Aviasales.
    public let code: String
    /// Aéroports séparés par des virgules pour SerpApi (Google Flights).
    public let serpapi: String
    /// Code Skyscanner (minuscules).
    public let skyscanner: String
}

public struct Place: Sendable, Identifiable {
    public let id: PlaceID
    public let name: String
    public let short: String
    /// Niveau d'éloignement depuis Toulouse : un trajet aller ne revient jamais à un niveau inférieur.
    public let tier: Int
    public let airport: AirportCode?
    public let flixbusCityID: String?
    /// Nom de ville pour BlaBlaCar.
    public let cityName: String
    /// Identifiant de gare ou de ville pour l'API SNCF (horaires).
    public var sncfID: String? = nil
}

public enum PriceKind: String, Sendable, Codable {
    /// Prix des vols par API (Travelpayouts, SerpApi).
    case flight
    /// Prix FlixBus en direct.
    case flixbus
    /// Fourchette estimée (pas d'API publique).
    case estimate
    /// Tarif fixe connu.
    case tariff
}

public enum LinkKind: Sendable, Equatable {
    case flightComparators
    case flixbus
    case blablacar
    case sncfConnect
    case trainline
    case ouigo
    case website(label: String, url: String)
    case search(label: String, query: String)
}

public struct TransportOption: Sendable, Identifiable {
    public let id: String
    public let mode: Mode
    public let operatorName: String
    public let durationMin: Int
    /// Prix bas estimé, aller simple, 1 adulte (€).
    public let priceMin: Double
    /// Prix courant estimé, aller simple, 1 adulte (€).
    public let priceTypical: Double
    public var perVehicle: Bool = false
    public let frequency: String
    public var rare: Bool = false
    public var verified: Bool = true
    public var notes: String? = nil
    public let kind: PriceKind
    public let links: [LinkKind]
    /// Mode commercial SNCF (« TGV INOUI », « OUIGO », « Intercités de nuit ») pour les horaires réels.
    public var sncfMode: String? = nil
}

/// Liaison dans les deux sens entre deux lieux, avec une ou plusieurs options.
public struct Connection: Sendable, Identifiable {
    public let id: String
    public let a: PlaceID
    public let b: PlaceID
    public let options: [TransportOption]

    public func other(_ p: PlaceID) -> PlaceID? {
        if p == a { return b }
        if p == b { return a }
        return nil
    }
}
