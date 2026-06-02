import Foundation
import AuthenticationServices
import AppKit
import CryptoKit

/// Flux OAuth 2.0 (Authorization Code) générique via la fenêtre d'authentification système.
/// Le schéma de redirection est `lumo://oauth` (déclaré dans Info.plist).
@MainActor
final class OAuthService: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = OAuthService()
    private static let redirectURI = "lumo://oauth"

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }

    /// Lance le flux (avec PKCE, donc sans client secret) et renvoie un access_token.
    func authorize(_ auth: AuthConfig) async throws -> String {
        let verifier = Self.randomVerifier()
        let challenge = Self.challenge(for: verifier)
        let code = try await requestCode(auth, challenge: challenge)
        return try await exchange(auth, code: code, verifier: verifier)
    }

    private func requestCode(_ auth: AuthConfig, challenge: String) async throws -> String {
        guard var comps = URLComponents(string: auth.authURL) else { throw URLError(.badURL) }
        var items = comps.queryItems ?? []
        items.append(contentsOf: [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: auth.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: auth.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: "lumo")
        ])
        comps.queryItems = items
        guard let url = comps.url else { throw URLError(.badURL) }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "lumo") { callbackURL, error in
                if let error {
                    continuation.resume(throwing: error); return
                }
                guard let callbackURL,
                      let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                        .queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: URLError(.badServerResponse)); return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }
    }

    private func exchange(_ auth: AuthConfig, code: String, verifier: String) async throws -> String {
        guard let url = URL(string: auth.tokenURL) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        var items = [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "client_id", value: auth.clientID),
            URLQueryItem(name: "code_verifier", value: verifier)
        ]
        // Secret optionnel : seulement si le fournisseur l'exige (sinon PKCE suffit).
        if !auth.clientSecret.isEmpty {
            items.append(URLQueryItem(name: "client_secret", value: auth.clientSecret))
        }
        var body = URLComponents()
        body.queryItems = items
        req.httpBody = body.query?.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: req)
        struct TokenResponse: Decodable { let access_token: String }
        return try JSONDecoder().decode(TokenResponse.self, from: data).access_token
    }

    // MARK: - PKCE

    private static func randomVerifier() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return Data(bytes).base64URLEncoded()
    }

    private static func challenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncoded()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
