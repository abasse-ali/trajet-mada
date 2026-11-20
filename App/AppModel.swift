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

struct BusRequest: Hashable, Sendable {
    let from: PlaceID
    let to: PlaceID
    let day: Day
}

struct BusResult: Sendable {
    let request: BusRequest
    let quote: Quote?
}

@Observable
@MainActor
final class AppModel {
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
    var serpAccount: SerpApiClient.Account?
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
        let counts = book.counts
        log.info(.app, "Démarrage de TrajetMada", details:
            "Prix en mémoire : \(counts.oneWay) allers simples, \(counts.roundTrip) allers-retours, \(counts.bus) bus.\n"
            + "Clé Travelpayouts : \(travelpayoutsToken.isEmpty ? "absente" : "présente"). "
            + "Clé SerpApi : \(serpApiKey.isEmpty ? "absente" : "présente").")
        Task { await self.recompute(reason: "ouverture de l'app") }
    }

    var hasTravelpayouts: Bool { !travelpayoutsToken.isEmpty }
    var hasSerpApi: Bool { !serpApiKey.isEmpty }

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

    func saveKeys(travelpayouts: String, serpapi: String) {
        travelpayoutsToken = travelpayouts.trimmingCharacters(in: .whitespacesAndNewlines)
        serpApiKey = serpapi.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.set(travelpayoutsToken, for: "travelpayouts")
        Keychain.set(serpApiKey, for: "serpapi")
        log.info(.app, "Clés enregistrées", details:
            "Travelpayouts : \(hasTravelpayouts ? "présente" : "absente"), SerpApi : \(hasSerpApi ? "présente" : "absente")")
    }

    func clearPrices() {
        book = PriceBook()
        Persist.remove("prices.json")
        log.warning(.app, "Cache des prix effacé")
        Task { await recompute(reason: "cache effacé") }
    }

    func resetParams() {
        params = SearchParams.defaults()
        Persist.save(params, "params.json")
        log.info(.app, "Paramètres remis par défaut", details: params.summary)
    }

    // MARK: - Recherche

    func search() async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        progress = 0
        defer { isBusy = false }
        Persist.save(params, "params.json")
        log.info(.app, "Recherche lancée", details: params.summary)

        if hasTravelpayouts {
            let network = FilteredNetwork(params: params)
            let tasks = TravelpayoutsScanner.plan(params: params, network: network)
            progressText = "Prix des vols : 0 / \(tasks.count)"
            log.info(.scan, "Scan des vols : \(tasks.count) requêtes Travelpayouts")
            let client = TravelpayoutsClient(token: travelpayoutsToken, http: HTTPClient(log: log))
            let scanner = TravelpayoutsScanner(client: client)
            let (newBook, stats) = await scanner.run(tasks, into: book) { done, total in
                Task { @MainActor in
                    self.progress = 0.75 * Double(done) / Double(max(total, 1))
                    self.progressText = "Prix des vols : \(done) / \(total)"
                }
            }
            book = newBook
            log.log(stats.failures > 0 ? .warning : .info, .scan, stats.summary, details: stats.details)
            if stats.requests > 0 && stats.failures == stats.requests {
                message = "Aucune réponse de Travelpayouts. Vérifiez le jeton dans Réglages (détails dans le Journal)."
            }
        } else {
            log.warning(.scan, "Pas de jeton Travelpayouts : prix des vols estimés")
            message = "Sans jeton Travelpayouts, les prix des vols sont estimés. Ajoutez-le dans Réglages."
        }

        progress = 0.8
        progressText = "Calcul de toutes les combinaisons…"
        await recompute(reason: "après le scan")
        await refreshBuses(top: 20)
        Persist.save(book, "prices.json")
        progress = 1
        progressText = "Terminé : \(results.count) allers-retours"
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

    /// Prix FlixBus réels pour les meilleurs résultats.
    func refreshBuses(top: Int) async {
        var wanted = Set<BusRequest>()
        for trip in results.prefix(top) {
            for step in trip.outbound + trip.inbound where step.options.contains(where: { $0.option.kind == .flixbus }) {
                if book.bus[PriceBook.key(step.from, step.to)]?[step.day.key] == nil {
                    wanted.insert(BusRequest(from: step.from, to: step.to, day: step.day))
                }
            }
        }
        guard !wanted.isEmpty else { return }
        let requests = wanted.sorted { $0.day < $1.day }
        progressText = "Prix FlixBus : \(requests.count) trajets"
        let fetched = await fetchBuses(requests)
        if fetched > 0 { await recompute(reason: "prix FlixBus") }
    }

    @discardableResult
    func fetchBuses(_ requests: [BusRequest]) async -> Int {
        let client = FlixBusClient(http: HTTPClient(log: log))
        let adults = params.adults
        let answers: [BusResult] = await boundedConcurrentMap(requests, limit: 3) { request in
            let quote = try? await client.quote(from: request.from, to: request.to, day: request.day, adults: adults)
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

    // MARK: - Vérification en temps réel

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
