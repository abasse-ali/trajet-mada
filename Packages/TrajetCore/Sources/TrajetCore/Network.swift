import Foundation

/// Réseau multimodal Toulouse ⇄ Antsiranana / Nosy Be.
/// Chaque liaison fonctionne dans les deux sens. Les vols sont des paires de villes
/// « toutes compagnies » : les API (Travelpayouts, Google Flights via SerpApi) trouvent
/// elles-mêmes les meilleures correspondances. Les prix ci-dessous ne servent que de
/// repli quand aucune API ne renvoie de prix (aller simple, 1 adulte, en euros).
public enum NetworkData {
    public static let dataDate = "novembre 2026"
    public static let start: PlaceID = .toulouse

    public static let places: [PlaceID: Place] = {
        let list: [Place] = [
            Place(id: .toulouse, name: "Toulouse (centre, gare Matabiau)", short: "Toulouse", tier: 0,
                  airport: nil, flixbusCityID: "40dfd612-8646-11e6-9066-549f350fcb0c", cityName: "Toulouse"),
            Place(id: .toulouseAirport, name: "Aéroport Toulouse-Blagnac", short: "Toulouse-Blagnac", tier: 1,
                  airport: AirportCode(code: "TLS", serpapi: "TLS", skyscanner: "tls"), flixbusCityID: nil, cityName: "Toulouse"),
            Place(id: .parisStations, name: "Paris (gares Montparnasse, Austerlitz, Bercy)", short: "Paris", tier: 1,
                  airport: nil, flixbusCityID: "40de8964-8646-11e6-9066-549f350fcb0c", cityName: "Paris"),
            Place(id: .parisAirports, name: "Aéroports de Paris (CDG, Orly)", short: "Paris CDG/Orly", tier: 2,
                  airport: AirportCode(code: "PAR", serpapi: "CDG,ORY", skyscanner: "pari"), flixbusCityID: nil, cityName: "Paris"),
            Place(id: .milan, name: "Milan (Malpensa)", short: "Milan", tier: 3,
                  airport: AirportCode(code: "MIL", serpapi: "MXP,LIN,BGY", skyscanner: "mila"), flixbusCityID: nil, cityName: "Milan"),
            Place(id: .reunion, name: "La Réunion (Saint-Denis Roland-Garros)", short: "La Réunion", tier: 4,
                  airport: AirportCode(code: "RUN", serpapi: "RUN", skyscanner: "run"), flixbusCityID: nil, cityName: "Saint-Denis"),
            Place(id: .mayotte, name: "Mayotte (Dzaoudzi-Pamandzi)", short: "Mayotte", tier: 4,
                  airport: AirportCode(code: "DZA", serpapi: "DZA", skyscanner: "dza"), flixbusCityID: nil, cityName: "Mayotte"),
            Place(id: .johannesburg, name: "Johannesburg (O.R. Tambo)", short: "Johannesburg", tier: 4,
                  airport: AirportCode(code: "JNB", serpapi: "JNB", skyscanner: "jnb"), flixbusCityID: nil, cityName: "Johannesburg"),
            Place(id: .tana, name: "Antananarivo (Ivato)", short: "Tana", tier: 5,
                  airport: AirportCode(code: "TNR", serpapi: "TNR", skyscanner: "tnr"), flixbusCityID: nil, cityName: "Antananarivo"),
            Place(id: .ankify, name: "Port d'Ankify (près d'Ambanja)", short: "Ankify", tier: 6,
                  airport: nil, flixbusCityID: nil, cityName: "Ankify"),
            Place(id: .nosyBe, name: "Nosy Be (Fascene, Hell-Ville)", short: "Nosy Be", tier: 6,
                  airport: AirportCode(code: "NOS", serpapi: "NOS", skyscanner: "nos"), flixbusCityID: nil, cityName: "Nosy Be"),
            Place(id: .diego, name: "Antsiranana / Diego-Suarez (Arrachart)", short: "Antsiranana", tier: 6,
                  airport: AirportCode(code: "DIE", serpapi: "DIE", skyscanner: "die"), flixbusCityID: nil, cityName: "Antsiranana"),
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }()

    public static func place(_ id: PlaceID) -> Place { places[id]! }

    public static let destinations: [PlaceID] = [.diego, .nosyBe]

    // MARK: - Fabriques

    private static func vol(_ id: String, _ dur: Int, _ min: Double, _ typ: Double, _ freq: String,
                            operators: String, rare: Bool = false, verified: Bool = true,
                            notes: String? = nil) -> TransportOption {
        TransportOption(id: id, mode: .avion, operatorName: operators, durationMin: dur, priceMin: min,
                        priceTypical: typ, frequency: freq, rare: rare, verified: verified, notes: notes,
                        kind: .flight, links: [.flightComparators])
    }

    private static func air(_ a: PlaceID, _ b: PlaceID, _ option: TransportOption) -> Connection {
        Connection(id: "\(a.rawValue)-\(b.rawValue)", a: a, b: b, options: [option])
    }

    // MARK: - Liaisons

    public static let connections: [Connection] = [
        // Toulouse : accès à l'aéroport et à Paris
        Connection(id: "TLS_V-TLS", a: .toulouse, b: .toulouseAirport, options: [
            TransportOption(id: "tram-t2", mode: .local, operatorName: "Tram T2 Tisséo", durationMin: 40,
                            priceMin: 2, priceTypical: 2, frequency: "Toutes les 10 à 15 min",
                            notes: "Ticket Tisséo standard. Navette aéroport : environ 9 €.",
                            kind: .tariff, links: [.website(label: "Tisséo", url: "https://www.tisseo.fr/")]),
        ]),
        Connection(id: "TLS_V-PAR_G", a: .toulouse, b: .parisStations, options: [
            TransportOption(id: "flixbus", mode: .bus, operatorName: "FlixBus", durationMin: 540,
                            priceMin: 10, priceTypical: 35, frequency: "Plusieurs par jour (dont de nuit)",
                            notes: "Prix FlixBus réel récupéré en direct pour la date du trajet.",
                            kind: .flixbus, links: [.flixbus]),
            TransportOption(id: "ouigo", mode: .train, operatorName: "OUIGO (TGV low-cost)", durationMin: 285,
                            priceMin: 19, priceTypical: 45, frequency: "1 à 3 par jour",
                            notes: "Pas d'API publique SNCF : prix estimé. Bagages en option.",
                            kind: .estimate, links: [.ouigo, .trainline]),
            TransportOption(id: "tgv", mode: .train, operatorName: "SNCF TGV INOUI", durationMin: 260,
                            priceMin: 29, priceTypical: 75, frequency: "6 à 8 par jour",
                            notes: "Pas d'API publique SNCF : prix estimé. Ventes ouvertes environ 4 mois avant.",
                            kind: .estimate, links: [.sncfConnect, .trainline]),
            TransportOption(id: "intercites-nuit", mode: .train, operatorName: "Intercités de nuit (couchette)",
                            durationMin: 480, priceMin: 29, priceTypical: 69, frequency: "1 par nuit selon calendrier",
                            notes: "Arrivée à Paris-Austerlitz le matin.",
                            kind: .estimate, links: [.sncfConnect, .trainline]),
            TransportOption(id: "blablacar", mode: .covoiturage, operatorName: "BlaBlaCar (covoiturage)",
                            durationMin: 420, priceMin: 40, priceTypical: 55, frequency: "Nombreux trajets",
                            notes: "API réservée aux partenaires : prix estimé, lien prérempli.",
                            kind: .estimate, links: [.blablacar]),
        ]),
        Connection(id: "PAR_G-PAR", a: .parisStations, b: .parisAirports, options: [
            TransportOption(id: "rer-metro", mode: .local, operatorName: "RER B / métro 14", durationMin: 60,
                            priceMin: 13, priceTypical: 13, frequency: "Toutes les 5 à 15 min",
                            notes: "Billet « Paris Région Aéroports ».",
                            kind: .tariff, links: [.website(label: "RATP", url: "https://www.ratp.fr/")]),
        ]),
        Connection(id: "PAR_G-MIL", a: .parisStations, b: .milan, options: [
            TransportOption(id: "train-milan", mode: .train, operatorName: "TGV / Frecciarossa Paris-Milan",
                            durationMin: 500, priceMin: 40, priceTypical: 120, frequency: "2 à 5 par jour",
                            verified: false,
                            notes: "Ligne de la Maurienne coupée en 2023 : vérifier la circulation des trains directs.",
                            kind: .estimate, links: [.sncfConnect, .trainline]),
        ]),

        // Vols au départ de Toulouse (toutes compagnies, correspondances comprises)
        air(.toulouseAirport, .parisAirports, vol("vol-tls-par", 80, 45, 110, "Plusieurs par jour",
            operators: "Air France, easyJet")),
        air(.toulouseAirport, .diego, vol("vol-tls-die", 1560, 650, 1000, "Variable",
            operators: "Toutes compagnies (via Paris, La Réunion, Mayotte ou Tana)")),
        air(.toulouseAirport, .nosyBe, vol("vol-tls-nos", 1260, 520, 800, "3 à 7 par semaine",
            operators: "Toutes compagnies (souvent Air France + Ethiopian)")),
        air(.toulouseAirport, .tana, vol("vol-tls-tnr", 930, 460, 720, "Quotidien",
            operators: "Toutes compagnies (souvent Air France via Paris)")),
        air(.toulouseAirport, .reunion, vol("vol-tls-run", 900, 330, 560, "Quotidien",
            operators: "Air France, Air Austral via Paris")),

        // Vols au départ de Paris
        air(.parisAirports, .diego, vol("vol-par-die", 1080, 600, 950, "Variable",
            operators: "Toutes compagnies (via La Réunion, Mayotte ou Tana)")),
        air(.parisAirports, .nosyBe, vol("vol-par-nos", 960, 480, 750, "3 à 7 par semaine",
            operators: "Ethiopian via Addis-Abeba, Air Austral via La Réunion")),
        air(.parisAirports, .tana, vol("vol-par-tnr", 665, 390, 620, "Quotidien",
            operators: "Air France direct, Corsair direct (Orly), Ethiopian, Kenya Airways, Air Mauritius",
            notes: "Air France a suspendu la ligne du 11 au 18 octobre 2025 (crise politique).")),
        air(.parisAirports, .reunion, vol("vol-par-run", 660, 270, 450, "Quotidien",
            operators: "French Bee, Corsair, Air Austral, Air France")),
        air(.parisAirports, .mayotte, vol("vol-par-dza", 660, 380, 620, "Plusieurs par semaine",
            operators: "Corsair, Air Austral")),
        air(.parisAirports, .johannesburg, vol("vol-par-jnb", 650, 350, 650, "Quotidien",
            operators: "Air France")),
        air(.parisAirports, .milan, vol("vol-par-mil", 90, 35, 100, "Plusieurs par jour",
            operators: "easyJet, Air France")),

        // Hubs régionaux
        air(.reunion, .nosyBe, vol("vol-run-nos", 135, 180, 300, "Jusqu'à 5 par semaine",
            operators: "Air Austral")),
        air(.reunion, .diego, vol("vol-run-die", 130, 200, 330, "1 à 2 par semaine selon saison",
            operators: "Air Austral, Ewa Air", rare: true, verified: false,
            notes: "Desservi 2 fois par semaine à l'été 2025 : programme 2027 à confirmer.")),
        air(.reunion, .tana, vol("vol-run-tnr", 125, 150, 280, "Plusieurs par semaine",
            operators: "Air Austral, Corsair (code Madagascar Airlines)")),
        air(.reunion, .mayotte, vol("vol-run-dza", 150, 150, 280, "Quotidien ou presque",
            operators: "Air Austral")),
        air(.mayotte, .diego, vol("vol-dza-die", 75, 130, 220, "2 à 4 par semaine",
            operators: "Ewa Air (code Madagascar Airlines)", rare: true)),
        air(.mayotte, .nosyBe, vol("vol-dza-nos", 70, 130, 220, "2 à 4 par semaine",
            operators: "Ewa Air (code Madagascar Airlines)", rare: true)),
        air(.johannesburg, .nosyBe, vol("vol-jnb-nos", 210, 220, 380, "1 à 2 par semaine",
            operators: "Airlink", rare: true)),
        air(.milan, .nosyBe, vol("vol-mil-nos", 570, 350, 600, "1 à 2 par semaine (saisonnier)",
            operators: "Neos (vol direct)", rare: true,
            notes: "Billets « vol seul » sur le site de Neos.")),

        // Madagascar
        Connection(id: "TNR-DIE", a: .tana, b: .diego, options: [
            vol("vol-tnr-die", 105, 140, 230, "Quotidien ou presque",
                operators: "Madagascar Airlines (vol intérieur)",
                notes: "Vols intérieurs souvent décalés : tarif modifiable et marge conseillés."),
            TransportOption(id: "brousse-tnr-die", mode: .taxiBrousse, operatorName: "Cotisse Transport / taxi-brousse (RN6)",
                            durationMin: 1620, priceMin: 25, priceTypical: 35, frequency: "Départ quotidien vers midi",
                            notes: "Pas de vente en ligne : réservation par téléphone ou sur place. 28 à 30 h de route, plus en saison des pluies.",
                            kind: .estimate,
                            links: [.website(label: "Cotisse Transport", url: "https://www.cotisse-transport.com/")]),
        ]),
        Connection(id: "TNR-NOS", a: .tana, b: .nosyBe, options: [
            vol("vol-tnr-nos", 85, 130, 220, "Quotidien ou presque",
                operators: "Madagascar Airlines (vol intérieur)"),
        ]),
        Connection(id: "NOS-DIE", a: .nosyBe, b: .diego, options: [
            vol("vol-nos-die", 45, 110, 190, "Selon programme",
                operators: "Madagascar Airlines (vol intérieur)", rare: true, verified: false),
        ]),
        Connection(id: "TNR-ANK", a: .tana, b: .ankify, options: [
            TransportOption(id: "brousse-tnr-ank", mode: .taxiBrousse, operatorName: "Taxi-brousse jusqu'à Ambanja puis Ankify",
                            durationMin: 1320, priceMin: 22, priceTypical: 32, frequency: "Départs quotidiens",
                            notes: "Pas de vente en ligne : achat à la gare routière.",
                            kind: .estimate,
                            links: [.search(label: "Infos taxi-brousse", query: "taxi-brousse Antananarivo Ambanja tarif")]),
        ]),
        Connection(id: "ANK-NOS", a: .ankify, b: .nosyBe, options: [
            TransportOption(id: "vedette", mode: .bateau, operatorName: "Vedette rapide ou bac",
                            durationMin: 60, priceMin: 6, priceTypical: 8, frequency: "Plusieurs le matin",
                            notes: "Environ 30 000 à 40 000 Ar, payé sur place. Partir le matin, la mer se lève l'après-midi.",
                            kind: .estimate,
                            links: [.search(label: "Horaires vedettes", query: "vedette Ankify Nosy Be horaires prix")]),
        ]),
        Connection(id: "ANK-DIE", a: .ankify, b: .diego, options: [
            TransportOption(id: "brousse-ank-die", mode: .taxiBrousse, operatorName: "Taxi-brousse via Ambanja",
                            durationMin: 380, priceMin: 8, priceTypical: 15, frequency: "Départs quotidiens",
                            notes: "Route refaite en 2025 : environ 6 h.",
                            kind: .estimate,
                            links: [.search(label: "Infos taxi-brousse", query: "taxi-brousse Ambanja Diego-Suarez")]),
            TransportOption(id: "taxi-ank-die", mode: .voiture, operatorName: "Taxi privé / 4x4 avec chauffeur",
                            durationMin: 300, priceMin: 70, priceTypical: 100, perVehicle: true, frequency: "À la demande",
                            notes: "Prix pour le véhicule entier (jusqu'à 4 personnes), à négocier.",
                            kind: .estimate,
                            links: [.search(label: "Chauffeurs", query: "chauffeur Ankify Diego-Suarez prix")]),
        ]),
    ]
}
