import Foundation

public enum PriceQuality: Int, Sendable, Comparable, Codable {
    case estimate = 0
    case tariff = 1
    case cached = 2
    case live = 3

    public static func < (lhs: PriceQuality, rhs: PriceQuality) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .estimate: return "estimation"
        case .tariff: return "tarif connu"
        case .cached: return "prix réel"
        case .live: return "temps réel"
        }
    }

    public var isReal: Bool { self >= .cached }
}

public struct PricedOption: Sendable, Identifiable {
    public var id: String { option.id }
    public let option: TransportOption
    /// Prix pour tous les voyageurs (€).
    public let price: Double
    public let quality: PriceQuality
    public let quote: Quote?
}

public struct PricedStep: Sendable, Identifiable {
    public let id: String
    public let from: PlaceID
    public let to: PlaceID
    public let day: Day
    public let dayOffset: Int
    /// Minutes depuis minuit du jour de départ du trajet.
    public let startMinute: Int
    /// Options triées par prix : la première est retenue.
    public let options: [PricedOption]
    /// Prix compté dans un billet aller-retour.
    public var roundTripPaired: Bool

    public var chosen: PricedOption { options[0] }
    public var mode: Mode { chosen.option.mode }
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
    public let total: Double
    public let outDurationMin: Int
    public let inDurationMin: Int
    public let tickets: Int
    /// Part du total couverte par des prix réels ou des tarifs connus (0 à 1).
    public let realShare: Double
    public let unprotected: Int
    public let unverified: Int
    public let rare: Int

    public var stayDays: Int { outDay.days(until: backDay) }
    public var arrival: PlaceID { outbound.last?.to ?? .diego }
    public var departureBack: PlaceID { inbound.first?.from ?? .diego }
    public var isOpenJaw: Bool { arrival != departureBack }

    /// Tous les vols ont un prix réel (cache ou temps réel).
    public var flightsAllReal: Bool {
        let flights = (outbound + inbound).filter { $0.mode == .avion }
        return flights.allSatisfy { step in
            step.roundTripPaired ? rtTickets.contains { $0.quality.isReal } : step.chosen.quality.isReal
        }
    }

    public var summary: String {
        "\(Fmt.dayShort(outDay)) au \(Fmt.dayShort(backDay)), arrivée \(NetworkData.place(arrival).short), "
            + "retour depuis \(NetworkData.place(departureBack).short), \(Fmt.euro(total))"
    }
}

public struct EngineStats: Sendable {
    public let outPaths: Int
    public let datePairs: Int
    public let combos: Int
    public let results: Int
    public let millis: Int

    public var description: String {
        "\(outPaths) trajets possibles par sens, \(datePairs) paires de dates, "
            + "\(combos) combinaisons évaluées, \(results) résultats, \(millis) ms"
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

/// Calcule tous les allers-retours possibles sur toutes les paires de dates.
public struct RouteEngine: Sendable {
    public let params: SearchParams
    public let book: PriceBook
    public let network: FilteredNetwork
    public let outPaths: [RoutePath]
    public let inPaths: [RoutePath]
    let calibration: [String: Double]
    let days: [Day]
    let dayIndex: [Day: Int]

    struct PathCalc: Sendable {
        let index: Int
        let cost: Double
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
        self.calibration = book.calibration()
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
            let route = PriceBook.key(from, to)
            if let quote = book.oneWay[route]?[day.key] {
                return PricedOption(option: option, price: quote.price * mult,
                                    quality: quote.source.isLive ? .live : .cached, quote: quote)
            }
            let fallback = calibration["\(route)#\(day.monthKey)"] ?? calibration[route] ?? option.priceTypical
            return PricedOption(option: option, price: fallback * mult, quality: .estimate, quote: nil)
        case .flixbus:
            if let quote = book.bus[PriceBook.key(from, to)]?[day.key] {
                return PricedOption(option: option, price: quote.price * mult, quality: .live, quote: quote)
            }
            return PricedOption(option: option, price: option.priceTypical * mult, quality: .estimate, quote: nil)
        case .estimate:
            return PricedOption(option: option, price: option.priceTypical * mult, quality: .estimate, quote: nil)
        case .tariff:
            return PricedOption(option: option, price: option.priceMin * mult, quality: .tariff, quote: nil)
        }
    }

    func pricePath(_ path: RoutePath, index: Int, start: Day) -> PathCalc {
        var minute = 8 * 60
        var cost = 0.0
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
                lhs.price < rhs.price || (lhs.price == rhs.price && lhs.quality > rhs.quality)
            }
            let chosen = options[0]
            steps.append(PricedStep(id: "\(k)-\(connection.id)", from: from, to: to, day: legDay,
                                    dayOffset: offset, startMinute: minute, options: options,
                                    roundTripPaired: false))
            cost += chosen.price
            minute += chosen.option.durationMin
            previousMode = chosen.option.mode
        }
        return PathCalc(index: index, cost: cost, duration: minute - 8 * 60, steps: steps)
    }

    /// Vols pris à l'aller et au retour sur la même paire de villes : billet aller-retour si moins cher.
    func pairing(_ out: PathCalc, _ back: PathCalc) -> (savings: Double, tickets: [RoundTripTicket]) {
        var savings = 0.0
        var tickets: [RoundTripTicket] = []
        for o in out.steps where o.chosen.option.kind == .flight {
            guard let b = back.steps.first(where: {
                $0.from == o.to && $0.to == o.from && $0.chosen.option.kind == .flight
            }) else { continue }
            guard let quote = book.roundTrip[PriceBook.key(o.from, o.to)]?[PriceBook.pairKey(o.day, b.day)] else { continue }
            let roundTrip = quote.price * Double(params.adults)
            let separate = o.chosen.price + b.chosen.price
            if roundTrip < separate {
                savings += separate - roundTrip
                tickets.append(RoundTripTicket(from: o.from, to: o.to, outDay: o.day, backDay: b.day,
                                               price: roundTrip, quality: quote.source.isLive ? .live : .cached,
                                               quote: quote))
            }
        }
        return (savings, tickets)
    }

    public func run(maxResults: Int = 400, independentTop: Int = 20) -> EngineResult {
        let started = Date()
        let pairs = params.datePairs
        guard !outPaths.isEmpty, !pairs.isEmpty else {
            return EngineResult(trips: [], bestByDay: [],
                                stats: EngineStats(outPaths: outPaths.count, datePairs: pairs.count,
                                                   combos: 0, results: 0, millis: 0))
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
        for (d, list) in outCalc { outOrder[d] = list.indices.sorted { list[$0].cost < list[$1].cost } }
        var inOrder: [Day: [Int]] = [:]
        for (d, list) in inCalc { inOrder[d] = list.indices.sorted { list[$0].cost < list[$1].cost } }

        var transfers: [String: Double] = [:]
        let ends = Set(outPaths.map(\.end))
        for a in ends {
            for b in ends {
                transfers["\(a.rawValue)>\(b.rawValue)"] =
                    network.cheapestTransfer(from: a, to: b, adults: params.adults)?.cost ?? .infinity
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
                if total < (bestByDay[pair.out] ?? .infinity) { bestByDay[pair.out] = total }
            }

            // Combinaisons libres entre les meilleurs allers et les meilleurs retours du jour.
            for o in outSorted.prefix(independentTop) {
                for i in inSorted.prefix(independentTop) {
                    let arrival = outPaths[o].end
                    let departure = inPaths[i].origin
                    if arrival != departure && !params.allowOpenJaw { continue }
                    let local = transfers["\(arrival.rawValue)>\(departure.rawValue)"] ?? .infinity
                    guard local.isFinite else { continue }
                    let savings = pairing(outs[o], ins[i]).savings
                    consider(o, i, outs[o].cost + ins[i].cost + local - savings)
                }
            }
            // Retour par le même chemin : chaque trajet possible apparaît au moins une fois.
            for o in outs.indices {
                let savings = pairing(outs[o], ins[o]).savings
                consider(o, o, outs[o].cost + ins[o].cost - savings)
            }
        }

        let ranked = best.values.sorted { $0.total < $1.total }.prefix(maxResults)
        var trips: [RoundTrip] = ranked.compactMap { candidate -> RoundTrip? in
            let pair = pairs[candidate.pair]
            guard let o = outCalc[pair.out]?[candidate.out], let i = inCalc[pair.back]?[candidate.back] else { return nil }
            return makeTrip(o, i, pair: pair)
        }
        trips.sort { $0.total < $1.total }
        let byDay = bestByDay.map { DayPrice(day: $0.key, price: $0.value) }.sorted { $0.day < $1.day }
        let millis = Int(Date().timeIntervalSince(started) * 1000)
        return EngineResult(trips: trips, bestByDay: byDay,
                            stats: EngineStats(outPaths: outPaths.count, datePairs: pairs.count,
                                               combos: combos, results: trips.count, millis: millis))
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
            localCost = calc.cost
        }

        let total = o.cost + i.cost - paired.savings + localCost
        var realAmount: Double = paired.tickets.reduce(0.0) { $0 + $1.price }
        for step in outbound + inbound + local where !step.roundTripPaired && step.chosen.quality >= .tariff {
            realAmount += step.chosen.price
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
            total: total,
            outDurationMin: o.duration,
            inDurationMin: i.duration,
            tickets: legs - paired.tickets.count,
            realShare: total > 0 ? min(1, realAmount / total) : 0,
            unprotected: unprotected(outbound) + unprotected(inbound),
            unverified: all.filter { !$0.chosen.option.verified }.count,
            rare: all.filter { $0.chosen.option.rare }.count
        )
    }
}
