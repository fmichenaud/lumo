# Contribuer à Lumo

Merci de l'intérêt ! Les contributions sont bienvenues : corrections, nouveaux modèles de connecteurs, support d'autres afficheurs, traductions, idées.

## Prérequis & build

- macOS 26 (Tahoe), Xcode 26+, `brew install xcodegen`.
- Le projet Xcode est **généré** : ne committez jamais `Lumo.xcodeproj` (gitignoré).

```bash
xcodegen generate
open Lumo.xcodeproj
# tests (nécessite un hôte macOS 26) :
xcodebuild -project Lumo.xcodeproj -scheme Lumo -destination 'platform=macOS' test
```

## Workflow des Pull Requests

- La branche `main` est **protégée** : pas de push direct, tout passe par une PR.
- Gardez les PR **petites et ciblées**, avec un titre clair.
- Le CI (build) doit passer. Lancez les tests en local avant de proposer.
- Pas de secret dans le code : voir `Config/Secrets.xcconfig` (non versionné en valeur réelle).

## Conventions

- **SwiftUI**, organisation par responsabilité (`Models` / `Networking` / `Services` / `Views` / `Design`).
- Commentaires utiles (le *pourquoi*, les pièges firmware), pas de bruit.
- Les types qui touchent à l'UI sont `@MainActor` ; la logique pure reste testable et sans dépendance réseau/UI.
- Code en anglais pour les identifiants, commentaires en français (cohérence avec l'existant).

## Pistes de contribution

### Ajouter un modèle de connecteur

Dans `Lumo/Models/Connector.swift`, ajoutez une entrée à `ConnectorTemplate.all` (URL publique, chemin JSON, gabarit, catégorie). Vérifiez l'endpoint et le chemin avant de proposer.

### Supporter un autre afficheur (LaMetric, Divoom/Pixoo, WLED…)

`AwtrixClient` cible l'API AWTRIX. Pour un autre firmware, l'objectif est d'extraire un protocole `DisplayDevice` et de fournir un adaptateur **testé avec le matériel réel** — n'hésitez pas à ouvrir une issue pour en discuter avant.

## Signaler un bug / proposer une idée

Ouvrez une **issue** avec le contexte (modèle d'afficheur, version firmware, étapes pour reproduire).
