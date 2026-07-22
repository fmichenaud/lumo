import Foundation
import Network
import Observation

/// Passerelle de notifications : mini serveur HTTP local (loopback uniquement) qui reçoit
/// des messages depuis n'importe quel outil (curl, Raccourcis, scripts…) et les relaie
/// sur l'afficheur via `/api/notify`. Gère aussi le schéma d'URL `lumo://notify`.
///
/// Endpoints :
/// - `POST /notify` avec corps JSON `{"text": "...", "title"?, "color"?, "icon"?, "hold"?, "duration"?}`
/// - `GET /notify?text=...&color=%23RRGGBB` (query string percent-encodée)
@MainActor
@Observable
final class NotificationGateway {
    private(set) var enabled: Bool
    private(set) var port: Int
    private(set) var isRunning = false
    private(set) var lastMessage: String?
    private(set) var receivedCount = 0
    private(set) var lastError: String?

    nonisolated static let defaultPort = 8787

    private weak var store: DeviceStore?
    private var listener: NWListener?
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabled = defaults.bool(forKey: "lumo.gateway.enabled")
        let saved = defaults.integer(forKey: "lumo.gateway.port")
        port = saved == 0 ? Self.defaultPort : saved
    }

    /// Relie le store (appelé au lancement) et démarre le serveur si activé.
    func attach(_ store: DeviceStore) {
        self.store = store
        if enabled { start() }
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: "lumo.gateway.enabled")
        if on { start() } else { stop() }
    }

    /// Change le port d'écoute (borné aux ports non privilégiés) et redémarre si besoin.
    func setPort(_ newPort: Int) {
        let clamped = min(max(newPort, 1024), 65535)
        guard clamped != port else { return }
        port = clamped
        defaults.set(clamped, forKey: "lumo.gateway.port")
        if enabled { start() }
    }

    /// Point d'entrée du schéma d'URL : ne traite que `lumo://notify`, ignore le reste
    /// (l'OAuth utilise d'autres hosts sur le même schéma).
    func handle(url: URL) {
        guard url.scheme?.lowercased() == "lumo",
              url.host()?.lowercased() == "notify" else { return }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery ?? ""
        guard let payload = Self.payload(fromParams: Self.parseQuery(query)) else { return }
        deliver(payload)
    }

    // MARK: - Cycle de vie du serveur

    private func start() {
        stop()
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            lastError = "Port invalide."
            return
        }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Loopback uniquement : la passerelle n'est jamais exposée sur le réseau local.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch state {
                    case .ready:
                        self.isRunning = true
                        self.lastError = nil
                    case .failed(let error):
                        self.isRunning = false
                        self.lastError = Self.describe(error)
                        self.listener?.cancel()
                        self.listener = nil
                    case .cancelled:
                        self.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { connection in
                // La capture faible vit sur la closure de livraison elle-même : imbriquer
                // deux `[weak self]` fait référencer une variable capturée depuis un
                // contexte concurrent (refusé par la vérification stricte de Swift 6).
                Self.serve(connection) { [weak self] payload in
                    Task { @MainActor in self?.deliver(payload) }
                }
            }
            listener.start(queue: .global(qos: .utility))
            self.listener = listener
        } catch {
            lastError = "Impossible de démarrer le serveur : \(error.localizedDescription)"
        }
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    /// Publie le message reçu et le pousse sur l'afficheur sélectionné (le premier sinon).
    private func deliver(_ payload: PushPayload) {
        receivedCount += 1
        lastMessage = payload.text
        guard let store, let device = store.selectedDevice ?? store.devices.first else { return }
        Task { try? await AwtrixClient(host: device.host).notify(payload) }
    }

    private nonisolated static func describe(_ error: NWError) -> String {
        if case .posix(.EADDRINUSE) = error {
            return "Le port est déjà utilisé par une autre application."
        }
        return "Erreur du serveur : \(error.localizedDescription)"
    }

    // MARK: - Serveur HTTP minimal

    private nonisolated static let headerSeparator = Data("\r\n\r\n".utf8)
    private nonisolated static let maxRequestSize = 64 * 1024

    /// Lit la requête entière puis répond et ferme la connexion.
    private nonisolated static func serve(_ connection: NWConnection,
                                          onPayload: @escaping @Sendable (PushPayload) -> Void) {
        connection.start(queue: .global(qos: .utility))
        readRequest(connection, buffer: Data()) { raw in
            guard let raw else {
                connection.cancel()
                return
            }
            let (response, payload) = handleRequest(raw)
            if let payload { onPayload(payload) }
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    /// Accumule les octets jusqu'à avoir en-têtes + corps complet (Content-Length),
    /// avec un plafond de taille pour rester robuste face aux données malformées.
    private nonisolated static func readRequest(_ connection: NWConnection, buffer: Data,
                                                completion: @escaping @Sendable (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { chunk, _, isComplete, error in
            var data = buffer
            if let chunk { data.append(chunk) }
            if error != nil || data.count > maxRequestSize {
                completion(nil)
            } else if requestIsComplete(data) {
                completion(data)
            } else if isComplete {
                completion(data.isEmpty ? nil : data)
            } else {
                readRequest(connection, buffer: data, completion: completion)
            }
        }
    }

    /// Vrai quand les en-têtes sont terminés et que le corps atteint Content-Length.
    nonisolated static func requestIsComplete(_ data: Data) -> Bool {
        guard let headerEnd = data.range(of: headerSeparator) else { return false }
        let head = String(decoding: data[data.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        let bodyLength = data.distance(from: headerEnd.upperBound, to: data.endIndex)
        return bodyLength >= contentLength(inHead: head)
    }

    /// Extrait Content-Length des en-têtes (0 si absent ou illisible).
    nonisolated static func contentLength(inHead head: String) -> Int {
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
            else { continue }
            return Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    /// Traite une requête HTTP brute → (réponse à écrire, payload à relayer ou nil).
    nonisolated static func handleRequest(_ raw: Data) -> (response: Data, payload: PushPayload?) {
        guard let headerEnd = raw.range(of: headerSeparator) else {
            return (httpResponse(400, "Bad Request"), nil)
        }
        let head = String(decoding: raw[raw.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        let body = raw.subdata(in: headerEnd.upperBound..<raw.endIndex)
        let requestLine = head.components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        guard parts.count == 3, parts[2].hasPrefix("HTTP/"), parts[1].hasPrefix("/") else {
            return (httpResponse(400, "Bad Request"), nil)
        }
        let method = parts[0].uppercased()
        let target = String(parts[1])
        let split = target.split(separator: "?", maxSplits: 1)
        let path = split.first.map(String.init) ?? ""
        let query = split.count > 1 ? String(split[1]) : ""

        guard path == "/notify" else { return (httpResponse(404, "Not Found"), nil) }

        switch method {
        case "GET":
            guard let payload = payload(fromParams: parseQuery(query)) else {
                return (httpResponse(400, "Bad Request"), nil)
            }
            return (httpResponse(200, "OK"), payload)
        case "POST":
            guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
                  let payload = payload(fromJSON: object) else {
                return (httpResponse(400, "Bad Request"), nil)
            }
            return (httpResponse(200, "OK"), payload)
        default:
            return (httpResponse(405, "Method Not Allowed"), nil)
        }
    }

    /// Réponse HTTP/1.1 complète, connexion fermée après envoi.
    nonisolated static func httpResponse(_ status: Int, _ body: String) -> Data {
        let reasons = [200: "OK", 400: "Bad Request", 404: "Not Found", 405: "Method Not Allowed"]
        let payload = Data(body.utf8)
        let head = "HTTP/1.1 \(status) \(reasons[status] ?? "Error")\r\n"
            + "Content-Type: text/plain; charset=utf-8\r\n"
            + "Content-Length: \(payload.count)\r\n"
            + "Connection: close\r\n\r\n"
        return Data(head.utf8) + payload
    }

    // MARK: - Logique pure (testable)

    /// Décode une query string percent-encodée ("a=1&color=%23FF5555" → dictionnaire).
    /// Le `+` est traité comme une espace, les paires illisibles sont ignorées.
    nonisolated static func parseQuery(_ query: String) -> [String: String] {
        var params: [String: String] = [:]
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let first = kv.first,
                  let key = decodeComponent(String(first)), !key.isEmpty,
                  let value = decodeComponent(kv.count > 1 ? String(kv[1]) : "")
            else { continue }
            params[key] = value
        }
        return params
    }

    private nonisolated static func decodeComponent(_ component: String) -> String? {
        component.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    /// Construit le payload depuis des paramètres de query string. `nil` si `text` manque.
    nonisolated static func payload(fromParams params: [String: String]) -> PushPayload? {
        guard let text = params["text"], !text.isEmpty else { return nil }
        return makePayload(text: text,
                           title: params["title"],
                           color: params["color"],
                           icon: params["icon"],
                           hold: params["hold"].map { $0 == "1" || $0.lowercased() == "true" },
                           duration: params["duration"].flatMap(Int.init))
    }

    /// Construit le payload depuis un corps JSON décodé. `nil` si invalide (pas de `text`).
    nonisolated static func payload(fromJSON json: [String: Any]) -> PushPayload? {
        guard let text = json["text"] as? String, !text.isEmpty else { return nil }
        let duration = (json["duration"] as? Int) ?? (json["duration"] as? Double).map(Int.init)
        return makePayload(text: text,
                           title: json["title"] as? String,
                           color: json["color"] as? String,
                           icon: json["icon"] as? String,
                           hold: json["hold"] as? Bool,
                           duration: duration)
    }

    private nonisolated static func makePayload(text: String, title: String?, color: String?,
                                                icon: String?, hold: Bool?, duration: Int?) -> PushPayload {
        var payload = PushPayload()
        if let title, !title.isEmpty {
            payload.text = "\(title) : \(text)"
        } else {
            payload.text = text
        }
        payload.wakeup = true
        if let color, !color.isEmpty { payload.color = color }
        if let icon, !icon.isEmpty { payload.icon = icon }
        if let hold { payload.hold = hold }
        if let duration, duration > 0 { payload.duration = duration }
        return payload
    }
}
