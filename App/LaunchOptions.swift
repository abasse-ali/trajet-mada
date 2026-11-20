import Foundation

/// Options passées au lancement (« -tab 1 », « -openFirst YES »…), utilisées par le CI
/// pour ouvrir chaque écran et en faire une capture. Sans option, l'app démarre normalement.
enum LaunchOptions {
    private static var defaults: UserDefaults { .standard }

    /// Onglet à ouvrir : 0 Trajets, 1 Journal, 2 Réglages.
    static var tab: Int { defaults.integer(forKey: "tab") }
    /// Lance une recherche dès l'ouverture.
    static var autoSearch: Bool { defaults.bool(forKey: "autoSearch") }
    /// Ouvre le détail du meilleur aller-retour.
    static var openFirst: Bool { defaults.bool(forKey: "openFirst") }
    /// Fait défiler jusqu'à la liste des résultats.
    static var scrollToResults: Bool { defaults.bool(forKey: "scrollResults") }
}
