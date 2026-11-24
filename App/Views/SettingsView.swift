import SwiftUI
import TrajetCore

struct SettingsView: View {
    var embedded = false

    var body: some View {
        if embedded {
            SettingsForm()
        } else {
            NavigationStack {
                SettingsForm()
            }
        }
    }
}

struct SettingsForm: View {
    @Environment(AppModel.self) private var model
    @State private var travelpayouts = ""
    @State private var serpapi = ""
    @State private var sncf = ""
    @State private var feedURL = ""
    @State private var feedAuto = true
    @State private var autoCollect = true
    @State private var serpBudget = 2
    @State private var saved = false
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section {
                Button {
                    Task { await model.collectAll(trigger: .manual) }
                } label: {
                    HStack(spacing: 8) {
                        if model.isBusy {
                            ProgressView()
                        } else {
                            Icon("ui.refresh", size: 16, color: .accentColor)
                        }
                        Text(model.isBusy ? model.progressText : "Lancer la collecte complète maintenant")
                    }
                }
                .disabled(model.isBusy)
                if model.isBusy {
                    ProgressView(value: model.progress)
                }
                Toggle("Collecte automatique chaque nuit", isOn: $autoCollect)
                Stepper(value: $serpBudget, in: 0...10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Calendriers Google Flights : \(serpBudget) par jour")
                        Text("Utilisés aujourd'hui par l'iPhone : \(model.serpUsedToday) (1 calendrier = 1 recherche = environ 120 dates)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let last = model.lastCollection {
                    LabeledContent("Dernière collecte", value: Fmt.age(last))
                    if let summary = model.lastCollectionSummary {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Collecte sur l'iPhone")
            } footer: {
                Text("L'iPhone relève lui-même tout ce que relève le serveur : calendriers de prix Google Flights (un prix réel par date de départ), vols Aviasales, FlixBus pour chaque jour, horaires SNCF, taux de change. Il faut les clés ci-dessous. La collecte de nuit est lancée par iOS quand l'iPhone a du réseau, souvent pendant la charge. La clé SerpApi a 250 recherches par mois au total, partagées avec le serveur ; un calendrier déjà relevé par le serveur depuis moins de 4 jours n'est pas refait.")
            }
            .onChange(of: autoCollect) { _, value in
                model.saveCollectSettings(auto: value, serpBudget: serpBudget)
            }
            .onChange(of: serpBudget) { _, value in
                model.saveCollectSettings(auto: autoCollect, serpBudget: value)
            }

            Section {
                Toggle("Mettre à jour à l'ouverture", isOn: $feedAuto)
                TextField("Adresse des données", text: $feedURL, axis: .vertical)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                Button {
                    model.saveFeedSettings(url: feedURL, autoUpdate: feedAuto)
                    Task { await model.syncFeed() }
                } label: {
                    HStack(spacing: 8) {
                        if model.isSyncingFeed {
                            ProgressView()
                        } else {
                            Icon("ui.refresh", size: 16, color: .accentColor)
                        }
                        Text("Mettre à jour maintenant")
                    }
                }
                .disabled(model.isSyncingFeed)
                if let date = model.feedDate {
                    LabeledContent("Dernières données", value: Fmt.age(date))
                }
                if let status = model.feedStatus {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Données du serveur (mise à jour quotidienne)")
            } footer: {
                Text("Votre serveur Oracle relève chaque matin les prix des vols, de FlixBus, la grille SNCF et les horaires des trains, puis les publie. L'app les récupère ici, même sans clé sur l'iPhone.")
            }
            .onChange(of: feedAuto) { _, value in
                model.saveFeedSettings(url: feedURL, autoUpdate: value)
            }

            Section {
                SecureField("Jeton API Travelpayouts", text: $travelpayouts)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Link(destination: URL(string: "https://www.travelpayouts.com/")!) {
                    linkLabel("Créer un compte gratuit Travelpayouts")
                }
            } header: {
                Text("1. Scan des prix des vols (gratuit)")
            } footer: {
                Text("Prix des vols vus par les utilisateurs d'Aviasales ces 2 à 7 derniers jours (souvent peu de dates pour l'été prochain). Jeton : menu Profil, rubrique API token.")
            }

            Section {
                SecureField("Clé API SerpApi", text: $serpapi)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Link(destination: URL(string: "https://serpapi.com/users/sign_up")!) {
                    linkLabel("Créer un compte gratuit SerpApi")
                }
            } header: {
                Text("2. Vérification en temps réel (Google Flights)")
            } footer: {
                Text("Calendriers de prix Google Flights (un prix réel pour chaque date de départ) et vérification d'un aller-retour précis. Offre gratuite : 250 recherches par mois.")
            }

            Section {
                SecureField("Clé API SNCF", text: $sncf)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Link(destination: URL(string: "https://numerique.sncf.com/startup/api/")!) {
                    linkLabel("Demander une clé API SNCF gratuite")
                }
            } header: {
                Text("3. Horaires des trains (SNCF)")
            } footer: {
                Text("Affiche les vrais horaires des trains Toulouse-Paris et Paris-Milan pour chaque étape. L'API SNCF ne donne pas les prix : ceux-ci viennent de la grille officielle SNCF (open data, sans clé). Les horaires sont publiés environ un mois à l'avance ; avant, l'app montre les horaires types du même jour de la semaine.")
            }

            Section {
                Button {
                    model.saveKeys(travelpayouts: travelpayouts, serpapi: serpapi, sncf: sncf)
                    saved = true
                    Task { await model.refreshAccount() }
                } label: {
                    HStack(spacing: 8) {
                        Icon(saved ? "ui.check" : "ui.key", size: 17, color: .accentColor)
                        Text(saved ? "Clés enregistrées" : "Enregistrer les clés")
                    }
                }
            } footer: {
                Text("Les clés restent dans le trousseau de l'iPhone. Elles n'apparaissent jamais dans le journal.")
            }

            if model.hasSerpApi {
                Section {
                    if let account = model.serpAccount {
                        LabeledContent("Recherches restantes", value: "\(account.totalSearchesLeft ?? account.planSearchesLeft ?? 0)")
                        LabeledContent("Utilisées ce mois-ci", value: "\(account.thisMonthUsage ?? 0)")
                        LabeledContent("Incluses par mois", value: "\(account.searchesPerMonth ?? 0)")
                    }
                    Button {
                        Task { await model.refreshAccount() }
                    } label: {
                        HStack(spacing: 8) {
                            Icon("ui.refresh", size: 16, color: .accentColor)
                            Text("Actualiser le quota")
                        }
                    }
                } header: {
                    Text("Quota SerpApi")
                }
            }

            Section {
                let counts = model.book.counts
                LabeledContent("Prix aller simple", value: "\(counts.oneWay)")
                LabeledContent("Prix aller-retour", value: "\(counts.roundTrip)")
                LabeledContent("Prix FlixBus", value: "\(counts.bus)")
                LabeledContent("Horaires SNCF", value: "\(model.trainSchedules.count)")
                if let last = model.book.lastScan {
                    LabeledContent("Dernier scan", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                Button("Remettre les paramètres par défaut") { model.resetParams() }
                Button("Effacer les prix en mémoire", role: .destructive) { confirmClear = true }
            } header: {
                Text("Données")
            }

            Section {
                Text("Aucun prix n'est inventé. Une étape sans prix publié en ligne affiche « prix non publié » et n'est pas comptée dans le total ; par défaut, seuls les trajets entièrement à prix réels sont listés.")
                Text("Vols : Google Flights (calendrier des prix) et Aviasales. Bus : FlixBus. Transports urbains : tarifs officiels Tisséo (1,90 €) et Île-de-France Mobilités (14 €). Bateau Ankify-Nosy Be : tarifs publiés (vedette 20 000 Ar, bac 8 000 Ar), convertis au taux de change du jour.")
                Text("Trains SNCF, OUIGO et Intercités de nuit : pas d'API publique de prix, et les billets de l'été prochain ne sont pas encore en vente. La grille officielle SNCF est affichée pour information ; les horaires viennent de l'API SNCF.")
                Text("BlaBlaCar, taxi-brousse, Cotisse, taxi privé : pas de prix publié en ligne. Ces étapes sont affichées sans prix, avec les liens et contacts utiles.")
                Text("Les vols sont recherchés « toutes compagnies » : Air France, Corsair, Ethiopian, Air Austral, French Bee, Ewa Air, Neos, Airlink, Madagascar Airlines…")
            } header: {
                Text("Sources des prix")
            }
            .font(.footnote)
        }
        .navigationTitle("Réglages")
        .onAppear {
            travelpayouts = model.travelpayoutsToken
            serpapi = model.serpApiKey
            sncf = model.sncfKey
            feedURL = model.feedURL
            feedAuto = model.feedAutoUpdate
            autoCollect = model.autoCollect
            serpBudget = model.serpDailyBudget
            saved = false
        }
        .task { await model.refreshAccount() }
        .confirmationDialog("Effacer tous les prix récupérés ?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Effacer", role: .destructive) { model.clearPrices() }
        }
    }

    private func linkLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text)
            Icon("ui.external", size: 13, color: .accentColor)
        }
    }
}
