import XCTest
@testable import TrajetCore

final class NetworkTests: XCTestCase {
    func testConnectionsAreConsistent() {
        var ids = Set<String>()
        for connection in NetworkData.connections {
            XCTAssertFalse(ids.contains(connection.id), "liaison en double : \(connection.id)")
            ids.insert(connection.id)
            XCTAssertNotNil(NetworkData.places[connection.a])
            XCTAssertNotNil(NetworkData.places[connection.b])
            XCTAssertFalse(connection.options.isEmpty)
            for option in connection.options {
                XCTAssertLessThanOrEqual(option.priceMin, option.priceTypical, option.id)
                XCTAssertFalse(option.links.isEmpty, "aucun lien pour \(option.id)")
                if option.kind == .flight {
                    XCTAssertNotNil(NetworkData.place(connection.a).airport, connection.id)
                    XCTAssertNotNil(NetworkData.place(connection.b).airport, connection.id)
                }
            }
        }
    }

    func testOutboundPathsReachBothDestinations() {
        let params = SearchParams.defaults(today: Day(year: 2026, month: 11, day: 20))
        let network = FilteredNetwork(params: params)
        let paths = network.outboundPaths(from: .toulouse, to: [.diego, .nosyBe])
        print("Trajets aller possibles : \(paths.count)")
        XCTAssertGreaterThan(paths.count, 20)
        XCTAssertTrue(paths.contains { $0.end == .diego })
        XCTAssertTrue(paths.contains { $0.end == .nosyBe })
        for path in paths {
            XCTAssertEqual(path.origin, .toulouse)
            XCTAssertEqual(Set(path.places).count, path.places.count, "lieu répété : \(path.signature)")
            for k in 1..<path.places.count {
                XCTAssertGreaterThanOrEqual(NetworkData.place(path.places[k]).tier,
                                            NetworkData.place(path.places[k - 1]).tier, path.signature)
            }
        }
    }

    func testNoFlightMeansNoPath() {
        var params = SearchParams.defaults(today: Day(year: 2026, month: 11, day: 20))
        params.modes = [.train, .bus, .covoiturage, .bateau, .taxiBrousse, .voiture]
        let network = FilteredNetwork(params: params)
        XCTAssertTrue(network.outboundPaths(from: .toulouse, to: [.diego]).isEmpty)
    }

    func testCheapestTransferNosyBeToDiego() {
        let params = SearchParams.defaults(today: Day(year: 2026, month: 11, day: 20))
        let transfer = FilteredNetwork(params: params).cheapestTransfer(from: .nosyBe, to: .diego, adults: 1)
        XCTAssertNotNil(transfer)
        XCTAssertEqual(transfer?.places.first, .nosyBe)
        XCTAssertEqual(transfer?.places.last, .diego)
        XCTAssertLessThan(transfer?.cost ?? 999, 60)
    }
}

final class DateTests: XCTestCase {
    func testDefaultsTargetNextSummer() {
        let params = SearchParams.defaults(today: Day(year: 2026, month: 11, day: 20))
        XCTAssertEqual(params.periodStart, Day(year: 2027, month: 5, day: 1))
        XCTAssertEqual(params.periodEnd, Day(year: 2027, month: 9, day: 30))
        XCTAssertEqual(params.months, ["2027-05", "2027-06", "2027-07", "2027-08", "2027-09"])
    }

    func testDatePairsRespectStayAndPeriod() {
        let params = SearchParams.defaults(today: Day(year: 2026, month: 11, day: 20))
        let pairs = params.datePairs
        XCTAssertFalse(pairs.isEmpty)
        for pair in pairs {
            XCTAssertTrue((28...30).contains(pair.stay))
            XCTAssertGreaterThanOrEqual(pair.out, params.periodStart)
            XCTAssertLessThanOrEqual(pair.back, params.lastReturnDay)
        }
        XCTAssertEqual(pairs.first?.out, Day(year: 2027, month: 5, day: 1))
        XCTAssertEqual(pairs.last?.back, Day(year: 2027, month: 9, day: 29))
    }

    func testDayArithmetic() {
        let d = Day(year: 2027, month: 5, day: 31)
        XCTAssertEqual(d.adding(days: 1), Day(year: 2027, month: 6, day: 1))
        XCTAssertEqual(d.days(until: Day(year: 2027, month: 6, day: 29)), 29)
        XCTAssertEqual(Day(isoPrefix: "2027-05-10T09:35:00+02:00"), Day(year: 2027, month: 5, day: 10))
        XCTAssertEqual(Day(year: 2027, month: 5, day: 10).weekday, 2) // lundi
        XCTAssertEqual(Fmt.dayLong(Day(year: 2027, month: 5, day: 10)), "lun. 10 mai 2027")
    }
}

final class EngineTests: XCTestCase {
    let params = SearchParams.defaults(today: Day(year: 2026, month: 11, day: 20))

    func testNoPriceIsInvented() {
        // Carnet de prix vide : aucun vol n'a de prix, rien n'est inventé.
        let result = RouteEngine(params: params, book: PriceBook()).run()
        print(result.stats.description)
        XCTAssertFalse(result.trips.isEmpty)
        XCTAssertTrue(result.bestByDay.isEmpty, "le graphique n'affiche que des totaux entièrement réels")
        for trip in result.trips.prefix(50) {
            XCTAssertFalse(trip.isComplete)
            XCTAssertEqual(trip.outbound.first?.from, .toulouse)
            XCTAssertEqual(trip.inbound.last?.to, .toulouse)
            XCTAssertTrue((28...30).contains(trip.stayDays))
            for step in trip.outbound + trip.inbound + trip.localTransfer {
                if !step.chosen.isKnown {
                    XCTAssertEqual(step.chosen.price, 0, "prix inventé pour \(step.chosen.option.id)")
                } else {
                    XCTAssertEqual(step.chosen.quality, .tariff, "seuls les tarifs officiels sont connus ici")
                }
            }
            let known = (trip.outbound + trip.inbound + trip.localTransfer).reduce(0.0) { $0 + $1.chosen.price }
            XCTAssertEqual(trip.total, known, accuracy: 0.001)
        }
    }

    func testCompleteTripsComeFirst() {
        var book = PriceBook()
        let out = Day(year: 2027, month: 6, day: 12)
        let back = Day(year: 2027, month: 7, day: 11)
        book.putRoundTrip(Quote(price: 924, source: .serpapi), from: .parisAirports, to: .nosyBe, out: out, back: back)
        book.putBus(Quote(price: 26, source: .flixbus), from: .toulouse, to: .parisStations, day: out)
        book.putBus(Quote(price: 30, source: .flixbus), from: .parisStations, to: .toulouse, day: back.adding(days: 1))
        book.putBus(Quote(price: 30, source: .flixbus), from: .parisStations, to: .toulouse, day: back)
        let result = RouteEngine(params: params, book: book).run()
        let first = result.trips.first
        XCTAssertEqual(first?.isComplete, true)
        XCTAssertEqual(first?.rtTickets.first?.price, 924)
        XCTAssertFalse(result.bestByDay.isEmpty)
        // Ordre : d'abord tous les trajets complets, puis les autres.
        let flags = result.trips.map(\.isComplete)
        XCTAssertEqual(flags, flags.sorted { $0 && !$1 })
    }

    func testOpenJawDisabledKeepsSameCity() {
        var p = params
        p.allowOpenJaw = false
        let result = RouteEngine(params: p, book: PriceBook()).run(maxResults: 200)
        XCTAssertFalse(result.trips.isEmpty)
        XCTAssertTrue(result.trips.allSatisfy { !$0.isOpenJaw })
    }

    func testOpenJawAddsLocalTransfer() {
        let result = RouteEngine(params: params, book: PriceBook()).run(maxResults: 400)
        if let trip = result.trips.first(where: { $0.isOpenJaw }) {
            XCTAssertFalse(trip.localTransfer.isEmpty)
            XCTAssertEqual(trip.localTransfer.first?.from, trip.arrival)
            XCTAssertEqual(trip.localTransfer.last?.to, trip.departureBack)
        }
    }

    func testRealPriceIsUsed() {
        var book = PriceBook()
        let day = Day(year: 2027, month: 5, day: 10)
        book.putOneWay(Quote(price: 111, source: .travelpayouts), from: .parisAirports, to: .tana, day: day)
        let engine = RouteEngine(params: params, book: book)
        let trip = engine.evaluate(outSignature: "TLS_V>PAR_G>PAR>TNR>DIE", inSignature: "DIE>TNR>PAR>PAR_G>TLS_V",
                                   out: day, back: day.adding(days: 29))
        let flight = trip?.outbound.first { $0.from == .parisAirports && $0.to == .tana }
        XCTAssertEqual(flight?.chosen.price, 111)
        XCTAssertEqual(flight?.chosen.quality, .cached)
        // Le vol Tana-Diego et le retour n'ont pas de prix : l'aller-retour est incomplet, pas inventé.
        XCTAssertEqual(trip?.isComplete, false)
    }

    func testRoundTripTicketIsUsedWhenCheaper() {
        var book = PriceBook()
        let out = Day(year: 2027, month: 6, day: 2)
        let back = out.adding(days: 29)
        book.putOneWay(Quote(price: 600, source: .travelpayouts), from: .parisAirports, to: .nosyBe, day: out)
        book.putOneWay(Quote(price: 600, source: .travelpayouts), from: .nosyBe, to: .parisAirports, day: back)
        book.putRoundTrip(Quote(price: 800, source: .travelpayouts), from: .parisAirports, to: .nosyBe, out: out, back: back)
        let engine = RouteEngine(params: params, book: book)
        let trip = engine.evaluate(outSignature: "TLS_V>PAR_G>PAR>NOS", inSignature: "NOS>PAR>PAR_G>TLS_V",
                                   out: out, back: back)
        XCTAssertEqual(trip?.rtTickets.count, 1)
        XCTAssertEqual(trip?.rtTickets.first?.price, 800)
        XCTAssertTrue(trip?.outbound.contains { $0.roundTripPaired } ?? false)
        XCTAssertTrue(trip?.inbound.contains { $0.roundTripPaired } ?? false)
    }

    func testRoundTripTicketCoversUnpricedOneWays() {
        var book = PriceBook()
        let out = Day(year: 2027, month: 6, day: 12)
        let back = Day(year: 2027, month: 7, day: 11)
        book.putRoundTrip(Quote(price: 924, source: .serpapi), from: .parisAirports, to: .nosyBe, out: out, back: back)
        book.putBus(Quote(price: 26, source: .flixbus), from: .toulouse, to: .parisStations, day: out)
        let engine = RouteEngine(params: params, book: book)
        let trip = engine.evaluate(outSignature: "TLS_V>PAR_G>PAR>NOS", inSignature: "NOS>PAR>PAR_G>TLS_V", out: out, back: back)
        XCTAssertEqual(trip?.rtTickets.count, 1)
        // Reste sans prix : le bus du retour (pas relevé). Total = billet AR + bus aller + 2 tickets RER.
        XCTAssertEqual(trip?.unpriced, 1)
        XCTAssertEqual(trip?.total ?? 0, 924 + 26 + 14 + 14, accuracy: 0.001)
        // Un autre jour, le vol n'a pas de prix : rien n'est déduit du billet aller-retour.
        let flight = NetworkData.connections.first { $0.id == "PAR-NOS" }!.options[0]
        let other = engine.priceOption(flight, from: .parisAirports, to: .nosyBe, day: Day(year: 2027, month: 6, day: 20))
        XCTAssertEqual(other.quality, .unknown)
        XCTAssertEqual(other.price, 0)
    }

    func testCheapestRecentRealPriceWins() {
        var book = PriceBook()
        let day = Day(year: 2027, month: 5, day: 10)
        // Sources différentes, prix récents : le moins cher des prix réels est gardé.
        book.putOneWay(Quote(price: 135, source: .travelpayouts), from: .tana, to: .nosyBe, day: day)
        book.putOneWay(Quote(price: 701, source: .serpapi), from: .tana, to: .nosyBe, day: day)
        XCTAssertEqual(book.oneWay["TNR>NOS"]?[day.key]?.price, 135)
        // Un prix de plus de 7 jours cède la place à un relevé récent, même plus cher.
        book.putOneWay(Quote(price: 400, source: .travelpayouts, fetchedAt: Date(timeIntervalSinceNow: -8 * 86_400)),
                       from: .parisAirports, to: .tana, day: day)
        book.putOneWay(Quote(price: 520, source: .serpapi), from: .parisAirports, to: .tana, day: day)
        XCTAssertEqual(book.oneWay["PAR>TNR"]?[day.key]?.price, 520)
        // Même source : le nouveau relevé remplace l'ancien (le prix a changé).
        book.putOneWay(Quote(price: 610, source: .serpapi, fetchedAt: Date(timeIntervalSinceNow: 7200)),
                       from: .parisAirports, to: .tana, day: day)
        XCTAssertEqual(book.oneWay["PAR>TNR"]?[day.key]?.price, 610)
    }

    func testOfficialTariffs() {
        var p = params
        p.adults = 3
        var book = PriceBook()
        let day = Day(year: 2027, month: 5, day: 10)
        let tram = NetworkData.connections.first { $0.id == "TLS_V-TLS" }!.options[0]
        let boat = NetworkData.connections.first { $0.id == "ANK-NOS" }!.options.first { $0.id == "vedette" }!
        let taxi = NetworkData.connections.first { $0.id == "ANK-DIE" }!.options.first { $0.perVehicle }!
        var engine = RouteEngine(params: p, book: book)
        XCTAssertEqual(engine.priceOption(tram, from: .toulouse, to: .toulouseAirport, day: day).price, 5.7, accuracy: 0.001)
        // Sans taux de change relevé, le tarif en ariary n'est pas converti au hasard.
        XCTAssertEqual(engine.priceOption(boat, from: .ankify, to: .nosyBe, day: day).quality, .unknown)
        book.setRate(5000, at: Date())
        engine = RouteEngine(params: p, book: book)
        let priced = engine.priceOption(boat, from: .ankify, to: .nosyBe, day: day)
        XCTAssertEqual(priced.quality, .tariff)
        XCTAssertEqual(priced.price, 12, accuracy: 0.001, "20 000 Ar = 4 € par personne, 3 adultes")
        let taxiPriced = engine.priceOption(taxi, from: .ankify, to: .diego, day: day)
        XCTAssertEqual(taxiPriced.quality, .unknown)
        XCTAssertEqual(taxiPriced.price, 0)
    }
}

final class FeedTests: XCTestCase {
    // Fichier réel produit par server/trajetmada_update.py (réduit ; vols ajoutés au même format).
    static let json = """
    {"version":1,"generatedAt":"2026-11-20T23:37:50Z","period":{"start":"2027-05-01","end":"2027-09-30"},"stay":{"min":28,"max":30},"adults":1,
    "trainGrid":{"tgv":{"min":25.5,"max":143.0,"source":"open data SNCF"},"ouigo":{"min":19.0,"max":119.0,"source":"open data SNCF"},"intercites-nuit":{"min":29.0,"max":142.0,"source":"open data SNCF"}},
    "sncfWindow":{"start":"2026-11-18","end":"2026-12-17"},
    "bus":[{"from":"TLS_V","to":"PAR_G","day":"2027-05-10","price":36.99,"source":"flixbus","carrier":"FlixBus","detail":"depart 21:25 - arrivee 06:25 - 49 places","link":"https://shop.flixbus.fr/search?rideDate=10.05.2027","fetchedAt":"2026-11-20T23:38:00Z"},
           {"from":"PAR_G","to":"TLS_V","day":"2027-05-10","price":35.99,"source":"flixbus","carrier":"FlixBus","detail":"depart 20:50","link":null,"fetchedAt":"2026-11-20T23:38:00Z"}],
    "schedules":[{"from":"TLS_V","to":"PAR_G","day":null,"weekday":1,"referenceDay":"2026-11-22","exact":false,"journeys":[
      {"departure":"05:39","arrival":"12:18","arrivalDayOffset":0,"durationMin":399,"transfers":1,"trains":["liO 876203","TGV INOUI 6202"],"modes":["liO","TGV INOUI"],"fare":null},
      {"departure":"07:37","arrival":"13:54","arrivalDayOffset":0,"durationMin":377,"transfers":1,"trains":["TGV INOUI 6871","OUIGO 7876"],"modes":["TGV INOUI","OUIGO"],"fare":null}]}],
    "oneWay":[{"from":"PAR","to":"TNR","day":"2027-05-10","price":612.0,"source":"travelpayouts","carrier":"AF","transfers":0,"detail":"AF 934 - direct","fetchedAt":"2026-11-20T23:37:50Z","link":"https://www.aviasales.com/search/PAR1005TNR1"}],
    "roundTrip":[{"from":"PAR","to":"TNR","out":"2027-05-10","back":"2027-06-08","price":980.0,"source":"serpapi","carrier":"Air France","detail":"Air France","link":"https://www.google.com/travel/flights?tfs=x","fetchedAt":"2026-11-20T23:37:50Z"}],
    "mgaPerEur":5037.0,"mgaRateAt":"2026-11-23T00:02:32Z","calendarFetched":{"PAR>NOS#29":"2026-11-24T06:00:00Z"},
    "stats":{"oneWay":0,"roundTrip":0,"serpapi":0,"bus":306,"schedules":28,"requests":337,"failures":0,"errors":0,"warnings":1}}
    """

    func testDecodeAndMerge() throws {
        let feed = try FeedReader.decode(Data(Self.json.utf8))
        XCTAssertEqual(feed.stats?["bus"], 306)
        let merged = FeedReader.merge(feed, into: PriceBook())
        XCTAssertEqual(merged.added, 4)
        let book = merged.book
        XCTAssertEqual(book.oneWay["PAR>TNR"]?["2027-05-10"]?.price, 612)
        XCTAssertEqual(book.roundTrip["PAR>TNR"]?["2027-05-10|2027-06-08"]?.source, .serpapi)
        XCTAssertEqual(book.bus["TLS_V>PAR_G"]?["2027-05-10"]?.price, 36.99)
        XCTAssertEqual(book.trainGrid["ouigo"]?.max, 119)
        let fetched = book.bus["TLS_V>PAR_G"]?["2027-05-10"]?.fetchedAt
        XCTAssertEqual(fetched, FeedReader.date("2026-11-20T23:38:00Z"))
        XCTAssertEqual(book.mgaPerEur, 5037)
        XCTAssertEqual(book.calendarFetched["PAR>NOS#29"], FeedReader.date("2026-11-24T06:00:00Z"))
    }

    func testOldLiveQuoteIsNoLongerLive() throws {
        // Relevé daté de janvier 2026 : toujours plus de 3 heures, quel que soit le moment du test.
        let old = Self.json.replacingOccurrences(of: "2026-11-20T23:38:00Z", with: "2026-01-01T00:00:00Z")
        let feed = try FeedReader.decode(Data(old.utf8))
        let book = FeedReader.merge(feed, into: PriceBook()).book
        let params = SearchParams.defaults(today: Day(year: 2026, month: 11, day: 20))
        let engine = RouteEngine(params: params, book: book)
        let bus = NetworkData.connections.first { $0.id == "TLS_V-PAR_G" }!.options.first { $0.kind == .flixbus }!
        let priced = engine.priceOption(bus, from: .toulouse, to: .parisStations, day: Day(year: 2027, month: 5, day: 10))
        XCTAssertEqual(priced.price, 36.99)
        // Relevé par le serveur il y a plus de 3 heures : prix réel, mais plus « temps réel ».
        XCTAssertEqual(priced.quality, .cached)
    }

    func testTypicalSchedulesByWeekday() throws {
        let feed = try FeedReader.decode(Data(Self.json.utf8))
        let schedules = FeedReader.schedules(feed)
        XCTAssertEqual(schedules.typical.count, 1)
        // Le 2 mai 2027 est un dimanche (jour 1), comme le 22 novembre 2026.
        let sunday = Day(year: 2027, month: 5, day: 2)
        XCTAssertEqual(sunday.weekday, 1)
        let schedule = schedules.schedule(from: .toulouse, to: .parisStations, day: sunday)
        XCTAssertNotNil(schedule)
        XCTAssertEqual(schedule?.exact, false)
        XCTAssertEqual(schedule?.day, sunday)
        XCTAssertEqual(schedule?.referenceDay, Day(year: 2026, month: 11, day: 22))
        XCTAssertEqual(schedule?.journeys.last?.trains, ["TGV INOUI 6871", "OUIGO 7876"])
        XCTAssertNil(schedules.schedule(from: .toulouse, to: .parisStations, day: Day(year: 2027, month: 5, day: 3)))
    }

    func testFresherCachedPriceReplacesOlderOne() {
        var book = PriceBook()
        let day = Day(year: 2027, month: 5, day: 10)
        let old = Date(timeIntervalSinceNow: -3 * 86_400)
        book.putOneWay(Quote(price: 500, source: .travelpayouts, fetchedAt: old), from: .parisAirports, to: .tana, day: day)
        book.putOneWay(Quote(price: 640, source: .travelpayouts), from: .parisAirports, to: .tana, day: day)
        XCTAssertEqual(book.oneWay["PAR>TNR"]?[day.key]?.price, 640, "le relevé le plus récent l'emporte")
        book.putOneWay(Quote(price: 600, source: .travelpayouts), from: .parisAirports, to: .tana, day: day)
        XCTAssertEqual(book.oneWay["PAR>TNR"]?[day.key]?.price, 600, "même relevé : le moins cher")
        book.putOneWay(Quote(price: 700, source: .travelpayouts, fetchedAt: old), from: .parisAirports, to: .tana, day: day)
        XCTAssertEqual(book.oneWay["PAR>TNR"]?[day.key]?.price, 600, "un relevé plus ancien est ignoré")
    }
}

final class CollectorTests: XCTestCase {
    let params = SearchParams.defaults(today: Day(year: 2026, month: 11, day: 20))
    let today = Day(year: 2026, month: 11, day: 21)

    func testBusRequestsCoverEveryDayAndSkipFreshPrices() {
        var book = PriceBook()
        let all = Collector.busRequests(params: params, book: book)
        XCTAssertEqual(all.count, 153 * 2, "153 jours de mai à septembre, dans les deux sens")
        book.putBus(Quote(price: 30, source: .flixbus), from: .toulouse, to: .parisStations, day: Day(year: 2027, month: 5, day: 1))
        book.putBus(Quote(price: 30, source: .flixbus, fetchedAt: Date(timeIntervalSinceNow: -86_400)),
                    from: .parisStations, to: .toulouse, day: Day(year: 2027, month: 5, day: 1))
        let remaining = Collector.busRequests(params: params, book: book)
        XCTAssertEqual(remaining.count, 153 * 2 - 1, "seul le prix relevé il y a moins de 12 h est ignoré")
        var noBus = params
        noBus.modes.remove(.bus)
        XCTAssertTrue(Collector.busRequests(params: noBus, book: book).isEmpty)
    }

    func testScheduleDays() {
        let window = SNCFWindow(start: Day(year: 2026, month: 11, day: 18), end: Day(year: 2026, month: 12, day: 17))
        let days = Collector.scheduleDays(params: params, window: window, today: today)
        XCTAssertTrue(days.exact.isEmpty, "mai 2027 n'est pas encore publié")
        XCTAssertEqual(Set(days.typical.keys), Set(1...7))
        for (weekday, day) in days.typical {
            XCTAssertEqual(day.weekday, weekday)
            XCTAssertTrue(day > today && day <= window.end)
        }
        let summer = SNCFWindow(start: Day(year: 2027, month: 4, day: 20), end: Day(year: 2027, month: 5, day: 20))
        XCTAssertEqual(Collector.scheduleDays(params: params, window: summer, today: Day(year: 2027, month: 4, day: 21)).exact.count, 20)
    }

    func testCalendarJobsCoverEveryStayAndDate() {
        let jobs = Collector.calendarJobs(params: params)
        XCTAssertEqual(jobs.count, Collector.serpRoundTrips.count * 3 + Collector.serpOneWays.count)
        XCTAssertFalse(jobs.contains { $0.to == .diego && $0.from != .tana }, "pas de calendrier France-Diego")
        for job in jobs {
            XCTAssertEqual(job.start, params.periodStart)
            if let stay = job.stay {
                XCTAssertTrue((28...30).contains(stay))
                XCTAssertEqual(job.end.adding(days: stay), params.lastReturnDay, "le dernier départ revient à temps")
            } else {
                XCTAssertEqual(job.end, params.lastReturnDay)
            }
        }
        XCTAssertEqual(Set(jobs.map(\.key)).count, jobs.count)
        XCTAssertTrue(jobs.contains { $0.key == "PAR>NOS#29" })
        XCTAssertTrue(jobs.contains { $0.key == "TNR>DIE#aller" })
    }

    func testCalendarPlanRefreshesOldestFirst() {
        let now = Date()
        let all = Collector.calendarJobs(params: params)
        XCTAssertEqual(Collector.calendarPlan(params: params, fetched: [:], budget: 100, now: now).count, all.count)
        XCTAssertEqual(Collector.calendarPlan(params: params, fetched: [:], budget: 5, now: now).count, 5)
        XCTAssertTrue(Collector.calendarPlan(params: params, fetched: [:], budget: 0, now: now).isEmpty)
        // Relevés récents (serveur ou iPhone) : rien à refaire. Anciens : les plus vieux d'abord.
        var fetched: [String: Date] = [:]
        for job in all { fetched[job.key] = now.addingTimeInterval(-3600) }
        XCTAssertTrue(Collector.calendarPlan(params: params, fetched: fetched, budget: 5, now: now).isEmpty)
        fetched["TNR>NOS#aller"] = now.addingTimeInterval(-6 * 86_400)
        fetched["PAR>TNR#28"] = now.addingTimeInterval(-9 * 86_400)
        XCTAssertEqual(Collector.calendarPlan(params: params, fetched: fetched, budget: 5, now: now).map(\.key),
                       ["PAR>TNR#28", "TNR>NOS#aller"])
    }

    func testStoreCalendarPrices() {
        var book = PriceBook()
        let job = Collector.calendarJobs(params: params).first { $0.key == "PAR>NOS#29" }!
        let prices = [
            SerpApiClient.CalendarPrice(out: Day(year: 2027, month: 5, day: 30), back: Day(year: 2027, month: 6, day: 28), price: 924),
            SerpApiClient.CalendarPrice(out: Day(year: 2027, month: 6, day: 1), back: Day(year: 2027, month: 6, day: 30), price: 1010),
        ]
        let at = Date()
        XCTAssertEqual(Collector.store(prices, for: job, adults: 1, into: &book, at: at), 2)
        XCTAssertEqual(book.roundTrip["PAR>NOS"]?["2027-05-30|2027-06-28"]?.price, 924)
        XCTAssertEqual(book.roundTrip["PAR>NOS"]?["2027-05-30|2027-06-28"]?.source, .serpapi)
        XCTAssertEqual(book.calendarFetched["PAR>NOS#29"], at)
        let oneWayJob = Collector.calendarJobs(params: params).first { $0.key == "TNR>DIE#aller" }!
        Collector.store([SerpApiClient.CalendarPrice(out: Day(year: 2027, month: 6, day: 2), back: nil, price: 152)],
                        for: oneWayJob, adults: 1, into: &book)
        XCTAssertEqual(book.oneWay["TNR>DIE"]?["2027-06-02"]?.price, 152)
        // Calendrier vide : pas de nouvel essai avant 14 jours.
        let empty = Collector.calendarJobs(params: params).first { $0.key == "DIE>TNR#aller" }!
        Collector.store([], for: empty, adults: 1, into: &book, at: at)
        XCTAssertTrue(Collector.calendarPlan(params: params, fetched: book.calendarFetched, budget: 50,
                                             now: at.addingTimeInterval(13 * 86_400)).allSatisfy { $0.key != "DIE>TNR#aller" })
        XCTAssertTrue(Collector.calendarPlan(params: params, fetched: book.calendarFetched, budget: 50,
                                             now: at.addingTimeInterval(15 * 86_400)).contains { $0.key == "DIE>TNR#aller" })
    }

    func testSchedulesMergeAndCodable() throws {
        var a = FeedSchedules()
        let journey = TrainJourney(departure: "06:10", arrival: "11:03", arrivalDayOffset: 0, durationMin: 293,
                                   transfers: 0, trains: ["TGV INOUI 8502"], modes: ["TGV INOUI"], fare: nil)
        let day = Day(year: 2026, month: 11, day: 22)
        a.typical["TLS_V>PAR_G#1"] = TrainSchedule(day: day, referenceDay: day, exact: false, journeys: [])
        var b = FeedSchedules()
        b.typical["TLS_V>PAR_G#1"] = TrainSchedule(day: day, referenceDay: day, exact: false, journeys: [journey])
        a.merge(b)
        XCTAssertEqual(a.typical["TLS_V>PAR_G#1"]?.journeys.count, 1)
        let decoded = try JSONDecoder().decode(FeedSchedules.self, from: JSONEncoder().encode(a))
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.typical["TLS_V>PAR_G#1"]?.journeys.first, journey)
    }
}

final class LinkTests: XCTestCase {
    let par = NetworkData.place(.parisAirports).airport!
    let tnr = NetworkData.place(.tana).airport!
    let out = Day(year: 2027, month: 5, day: 10)
    let back = Day(year: 2027, month: 6, day: 8)

    func testSkyscannerRoundTrip() {
        XCTAssertEqual(LinkBuilder.skyscannerURL(from: par, to: tnr, out: out, back: back, adults: 1).absoluteString,
                       "https://www.skyscanner.fr/transport/vols/pari/tnr/270510/270608/?adultsv2=1&cabinclass=economy&rtn=1")
    }

    func testKayakAndAviasales() {
        XCTAssertEqual(LinkBuilder.kayakURL(from: par, to: tnr, out: out, back: back, adults: 2).absoluteString,
                       "https://www.kayak.fr/flights/PAR-TNR/2027-05-10/2027-06-08/2adults?sort=price_a")
        XCTAssertEqual(LinkBuilder.aviasalesURL(from: par, to: tnr, out: out, back: back, adults: 1).absoluteString,
                       "https://www.aviasales.fr/search/PAR1005TNR08061")
        let nos = NetworkData.place(.nosyBe).airport!
        let die = NetworkData.place(.diego).airport!
        let tls = NetworkData.place(.toulouseAirport).airport!
        XCTAssertEqual(LinkBuilder.kayakMultiCityURL(legs: [(tls, nos, out), (die, tls, back)], adults: 1).absoluteString,
                       "https://www.kayak.fr/flights/TLS-NOS/2027-05-10/DIE-TLS/2027-06-08?sort=price_a")
    }

    func testGoogleFlightsAndFlixBus() {
        let google = LinkBuilder.googleFlightsURL(from: par, to: tnr, out: out, back: back).absoluteString
        XCTAssertTrue(google.contains("Flights%20from%20PAR%20to%20TNR%20on%202027-05-10%20through%202027-06-08"), google)
        let flix = LinkBuilder.flixbusURL(fromCity: "A", toCity: "B", day: out, adults: 1)!.absoluteString
        XCTAssertEqual(flix, "https://shop.flixbus.fr/search?departureCity=A&arrivalCity=B&rideDate=10.05.2027&adult=1&_locale=fr")
    }

    func testRedaction() {
        let url = URL(string: "https://serpapi.com/search.json?engine=google_flights&api_key=SECRET&q=1")!
        XCTAssertFalse(Redact.url(url).contains("SECRET"))
        let tp = URL(string: "https://api.travelpayouts.com/x?origin=PAR&token=ABC")!
        XCTAssertFalse(Redact.url(tp).contains("ABC"))
    }
}

final class ParsingTests: XCTestCase {
    func testTravelpayoutsResponse() throws {
        let json = """
        {"success":true,"data":[{"origin":"PAR","destination":"TNR","price":612,"airline":"AF","flight_number":934,
        "departure_at":"2027-05-10T21:05:00+02:00","return_at":"2027-06-08T23:30:00+03:00","transfers":0,
        "return_transfers":1,"link":"/search/PAR1005TNR08061?t=AF"}],"currency":"eur"}
        """
        let tickets = try TravelpayoutsClient.decode(Data(json.utf8))
        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets[0].price, 612)
        XCTAssertEqual(tickets[0].flightNumber, "934")
        XCTAssertEqual(tickets[0].returnTransfers, 1)
        XCTAssertEqual(TravelpayoutsScanner.describe(tickets[0]), "AF 934 · direct · retour 1 escale")
    }

    func testTravelpayoutsError() {
        let json = #"{"success":false,"error":"Unauthorized"}"#
        XCTAssertThrowsError(try TravelpayoutsClient.decode(Data(json.utf8)))
    }

    func testSerpApiResponse() throws {
        let json = """
        {"search_metadata":{"status":"Success","google_flights_url":"https://www.google.com/travel/flights?tfs=abc"},
         "best_flights":[{"price":1290,"total_duration":1015,"flights":[
            {"airline":"Air France","flight_number":"AF 934","departure_airport":{"id":"CDG","time":"2027-05-10 21:05"},
             "arrival_airport":{"id":"TNR","time":"2027-05-11 10:10"}}]}],
         "other_flights":[{"price":1180,"total_duration":1300,"flights":[
            {"airline":"Ethiopian","departure_airport":{"id":"CDG","time":"2027-05-10 22:00"},"arrival_airport":{"id":"ADD"}},
            {"airline":"Ethiopian","departure_airport":{"id":"ADD"},"arrival_airport":{"id":"TNR"}}]}]}
        """
        let result = try SerpApiClient.parse(Data(json.utf8))
        XCTAssertEqual(result.totalPrice, 1180)
        XCTAssertEqual(result.googleFlightsURL?.absoluteString, "https://www.google.com/travel/flights?tfs=abc")
        XCTAssertTrue(result.detail.contains("Ethiopian"))
        XCTAssertTrue(result.detail.contains("CDG-ADD-TNR"))
    }

    func testSerpApiNoResults() throws {
        let json = #"{"error":"Google Flights hasn't returned any results for this query."}"#
        let result = try SerpApiClient.parse(Data(json.utf8))
        XCTAssertNil(result.totalPrice)
    }

    func testFlixBusResponse() throws {
        let json = """
        {"trips":[{"results":{
          "a":{"status":"available","price":{"total":40.99},"departure":{"date":"2027-05-10T15:30:00+02:00"},
               "arrival":{"date":"2027-05-11T00:25:00+02:00"},"available":{"seats":52}},
          "b":{"status":"available","price":{"total":36.99},"departure":{"date":"2027-05-10T21:25:00+02:00"},
               "arrival":{"date":"2027-05-11T06:25:00+02:00"},"available":{"seats":49}},
          "c":{"status":"full","price":{"total":19.99}}}}]}
        """
        let offer = try FlixBusClient.cheapest(Data(json.utf8))
        XCTAssertEqual(offer?.total, 36.99)
        XCTAssertEqual(offer?.seats, 49)
    }

    func testSNCFJourneys() throws {
        // Réponse réelle de api.sncf.com (Toulouse Matabiau - Paris, 1er décembre 2026), réduite.
        let json = """
        {"journeys":[{"departure_date_time":"20261201T061000","arrival_date_time":"20261201T110300","duration":17580,"nb_transfers":0,"fare":{"found":false,"total":{"value":"0.0"},"links":[]},"sections":[{"type":"crow_fly"},{"type":"public_transport","display_informations":{"commercial_mode":"TGV INOUI","headsign":"8502"}},{"type":"crow_fly"}]},{"departure_date_time":"20261201T092400","arrival_date_time":"20261201T142200","duration":17880,"nb_transfers":1,"fare":{"found":false,"total":{"value":"0.0"},"links":[]},"sections":[{"type":"crow_fly"},{"type":"public_transport","display_informations":{"commercial_mode":"Intercités","headsign":"4752"}},{"type":"waiting"},{"type":"public_transport","display_informations":{"commercial_mode":"TGV INOUI","headsign":"12264"}},{"type":"crow_fly"}]},{"departure_date_time":"20261201T194300","arrival_date_time":"20261202T071600","duration":41580,"nb_transfers":0,"fare":{"found":false,"total":{"value":"0.0"}},"sections":[{"type":"public_transport","display_informations":{"commercial_mode":"Intercités de nuit","headsign":"3750"}}]}]}
        """
        let journeys = try SNCFClient.parseJourneys(Data(json.utf8))
        XCTAssertEqual(journeys.count, 3)
        XCTAssertEqual(journeys[0].departure, "06:10")
        XCTAssertEqual(journeys[0].arrival, "11:03")
        XCTAssertEqual(journeys[0].trains, ["TGV INOUI 8502"])
        XCTAssertEqual(journeys[0].durationMin, 293)
        XCTAssertNil(journeys[0].fare)
        XCTAssertEqual(journeys[1].trains, ["Intercités 4752", "TGV INOUI 12264"])
        XCTAssertEqual(journeys[1].transfers, 1)
        XCTAssertEqual(journeys[2].arrivalDayOffset, 1)
        XCTAssertEqual(journeys[2].modes, ["Intercités de nuit"])
    }

    func testSNCFErrorsAndWindow() throws {
        XCTAssertEqual(try SNCFClient.parseJourneys(Data(#"{"error":{"id":"no_solution","message":"no solution"}}"#.utf8)).count, 0)
        XCTAssertThrowsError(try SNCFClient.parseJourneys(Data(#"{"error":{"id":"date_out_of_bounds","message":"date is not in data production period"}}"#.utf8)))
        let window = try SNCFClient.parseWindow(Data(#"{"regions":[{"start_production_date":"20261118","end_production_date":"20261217","status":"running"}]}"#.utf8))
        XCTAssertEqual(window, SNCFWindow(start: Day(year: 2026, month: 11, day: 18), end: Day(year: 2026, month: 12, day: 17)))
        let today = Day(year: 2026, month: 11, day: 20)
        // Jour publié : interrogé tel quel.
        let inside = SNCFClient.referenceDay(for: Day(year: 2026, month: 12, day: 1), window: window, today: today)
        XCTAssertTrue(inside.exact)
        // Mai 2027 pas encore publié : même jour de la semaine dans la période publiée.
        let may = Day(year: 2027, month: 5, day: 10)
        let reference = SNCFClient.referenceDay(for: may, window: window, today: today)
        XCTAssertFalse(reference.exact)
        XCTAssertEqual(reference.day.weekday, may.weekday)
        XCTAssertTrue(reference.day > today && reference.day <= window.end)
    }

    func testSNCFFareGrids() throws {
        // Extrait réel de ressources.data.sncf.com (tarifs-tgv-inoui-ouigo et tarifs-intercites).
        let tgv = """
        {"total_count":4,"results":[
        {"transporteur":"OUIGO","gare_origine":"TOULOUSE MATABIAU","gare_destination":"PARIS MONTPARNASSE 1 ET 2","classe":"2","profil_tarifaire":"Tarif Normal","prix_minimum":19,"prix_maximum":119},
        {"transporteur":"TGV INOUI","gare_origine":"PARIS MONTPARNASSE 1 ET 2","gare_destination":"TOULOUSE MATABIAU","classe":"2","profil_tarifaire":"Tarif Normal","prix_minimum":25.5,"prix_maximum":143},
        {"transporteur":"TGV INOUI","gare_origine":"PARIS GARE DE LYON","gare_destination":"TOULOUSE MATABIAU","classe":"2","profil_tarifaire":"Tarif Normal","prix_minimum":25.5,"prix_maximum":155}]}
        """
        let grids = try SNCFFareClient.parseTGV(Data(tgv.utf8))
        XCTAssertEqual(grids["ouigo"], FareRange(min: 19, max: 119, source: grids["ouigo"]!.source))
        XCTAssertEqual(grids["tgv"]?.max, 143, "la grille de Montparnasse est prioritaire")
        XCTAssertEqual(grids["ouigo"]?.likely, 44)
        let night = """
        {"results":[{"transporteur":"Intercités de nuit à réservation obligatoire","origine":"PARIS AUSTERLITZ","destination":"TOULOUSE MATABIAU","classe":"2","type_place":"couchette","prix_min":29,"prix_max":142}]}
        """
        XCTAssertEqual(try SNCFFareClient.parseIntercites(Data(night.utf8))?.min, 29)
    }

    func testTrainsHaveNoInventedPrice() {
        let params = SearchParams.defaults(today: Day(year: 2026, month: 11, day: 20))
        let engine = RouteEngine(params: params, book: PriceBook())
        let ouigo = NetworkData.connections.first { $0.id == "TLS_V-PAR_G" }!.options.first { $0.id == "ouigo" }!
        let priced = engine.priceOption(ouigo, from: .toulouse, to: .parisStations, day: Day(year: 2027, month: 5, day: 10))
        XCTAssertEqual(priced.quality, .unknown)
        XCTAssertEqual(priced.price, 0)
        XCTAssertTrue(priced.info?.contains("19") ?? false, "la grille officielle est affichée comme information")
    }

    func testCalendarAndRateParsing() throws {
        // Réponse réelle du calendrier Google Flights (SerpApi), réduite.
        let calendar = """
        {"search_metadata":{"status":"Success"},"prices":[
          {"outbound_date":"2027-05-30","return_date":"2027-06-28","price":924,"low_price":true},
          {"outbound_date":"2027-07-12","return_date":"2027-08-10","price":1933}]}
        """
        let prices = try SerpApiClient.parseCalendar(Data(calendar.utf8))
        XCTAssertEqual(prices.count, 2)
        XCTAssertEqual(prices[0].out, Day(year: 2027, month: 5, day: 30))
        XCTAssertEqual(prices[0].back, Day(year: 2027, month: 6, day: 28))
        XCTAssertEqual(prices[1].price, 1933)
        let empty = #"{"error":"Google Flights hasn't returned any results for this query."}"#
        XCTAssertTrue(try SerpApiClient.parseCalendar(Data(empty.utf8)).isEmpty)
        let rateJSON = #"{"result":"success","time_last_update_unix":1763856152,"rates":{"EUR":1,"MGA":5037.001324}}"#
        let rate = try ExchangeRateClient.parse(Data(rateJSON.utf8))
        XCTAssertEqual(rate.rate, 5037.001324, accuracy: 0.0001)
        XCTAssertEqual(Fmt.ariary(20_000), "20\u{202F}000\u{202F}Ar")
    }

    func testEuroFormat() {
        XCTAssertEqual(Fmt.euro(1234.4), "1\u{202F}234\u{202F}€")
        XCTAssertEqual(Fmt.duration(1530), "1 j 1 h")
        XCTAssertEqual(Fmt.duration(260), "4 h 20")
    }
}
