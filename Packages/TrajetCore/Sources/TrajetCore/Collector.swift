import Foundation

/// Collecte complète des prix et horaires, identique à celle du serveur (server/trajetmada_update.py),
/// mais exécutée sur l'iPhone.

public struct BusRequest: Hashable, Sendable {
    public let from: PlaceID
    public let to: PlaceID
    public let day: Day

    public init(from: PlaceID, to: PlaceID, day: Day) {
        self.from = from
        self.to = to
        self.day = day
    }
}

public struct SerpCandidate: Hashable, Sendable {
    public let from: PlaceID
    public let to: PlaceID
    public let out: Day
    public let back: Day
    /// Prix Aviasales à vérifier ; nil pour un sondage d'une date sans prix connu.
    public let aviasalesPrice: Double?
}

public enum Collector {
    /// Grands axes vérifiés sur Google Flights (aller côté France).
    public static let serpCorridors: [(PlaceID, PlaceID)] = [
        (.toulouseAirport, .diego), (.toulouseAirport, .nosyBe), (.parisAirports, .tana),
        (.parisAirports, .nosyBe), (.parisAirports, .diego), (.milan, .nosyBe), (.toulouseAirport, .tana),
    ]

    /// Trajets en train dont on relève les horaires SNCF.
    public static let trainRoutes: [(PlaceID, PlaceID)] = [
        (.toulouse, .parisStations), (.parisStations, .toulouse), (.parisStations, .milan), (.milan, .parisStations),
    ]

    /// Prix FlixBus à relever : chaque jour de la période, dans les deux sens, sauf ceux relevés depuis moins de `maxAge`.
    public static func busRequests(params: SearchParams, book: PriceBook, now: Date = Date(),
                                   maxAge: TimeInterval = 12 * 3600) -> [BusRequest] {
        guard params.modes.contains(.bus) else { return [] }
        var result: [BusRequest] = []
        var day = params.periodStart
        while day <= params.periodEnd {
            for (from, to) in [(PlaceID.toulouse, PlaceID.parisStations), (.parisStations, .toulouse)] {
                if let quote = book.bus[PriceBook.key(from, to)]?[day.key], now.timeIntervalSince(quote.fetchedAt) < maxAge {
                    continue
                }
                result.append(BusRequest(from: from, to: to, day: day))
            }
            day = day.adding(days: 1)
        }
        return result
    }

    /// Jours à interroger pour les horaires SNCF : jours exacts publiés dans la période,
    /// et un jour de référence par jour de semaine (horaires types).
    public static func scheduleDays(params: SearchParams, window: SNCFWindow, today: Day)
        -> (exact: [Day], typical: [Int: Day]) {
        var exact: [Day] = []
        var day = max(params.periodStart, window.start)
        let last = min(params.periodEnd, window.end)
        while day <= last {
            exact.append(day)
            day = day.adding(days: 1)
        }
        var typical: [Int: Day] = [:]
        day = max(window.start, today.adding(days: 1))
        while day <= window.end {
            if typical[day.weekday] == nil { typical[day.weekday] = day }
            day = day.adding(days: 1)
        }
        return (exact, typical)
    }

    /// Allers-retours à vérifier sur Google Flights : d'abord le moins cher d'Aviasales sur chaque axe,
    /// puis un sondage par axe (date tournant chaque jour, axes jamais vérifiés en premier).
    /// Les couples déjà vérifiés depuis moins de `keepDays` jours (par l'app ou le serveur) sont ignorés.
    public static func serpPlan(book: PriceBook, params: SearchParams, today: Day, budget: Int,
                                now: Date = Date(), keepDays: Int = 10, rotationOffset: Int = 5) -> [SerpCandidate] {
        guard budget > 0 else { return [] }
        let keep = TimeInterval(keepDays) * 86_400
        let low = min(params.stayMin, params.stayMax)
        let high = max(params.stayMin, params.stayMax)
        let lastBack = params.lastReturnDay

        var verified = Set<String>()
        var covered = Set<String>()
        for (route, pairs) in book.roundTrip {
            for (pair, quote) in pairs where quote.source == .serpapi && now.timeIntervalSince(quote.fetchedAt) < keep {
                verified.insert("\(route)|\(pair)")
                covered.insert(route)
            }
        }

        var verify: [SerpCandidate] = []
        for (from, to) in serpCorridors {
            let route = PriceBook.key(from, to)
            var best: SerpCandidate?
            for (pair, quote) in book.roundTrip[route] ?? [:] where quote.source == .travelpayouts {
                let parts = pair.split(separator: "|").map(String.init)
                guard parts.count == 2, let out = Day(isoPrefix: parts[0]), let back = Day(isoPrefix: parts[1]),
                      out >= params.periodStart, back <= lastBack,
                      (low...high).contains(out.days(until: back)),
                      !verified.contains("\(route)|\(pair)") else { continue }
                if best == nil || quote.price < (best?.aviasalesPrice ?? .infinity) {
                    best = SerpCandidate(from: from, to: to, out: out, back: back, aviasalesPrice: quote.price)
                }
            }
            if let best { verify.append(best) }
        }
        verify.sort { ($0.aviasalesPrice ?? 0) < ($1.aviasalesPrice ?? 0) }

        let stay = (low + high) / 2
        var grid: [Day] = []
        var day = params.periodStart
        while day.adding(days: stay) <= lastBack {
            grid.append(day)
            day = day.adding(days: 7)
        }
        // Un axe déjà vérifié pendant cette collecte n'est pas sondé en plus.
        let verifyRoutes = Set(verify.map { PriceBook.key($0.from, $0.to) })
        var probes: [(candidate: SerpCandidate, covered: Bool, order: Int)] = []
        if !grid.isEmpty {
            let ordinal = Day(year: 2000, month: 1, day: 1).days(until: today)
            for (index, corridor) in serpCorridors.enumerated() {
                let route = PriceBook.key(corridor.0, corridor.1)
                guard !verifyRoutes.contains(route) else { continue }
                let out = grid[((ordinal + rotationOffset + index * 3) % grid.count + grid.count) % grid.count]
                let back = out.adding(days: stay)
                guard !verified.contains("\(route)|\(PriceBook.pairKey(out, back))") else { continue }
                probes.append((SerpCandidate(from: corridor.0, to: corridor.1, out: out, back: back, aviasalesPrice: nil),
                               covered.contains(route), index))
            }
        }
        probes.sort { ($0.covered ? 1 : 0, $0.order) < ($1.covered ? 1 : 0, $1.order) }
        return Array((verify + probes.map(\.candidate)).prefix(budget))
    }
}

extension SNCFClient {
    /// Horaires SNCF de tous les trajets en train : jours exacts publiés et horaires types par jour de semaine.
    public func collectSchedules(params: SearchParams, today: Day) async throws -> (schedules: FeedSchedules, window: SNCFWindow, failures: Int) {
        let window = try await self.window()
        let days = Collector.scheduleDays(params: params, window: window, today: today)
        struct Job: Sendable {
            let from: PlaceID
            let to: PlaceID
            let day: Day
            let exact: Bool
        }
        var jobs: [Job] = []
        for (from, to) in Collector.trainRoutes {
            guard NetworkData.place(from).sncfID != nil, NetworkData.place(to).sncfID != nil else { continue }
            for day in days.exact { jobs.append(Job(from: from, to: to, day: day, exact: true)) }
            for (_, day) in days.typical.sorted(by: { $0.key < $1.key }) { jobs.append(Job(from: from, to: to, day: day, exact: false)) }
        }
        struct Outcome: Sendable {
            let job: Job
            let journeys: [TrainJourney]?
        }
        let client = self
        let outcomes: [Outcome] = await boundedConcurrentMap(jobs, limit: 2) { job in
            let label = "SNCF horaires \(NetworkData.place(job.from).short)-\(NetworkData.place(job.to).short) \(job.day.key)"
            let journeys = try? await client.journeys(from: NetworkData.place(job.from).sncfID!,
                                                      to: NetworkData.place(job.to).sncfID!, day: job.day, label: label)
            return Outcome(job: job, journeys: journeys)
        }
        var result = FeedSchedules()
        var failures = 0
        for outcome in outcomes {
            guard let journeys = outcome.journeys else {
                failures += 1
                continue
            }
            let job = outcome.job
            if job.exact {
                result.exact["\(job.from.rawValue)>\(job.to.rawValue)>\(job.day.key)"] =
                    TrainSchedule(day: job.day, referenceDay: job.day, exact: true, journeys: journeys)
            } else {
                result.typical["\(job.from.rawValue)>\(job.to.rawValue)#\(job.day.weekday)"] =
                    TrainSchedule(day: job.day, referenceDay: job.day, exact: false, journeys: journeys)
            }
        }
        return (result, window, failures)
    }
}
