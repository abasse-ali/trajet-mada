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

/// Un calendrier de prix Google Flights : tous les départs d'une période pour un trajet
/// (aller-retour avec une durée de séjour fixe, ou aller simple).
public struct CalendarJob: Hashable, Sendable {
    public let from: PlaceID
    public let to: PlaceID
    /// Durée du séjour en jours ; nil pour un aller simple.
    public let stay: Int?
    public let start: Day
    public let end: Day

    /// « PAR>NOS#29 » ou « TNR>DIE#aller »
    public var key: String { "\(PriceBook.key(from, to))#\(stay.map(String.init) ?? "aller")" }
}

public enum Collector {
    /// Allers-retours relevés dans le calendrier Google Flights (aller côté France). Pas de Toulouse-Diego
    /// ni de Paris-Diego : Google Flights ne vend aucun billet jusqu'à Antsiranana depuis la France.
    public static let serpRoundTrips: [(PlaceID, PlaceID)] = [
        (.parisAirports, .nosyBe), (.parisAirports, .tana), (.toulouseAirport, .nosyBe),
        (.toulouseAirport, .tana), (.milan, .nosyBe),
    ]

    /// Vols intérieurs à Madagascar (Madagascar Airlines) relevés en aller simple.
    public static let serpOneWays: [(PlaceID, PlaceID)] = [
        (.tana, .diego), (.diego, .tana), (.tana, .nosyBe), (.nosyBe, .tana),
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
    /// Tous les calendriers nécessaires pour couvrir la période : chaque grand axe pour chaque durée de
    /// séjour autorisée, et chaque vol intérieur en aller simple. Environ 20 recherches au total.
    public static func calendarJobs(params: SearchParams) -> [CalendarJob] {
        let low = max(1, min(params.stayMin, params.stayMax))
        let high = max(params.stayMin, params.stayMax)
        let lastBack = params.lastReturnDay
        var jobs: [CalendarJob] = []
        for stay in low...high {
            let lastOut = lastBack.adding(days: -stay)
            guard lastOut >= params.periodStart else { continue }
            for (from, to) in serpRoundTrips {
                jobs.append(CalendarJob(from: from, to: to, stay: stay, start: params.periodStart, end: lastOut))
            }
        }
        for (from, to) in serpOneWays {
            jobs.append(CalendarJob(from: from, to: to, stay: nil, start: params.periodStart, end: lastBack))
        }
        return jobs
    }

    /// Calendriers à relever maintenant : ceux jamais relevés, puis les plus anciens, s'ils datent de plus
    /// de `maxAge` (par l'iPhone ou le serveur). Au plus `budget` recherches.
    public static func calendarPlan(params: SearchParams, fetched: [String: Date], budget: Int,
                                    now: Date = Date(), maxAge: TimeInterval = 4 * 86_400) -> [CalendarJob] {
        guard budget > 0 else { return [] }
        let jobs = calendarJobs(params: params).enumerated().filter { _, job in
            guard let last = fetched[job.key] else { return true }
            return now.timeIntervalSince(last) >= maxAge
        }
        let sorted = jobs.sorted { lhs, rhs in
            let l = fetched[lhs.element.key] ?? .distantPast
            let r = fetched[rhs.element.key] ?? .distantPast
            return l != r ? l < r : lhs.offset < rhs.offset
        }
        return Array(sorted.map(\.element).prefix(budget))
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
