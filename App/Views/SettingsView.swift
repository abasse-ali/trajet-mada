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
    @State private var saved = false
    @State private var confirmClear = false

    var body: some View {
        Form {
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
                Text("Parcourt toutes les dates de la période avec les prix vus par les utilisateurs d'Aviasales ces 2 à 7 derniers jours. Jeton : menu Profil, rubrique API token.")
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
                Text("Vérifie un aller-retour précis sur Google Flights au moment où vous le consultez. Offre gratuite : 250 recherches par mois.")
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
                if let last = model.book.lastScan {
                    LabeledContent("Dernier scan", value: last.formatted(date: .abbreviated, time: .shortened))
                }
                Button("Remettre les paramètres par défaut") { model.resetParams() }
                Button("Effacer les prix en mémoire", role: .destructive) { confirmClear = true }
            } header: {
                Text("Données")
            }

            Section {
                Text("Trains SNCF, OUIGO et Intercités de nuit : pas d'API publique de prix au jour près (réservée aux revendeurs sous contrat). L'app utilise la grille officielle SNCF (prix minimum et maximum, open data) et retient le premier quart de la fourchette, soit le prix d'un billet pris tôt. Les horaires viennent de l'API SNCF.")
                Text("BlaBlaCar : API réservée aux partenaires. Lien prérempli avec la ville et la date.")
                Text("Taxi-brousse, Cotisse, vedettes d'Ankify : pas de vente en ligne, réservation sur place ou par téléphone. Prix estimés d'après des relevés (1 € = environ 5 000 à 5 300 Ar).")
                Text("Estimations relevées en \(NetworkData.dataDate). Les vols sont recherchés « toutes compagnies » : Air France, Corsair, Ethiopian, Air Austral, French Bee, Ewa Air, Neos, Airlink, Madagascar Airlines…")
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
