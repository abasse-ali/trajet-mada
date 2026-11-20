# TrajetMada : Toulouse ⇄ Antsiranana / Nosy Be

App iPhone native (Swift / SwiftUI, iOS 17 à 27) qui cherche **tous les allers-retours possibles**
de Toulouse vers Antsiranana (Diego-Suarez) et Nosy Be, tous modes confondus, et les classe
du moins cher au plus cher.

- **Aller-retour** de mai à septembre, séjour de 28 à 30 jours (modifiable).
- Arrivée et retour par des villes différentes possibles (ex. arrivée Nosy Be, retour Antsiranana),
  trajet sur place compris dans le total.
- 63 trajets possibles par sens (train, OUIGO, train de nuit, FlixBus, BlaBlaCar, avion via Paris,
  Milan, La Réunion, Mayotte, Johannesburg, Tana, taxi-brousse, vedette, taxi privé) sur
  369 paires de dates, soit environ 170 000 combinaisons évaluées en moins d'une seconde.
- **Prix réels** :
  - vols : scan de toutes les dates avec Travelpayouts (Aviasales), puis vérification en temps
    réel sur Google Flights via SerpApi ; billets aller-retour utilisés quand ils sont moins chers ;
  - FlixBus : prix, horaires et places en temps réel ;
  - trains SNCF (TGV INOUI, OUIGO, Intercités de nuit) : grille officielle des prix de l'open data
    SNCF (minimum et maximum) et vrais horaires via l'API SNCF (clé gratuite) ;
  - BlaBlaCar, taxi-brousse, vedette : pas d'API publique, estimation clairement signalée.
- Chaque étape affiche la source et la fiabilité de son prix, et des **liens préremplis** (Google
  Flights, Skyscanner, Kayak, Aviasales, FlixBus, BlaBlaCar ; Kayak multi-destinations pour tout
  le voyage).
- **Journal** : chaque appel d'API (sans les clés), erreur et calcul, filtrable, à partager.
- Icônes SVG, thème clair/sombre, Liquid Glass d'iOS 26 automatique.

## Installer l'IPA sur l'iPhone (Windows, gratuit)

1. Récupérez `TrajetMada.ipa` : onglet **Actions** du dépôt GitHub, dernier build réussi,
   artefact `TrajetMada-ipa` (fichier zip contenant l'IPA).
2. Installez [Sideloadly](https://sideloadly.io/) sur le PC, avec iTunes et iCloud téléchargés
   depuis le site d'Apple (pas la version Microsoft Store).
3. Branchez l'iPhone en USB, glissez l'IPA dans Sideloadly, entrez votre identifiant Apple,
   cliquez **Start**.
4. Sur l'iPhone : Réglages, Confidentialité et sécurité, **Mode développeur**, activer
   (redémarrage). Puis Réglages, Général, VPN et gestion de l'appareil, votre identifiant,
   **Faire confiance**.

Avec un identifiant Apple gratuit, l'app doit être réinstallée tous les 7 jours (Sideloadly sait
le faire automatiquement s'il reste ouvert sur le PC). Avec un compte Apple Developer (99 $/an),
elle reste valable un an.

## Clés d'API (onglet Réglages de l'app)

| Service | Rôle | Coût |
|---|---|---|
| [Travelpayouts](https://www.travelpayouts.com/) | scan des prix des vols sur toute la période | gratuit |
| [SerpApi](https://serpapi.com/users/sign_up) | vérification Google Flights en temps réel | 250 recherches/mois gratuites |
| FlixBus | prix des bus en temps réel | sans clé |
| [API SNCF](https://numerique.sncf.com/startup/api/) | vrais horaires des trains (publiés environ 1 mois à l'avance) | gratuit |
| Open data SNCF | grille officielle des prix TGV, OUIGO, Intercités | sans clé |

## Serveur de mise à jour quotidienne (Oracle Cloud)

Le script [server/trajetmada_update.py](server/trajetmada_update.py) (Python 3.6+, sans dépendance)
relève chaque matin, sur toute la période :

- les prix des vols (Travelpayouts : allers simples et allers-retours) ;
- les prix FlixBus Toulouse ⇄ Paris pour chaque jour (environ 300 prix) ;
- la grille officielle des prix SNCF ;
- les horaires SNCF (jours publiés et horaires types par jour de semaine) ;
- une vérification Google Flights des allers-retours les moins chers (5 recherches SerpApi par jour).

Il écrit `trajetmada-data.json` et un résumé lisible `rapport.md`, puis les publie sur la branche
`data` de ce dépôt. L'app les télécharge à l'ouverture (Réglages, « Données du serveur »).

Installation sur la machine Oracle (Oracle Linux ou Ubuntu), en une commande :

```
curl -fsSL https://raw.githubusercontent.com/abasse-ali/trajet-mada/main/server/install.sh | bash
```

L'installateur demande les clés (gardées dans `~/.config/trajetmada/config.env`, lisible par vous
seul), programme la tâche quotidienne (cron, 6 h), lance un premier passage et affiche une clé
publique à ajouter une fois au dépôt (Settings, Deploy keys, « Allow write access »).

Commandes utiles sur le serveur :

| Action | Commande |
|---|---|
| Lancer une mise à jour | `python3 ~/trajetmada/app/server/trajetmada_update.py` |
| Test rapide sans publier | `python3 ~/trajetmada/app/server/trajetmada_update.py --quick --no-publish` |
| Voir le dernier résumé | `cat ~/trajetmada/data/rapport.md` |
| Journal des passages | `tail -n 50 ~/trajetmada/update.log` |
| Modifier les clés | `nano ~/.config/trajetmada/config.env` |

## Développement

- `Packages/TrajetCore` : moteur et API (Swift Package), testé par `swift test`.
  - `Network.swift` : toutes les liaisons et leurs estimations ;
  - `RouteEngine.swift` : combinaisons aller-retour, dates, billets aller-retour ;
  - `Travelpayouts.swift`, `SerpApi.swift`, `FlixBus.swift` : sources de prix ;
  - `Links.swift` : liens préremplis.
- `App/` : interface SwiftUI. `project.yml` : projet Xcode généré par XcodeGen.
- `tools/make-icons.mjs` : génère les icônes SVG du catalogue d'assets.
- `.github/workflows/ios-ipa.yml` : à chaque push, tests du moteur puis compilation de l'IPA
  non signé sur un Mac GitHub (Xcode 26).
