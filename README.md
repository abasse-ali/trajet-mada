# TrajetMada : Toulouse → Antsiranana / Nosy Be

App iPhone (et Android / web) qui calcule **tous les trajets possibles** de Toulouse vers
Antsiranana (Diego-Suarez) ou Nosy Be, tous modes confondus (train, bus, covoiturage, avion,
bateau, taxi-brousse, taxi privé), et les classe du moins cher au plus cher.

- 48 liaisons, 727 combinaisons vers Diego et 355 vers Nosy Be.
- Tri par prix bas, prix courant, durée ou simplicité (nombre de billets).
- Signale les correspondances non protégées (billets séparés), les vols hebdomadaires
  et les liaisons à vérifier.
- Pour chaque étape : liens de réservation (site du transporteur, Google Flights, Skyscanner,
  Kayak, SNCF Connect, BlaBlaCar…) ouverts à la bonne date.
- Prix des vols en direct (optionnel) avec un jeton gratuit Travelpayouts / Aviasales.

## Tester sur iPhone en 2 minutes (sans IPA)

1. Installez **Expo Go** depuis l'App Store sur l'iPhone.
2. Sur le PC, dans ce dossier :
   ```
   npm install
   npx expo start
   ```
   (Si l'iPhone n'est pas sur le même Wi-Fi : `npx expo start --tunnel`.)
3. Scannez le QR code avec l'appareil photo de l'iPhone.

Aperçu dans le navigateur du PC : `npx expo start --web`.

## Obtenir un vrai fichier .ipa

Apple n'autorise la compilation iOS que sur un Mac. Depuis Windows, deux solutions :

### Option A : gratuite (GitHub Actions + Sideloadly)
1. Créez un dépôt sur GitHub et poussez ce dossier.
2. Onglet **Actions** → **Build iOS IPA** → **Run workflow** (environ 15-25 min, Xcode 26 /
   SDK iOS 26 sur un Mac `macos-26`).
3. Téléchargez l'artefact `TrajetMada-ipa` (fichier `TrajetMada.ipa`, non signé).
4. Installez [Sideloadly](https://sideloadly.io/) sur le PC (avec iTunes et iCloud version
   site Apple, pas Microsoft Store), branchez l'iPhone en USB, glissez l'IPA et connectez-vous
   avec votre identifiant Apple : Sideloadly signe et installe l'app.
5. Sur l'iPhone (iOS 26/27) : Réglages → Confidentialité et sécurité → **Mode développeur**
   → activer (l'iPhone redémarre), puis Réglages → Général → VPN et gestion de l'appareil →
   votre identifiant Apple → **Faire confiance**.

Avec un identifiant Apple gratuit, l'app expire au bout de 7 jours : il suffit de la réinstaller
avec Sideloadly.

Compatibilité : app iPhone uniquement (dont iPhone 15), iOS 26 et 27,
thème clair/sombre automatique, Dynamic Island et zones sûres gérées. Toutes les icônes sont
en SVG (aucun emoji).

### Option B : EAS Build (compte Apple Developer, 99 $/an)
```
npm install -g eas-cli
eas login
eas build --platform ios --profile preview
```
EAS compile dans le cloud, signe l'IPA et donne un lien d'installation directe sur l'iPhone.

## Prix des vols en direct

1. Créez un compte gratuit sur https://www.travelpayouts.com puis copiez votre jeton
   (Profil → API token).
2. Dans l'app : bouton Réglages (en haut à droite) → collez le jeton → Enregistrer → **Actualiser**.

Les prix viennent du cache Aviasales (recherches des 2 à 7 derniers jours) pour le mois choisi.
Les trains, bus, bateaux et taxis-brousse n'ont pas d'API publique : leurs prix restent des estimations.

## Mettre à jour les données

Toutes les liaisons sont dans [src/data/network.ts](src/data/network.ts) : durée, prix bas et
courant, fréquence, liens. Ajoutez un objet dans `LEGS` pour créer une nouvelle liaison ; le
moteur ([src/engine/routes.ts](src/engine/routes.ts)) la combinera automatiquement.

Vérifications du moteur : `npm run test:engine`. Types : `npm run typecheck`.

## Limites

- Prix estimés en novembre 2026 : ils bougent selon la date et la saison. Vérifiez toujours
  avant d'acheter.
- La durée affichée n'inclut pas l'attente d'un vol hebdomadaire (Corsair Orly–Tana, Neos
  Milan–Nosy Be, Airlink, Ewa Air…).
- Liaisons « à vérifier » : signalées par des sources récentes mais non confirmées pour la saison
  en cours (Air Austral Réunion–Diego, Emirates via Dubaï, train Paris–Milan, vol Nosy Be–Diego,
  billets uniques toutes compagnies).
