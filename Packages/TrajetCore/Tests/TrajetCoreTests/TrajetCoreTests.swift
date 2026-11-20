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

    func testEngineWithoutPricesUsesEstimates() {
        let result = RouteEngine(params: params, book: PriceBook()).run()
        print(result.stats.description)
        XCTAssertFalse(result.trips.isEmpty)
        let totals = result.trips.map(\.total)
        XCTAssertEqual(totals, totals.sorted())
        XCTAssertEqual(Set(result.trips.map(\.id)).count, result.trips.count, "identifiants en double")
        for trip in result.trips.prefix(50) {
            XCTAssertGreaterThan(trip.total, 0)
            XCTAssertEqual(trip.outbound.first?.from, .toulouse)
            XCTAssertEqual(trip.inbound.last?.to, .toulouse)
            XCTAssertTrue((28...30).contains(trip.stayDays))
        }
        XCTAssertFalse(result.bestByDay.isEmpty)
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

    func testRealPriceReplacesEstimate() {
        var book = PriceBook()
        let day = Day(year: 2027, month: 5, day: 10)
        book.putOneWay(Quote(price: 111, source: .travelpayouts), from: .parisAirports, to: .tana, day: day)
        let engine = RouteEngine(params: params, book: book)
        let trip = engine.evaluate(outSignature: "TLS_V>PAR_G>PAR>TNR>DIE", inSignature: "DIE>TNR>PAR>PAR_G>TLS_V",
                                   out: day, back: day.adding(days: 29))
        XCTAssertNotNil(trip)
        let flight = trip?.outbound.first { $0.from == .parisAirports && $0.to == .tana }
        XCTAssertEqual(flight?.chosen.price, 111)
        XCTAssertEqual(flight?.chosen.quality, .cached)
    }

    func testRoundTripTicketIsUsedWhenCheaper() {
        var book = PriceBook()
        let out = Day(year: 2027, month: 6, day: 2)
        let back = out.adding(days: 29)
        // Le vol Paris-Nosy Be part le jour même à l'aller (bus + RER) et le jour du retour depuis Nosy Be.
        book.putOneWay(Quote(price: 600, source: .travelpayouts), from: .parisAirports, to: .nosyBe, day: out)
        book.putOneWay(Quote(price: 600, source: .travelpayouts), from: .nosyBe, to: .parisAirports, day: back)
        book.putRoundTrip(Quote(price: 800, source: .travelpayouts), from: .parisAirports, to: .nosyBe, out: out, back: back)
        let engine = RouteEngine(params: params, book: book)
        let trip = engine.evaluate(outSignature: "TLS_V>PAR_G>PAR>NOS", inSignature: "NOS>PAR>PAR_G>TLS_V",
                                   out: out, back: back)
        XCTAssertEqual(trip?.outbound.first { $0.mode == .avion }?.day, out)
        XCTAssertEqual(trip?.inbound.first { $0.mode == .avion }?.day, back)
        XCTAssertEqual(trip?.rtTickets.count, 1)
        XCTAssertEqual(trip?.rtTickets.first?.price, 800)
        XCTAssertTrue(trip?.outbound.contains { $0.roundTripPaired } ?? false)
        XCTAssertTrue(trip?.inbound.contains { $0.roundTripPaired } ?? false)
    }

    func testLiveQuoteBeatsCachedQuote() {
        var book = PriceBook()
        let day = Day(year: 2027, month: 5, day: 10)
        book.putOneWay(Quote(price: 400, source: .travelpayouts), from: .parisAirports, to: .tana, day: day)
        book.putOneWay(Quote(price: 520, source: .serpapi), from: .parisAirports, to: .tana, day: day)
        book.putOneWay(Quote(price: 300, source: .travelpayouts), from: .parisAirports, to: .tana, day: day)
        XCTAssertEqual(book.oneWay["PAR>TNR"]?[day.key]?.price, 520)
        XCTAssertEqual(book.oneWay["PAR>TNR"]?[day.key]?.source, .serpapi)
    }

    func testAdultsMultiplyButVehicleDoesNot() {
        var p = params
        p.adults = 3
        let engine = RouteEngine(params: p, book: PriceBook())
        let option = NetworkData.connections.first { $0.id == "ANK-DIE" }!.options.first { $0.perVehicle }!
        let priced = engine.priceOption(option, from: .ankify, to: .diego, day: Day(year: 2027, month: 5, day: 10))
        XCTAssertEqual(priced.price, option.priceTypical)
        let bus = NetworkData.connections.first { $0.id == "ANK-DIE" }!.options.first { !$0.perVehicle }!
        XCTAssertEqual(engine.priceOption(bus, from: .ankify, to: .diego, day: Day(year: 2027, month: 5, day: 10)).price,
                       bus.priceTypical * 3)
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
    }

    func testOldLiveQuoteIsNoLongerLive() throws {
        let feed = try FeedReader.decode(Data(Self.json.utf8))
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

    func testTrainGridUsedByEngine() {
        let params = SearchParams.defaults(today: Day(year: 2026, month: 11, day: 20))
        let engine = RouteEngine(params: params, book: PriceBook())
        let ouigo = NetworkData.connections.first { $0.id == "TLS_V-PAR_G" }!.options.first { $0.id == "ouigo" }!
        let priced = engine.priceOption(ouigo, from: .toulouse, to: .parisStations, day: Day(year: 2027, month: 5, day: 10))
        XCTAssertEqual(priced.quality, .grid)
        XCTAssertEqual(priced.price, 44)
        XCTAssertTrue(priced.quote?.detail?.contains("19") ?? false)
    }

    func testEuroFormat() {
        XCTAssertEqual(Fmt.euro(1234.4), "1\u{202F}234\u{202F}€")
        XCTAssertEqual(Fmt.duration(1530), "1 j 1 h")
        XCTAssertEqual(Fmt.duration(260), "4 h 20")
    }
}
