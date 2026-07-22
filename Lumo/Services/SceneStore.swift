import Foundation
import Observation

/// Persistance des scènes de l'utilisateur (presets).
@MainActor
@Observable
final class SceneStore {
    var scenes: [DisplayScene] = []
    private let storageKey = "lumo.scenes.v1"

    init() { load() }

    func add(_ scene: DisplayScene) { scenes.append(scene); save() }

    func update(_ scene: DisplayScene) {
        guard let index = scenes.firstIndex(where: { $0.id == scene.id }) else { return }
        scenes[index] = scene
        save()
    }

    func remove(_ scene: DisplayScene) { scenes.removeAll { $0.id == scene.id }; save() }

    private func save() {
        if let data = try? JSONEncoder().encode(scenes) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([DisplayScene].self, from: data) else { return }
        scenes = saved
    }
}
