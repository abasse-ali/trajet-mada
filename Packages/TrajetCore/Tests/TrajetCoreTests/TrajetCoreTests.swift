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
        book.putOneWay(Quote(price: 600, source: .travelpayouts), from: .parisAirports, to: .tana, day: out)
        book.putOneWay(Quote(price: 600, source: .travelpayouts), from: .tana, to: .parisAirports, day: back)
        book.putRoundTrip(Quote(price: 800, source: .travelpayouts), from: .parisAirports, to: .tana, out: out, back: back)
        let engine = RouteEngine(params: params, book: book)
        let trip = engine.evaluate(outSignature: "TLS_V>PAR_G>PAR>TNR>DIE", inSignature: "DIE>TNR>PAR>PAR_G>TLS_V",
                                   out: out, back: back)
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

    func testEuroFormat() {
        XCTAssertEqual(Fmt.euro(1234.4), "1\u{202F}234\u{202F}€")
        XCTAssertEqual(Fmt.duration(1530), "1 j 1 h")
        XCTAssertEqual(Fmt.duration(260), "4 h 20")
    }
}
