import SwiftUI
import TrajetCore
import UIKit

struct TripDetailView: View {
    let tripID: String
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let trip = model.trip(id: tripID) {
                content(trip)
            } else {
                ContentUnavailableView("Trajet introuvable", image: "ui.alert",
                                       description: Text("Relancez une recherche depuis l'onglet Trajets."))
            }
        }
        .navigationTitle("Aller-retour")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func content(_ trip: RoundTrip) -> some View {
        let adults = model.params.adults
        let isVerifying = model.verifying.contains(trip.id)
        return List {
            Section {
                SummaryView(trip: trip, adults: adults)
            }

            Section {
                Button {
                    Task { await model.verify(trip) }
                } label: {
                    HStack(spacing: 10) {
                        if isVerifying {
                            ProgressView()
                        } else {
                            Icon("ui.bolt", size: 18, color: .accentColor)
                        }
                        Text(isVerifying ? "Vérification en cours…" : "Vérifier les prix en temps réel")
                            .font(.headline)
                    }
                }
                .disabled(isVerifying || !model.hasSerpApi)
            } footer: {
                Text(verifyFooter(trip))
            }

            Section {
                ForEach(trip.outbound) { step in
                    StepRow(step: step, adults: adults)
                }
            } header: {
                Text("Aller · \(Fmt.dayLong(trip.outDay))")
            } footer: {
                Text("Durée totale environ \(Fmt.duration(trip.outDurationMin)), correspondances comprises. Horaires indicatifs (départ supposé à 8 h).")
            }

            if !trip.localTransfer.isEmpty {
                Section {
                    ForEach(trip.localTransfer) { step in
                        StepRow(step: step, adults: adults, flexibleDate: true)
                    }
                } header: {
                    Text("Sur place : \(NetworkData.place(trip.arrival).short) vers \(NetworkData.place(trip.departureBack).short)")
                } footer: {
                    Text("Trajet à faire pendant le séjour, à la date de votre choix. Son prix est compris dans le total.")
                }
            }

            Section {
                ForEach(trip.inbound) { step in
                    StepRow(step: step, adults: adults)
                }
            } header: {
                Text("Retour · \(Fmt.dayLong(trip.backDay))")
            } footer: {
                Text("Durée totale environ \(Fmt.duration(trip.inDurationMin)), correspondances comprises.")
            }

            if !trip.rtTickets.isEmpty {
                Section {
                    ForEach(trip.rtTickets) { ticket in
                        TicketRow(ticket: ticket, adults: adults)
                    }
                } header: {
                    Text("Billets aller-retour")
                } footer: {
                    Text("Moins cher que deux allers simples pour ces dates.")
                }
            }

            let flights = (trip.outbound + trip.inbound).filter { $0.mode == .avion }
            if flights.count >= 2 {
                Section {
                    BookingLinks(links: [multiCityLink(flights, adults: adults)])
                } header: {
                    Text("Tous les vols en un seul billet")
                } footer: {
                    Text("Recherche multi-destinations sur Kayak avec les mêmes vols et les mêmes dates : parfois moins cher et avec correspondances protégées.")
                }
            }
        }
    }

    private func verifyFooter(_ trip: RoundTrip) -> String {
        guard model.hasSerpApi else {
            return "Ajoutez une clé SerpApi (onglet Réglages) pour vérifier les vols sur Google Flights et les bus FlixBus à l'instant."
        }
        let outFlights = trip.outbound.filter { $0.mode == .avion }
        let inFlights = trip.inbound.filter { $0.mode == .avion }
        let paired = outFlights.filter { o in inFlights.contains { $0.from == o.to && $0.to == o.from } }.count
        let searches = outFlights.count + inFlights.count - paired
        var text = "Interroge Google Flights (\(searches) recherche\(searches > 1 ? "s" : "") SerpApi) et FlixBus pour ces dates exactes."
        if let account = model.serpAccount, let left = account.totalSearchesLeft ?? account.planSearchesLeft {
            text += " Recherches restantes ce mois-ci : \(left)."
        }
        return text
    }

    private func multiCityLink(_ flights: [PricedStep], adults: Int) -> BookingLink {
        let legs: [(AirportCode, AirportCode, Day)] = flights.compactMap { step in
            guard let a = NetworkData.place(step.from).airport, let b = NetworkData.place(step.to).airport else { return nil }
            return (a, b, step.day)
        }
        return BookingLink(label: "Kayak multi-destinations",
                           url: LinkBuilder.kayakMultiCityURL(legs: Array(legs.prefix(6)), adults: adults),
                           prefilled: true)
    }
}

struct SummaryView: View {
    let trip: RoundTrip
    let adults: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Fmt.euro(trip.total))
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                    Text("aller-retour, \(adults) adulte\(adults > 1 ? "s" : ""), tout compris")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(trip.stayDays) jours")
                        .font(.headline)
                    Text("sur place")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: trip.realShare) {
                Text("\(Int((trip.realShare * 100).rounded())) % du total vient de prix réels ou de tarifs connus")
                    .font(.caption)
            }
            .tint(trip.realShare >= 0.75 ? .green : (trip.realShare >= 0.4 ? .teal : .orange))
            HStack(spacing: 16) {
                label("ui.calendar", "Aller", "\(Fmt.dayShort(trip.outDay)), \(Fmt.duration(trip.outDurationMin))")
                label("ui.calendar", "Retour", "\(Fmt.dayShort(trip.backDay)), \(Fmt.duration(trip.inDurationMin))")
            }
            HStack(spacing: 6) {
                Icon("ui.pin", size: 14, color: .accentColor)
                Text("Arrivée : \(NetworkData.place(trip.arrival).short) · Retour depuis : \(NetworkData.place(trip.departureBack).short)")
                    .font(.footnote)
            }
        }
        .padding(.vertical, 4)
    }

    private func label(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Icon(icon, size: 14, color: .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.footnote.weight(.semibold))
            }
        }
    }
}

struct StepRow: View {
    let step: PricedStep
    let adults: Int
    var flexibleDate = false
    @State private var showOptions = false

    var body: some View {
        let option = step.chosen.option
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                ModeIcon(mode: step.mode, size: 20)
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(NetworkData.place(step.from).short).font(.headline)
                        Icon("ui.arrow", size: 13, color: .secondary)
                        Text(NetworkData.place(step.to).short).font(.headline)
                    }
                    Text(option.operatorName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(flexibleDate
                         ? "Date libre · \(Fmt.duration(option.durationMin))"
                         : "\(Fmt.dayLong(step.day)) · \(Fmt.duration(option.durationMin))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    if step.roundTripPaired {
                        Text("billet AR")
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Text(Fmt.euro(step.chosen.price))
                            .font(.headline)
                            .monospacedDigit()
                    }
                    QualityPill(quality: step.chosen.quality)
                }
            }

            if let quote = step.chosen.quote {
                Text(quote.source.label + (quote.detail.map { " · " + $0 } ?? "")
                     + (quote.source == .sncf ? "" : " · relevé \(Fmt.age(quote.fetchedAt))"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Fréquence : \(option.frequency)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !option.verified {
                HStack(spacing: 6) {
                    Icon("ui.alert", size: 13, color: .orange)
                    Text("Liaison à vérifier pour la saison en cours.")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            if let notes = option.notes {
                Text(notes).font(.footnote)
            }

            if !flexibleDate && step.options.contains(where: { $0.option.sncfMode != nil }) {
                TrainScheduleView(step: step)
            }

            if step.roundTripPaired {
                Text("Prix compris dans le billet aller-retour (plus bas).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                let links = bookingLinks(for: step.chosen)
                BookingLinks(links: links)
                if links.contains(where: { !$0.prefilled }) && !flexibleDate {
                    HStack(spacing: 8) {
                        Text("Date à saisir sur le site : \(Fmt.dayLong(step.day))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = "\(Fmt.dayLong(step.day)), \(NetworkData.place(step.from).cityName) - \(NetworkData.place(step.to).cityName)"
                        } label: {
                            Icon("ui.copy", size: 15, color: .accentColor)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Copier la date et le trajet")
                    }
                }
            }

            if step.options.count > 1 {
                DisclosureGroup(isExpanded: $showOptions) {
                    ForEach(step.options.dropFirst()) { alternative in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                ModeIcon(mode: alternative.option.mode, size: 15)
                                Text(alternative.option.operatorName)
                                    .font(.footnote.weight(.semibold))
                                Spacer()
                                Text(Fmt.euro(alternative.price))
                                    .font(.footnote.weight(.semibold))
                                    .monospacedDigit()
                                QualityPill(quality: alternative.quality)
                            }
                            if let detail = alternative.quote?.detail {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                            BookingLinks(links: bookingLinks(for: alternative))
                        }
                        .padding(.vertical, 4)
                    }
                } label: {
                    Text("Autres options pour cette étape (\(step.options.count - 1))")
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func bookingLinks(for priced: PricedOption) -> [BookingLink] {
        var links: [BookingLink] = []
        if let quote = priced.quote, let url = quote.link {
            let label: String
            switch quote.source {
            case .flixbus: label = "Réserver ce bus"
            case .serpapi: label = "Google Flights (ce vol)"
            case .travelpayouts: label = "Offre Aviasales"
            case .sncf: label = "SNCF"
            }
            links.append(BookingLink(label: label, url: url, prefilled: true))
        }
        links += LinkBuilder.links(for: priced.option, from: step.from, to: step.to, day: step.day, adults: adults)
        return links
    }
}

/// Horaires réels des trains SNCF pour une étape (API SNCF, clé personnelle).
struct TrainScheduleView: View {
    let step: PricedStep
    @Environment(AppModel.self) private var model
    @State private var expanded = false

    var body: some View {
        let key = AppModel.scheduleKey(step)
        let preferred = step.chosen.option.sncfMode
        Group {
            if let schedule = model.schedules[key] {
                DisclosureGroup(isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(schedule.exact
                             ? "Horaires réels du \(Fmt.dayLong(schedule.day))."
                             : "Les horaires du \(Fmt.dayLong(schedule.day)) ne sont pas encore publiés : horaires types relevés le \(Fmt.dayLong(schedule.referenceDay)) (même jour de la semaine).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if schedule.journeys.isEmpty {
                            Text("Aucun train trouvé ce jour-là.")
                                .font(.caption)
                        }
                        ForEach(schedule.journeys) { journey in
                            JourneyRow(journey: journey, highlighted: preferred.map { journey.modes.contains($0) } ?? false)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    HStack(spacing: 6) {
                        Icon("mode.train", size: 14, color: .accentColor)
                        Text("Horaires SNCF : \(schedule.journeys.count) train\(schedule.journeys.count > 1 ? "s" : "")\(schedule.exact ? "" : " (horaires types)")")
                            .font(.footnote.weight(.semibold))
                    }
                }
            } else if !model.hasSNCF {
                HStack(alignment: .top, spacing: 6) {
                    Icon("mode.train", size: 13, color: .secondary)
                    Text("Horaires des trains : ajoutez votre clé API SNCF dans Réglages, ou installez le serveur de mise à jour.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if let error = model.scheduleErrors[key] {
                HStack(alignment: .top, spacing: 6) {
                    Icon("ui.alert", size: 13, color: .orange)
                    Text("Horaires SNCF indisponibles : \(error)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Chargement des horaires SNCF…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: key) { await model.loadSchedule(for: step) }
    }
}

struct JourneyRow: View {
    let journey: TrainJourney
    let highlighted: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(spacing: 4) {
                Text(journey.departure)
                Icon("ui.arrow", size: 10, color: .secondary)
                Text(journey.arrival + (journey.arrivalDayOffset > 0 ? " (+\(journey.arrivalDayOffset) j)" : ""))
            }
            .font(.footnote.monospacedDigit().weight(highlighted ? .semibold : .regular))
            .frame(minWidth: 118, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(journey.trains.joined(separator: " + "))
                    .font(.caption.weight(highlighted ? .semibold : .regular))
                    .foregroundStyle(highlighted ? Color.accentColor : Color.primary)
                Text("\(Fmt.duration(journey.durationMin)) · "
                     + (journey.transfers == 0 ? "direct" : "\(journey.transfers) correspondance\(journey.transfers > 1 ? "s" : "")")
                     + (journey.fare.map { " · \(Fmt.euro($0))" } ?? ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TicketRow: View {
    let ticket: RoundTripTicket
    let adults: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Icon("ui.swap", size: 18, color: .accentColor)
                Text("\(NetworkData.place(ticket.from).short) - \(NetworkData.place(ticket.to).short)")
                    .font(.headline)
                Spacer()
                Text(Fmt.euro(ticket.price))
                    .font(.headline)
                    .monospacedDigit()
            }
            Text("Aller \(Fmt.dayLong(ticket.outDay)), retour \(Fmt.dayLong(ticket.backDay))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                QualityPill(quality: ticket.quality)
                if let quote = ticket.quote {
                    Text((quote.detail.map { $0 + " · " } ?? "") + "relevé \(Fmt.age(quote.fetchedAt))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            BookingLinks(links: links)
        }
        .padding(.vertical, 4)
    }

    private var links: [BookingLink] {
        var result: [BookingLink] = []
        if let quote = ticket.quote, let url = quote.link {
            result.append(BookingLink(label: quote.source == .serpapi ? "Google Flights (cette recherche)" : "Offre Aviasales",
                                      url: url, prefilled: true))
        }
        if let a = NetworkData.place(ticket.from).airport, let b = NetworkData.place(ticket.to).airport {
            result += LinkBuilder.flightLinks(from: a, to: b, out: ticket.outDay, back: ticket.backDay, adults: adults)
        }
        return result
    }
}
