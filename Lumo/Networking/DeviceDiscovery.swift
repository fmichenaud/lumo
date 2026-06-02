import Foundation

/// Découverte des AWTRIX par scan actif du sous-réseau /24
/// (AWTRIX Light n'annonce pas de service mDNS — on sonde /api/stats sur chaque hôte).
@MainActor
final class DeviceDiscovery: ObservableObject {
    @Published var isScanning = false
    @Published var progress: Double = 0

    func scan() async -> [Device] {
        guard let ip = NetworkUtils.localIPv4(),
              let base = NetworkUtils.subnetBase(from: ip) else { return [] }

        isScanning = true
        progress = 0
        defer { isScanning = false }

        let hosts = (1...254).map { "\(base).\($0)" }
        var found: [Device] = []
        var completed = 0

        await withTaskGroup(of: Device?.self) { group in
            for host in hosts {
                group.addTask { await Self.probe(host: host) }
            }
            for await result in group {
                completed += 1
                progress = Double(completed) / Double(hosts.count)
                if let device = result { found.append(device) }
            }
        }
        return found
    }

    /// Sonde un hôte : c'est un AWTRIX si /api/stats renvoie un uid "awtrix…" ou matrix=true.
    private static func probe(host: String) async -> Device? {
        let client = AwtrixClient(host: host)
        guard let stats = try? await client.fetchStats(timeout: 1.2) else { return nil }
        let uid = stats.uid ?? ""
        guard uid.lowercased().contains("awtrix") || stats.matrix == true else { return nil }
        let id = uid.isEmpty ? host : uid
        return Device(id: id, name: Device.defaultName(for: id), host: host)
    }
}
