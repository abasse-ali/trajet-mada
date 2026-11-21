import Foundation
import Observation
import SwiftUI
import TrajetCore

enum SortKey: String, CaseIterable, Identifiable {
    case price
    case duration
    case simple
    case real

    var id: String { rawValue }
    var label: String {
        switch self {
        case .price: return "Prix"
        case .duration: return "Durée"
        case .simple: return "Billets"
        case .real: return "Fiabilité"
        }
    }
}

enum CollectTrigger: String {
    case manual = "manuelle"
    case background = "automatique (arrière-plan)"
}

struct BusResult: Sendable {
    let request: BusRequest
    let quote: Quote?
}

/// Compteur partagé entre les tâches parallèles pour afficher l'avancement.
actor ProgressCounter {
    private var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}

@Observable
@MainActor
final class AppModel {
    static let shared = AppModel()

    let log: LogStore
    var params: SearchParams
    var book: PriceBook
    var results: [RoundTrip] = []
    var bestByDay: [DayPrice] = []
    var stats: EngineStats?
    var isBusy = false
    var progress: Double = 0
    var progressText = ""
    var travelpayoutsToken: String
    var serpApiKey: String
    var sncfKey: String
    var serpAccount: SerpApiClient.Account?
    var sncfWindow: SNCFWindow?
    /// Horaires demandés à l'API SNCF pour une étape précise (clé personnelle sur l'iPhone).
    var schedules: [String: TrainSchedule] = [:]
    var scheduleErrors: [String: String] = [:]
    private var schedulesLoading: Set<String> = []
    /// Horaires de tous les trains : collectés sur l'iPhone ou publiés par le serveur.
    var trainSchedules = FeedSchedules()

    /// Données publiées chaque jour par le serveur Oracle (prix et horaires).
    var feedURL: String = UserDefaults.standard.string(forKey: "feedURL") ?? AppModel.defaultFeedURL
    var feedAutoUpdate: Bool = UserDefaults.standard.object(forKey: "feedAutoUpdate") as? Bool ?? true
    var feedStatus: String?
    var feedDate: Date?
    var isSyncingFeed = false
    static let defaultFeedURL = "https://raw.githubusercontent.com/abasse-ali/trajet-mada/data/trajetmada-data.json"

    /// Collecte sur l'iPhone.
    var autoCollect: Bool = UserDefaults.standard.object(forKey: "autoCollect") as? Bool ?? true
    var serpDailyBudget: Int = UserDefaults.standard.object(forKey: "serpBudget") as? Int ?? 2
    var lastCollection: Date? = UserDefaults.standard.object(forKey: "lastCollection") as? Date
    var lastCollectionSummary: String? = UserDefaults.standard.string(forKey: "lastCollectionSummary")

    var verifying: Set<String> = []
    var sort: SortKey = .price
    var onlyRealFlights = false
    var visibleCount = 60
    var message: String?

    init() {
        let log = LogStore()
        self.log = log
        self.params = Persist.load(SearchParams.self, "params.json") ?? SearchParams.defaults()
        self.book = Persist.load(PriceBook.self, "prices.json") ?? PriceBook()
        self.travelpayoutsToken = Keychain.get("travelpayouts") ?? ""
        self.serpApiKey = Keychain.get("serpapi") ?? ""
        self.sncfKey = Keychain.get("sncf") ?? ""
        let counts = book.counts
        log.info(.app, "Démarrage de TrajetMada", details:
            "Prix en mémoire : \(counts.oneWay) allers simples, \(counts.roundTrip) allers-retours, \(counts.bus) bus.\n"
            + "Clé Travelpayouts : \(travelpayoutsToken.isEmpty ? "absente" : "présente"). "
            + "Clé SerpApi : \(serpApiKey.isEmpty ? "absente" : "présente"). "
            + "Clé SNCF : \(sncfKey.isEmpty ? "absente" : "présente").")
        if let saved = Persist.load(FeedSchedules.self, "schedules.json") {
            trainSchedules = saved
        }
        if let saved = Persist.loadData("feed.json"), let feed = try? FeedReader.decode(saved) {
            if trainSchedules.isEmpty { trainSchedules = FeedReader.schedules(feed) }
            feedDate = FeedReader.generatedDate(feed)
        }
        Task {
            await self.recompute(reason: "ouverture de l'app")
            if self.feedAutoUpdate { await self.syncFeed() }
            if LaunchOptions.autoSearch { await self.collectAll(trigger: .manual) }
        }
    }

    var hasTravelpayouts: Bool { !travelpayoutsToken.isEmpty }
    var hasSerpApi: Bool { !serpApiKey.isEmpty }
    var hasSNCF: Bool { !sncfKey.isEmpty }

    var sortedResults: [RoundTrip] {
        var list = results
        if onlyRealFlights { list = list.filter { $0.flightsAllReal } }
        switch sort {
        case .price:
            list.sort { $0.total < $1.total }
        case .duration:
            list.sort { ($0.outDurationMin + $0.inDurationMin, $0.total) < ($1.outDurationMin + $1.inDurationMin, $1.total) }
        case .simple:
            list.sort { ($0.tickets, $0.unprotected, $0.total) < ($1.tickets, $1.unprotected, $1.total) }
        case .real:
            list.sort { $0.realShare > $1.realShare || ($0.realShare == $1.realShare && $0.total < $1.total) }
        }
        return list
    }

    func trip(id: String) -> RoundTrip? { results.first { $0.id == id } }

    // MARK: - Réglages

    func saveKeys(travelpayouts: String, serpapi: String, sncf: String) {
        travelpayoutsToken = travelpayouts.trimmingCharacters(in: .whitespacesAndNewlines)
        serpApiKey = serpapi.trimmingCharacters(in: .whitespacesAndNewlines)
        let newSNCF = sncf.trimmingCharacters(in: .whitespacesAndNewlines)
        if newSNCF != sncfKey {
            sncfKey = newSNCF
            schedules = [:]
            scheduleErrors = [:]
            sncfWindow = nil
        }
        Keychain.set(travelpayoutsToken, for: "travelpayouts")
        Keychain.set(serpApiKey, for: "serpapi")
        Keychain.set(sncfKey, for: "sncf")
        log.info(.app, "Clés enregistrées", details:
            "Travelpayouts : \(hasTravelpayouts ? "présente" : "absente"), SerpApi : \(hasSerpApi ? "présente" : "absente"), "
            + "SNCF : \(hasSNCF ? "présente" : "absente")")
    }

    func saveCollectSettings(auto: Bool, serpBudget: Int) {
        autoCollect = auto
        serpDailyBudget = max(0, serpBudget)
        UserDefaults.standard.set(auto, forKey: "autoCollect")
        UserDefaults.standard.set(serpDailyBudget, forKey: "serpBudget")
        scheduleBackgroundCollection()
    }

    func saveFeedSettings(url: String, autoUpdate: Bool) {
        feedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        feedAutoUpdate = autoUpdate
        UserDefaults.standard.set(feedURL, forKey: "feedURL")
        UserDefaults.standard.set(autoUpdate, forKey: "feedAutoUpdate")
    }

    func clearPrices() {
        book = PriceBook()
        trainSchedules = FeedSchedules()
        Persist.remove("prices.json")
        Persist.remove("schedules.json")
        log.warning(.app, "Cache des prix et des horaires effacé")
        Task { await recompute(reason: "cache effacé") }
    }

    func resetParams() {
        params = SearchParams.defaults()
        Persist.save(params, "params.json")
        log.info(.app, "Paramètres remis par défaut", details: params.summary)
    }

    /// Programme (ou annule) la collecte automatique en arrière-plan.
    func scheduleBackgroundCollection() {
        if autoCollect {
            BackgroundCollect.schedule(log: log)
        } else {
            BackgroundCollect.cancel()
        }
    }

    // MARK: - Recherches Google Flights du jour (budget)

    var serpUsedToday: Int {
        let defaults = UserDefaults.standard
        return defaults.string(forKey: "serpDay") == Day(localDate: Date()).key ? defaults.integer(forKey: "serpUsed") : 0
    }

    private func recordSerpUse() {
        let defaults = UserDefaults.standard
        let used = serpUsedToday + 1
        defaults.set(Day(localDate: Date()).key, forKey: "serpDay")
        defaults.set(used, forKey: "serpUsed")
    }

    // MARK: - Collecte complète (identique au serveur)

    /// Bouton « Chercher les prix réels ».
    func search() async {
        await collectAll(trigger: .manual)
    }

    /// Relève tous les prix et horaires depuis l'iPhone : données du serveur, grille SNCF, vols
    /// Travelpayouts, FlixBus jour par jour, horaires SNCF, vérifications Google Flights, puis recalcule.
    @discardableResult
    func collectAll(trigger: CollectTrigger) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        message = nil
        progress = 0
        defer { isBusy = false }
        let started = Date()
        let today = Day(localDate: Date())
        Persist.save(params, "params.json")
        log.info(.scan, "Collecte \(trigger.rawValue) lancée", details: params.summary)
        var summary: [String] = []
        var failures = 0

        // 1. Données du serveur (facultatives : la collecte continue sans elles).
        if feedAutoUpdate {
            progressText = "Données du serveur…"
            await syncFeed(recomputeAfter: false)
        }

        // 2. Grille officielle des prix SNCF.
        progress = 0.04
        progressText = "Grille des prix SNCF…"
        await refreshTrainGrid()
        if Task.isCancelled { return finishCancelled() }

        // 3. Prix des vols (Travelpayouts / Aviasales).
        if hasTravelpayouts {
            let tasks = TravelpayoutsScanner.plan(params: params, network: FilteredNetwork(params: params))
            progressText = "Prix des vols : 0 / \(tasks.count)"
            let scanner = TravelpayoutsScanner(client: TravelpayoutsClient(token: travelpayoutsToken, http: HTTPClient(log: log)))
            let (newBook, scan) = await scanner.run(tasks, into: book) { done, total in
                Task { @MainActor in
                    self.progress = 0.05 + 0.40 * Double(done) / Double(max(total, 1))
                    self.progressText = "Prix des vols : \(done) / \(total)"
                }
            }
            book = newBook
            failures += scan.failures
            summary.append("vols : \(scan.oneWayQuotes) allers simples et \(scan.roundTripQuotes) allers-retours")
            log.log(scan.failures > 0 ? .warning : .info, .scan, scan.summary, details: scan.details)
            if scan.requests > 0 && scan.failures == scan.requests {
                message = "Aucune réponse de Travelpayouts. Vérifiez le jeton dans Réglages (détails dans le Journal)."
            }
        } else if !book.oneWay.isEmpty || !book.roundTrip.isEmpty {
            log.info(.scan, "Pas de jeton Travelpayouts sur l'iPhone : prix des vols du serveur utilisés")
        } else {
            log.warning(.scan, "Pas de jeton Travelpayouts : prix des vols estimés")
            message = "Prix des vols estimés : ajoutez un jeton Travelpayouts dans Réglages, ou installez le serveur de mise à jour."
        }
        if Task.isCancelled { return finishCancelled() }

        // 4. FlixBus, chaque jour de la période et dans les deux sens.
        let busRequests = Collector.busRequests(params: params, book: book)
        if !busRequests.isEmpty {
            progressText = "Prix FlixBus : 0 / \(busRequests.count)"
            let found = await fetchBuses(busRequests, progressFrom: 0.45, progressSpan: 0.30)
            summary.append("FlixBus : \(found) prix")
        }
        if Task.isCancelled { return finishCancelled() }

        // 5. Horaires SNCF (jours publiés et horaires types par jour de semaine).
        if hasSNCF {
            progress = 0.76
            progressText = "Horaires SNCF…"
            do {
                let collected = try await SNCFClient(key: sncfKey, http: HTTPClient(log: log))
                    .collectSchedules(params: params, today: today)
                trainSchedules.merge(collected.schedules)
                sncfWindow = collected.window
                Persist.save(trainSchedules, "schedules.json")
                failures += collected.failures
                summary.append("horaires SNCF : \(collected.schedules.count)")
                log.info(.api, "Horaires SNCF : \(collected.schedules.count) relevés (publiés jusqu'au \(Fmt.dayLong(collected.window.end)))")
            } catch {
                failures += 1
                log.error(.api, "Horaires SNCF : \(error.localizedDescription)")
            }
        }
        if Task.isCancelled { return finishCancelled() }

        // 6. Google Flights : vérification et sondage des grands axes, dans le budget du jour.
        if hasSerpApi {
            let plan = Collector.serpPlan(book: book, params: params, today: today,
                                          budget: max(0, serpDailyBudget - serpUsedToday))
            if !plan.isEmpty {
                let serp = SerpApiClient(key: serpApiKey, http: HTTPClient(log: log))
                var found = 0
                for (index, candidate) in plan.enumerated() {
                    if Task.isCancelled { break }
                    progress = 0.83 + 0.09 * Double(index) / Double(plan.count)
                    progressText = "Google Flights : \(index + 1) / \(plan.count)"
                    guard let a = NetworkData.place(candidate.from).airport, let b = NetworkData.place(candidate.to).airport else { continue }
                    recordSerpUse()
                    do {
                        let r = try await serp.roundTrip(from: a, to: b, out: candidate.out, back: candidate.back, adults: params.adults)
                        let label = "Google Flights \(a.code)-\(b.code) \(Fmt.dayShort(candidate.out)) - \(Fmt.dayShort(candidate.back))"
                        if let total = r.totalPrice {
                            book.putRoundTrip(Quote(price: total / Double(params.adults), source: .serpapi, detail: r.detail,
                                                    link: r.googleFlightsURL),
                                              from: candidate.from, to: candidate.to, out: candidate.out, back: candidate.back)
                            found += 1
                            let compare = candidate.aviasalesPrice.map { "Aviasales : \(Fmt.euro($0 * Double(params.adults)))" }
                                ?? "sondage d'une date sans prix Aviasales"
                            log.info(.api, "\(label) : \(Fmt.euro(total))", details: "\(compare)\n\(r.detail)")
                        } else {
                            log.warning(.api, "\(label) : \(r.detail)")
                        }
                    } catch {
                        failures += 1
                        log.error(.api, "SerpApi : \(error.localizedDescription)")
                    }
                }
                summary.append("Google Flights : \(found) prix")
                await refreshAccount()
            } else {
                log.info(.api, "Google Flights : budget du jour déjà utilisé (\(serpUsedToday) / \(serpDailyBudget)) ou rien à vérifier")
            }
        }

        // 7. Calcul de toutes les combinaisons.
        progress = 0.93
        progressText = "Calcul de toutes les combinaisons…"
        await recompute(reason: "collecte \(trigger.rawValue)")
        Persist.save(book, "prices.json")
        let seconds = Int(Date().timeIntervalSince(started))
        let text = summary.isEmpty ? "aucune nouvelle donnée" : summary.joined(separator: ", ")
        lastCollection = Date()
        lastCollectionSummary = text
        UserDefaults.standard.set(lastCollection, forKey: "lastCollection")
        UserDefaults.standard.set(text, forKey: "lastCollectionSummary")
        log.log(failures > 0 ? .warning : .info, .scan, "Collecte terminée en \(seconds) s : \(text)",
                details: "\(failures) requête(s) en échec. \(results.count) allers-retours calculés.")
        progress = 1
        progressText = "Terminé : \(results.count) allers-retours"
        return true
    }

    private func finishCancelled() -> Bool {
        Persist.save(book, "prices.json")
        log.warning(.scan, "Collecte interrompue par iOS (temps d'arrière-plan écoulé) : les prix déjà relevés sont gardés")
        progressText = "Collecte interrompue"
        return false
    }

    func recompute(reason: String) async {
        let params = self.params
        let book = self.book
        let result = await Task.detached(priority: .userInitiated) {
            RouteEngine(params: params, book: book).run()
        }.value
        results = result.trips
        bestByDay = result.bestByDay
        stats = result.stats
        visibleCount = 60
        log.info(.engine, "Calcul (\(reason)) : \(result.trips.count) allers-retours", details: result.stats.description)
    }

    /// Prix FlixBus réels pour une liste de trajets (3 requêtes en parallèle).
    @discardableResult
    func fetchBuses(_ requests: [BusRequest], progressFrom: Double? = nil, progressSpan: Double = 0) async -> Int {
        let client = FlixBusClient(http: HTTPClient(log: log))
        let adults = params.adults
        let counter = ProgressCounter()
        let total = requests.count
        let answers: [BusResult] = await boundedConcurrentMap(requests, limit: 3) { request in
            let quote = try? await client.quote(from: request.from, to: request.to, day: request.day, adults: adults)
            if let start = progressFrom {
                let done = await counter.next()
                Task { @MainActor in
                    self.progress = start + progressSpan * Double(done) / Double(max(total, 1))
                    self.progressText = "Prix FlixBus : \(done) / \(total)"
                }
            }
            return BusResult(request: request, quote: quote ?? nil)
        }
        var found = 0
        for answer in answers {
            guard let quote = answer.quote else { continue }
            book.putBus(quote, from: answer.request.from, to: answer.request.to, day: answer.request.day)
            found += 1
        }
        log.info(.api, "FlixBus : \(found) prix réels sur \(requests.count) trajets demandés")
        return found
    }

    // MARK: - Trains SNCF

    static func scheduleKey(_ step: PricedStep) -> String {
        "\(step.from.rawValue)>\(step.to.rawValue)>\(step.day.key)"
    }

    /// Horaires à afficher : demande précise à l'API SNCF, sinon horaires collectés (iPhone ou serveur).
    func displayedSchedule(for step: PricedStep) -> TrainSchedule? {
        schedules[Self.scheduleKey(step)] ?? trainSchedules.schedule(from: step.from, to: step.to, day: step.day)
    }

    /// Horaires SNCF d'une étape précise (jour exact si publié, sinon horaires types).
    func loadSchedule(for step: PricedStep) async {
        let key = Self.scheduleKey(step)
        guard hasSNCF, schedules[key] == nil, !schedulesLoading.contains(key) else { return }
        // Déjà relevés par la collecte : pas besoin d'interroger l'API.
        if let collected = trainSchedules.schedule(from: step.from, to: step.to, day: step.day), collected.exact {
            schedules[key] = collected
            return
        }
        guard let from = NetworkData.place(step.from).sncfID,
              let to = NetworkData.place(step.to).sncfID else { return }
        schedulesLoading.insert(key)
        defer { schedulesLoading.remove(key) }
        let client = SNCFClient(key: sncfKey, http: HTTPClient(log: log))
        do {
            if sncfWindow == nil {
                let window = try await client.window()
                sncfWindow = window
                log.info(.api, "Horaires SNCF publiés du \(Fmt.dayShort(window.start)) au \(Fmt.dayLong(window.end))")
            }
            guard let window = sncfWindow else { return }
            let reference = SNCFClient.referenceDay(for: step.day, window: window, today: Day(localDate: Date()))
            let label = "SNCF horaires \(NetworkData.place(step.from).short)-\(NetworkData.place(step.to).short) \(reference.day.key)"
            let journeys = try await client.journeys(from: from, to: to, day: reference.day, label: label)
            schedules[key] = TrainSchedule(day: step.day, referenceDay: reference.day, exact: reference.exact, journeys: journeys)
            log.info(.api, "Horaires SNCF \(NetworkData.place(step.from).short)-\(NetworkData.place(step.to).short) : \(journeys.count) trains",
                     details: reference.exact
                        ? "Jour exact : \(Fmt.dayLong(step.day))"
                        : "Horaires de \(Fmt.dayShort(step.day)) pas encore publiés : horaires types du \(Fmt.dayLong(reference.day))")
        } catch {
            scheduleErrors[key] = error.localizedDescription
            if trainSchedules.schedule(from: step.from, to: step.to, day: step.day) != nil {
                log.warning(.api, "Horaires SNCF en direct indisponibles, horaires collectés utilisés : \(error.localizedDescription)")
            } else {
                log.error(.api, "Horaires SNCF : \(error.localizedDescription)")
            }
        }
    }

    /// Grille officielle des prix SNCF (open data, sans clé).
    func refreshTrainGrid() async {
        let grid = await SNCFFareClient(http: HTTPClient(log: log)).fetchToulouseParis()
        guard !grid.isEmpty else { return }
        book.trainGrid = grid
        let lines = grid.sorted { $0.key < $1.key }.map { "\($0.key) : \(Fmt.euro($0.value.min)) à \(Fmt.euro($0.value.max))" }
        log.info(.api, "Grille officielle SNCF mise à jour (\(grid.count) tarifs)", details: lines.joined(separator: "\n"))
    }

    // MARK: - Données du serveur Oracle

    /// Télécharge les prix et horaires publiés par le serveur, les ajoute à ceux de l'iPhone et recalcule.
    func syncFeed(recomputeAfter: Bool = true) async {
        guard !isSyncingFeed, let url = URL(string: feedURL), !feedURL.isEmpty else { return }
        isSyncingFeed = true
        defer { isSyncingFeed = false }
        do {
            let data = try await HTTPClient(log: log).get(url, label: "Données du serveur", timeout: 60, quiet: true)
            let feed = try FeedReader.decode(data)
            let merged = FeedReader.merge(feed, into: book)
            book = merged.book
            trainSchedules.merge(FeedReader.schedules(feed))
            feedDate = FeedReader.generatedDate(feed)
            Persist.saveData(data, "feed.json")
            Persist.save(book, "prices.json")
            Persist.save(trainSchedules, "schedules.json")
            let stats = feed.stats ?? [:]
            feedStatus = "\(merged.added) prix et \(feed.schedules?.count ?? 0) horaires"
            log.info(.api, "Données du serveur \(feedDate.map { Fmt.age($0) } ?? "") : \(merged.added) prix, \(feed.schedules?.count ?? 0) horaires",
                     details: stats.sorted { $0.key < $1.key }.map { "\($0.key) : \($0.value)" }.joined(separator: "\n"))
            if recomputeAfter { await recompute(reason: "données du serveur") }
        } catch HTTPError.status(404, _) {
            feedStatus = "Aucune donnée publiée pour l'instant (serveur pas encore installé ?)"
            log.info(.api, "Données du serveur : pas encore publiées")
        } catch {
            feedStatus = "Indisponibles : \(error.localizedDescription)"
            log.warning(.api, "Données du serveur indisponibles : \(error.localizedDescription)")
        }
    }

    // MARK: - Vérification en temps réel d'un aller-retour

    func verify(_ trip: RoundTrip) async {
        guard hasSerpApi else {
            message = "Ajoutez une clé SerpApi dans Réglages pour vérifier les vols en temps réel."
            return
        }
        guard !verifying.contains(trip.id) else { return }
        verifying.insert(trip.id)
        defer { verifying.remove(trip.id) }
        log.info(.api, "Vérification en temps réel", details: trip.summary)

        let serp = SerpApiClient(key: serpApiKey, http: HTTPClient(log: log))
        let adults = params.adults
        let outFlights = trip.outbound.filter { $0.chosen.option.kind == .flight }
        let inFlights = trip.inbound.filter { $0.chosen.option.kind == .flight }
        var pairedInbound = Set<String>()
        var searches = 0

        for o in outFlights {
            guard let a = NetworkData.place(o.from).airport, let b = NetworkData.place(o.to).airport else { continue }
            if let i = inFlights.first(where: { $0.from == o.to && $0.to == o.from }) {
                pairedInbound.insert(i.id)
                searches += 1
                do {
                    let r = try await serp.roundTrip(from: a, to: b, out: o.day, back: i.day, adults: adults)
                    if let total = r.totalPrice {
                        book.putRoundTrip(Quote(price: total / Double(adults), source: .serpapi, detail: r.detail,
                                                link: r.googleFlightsURL),
                                          from: o.from, to: o.to, out: o.day, back: i.day)
                        log.info(.api, "Google Flights aller-retour \(a.code)-\(b.code) : \(Fmt.euro(total))", details: r.detail)
                    } else {
                        log.warning(.api, "Google Flights aller-retour \(a.code)-\(b.code) : \(r.detail)")
                    }
                } catch {
                    log.error(.api, "SerpApi aller-retour \(a.code)-\(b.code) : \(error.localizedDescription)")
                }
            } else {
                searches += 1
                await verifyOneWay(serp, step: o, from: a, to: b, adults: adults)
            }
        }
        for i in inFlights where !pairedInbound.contains(i.id) {
            guard let a = NetworkData.place(i.from).airport, let b = NetworkData.place(i.to).airport else { continue }
            searches += 1
            await verifyOneWay(serp, step: i, from: a, to: b, adults: adults)
        }

        let buses = (trip.outbound + trip.inbound)
            .filter { step in step.options.contains { $0.option.kind == .flixbus } }
            .map { BusRequest(from: $0.from, to: $0.to, day: $0.day) }
        if !buses.isEmpty { await fetchBuses(buses) }

        let engine = RouteEngine(params: params, book: book)
        if let updated = engine.evaluate(outSignature: trip.outSignature, inSignature: trip.inSignature,
                                         out: trip.outDay, back: trip.backDay) {
            if let index = results.firstIndex(where: { $0.id == trip.id }) {
                results[index] = updated
            } else {
                results.append(updated)
            }
            log.info(.engine, "Prix vérifié : \(Fmt.euro(trip.total)) devient \(Fmt.euro(updated.total))",
                     details: "\(searches) recherche(s) SerpApi utilisée(s)")
        }
        Persist.save(book, "prices.json")
        await refreshAccount()
    }

    private func verifyOneWay(_ serp: SerpApiClient, step: PricedStep, from a: AirportCode, to b: AirportCode, adults: Int) async {
        do {
            let r = try await serp.oneWay(from: a, to: b, day: step.day, adults: adults)
            if let total = r.totalPrice {
                book.putOneWay(Quote(price: total / Double(adults), source: .serpapi, detail: r.detail, link: r.googleFlightsURL),
                               from: step.from, to: step.to, day: step.day)
                log.info(.api, "Google Flights aller \(a.code)-\(b.code) : \(Fmt.euro(total))", details: r.detail)
            } else {
                log.warning(.api, "Google Flights aller \(a.code)-\(b.code) : \(r.detail)")
            }
        } catch {
            log.error(.api, "SerpApi aller \(a.code)-\(b.code) : \(error.localizedDescription)")
        }
    }

    func refreshAccount() async {
        guard hasSerpApi else {
            serpAccount = nil
            return
        }
        do {
            let account = try await SerpApiClient(key: serpApiKey, http: HTTPClient(log: log)).account()
            serpAccount = account
            log.debug(.api, "Quota SerpApi : \(account.totalSearchesLeft ?? account.planSearchesLeft ?? 0) recherches restantes")
        } catch {
            log.error(.api, "Quota SerpApi : \(error.localizedDescription)")
        }
    }
}
