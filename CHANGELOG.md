# Changelog

Toutes les évolutions notables de Lumo. Le format suit [Keep a Changelog](https://keepachangelog.com/fr/1.1.0/),
et le projet respecte le [versionnage sémantique](https://semver.org/lang/fr/).

## [0.4.0] — 2026-07-22

Une version de fond : Lumo sollicite beaucoup moins l'afficheur et le réseau, et
gagne quelques réglages réclamés sur la rotation et les quotas.

### Ajouté

- **Réglages de transition dans la rotation** : effet de transition entre deux apps
  et durée de l'animation, directement dans la barre de réglages de la section Écran.
  La barre passe sur deux lignes quand la fenêtre est étroite, sans couper les libellés.
- **Temps avant remise à zéro des quotas Claude** dans la menu-bar (« session dans 2h19 ·
  semaine dans 1j 4h »), et jetons `{reset}` / `{weekReset}` utilisables dans le gabarit
  d'affichage d'un connecteur.
- **Couleur pilotée par le niveau** pour les connecteurs qui le permettent (quota Claude) :
  vert, puis orange, puis rouge à l'approche de la limite. Réglable dans l'éditeur, la
  couleur fixe reste disponible.

### Performance

- **Aperçu live** : la cadence suit désormais l'attention portée à la fenêtre — 40 ms
  quand l'aperçu est déployé, 200 ms pour la mini-matrice, 1 s en arrière-plan, et plus
  aucune requête quand aucune fenêtre n'est visible. L'aperçu tournait jusqu'ici à pleine
  vitesse en permanence, dans les quatre sections et même Lumo en arrière-plan.
- **Sondage unifié de l'afficheur** : une seule boucle `/api/loop` + `/api/stats` alimente
  tout le détail, là où la barre « à l'écran » et la section Écran interrogeaient chacune
  l'appareil de leur côté — deux fois moins de requêtes, et un état cohérent entre les vues.
- **Rendu de la matrice** : les LEDs éteintes sont dessinées en une seule passe et les
  couleurs allumées mémorisées, au lieu de 256 tracés et 256 couleurs par image.
- **Connecteurs** : rafraîchis quatre par quatre — un service lent (Stripe pagine, une API
  peut mettre 8 s à répondre) ne retarde plus les autres. La boucle se réveille à la
  prochaine échéance au lieu de tourner toutes les 5 s.
- **Scan réseau** : les 254 sondes passent par une session dédiée et ne monopolisent plus
  le pool de connexions partagé avec l'aperçu live et les connecteurs.
- **Réactivité de l'interface** : migration des services vers `@Observable` — une donnée qui
  change n'invalide plus que les vues qui la lisent réellement.

### Corrigé

- L'icône météo était re-téléchargée chez LaMetric puis ré-téléversée sur l'afficheur à
  chaque rafraîchissement (toutes les 15 minutes) alors qu'elle y était déjà.
- Les icônes déjà envoyées étaient mémorisées sans tenir compte de l'afficheur : après un
  changement d'appareil, celles qui manquaient au nouveau n'étaient pas téléversées.
- L'aperçu live signalait un changement d'état à chaque relevé, même écran figé, ce qui
  redessinait toute la barre « à l'écran » une douzaine de fois par seconde.
- La barre de progression du scan réseau était rafraîchie 254 fois en une seconde.

### Modifié

- Passage à **Swift 6** avec vérification stricte de la concurrence.
- `MARKETING_VERSION` suit de nouveau la version publiée (elle était restée à `0.1.0`).

## [0.3.0] — 2026-07-16

### Ajouté

- **Release signée et notarisée** : le `.dmg` publié est signé Developer ID et notarisé par
  Apple. Fin de l'avertissement Gatekeeper au premier lancement — plus besoin du
  clic droit → Ouvrir.

## [0.2.0] — 2026-07-16

### Ajouté

- **Navigation par intention** : l'app s'organise en quatre sections — Écran, Studio,
  Moments, Appareil.
- **Écran** : la rotation éditée comme une playlist (glisser pour ordonner, app courante
  marquée « À l'écran », sources éteintes en attente), aperçu live compact et déployable.
- **Studio** : compositions texte et pixel art 32×8, scènes sauvegardées renvoyables en un clic.
- **Moments** : notification ponctuelle, règles d'alerte par seuil ou à heure fixe, minuteur
  Pomodoro affiché sur la matrice, LED témoins, passerelle de notifications
  (curl, Raccourcis, `lumo://notify`).
- **Appareil** : mode nuit programmé, luminosité manuelle ou automatique, lampe d'ambiance,
  fiche capteurs.
- **Connecteurs** : n'importe quelle API branchée par chemin JSON et gabarit d'affichage,
  authentification par clé API, Bearer ou OAuth 2.0 + PKCE, et un catalogue de modèles prêts
  à l'emploi (GitHub, Plausible, AQI, Tempo EDF, YouTube, Spotify, Stripe, quota Claude Code…).
- **Calendrier Apple**, cours crypto, CPU/RAM du Mac et apps natives du firmware comme sources.
- **Mode menu-bar** : météo, quotas, minuteur et extinction sans ouvrir la fenêtre.
- **Raccourcis / App Intents** en français.
- **Interface FR/EN** via String Catalog.
- **Galerie d'icônes LaMetric** intégrée : recherche, import en un clic, conversion et
  téléversement automatiques (animations préservées).

## [0.1.0] — 2026-06-02

### Ajouté

- Première version de Lumo : application macOS native pour piloter les afficheurs AWTRIX
  (Ulanzi TC001 & co), avec découverte automatique sur le réseau, aperçu de la matrice 32×8,
  météo Open-Meteo et envoi de notifications.
- Intégration continue (build de vérification) et pipeline de release du `.dmg`.

[0.4.0]: https://github.com/fmichenaud/lumo/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/fmichenaud/lumo/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/fmichenaud/lumo/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/fmichenaud/lumo/releases/tag/v0.1.0
