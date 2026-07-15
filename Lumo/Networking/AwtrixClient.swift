import Foundation

enum AwtrixError: LocalizedError {
    case httpStatus(Int)
    case notAwtrix

    var errorDescription: String? {
        switch self {
        case .httpStatus(let code): return "Le device a répondu avec le code HTTP \(code)."
        case .notAwtrix: return "Aucun afficheur AWTRIX trouvé à cette adresse."
        }
    }
}

/// Enveloppe asynchrone de l'API REST d'AWTRIX Light.
struct AwtrixClient: Sendable {
    let host: String
    private let session: URLSession

    init(host: String, session: URLSession = .shared) {
        self.host = host
        self.session = session
    }

    private func url(_ path: String) -> URL {
        URL(string: "http://\(host)\(path)")!
    }

    // MARK: - Primitives

    private func getData(_ path: String, timeout: TimeInterval = 5) async throws -> Data {
        var req = URLRequest(url: url(path))
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp)
        return data
    }

    private func post(_ path: String, json: Any, timeout: TimeInterval = 5) async throws {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: json)
        let (_, resp) = try await session.data(for: req)
        try Self.check(resp)
    }

    private func postEncodable<T: Encodable>(_ path: String, body: T, timeout: TimeInterval = 5) async throws {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let (_, resp) = try await session.data(for: req)
        try Self.check(resp)
    }

    /// POST avec un corps réellement vide (certains endpoints AWTRIX, ex. moodlight off, l'exigent).
    private func postEmpty(_ path: String, timeout: TimeInterval = 5) async throws {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.httpBody = Data()
        let (_, resp) = try await session.data(for: req)
        try Self.check(resp)
    }

    private static func check(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw AwtrixError.httpStatus(http.statusCode)
        }
    }

    private func encodedName(_ name: String) -> String {
        name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name
    }

    // MARK: - Lecture

    func fetchStats(timeout: TimeInterval = 5) async throws -> AwtrixStats {
        let data = try await getData("/api/stats", timeout: timeout)
        return try JSONDecoder().decode(AwtrixStats.self, from: data)
    }

    func fetchSettings() async throws -> AwtrixSettings {
        let data = try await getData("/api/settings")
        return try JSONDecoder().decode(AwtrixSettings.self, from: data)
    }

    func fetchLoop() async throws -> [String: Int] {
        let data = try await getData("/api/loop")
        return try JSONDecoder().decode([String: Int].self, from: data)
    }

    func fetchScreen() async throws -> [Int] {
        let data = try await getData("/api/screen", timeout: 3)
        return try JSONDecoder().decode([Int].self, from: data)
    }

    // MARK: - Réglages

    func updateSettings(_ values: [String: Any]) async throws {
        try await post("/api/settings", json: values)
    }

    func setBrightness(_ value: Int) async throws {
        try await updateSettings(["ABRI": false, "BRI": max(0, min(255, value))])
    }

    func setAutoTransition(_ on: Bool) async throws {
        try await updateSettings(["ATRANS": on])
    }

    func setPower(_ on: Bool) async throws {
        try await post("/api/power", json: ["power": on])
    }

    /// Redémarre l'afficheur. Nécessaire pour appliquer les toggles d'apps natives (TIM, DAT, TEMP…) :
    /// AWTRIX 0.94 ne reconstruit la rotation qu'au boot (vérifié sur device).
    func reboot() async throws {
        try await postEmpty("/api/reboot")
    }

    // MARK: - Affichage

    func notify(_ payload: PushPayload) async throws {
        try await postEncodable("/api/notify", body: payload)
    }

    func upsertCustomApp(name: String, payload: PushPayload) async throws {
        try await postEncodable("/api/custom?name=\(encodedName(name))", body: payload)
    }

    func deleteCustomApp(name: String) async throws {
        try await post("/api/custom?name=\(encodedName(name))", json: [String: String]())
    }

    /// Envoi d'une app custom avec un JSON arbitraire (graphiques, dessin, etc.).
    func upsertCustomAppRaw(name: String, json: [String: Any]) async throws {
        try await post("/api/custom?name=\(encodedName(name))", json: json)
    }

    func switchApp(name: String) async throws {
        try await post("/api/switch", json: ["name": name])
    }

    // MARK: - Indicateurs / ambiance / son

    func setIndicator(_ index: Int, rgb: [Int]) async throws {
        try await post("/api/indicator\(index)", json: ["color": rgb])
    }

    func clearIndicator(_ index: Int) async throws {
        try await postEmpty("/api/indicator\(index)")
    }

    func setMoodlight(hex: String, brightness: Int = 100) async throws {
        try await post("/api/moodlight", json: ["brightness": brightness, "color": hex])
    }

    func moodlightOff() async throws {
        try await postEmpty("/api/moodlight")
    }

    func fetchEffects() async throws -> [String] {
        let data = try await getData("/api/effects")
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    // MARK: - Icônes (upload vers /edit en multipart)

    func uploadIcon(id: String, data: Data, ext: String) async throws {
        let boundary = "lumo-\(UUID().uuidString)"
        var req = URLRequest(url: url("/edit"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let filename = "/ICONS/\(id).\(ext)"
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"data\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (_, resp) = try await session.data(for: req)
        try Self.check(resp)
    }
}
