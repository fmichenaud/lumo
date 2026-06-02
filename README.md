# Lumo

Une application macOS native, élégante, pour piloter vos afficheurs **AWTRIX** (Ulanzi TC001 & co) — pensée pour être simple, belle et sans terminal.

L'interface officielle est austère et demande des manipulations techniques ; Lumo offre une expérience moderne (design Liquid Glass), un aperçu live de la matrice, et surtout un système de **connecteurs** pour afficher *n'importe quelle* donnée sur votre écran.

> ⚠️ Projet communautaire, non affilié à Ulanzi ni au projet AWTRIX.

## ⬇️ Télécharger

Récupérez le `.dmg` dans la page [Releases](../../releases). L'app n'est pas notarisée (pas de compte Apple Developer payant) : au **premier lancement**, faites **clic droit → Ouvrir** (une seule fois). Ou compilez depuis les sources (voir plus bas).

## ✨ Fonctionnalités

- **Découverte automatique** des afficheurs sur le réseau (scan, sans mDNS) + ajout manuel par IP, multi-device.
- **Aperçu live** de la matrice 32×8, fluide et fidèle.
- **Composer** : texte, couleur, icône → app permanente dans la rotation.
- **Galerie d'icônes intégrée** : recherche LaMetric, import en 1 clic, conversion/upload automatique (animations préservées).
- **Scènes** : compositions sauvegardées et renvoyables en 1 clic (persistantes après reboot).
- **Météo** (Open-Meteo, sans clé) avec mise à jour automatique.
- **Données live** : CPU/RAM du Mac, cours crypto — apps auto-rafraîchies.
- **Intégrations / connecteurs** : branchez n'importe quelle API (la vôtre ou externe), extraction par chemin JSON, gabarit d'affichage, auth (Clé API / Bearer / **OAuth 2.0 + PKCE**), catalogue de modèles prêts à l'emploi.
- **Dessin** : éditeur pixel art 32×8.
- **Alertes** : notifications, indicateurs LED, mood light.
- **Mode menu-bar** : rafraîchissement des données en arrière-plan, fenêtre fermée.

## 🛠️ Prérequis

- **macOS 26 (Tahoe)** ou plus récent (utilise les APIs Liquid Glass natives).
- **Xcode 26+**.
- [**XcodeGen**](https://github.com/yonatanmd/XcodeGen) : `brew install xcodegen`.
- Un afficheur sous **AWTRIX Light / AWTRIX3** sur le même réseau.

### Mettre l'afficheur sous AWTRIX

Le Ulanzi TC001 est livré avec le **firmware Ulanzi d'origine**, *pas* AWTRIX — Lumo ne fonctionnera pas tant qu'il n'est pas flashé. Branche-le en USB-C et utilise le **flasher web officiel AWTRIX3** (Chrome/Edge) : <https://blueforcer.github.io/awtrix3/#/flasher>. L'opération est réversible. Une fois sur le Wi-Fi, Lumo le découvre automatiquement.

## 🚀 Build

```bash
git clone <repo>
cd Lumo
xcodegen generate          # génère Lumo.xcodeproj depuis project.yml
open Lumo.xcodeproj        # puis Cmd+R dans Xcode
# ou en ligne de commande :
xcodebuild -project Lumo.xcodeproj -scheme Lumo -configuration Debug build
```

### Tests

Tests unitaires (Swift Testing) sur la logique pure — extraction JSON des connecteurs, couleurs, en-têtes/auth, mapping météo, parsing réseau :

```bash
xcodebuild -project Lumo.xcodeproj -scheme Lumo -destination 'platform=macOS' test
```

## 🧱 Architecture

SwiftUI, organisé par responsabilité :

```
Lumo/
  App/          point d'entrée, scènes (fenêtre + menu-bar)
  Models/       Device, AwtrixStats/Settings, PushPayload, Scene, Connector…
  Networking/   AwtrixClient (API REST AWTRIX), DeviceDiscovery, NetworkUtils
  Services/     DeviceStore, WeatherStation, LiveAppsStation, ConnectorsStation,
                OAuthService, IconConverter, ScreenStreamer…
  Views/        Sidebar, DeviceDetail, LivePreview, Compose, Scenes, Weather,
                Data, Integrations, Alerts, Draw, Apps…
  Design/       Theme (Liquid Glass, couleurs), VisualEffectView
```

Le projet Xcode est **généré** par XcodeGen : on versionne `project.yml`, pas le `.xcodeproj`.

## 🔌 Connecteurs

Un connecteur = URL + (auth) + un **chemin JSON** (`data.price`, `items[0].value`) + un **gabarit** (`{value}€`). Exemple Bitcoin :

- URL : `https://api.coingecko.com/api/v3/simple/price?ids=bitcoin&vs_currencies=eur`
- Chemin : `bitcoin.eur` · Gabarit : `BTC {value}€`

### OAuth

Lumo gère OAuth 2.0 (Authorization Code + PKCE), redirection `lumo://oauth`. Pour les services préconfigurés (ex. Spotify), il faut un **Client ID** (non secret avec PKCE). Sans configuration, l'app affiche un guide pour le saisir à la main.

Pour embarquer un Client ID par défaut (build « officiel »), renseigne-le dans `Config/Secrets.xcconfig` :

```
SPOTIFY_CLIENT_ID = ton_client_id
```

Il est injecté dans l'app via `Info.plist` — aucun secret n'est commité dans le dépôt.

## 🤝 Contribuer

Issues et PR bienvenues : support d'autres afficheurs (LaMetric, Pixoo/Divoom, WLED), nouveaux modèles de connecteurs, traductions…

## 📄 Licence

MIT — voir [LICENSE](LICENSE).
