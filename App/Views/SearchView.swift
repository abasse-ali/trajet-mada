import SwiftUI
import TrajetCore

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
            List {
                Section {
                    destinationToggle(.diego, title: "Antsiranana (Diego-Suarez)")
                    destinationToggle(.nosyBe, title: "Nosy Be")
                    Toggle(isOn: $model.params.allowOpenJaw) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Arrivée et retour par des villes différentes")
                            Text("Ex. arrivée à Nosy Be, retour depuis Antsiranana")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Destination au départ de Toulouse")
                }

                Section {
                    DatePicker("Partir à partir du", selection: dayBinding(\.periodStart), displayedComponents: .date)
                    DatePicker("Être rentré le", selection: dayBinding(\.periodEnd), displayedComponents: .date)
                    Stepper(value: $model.params.stayMin, in: 1...120) {
                        Text("Séjour minimum : \(model.params.stayMin) jours")
                    }
                    Stepper(value: $model.params.stayMax, in: max(1, model.params.stayMin)...150) {
                        Text("Séjour maximum : \(model.params.stayMax) jours")
                    }
                    Stepper(value: $model.params.adults, in: 1...9) {
                        HStack(spacing: 8) {
                            Icon("ui.user", size: 16, color: .secondary)
                            Text("\(model.params.adults) adulte\(model.params.adults > 1 ? "s" : "")")
                        }
                    }
                } header: {
                    Text("Aller-retour")
                } footer: {
                    Text("\(model.params.datePairs.count) combinaisons de dates possibles.")
                }

                Section {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(Mode.filterable) { mode in
                            ModeChip(mode: mode, selected: model.params.modes.contains(mode)) {
                                toggle(mode)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                    Toggle("Inclure les liaisons à vérifier", isOn: $model.params.includeUnverified)
                } header: {
                    Text("Moyens de transport")
                }

                Section {
                    Button {
                        Task { await self.model.search() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.isBusy {
                                ProgressView()
                            } else {
                                Icon("ui.search", size: 18, color: .white)
                            }
                            Text(model.isBusy ? "Recherche en cours…" : "Chercher les prix réels")
                                .font(.headline)
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Color.accentColor)
                    .disabled(model.isBusy || model.params.destinations.isEmpty || !model.params.modes.contains(.avion))

                    if model.isBusy || model.progress > 0 {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: model.progress)
                            Text(model.progressText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if !model.params.modes.contains(.avion) {
                        warning("Sans avion, aucun trajet n'est possible : il n'existe pas de liaison maritime régulière entre la France et Madagascar.")
                    }
                    if let message = model.message {
                        warning(message)
                    }
                    if !model.hasTravelpayouts {
                        NavigationLink {
                            SettingsView(embedded: true)
                        } label: {
                            Label {
                                Text("Ajouter les clés d'API pour les prix réels")
                            } icon: {
                                Icon("ui.key", size: 18, color: .accentColor)
                            }
                        }
                    }
                }

                if !model.results.isEmpty {
                    if model.bestByDay.count > 1 {
                        Section {
                            PriceChart(data: model.bestByDay)
                                .padding(.vertical, 6)
                        } header: {
                            Text("Meilleur prix total selon la date de départ")
                        }
                    }

                    Section {
                        Picker("Trier par", selection: $model.sort) {
                            ForEach(SortKey.allCases) { key in
                                Text(key.label).tag(key)
                            }
                        }
                        .pickerStyle(.segmented)
                        .id("results")
                        Toggle("Seulement des vols à prix réel", isOn: $model.onlyRealFlights)
                    } header: {
                        Text("\(model.sortedResults.count) allers-retours")
                    } footer: {
                        if let stats = model.stats {
                            Text(stats.description)
                        }
                    }

                    Section {
                        let list = model.sortedResults
                        ForEach(list.prefix(model.visibleCount)) { trip in
                            NavigationLink(value: trip.id) {
                                TripRow(trip: trip)
                            }
                        }
                        if list.count > model.visibleCount {
                            Button("Afficher 60 de plus (\(list.count - model.visibleCount) restants)") {
                                self.model.visibleCount += 60
                            }
                        }
                    }
                }
            }
            .task(id: model.results.count) {
                // Options de lancement utilisées pour les captures d'écran automatiques (CI).
                guard !model.results.isEmpty else { return }
                if LaunchOptions.openFirst, path.isEmpty, let first = model.sortedResults.first {
                    path.append(first.id)
                } else if LaunchOptions.scrollToResults {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    withAnimation { proxy.scrollTo("results", anchor: .top) }
                }
            }
            }
            .navigationTitle("Toulouse - Madagascar")
            .navigationDestination(for: String.self) { id in
                TripDetailView(tripID: id)
            }
            .onChange(of: model.params) { _, _ in
                Persist.save(self.model.params, "params.json")
            }
        }
    }

    private func toggle(_ mode: Mode) {
        if model.params.modes.contains(mode) {
            model.params.modes.remove(mode)
        } else {
            model.params.modes.insert(mode)
        }
    }

    private func destinationToggle(_ place: PlaceID, title: String) -> some View {
        Toggle(isOn: Binding(
            get: { model.params.destinations.contains(place) },
            set: { on in
                if on {
                    model.params.destinations.insert(place)
                } else if model.params.destinations.count > 1 {
                    model.params.destinations.remove(place)
                }
            }
        )) {
            HStack(spacing: 8) {
                Icon("ui.pin", size: 16, color: .accentColor)
                Text(title)
            }
        }
    }

    private func dayBinding(_ keyPath: WritableKeyPath<SearchParams, Day>) -> Binding<Date> {
        Binding(
            get: { model.params[keyPath: keyPath].localDate() },
            set: { model.params[keyPath: keyPath] = Day(localDate: $0) }
        )
    }

    private func warning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Icon("ui.alert", size: 16, color: .orange)
            Text(text)
                .font(.footnote)
        }
    }
}

struct ModeChip: View {
    let mode: Mode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                ModeIcon(mode: mode, size: 15, color: selected ? .white : .accentColor)
                Text(mode.label)
                    .font(.subheadline)
                    .foregroundStyle(selected ? Color.white : Color.primary)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(selected ? Color.accentColor : Color.secondary.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.borderless)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct TripRow: View {
    let trip: RoundTrip

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(Fmt.euro(trip.total))
                    .font(.title3.bold())
                    .monospacedDigit()
                Spacer()
                HStack(spacing: 4) {
                    Icon("ui.calendar", size: 13, color: .secondary)
                    Text("\(Fmt.dayShort(trip.outDay)) - \(Fmt.dayShort(trip.backDay)) · \(trip.stayDays) j")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .top, spacing: 6) {
                Text("Aller").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                RouteChain(steps: trip.outbound)
            }
            HStack(alignment: .top, spacing: 6) {
                Text("Retour").font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                RouteChain(steps: trip.inbound)
            }
            FlowLayout(spacing: 6, lineSpacing: 6) {
                Pill(text: "\(Int((trip.realShare * 100).rounded())) % prix réels",
                     icon: trip.realShare >= 0.75 ? "ui.check" : "ui.info",
                     color: trip.realShare >= 0.75 ? .green : (trip.realShare >= 0.4 ? .teal : .orange))
                Pill(text: "\(trip.tickets) billet\(trip.tickets > 1 ? "s" : "")", icon: "ui.ticket")
                if !trip.rtTickets.isEmpty {
                    Pill(text: "billet aller-retour", icon: "ui.swap", color: .teal)
                }
                if trip.isOpenJaw {
                    Pill(text: "2 villes", icon: "ui.pin", color: .indigo)
                }
                if trip.unprotected > 0 {
                    Pill(text: "correspondance non protégée", icon: "ui.alert", color: .orange)
                }
                if trip.rare > 0 {
                    Pill(text: "vol peu fréquent", icon: "ui.alert", color: .orange)
                }
                if trip.unverified > 0 {
                    Pill(text: "à vérifier", icon: "ui.alert", color: .orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
