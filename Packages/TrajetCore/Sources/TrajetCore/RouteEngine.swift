import Foundation

/// Nature d'un prix. Aucun prix n'est inventé : sans source, l'étape est « sans prix publié ».
public enum PriceQuality: Int, Sendable, Comparable, Codable {
    /// Aucun prix publié en ligne pour cette date (taxi-brousse, billets pas encore en vente…).
    case unknown = 0
    /// Tarif officiel publié (ticket de transport, traversée en bateau…).
    case tariff = 1
    /// Prix réel relevé (Aviasales, Google Flights, FlixBus) il y a plus de 3 heures.
    case cached = 2
    /// Prix réel relevé il y a moins de 3 heures.
    case live = 3

    public static func < (lhs: PriceQuality, rhs: PriceQuality) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .unknown: return "prix non publié"
        case .tariff: return "tarif officiel"
        case .cached: return "prix réel"
        case .live: return "temps réel"
        }
    }

    public var isKnown: Bool { self != .unknown }
}

public struct PricedOption: Sendable, Identifiable {
    public var id: String { option.id }
    public let option: TransportOption
    /// Prix réel pour tous les voyageurs (€), 0 si inconnu.
    public let price: Double
    public let quality: PriceQuality
    public let quote: Quote?
    /// Explication quand le prix n'est pas publié (grille officielle, vente sur place…).
    public var info: String? = nil

    public var isKnown: Bool { quality.isKnown }
    /// Valeur de classement : un prix inconnu passe après tous les prix connus.
    public var rankPrice: Double { isKnown ? price : RouteEngine.unknownPenalty }
}

public struct PricedStep: Sendable, Identifiable {
    public let id: String
    public let from: PlaceID
    public let to: PlaceID
    public let day: Day
    public let dayOffset: Int
    /// Minutes depuis minuit du jour de départ du trajet.
    public let startMinute: Int
    /// Options triées : prix connus d'abord, du moins cher au plus cher. La première est retenue.
    public let options: [PricedOption]
    /// Prix compté dans un billet aller-retour.
    public var roundTripPaired: Bool

    public var chosen: PricedOption { options[0] }
    public var mode: Mode { chosen.option.mode }
    /// Étape dont le prix n'est connu ni seul ni dans un billet aller-retour.
    public var isUnpriced: Bool { !roundTripPaired && !chosen.isKnown }
}

public struct RoundTripTicket: Sendable, Identifiable {
    public var id: String { PriceBook.key(from, to) }
    public let from: PlaceID
    public let to: PlaceID
    public let outDay: Day
    public let backDay: Day
    /// Prix pour tous les voyageurs (€).
    public let price: Double
    public let quality: PriceQuality
    public let quote: Quote?
}

public struct RoundTrip: Sendable, Identifiable {
    public let id: String
    public let outSignature: String
    public let inSignature: String
    public let outDay: Day
    public let backDay: Day
    public let outbound: [PricedStep]
    public let inbound: [PricedStep]
    public let localTransfer: [PricedStep]
    public let rtTickets: [RoundTripTicket]
    /// Somme des prix réels connus (€). Les étapes sans prix publié n'y sont pas comptées.
    public let total: Double
    public let outDurationMin: Int
    public let inDurationMin: Int
    public let tickets: Int
    /// Étapes sans prix publié.
    public let unpriced: Int
    public let unprotected: Int
    public let unverified: Int
    public let rare: Int

    public var stayDays: Int { outDay.days(until: backDay) }
    public var arrival: PlaceID { outbound.last?.to ?? .diego }
    public var departureBack: PlaceID { inbound.first?.from ?? .diego }
    public var isOpenJaw: Bool { arrival != departureBack }
    /// Toutes les étapes ont un prix réel ou un tarif officiel.
    public var isComplete: Bool { unpriced == 0 }

    public var summary: String {
        "\(Fmt.dayShort(outDay)) au \(Fmt.dayShort(backDay)), arrivée \(NetworkData.place(arrival).short), "
            + "retour depuis \(NetworkData.place(departureBack).short), \(Fmt.euro(total))"
            + (isComplete ? "" : " + \(unpriced) étape(s) sans prix publié")
    }
}

public struct EngineStats: Sendable {
    public let outPaths: Int
    public let datePairs: Int
    public let combos: Int
    public let results: Int
    public let complete: Int
    public let millis: Int

    public var description: String {
        "\(outPaths) trajets possibles par sens, \(datePairs) paires de dates, "
            + "\(combos) combinaisons évaluées, \(results) résultats dont \(complete) entièrement à prix réels, \(millis) ms"
    }
}

public struct DayPrice: Sendable, Identifiable {
    public var id: String { day.key }
    public let day: Day
    public let price: Double
}

public struct EngineResult: Sendable {
    public let trips: [RoundTrip]
    public let bestByDay: [DayPrice]
    public let stats: EngineStats
}

/// Calcule tous les allers-retours possibles sur toutes les paires de dates, uniquement avec des prix réels.
public struct RouteEngine: Sendable {
    /// Coût de classement d'une étape sans prix publié : les trajets complets passent toujours devant.
    public static let unknownPenalty = 100_000.0

    public let params: SearchParams
    public let book: PriceBook
    public let network: FilteredNetwork
    public let outPaths: [RoutePath]
    public let inPaths: [RoutePath]
    let days: [Day]
    let dayIndex: [Day: Int]
    /// Un prix relevé n'est affiché « temps réel » que s'il date de moins de 3 heures.
    let now = Date()

    func quality(of quote: Quote) -> PriceQuality {
        quote.source.isLive && now.timeIntervalSince(quote.fetchedAt) < 3 * 3600 ? .live : .cached
    }

    struct PathCalc: Sendable {
        let index: Int
        /// Coût de classement (prix connus + pénalité par étape sans prix).
        let rankCost: Double
        /// Somme des prix connus.
        let knownCost: Double
        let duration: Int
        let steps: [PricedStep]
    }

    struct Candidate {
        let pair: Int
        let out: Int
        let back: Int
        let total: Double
    }

    public init(params: SearchParams, book: PriceBook, connections: [Connection] = NetworkData.connections) {
        self.params = params
        self.book = book
        let network = FilteredNetwork(params: params, all: connections)
        self.network = network
        let targets = params.destinations.isEmpty ? Set(NetworkData.destinations) : params.destinations
        let outs = network.outboundPaths(from: NetworkData.start, to: targets)
        self.outPaths = outs
        self.inPaths = outs.map { $0.reversed() }
        var list: [Day] = []
        var cursor = params.periodStart.adding(days: -3)
        let end = params.periodEnd.adding(days: 6)
        while cursor <= end {
            list.append(cursor)
            cursor = cursor.adding(days: 1)
        }
        self.days = list
        var index: [Day: Int] = [:]
        for (i, day) in list.enumerated() { index[day] = i }
        self.dayIndex = index
    }

    func day(_ start: Day, plus offset: Int) -> Day {
        if let i = dayIndex[start], i + offset >= 0, i + offset < days.count { return days[i + offset] }
        return start.adding(days: offset)
    }

    static func buffer(previous: Mode, next: Mode) -> Int {
        if next == .avion { return previous == .avion ? 180 : 120 }
        if previous == .avion { return 60 }
        if next == .local || previous == .local { return 15 }
        return 45
    }

    func priceOption(_ option: TransportOption, from: PlaceID, to: PlaceID, day: Day) -> PricedOption {
        let mult = option.perVehicle ? 1.0 : Double(params.adults)
        switch option.kind {
        case .flight:
            if let quote = book.oneWay[PriceBook.key(from, to)]?[day.key] {
                return PricedOption(option: option, price: quote.price * mult, quality: quality(of: quote), quote: quote)
            }
            return PricedOption(option: option, price: 0, quality: .unknown, quote: nil,
                                info: "Aucun prix relevé pour ce vol à cette date.")
        case .flixbus:
            if let quote = book.bus[PriceBook.key(from, to)]?[day.key] {
                return PricedOption(option: option, price: quote.price * mult, quality: quality(of: quote), quote: quote)
            }
            return PricedOption(option: option, price: 0, quality: .unknown, quote: nil,
                                info: "Prix FlixBus pas encore relevé pour cette date.")
        case .tariff:
            if let mga = option.tariffMGA {
                guard let rate = book.mgaPerEur, rate > 0 else {
                    return PricedOption(option: option, price: 0, quality: .unknown, quote: nil,
                                        info: "Tarif : \(Fmt.ariary(mga)). Taux de change euro/ariary pas encore relevé.")
                }
                let euros = (mga / rate * 100).rounded() / 100
                let quote = Quote(price: euros, source: .tariff,
                                  detail: "\(Fmt.ariary(mga)) au taux de 1 € = \(Fmt.ariary(rate.rounded()))",
                                  fetchedAt: book.mgaRateDate ?? Date())
                return PricedOption(option: option, price: euros * mult, quality: .tariff, quote: quote)
            }
            let quote = Quote(price: option.priceMin, source: .tariff, detail: option.tariffSource,
                              fetchedAt: Date(timeIntervalSince1970: 0))
            return PricedOption(option: option, price: option.priceMin * mult, quality: .tariff, quote: quote)
        case .offline:
            var info = "Pas de prix publié en ligne pour cette date."
            if let grid = book.trainGrid[option.id] ?? NetworkData.defaultTrainGrid[option.id] {
                info = "Billets pas encore en vente pour cette date. \(grid.summary.prefix(1).uppercased())\(grid.summary.dropFirst())."
            }
            return PricedOption(option: option, price: 0, quality: .unknown, quote: nil, info: info)
        }
    }

    func pricePath(_ path: RoutePath, index: Int, start: Day) -> PathCalc {
        var minute = 8 * 60
        var rankCost = 0.0
        var knownCost = 0.0
        var steps: [PricedStep] = []
        steps.reserveCapacity(path.connections.count)
        var previousMode: Mode?
        for (k, connectionIndex) in path.connections.enumerated() {
            let connection = network.connections[connectionIndex]
            let from = path.places[k]
            let to = path.places[k + 1]
            if let prev = previousMode {
                minute += Self.buffer(previous: prev, next: connection.options[0].mode)
            }
            let offset = minute / 1440
            let legDay = day(start, plus: offset)
            var options = connection.options.map { priceOption($0, from: from, to: to, day: legDay) }
            options.sort { lhs, rhs in
                lhs.rankPrice < rhs.rankPrice || (lhs.rankPrice == rhs.rankPrice && lhs.quality > rhs.quality)
            }
            let chosen = options[0]
            steps.append(PricedStep(id: "\(k)-\(connection.id)", from: from, to: to, day: legDay,
                                    dayOffset: offset, startMinute: minute, options: options,
                                    roundTripPaired: false))
            rankCost += chosen.rankPrice
            knownCost += chosen.price
            minute += chosen.option.durationMin
            previousMode = chosen.option.mode
        }
        return PathCalc(index: index, rankCost: rankCost, knownCost: knownCost, duration: minute - 8 * 60, steps: steps)
    }

    /// Vols pris à l'aller et au retour sur la même paire de villes : billet aller-retour réel s'il est
    /// moins cher que deux allers simples (un aller simple sans prix publié compte comme très cher).
    func pairing(_ out: PathCalc, _ back: PathCalc) -> (rankSavings: Double, knownSavings: Double, tickets: [RoundTripTicket]) {
        var rankSavings = 0.0
        var knownSavings = 0.0
        var tickets: [RoundTripTicket] = []
        for o in out.steps where o.chosen.option.kind == .flight {
            guard let b = back.steps.first(where: {
                $0.from == o.to && $0.to == o.from && $0.chosen.option.kind == .flight
            }) else { continue }
            guard let quote = book.roundTrip[PriceBook.key(o.from, o.to)]?[PriceBook.pairKey(o.day, b.day)] else { continue }
            let roundTrip = quote.price * Double(params.adults)
            let separateRank = o.chosen.rankPrice + b.chosen.rankPrice
            if roundTrip < separateRank {
                rankSavings += separateRank - roundTrip
                knownSavings += o.chosen.price + b.chosen.price - roundTrip
                tickets.append(RoundTripTicket(from: o.from, to: o.to, outDay: o.day, backDay: b.day,
                                               price: roundTrip, quality: quality(of: quote), quote: quote))
            }
        }
        return (rankSavings, knownSavings, tickets)
    }

    public func run(maxResults: Int = 400, independentTop: Int = 20) -> EngineResult {
        let started = Date()
        let pairs = params.datePairs
        guard !outPaths.isEmpty, !pairs.isEmpty else {
            return EngineResult(trips: [], bestByDay: [],
                                stats: EngineStats(outPaths: outPaths.count, datePairs: pairs.count,
                                                   combos: 0, results: 0, complete: 0, millis: 0))
        }

        var outCalc: [Day: [PathCalc]] = [:]
        for d in Set(pairs.map(\.out)) {
            outCalc[d] = outPaths.enumerated().map { pricePath($0.element, index: $0.offset, start: d) }
        }
        var inCalc: [Day: [PathCalc]] = [:]
        for d in Set(pairs.map(\.back)) {
            inCalc[d] = inPaths.enumerated().map { pricePath($0.element, index: $0.offset, start: d) }
        }
        var outOrder: [Day: [Int]] = [:]
        for (d, list) in outCalc { outOrder[d] = list.indices.sorted { list[$0].rankCost < list[$1].rankCost } }
        var inOrder: [Day: [Int]] = [:]
        for (d, list) in inCalc { inOrder[d] = list.indices.sorted { list[$0].rankCost < list[$1].rankCost } }

        // Trajet sur place entre les deux villes (arrivée à l'une, retour depuis l'autre).
        var transfers: [String: Double] = [:]
        let ends = Set(outPaths.map(\.end))
        for a in ends {
            for b in ends where a != b {
                guard let t = network.cheapestTransfer(from: a, to: b, adults: params.adults) else { continue }
                let calc = pricePath(RoutePath(places: t.places, connections: t.connections), index: -1,
                                     start: params.periodStart)
                transfers["\(a.rawValue)>\(b.rawValue)"] = calc.rankCost
            }
        }

        var best: [Int: Candidate] = [:]
        var bestByDay: [Day: Double] = [:]
        var combos = 0
        let keyStride = inPaths.count + 1

        for (pairIndex, pair) in pairs.enumerated() {
            guard let outs = outCalc[pair.out], let ins = inCalc[pair.back],
                  let outSorted = outOrder[pair.out], let inSorted = inOrder[pair.back] else { continue }

            func consider(_ o: Int, _ i: Int, _ total: Double) {
                combos += 1
                let key = o * keyStride + i
                if (best[key]?.total ?? .infinity) > total {
                    best[key] = Candidate(pair: pairIndex, out: o, back: i, total: total)
                }
                // Le graphique ne montre que des totaux entièrement réels.
                if total < Self.unknownPenalty && total < (bestByDay[pair.out] ?? .infinity) {
                    bestByDay[pair.out] = total
                }
            }

            for o in outSorted.prefix(independentTop) {
                for i in inSorted.prefix(independentTop) {
                    let arrival = outPaths[o].end
                    let departure = inPaths[i].origin
                    if arrival != departure && !params.allowOpenJaw { continue }
                    let local = arrival == departure ? 0 : (transfers["\(arrival.rawValue)>\(departure.rawValue)"] ?? .infinity)
                    guard local.isFinite else { continue }
                    let savings = pairing(outs[o], ins[i]).rankSavings
                    consider(o, i, outs[o].rankCost + ins[i].rankCost + local - savings)
                }
            }
            for o in outs.indices {
                let savings = pairing(outs[o], ins[o]).rankSavings
                consider(o, o, outs[o].rankCost + ins[o].rankCost - savings)
            }
        }

        let ranked = best.values.sorted { $0.total < $1.total }.prefix(maxResults)
        var trips: [RoundTrip] = ranked.compactMap { candidate -> RoundTrip? in
            let pair = pairs[candidate.pair]
            guard let o = outCalc[pair.out]?[candidate.out], let i = inCalc[pair.back]?[candidate.back] else { return nil }
            return makeTrip(o, i, pair: pair)
        }
        trips.sort { ($0.unpriced, $0.total) < ($1.unpriced, $1.total) }
        let byDay = bestByDay.map { DayPrice(day: $0.key, price: $0.value) }.sorted { $0.day < $1.day }
        let millis = Int(Date().timeIntervalSince(started) * 1000)
        return EngineResult(trips: trips, bestByDay: byDay,
                            stats: EngineStats(outPaths: outPaths.count, datePairs: pairs.count, combos: combos,
                                               results: trips.count, complete: trips.filter(\.isComplete).count,
                                               millis: millis))
    }

    /// Recalcule un aller-retour précis (après une vérification des prix en temps réel).
    public func evaluate(outSignature: String, inSignature: String, out: Day, back: Day) -> RoundTrip? {
        guard let oi = outPaths.firstIndex(where: { $0.signature == outSignature }),
              let ii = inPaths.firstIndex(where: { $0.signature == inSignature }) else { return nil }
        let o = pricePath(outPaths[oi], index: oi, start: out)
        let i = pricePath(inPaths[ii], index: ii, start: back)
        return makeTrip(o, i, pair: DatePair(out: out, back: back))
    }

    func makeTrip(_ o: PathCalc, _ i: PathCalc, pair: DatePair) -> RoundTrip {
        let paired = pairing(o, i)
        let pairedRoutes = Set(paired.tickets.map { PriceBook.key($0.from, $0.to) })

        let outbound: [PricedStep] = o.steps.map { step in
            var s = step
            s.roundTripPaired = pairedRoutes.contains(PriceBook.key(step.from, step.to))
            return s
        }
        let inbound: [PricedStep] = i.steps.map { step in
            var s = step
            s.roundTripPaired = pairedRoutes.contains(PriceBook.key(step.to, step.from))
            return s
        }

        let arrival = outPaths[o.index].end
        let departure = inPaths[i.index].origin
        var local: [PricedStep] = []
        var localCost = 0.0
        if arrival != departure, let transfer = network.cheapestTransfer(from: arrival, to: departure, adults: params.adults) {
            let path = RoutePath(places: transfer.places, connections: transfer.connections)
            let calc = pricePath(path, index: -1, start: pair.out.adding(days: 3))
            local = calc.steps
            localCost = calc.knownCost
        }

        func unprotected(_ steps: [PricedStep]) -> Int {
            guard steps.count > 1 else { return 0 }
            var count = 0
            for k in 1..<steps.count where steps[k - 1].mode == .avion && steps[k].mode == .avion {
                count += 1
            }
            return count
        }

        let all = outbound + inbound + local
        let legs = all.filter { $0.mode != .local }.count
        return RoundTrip(
            id: "\(outPaths[o.index].signature)|\(inPaths[i.index].signature)",
            outSignature: outPaths[o.index].signature,
            inSignature: inPaths[i.index].signature,
            outDay: pair.out,
            backDay: pair.back,
            outbound: outbound,
            inbound: inbound,
            localTransfer: local,
            rtTickets: paired.tickets,
            total: o.knownCost + i.knownCost - paired.knownSavings + localCost,
            outDurationMin: o.duration,
            inDurationMin: i.duration,
            tickets: legs - paired.tickets.count,
            unpriced: all.filter(\.isUnpriced).count,
            unprotected: unprotected(outbound) + unprotected(inbound),
            unverified: all.filter { !$0.chosen.option.verified }.count,
            rare: all.filter { $0.chosen.option.rare }.count
        )
    }
}
