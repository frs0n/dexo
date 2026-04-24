import AuthenticationServices
import Foundation
import Perception

@Perceptible
final class AuthManager: @unchecked Sendable {
    static let shared = AuthManager()

    // Per-baseURL username cache (populated from DB or after login)
    private var usernameCache: [String: String] = [:]

    private init() {}

    // MARK: - Public API

    func isAuthenticated(for baseURL: String) -> Bool {
        KeychainHelper.getUserApiKey(for: baseURL) != nil
    }

    func username(for baseURL: String) -> String? {
        usernameCache[baseURL]
    }

    /// Backfill the username cache for a baseURL when a call site discovered
    /// the current user's identity through another path (e.g., `MeViewModel`
    /// falling back to `/session/current.json` because the login-time fetch
    /// failed silently).
    func setCachedUsername(_ username: String, for baseURL: String) {
        let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        usernameCache[normalized] = username
    }

    func login(forum: ForumInstance, presentationAnchor: ASPresentationAnchor) async throws {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Clean up any existing web login data to ensure isolation
        cleanupWebAuthData(for: baseURL)

        // 1. Generate RSA key pair
        let privateKey: SecKey
        do {
            privateKey = try KeychainHelper.generateAndStoreRSAKeyPair(for: baseURL)
        } catch {
            throw AuthError.keyGenerationFailed(error)
        }

        // 2. Export public key PEM
        let pem: String
        do {
            pem = try KeychainHelper.exportPublicKeyPEM(from: privateKey)
        } catch {
            KeychainHelper.deleteRSAKeyPair(for: baseURL)
            throw AuthError.keyGenerationFailed(error)
        }

        // 3. Build auth URL (match Python urllib.parse.quote per-value encoding)
        let clientId = UUID().uuidString
        // Equivalent to Python's secrets.token_urlsafe(32)
        var nonceBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, nonceBytes.count, &nonceBytes)
        let nonce = Data(nonceBytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let normalizedPem = pem
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // Equivalent to Python's urllib.parse.quote (safe='/')
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")

        let params: [(String, String)] = [
            ("application_name", "Dexo iOS"),
            ("client_id", clientId),
            ("scopes", "read,write"),
            ("public_key", normalizedPem),
            ("nonce", nonce),
            ("auth_redirect", "discourse://auth_redirect"),
        ]
        let queryString = params
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }
            .joined(separator: "&")
        let authURLString = "\(baseURL)/user-api-key/new?\(queryString)"

        guard let authURL = URL(string: authURLString) else {
            KeychainHelper.deleteRSAKeyPair(for: baseURL)
            throw AuthError.invalidURL
        }

        debugLog("[AuthManager] Auth URL: \(authURL.absoluteString)")

        // 4. Launch browser auth session
        let callbackURL: URL
        let contextProvider = PresentationContextProvider(anchor: presentationAnchor)
        do {
            callbackURL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: "discourse"
                ) { url, error in
                    // Keep contextProvider alive until callback completes
                    _ = contextProvider
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: AuthError.unknownError)
                    }
                }
                session.presentationContextProvider = contextProvider
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // User cancelled — silently clean up
            KeychainHelper.deleteRSAKeyPair(for: baseURL)
            return
        } catch {
            KeychainHelper.deleteRSAKeyPair(for: baseURL)
            throw AuthError.browserSessionFailed(error)
        }

        // 5. Extract payload from callback URL
        debugLog("[AuthManager] Callback URL: \(callbackURL.absoluteString)")
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value
        else {
            debugLog("[AuthManager] ERROR: Missing payload in callback URL")
            KeychainHelper.deleteRSAKeyPair(for: baseURL)
            throw AuthError.missingPayload
        }

        debugLog("[AuthManager] Payload length: \(payload.count)")

        // 6. Decrypt payload
        let authPayload: RSACrypto.AuthPayload
        do {
            authPayload = try RSACrypto.decryptPayload(payload, with: privateKey)
        } catch {
            debugLog("[AuthManager] ERROR: Decryption failed: \(error)")
            KeychainHelper.deleteRSAKeyPair(for: baseURL)
            throw AuthError.decryptionFailed(error)
        }

        debugLog("[AuthManager] Decrypted nonce: \(authPayload.nonce)")
        debugLog("[AuthManager] Expected nonce: \(nonce)")

        // 7. Verify nonce
        guard authPayload.nonce == nonce else {
            debugLog("[AuthManager] ERROR: Nonce mismatch")
            KeychainHelper.deleteRSAKeyPair(for: baseURL)
            throw AuthError.nonceMismatch
        }

        debugLog("[AuthManager] Auth success! Key length: \(authPayload.key.count)")

        // 8. Store API key in Keychain
        do {
            try KeychainHelper.saveUserApiKey(authPayload.key, for: baseURL)
        } catch {
            KeychainHelper.deleteRSAKeyPair(for: baseURL)
            throw error
        }

        // Clean up RSA key pair (no longer needed)
        KeychainHelper.deleteRSAKeyPair(for: baseURL)

        // 9. Fetch current user to get username
        await fetchAndCacheUsername(baseURL: baseURL, forum: forum)
    }

    static let webAuthSentinel = "__web__"

    /// Called after WebLoginViewController successfully captures cookies.
    /// Saves the sentinel key so isAuthenticated returns true, then fetches the username.
    func loginViaWeb(forum: ForumInstance, cookies: [HTTPCookie], userAgent: String?) async {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Clean up any existing API key login data to ensure isolation
        cleanupApiKeyAuthData(for: baseURL)

        WebCookieStore.shared.setCookies(cookies)
        WebCookieStore.shared.userAgent = userAgent
        try? KeychainHelper.saveUserApiKey(AuthManager.webAuthSentinel, for: baseURL)

        await fetchAndCacheUsername(baseURL: baseURL, forum: forum)
    }

    // MARK: - Username Fetching

    /// Fetches the current user's username via `/session/current.json`, falling back to `/notifications.json`.
    /// For linux.do, skip `/session/current.json` and go straight to `/notifications.json`.
    private func fetchAndCacheUsername(baseURL: String, forum: ForumInstance) async {
        let api = DiscourseAPI(baseURL: baseURL)
        var username: String?

        if !api.isLinuxDo {
            // Primary: /session/current.json
            if let currentUser = try? await api.fetchCurrentUser() {
                username = currentUser.username
            }
        }

        // Fallback: extract from /notifications.json pagination URL
        if username == nil, let notifList = try? await api.fetchNotifications() {
            username = notifList.username
        }

        guard let username else { return }
        usernameCache[baseURL] = username
        var forumToUpdate = forum
        forumToUpdate.username = username
        _ = try? DatabaseManager.shared.saveForum(&forumToUpdate)
    }

    // MARK: - Auth Isolation Helpers

    /// Cleans up web login artifacts (cookies, user agent, CSRF) before switching to API key auth.
    private func cleanupWebAuthData(for baseURL: String) {
        if let existingKey = KeychainHelper.getUserApiKey(for: baseURL),
           existingKey == AuthManager.webAuthSentinel
        {
            // Server-side session cleanup
            if let username = usernameCache[baseURL] {
                let api = DiscourseAPI(baseURL: baseURL)
                Task { await api.deleteSession(username: username) }
            }
        }
        WebCookieStore.shared.clearCookies(for: baseURL)
        NotificationCenter.default.post(name: .discourseAuthDidChange, object: nil, userInfo: ["baseURL": baseURL])
    }

    /// Cleans up API key artifacts (revoke key, delete RSA pair) before switching to web auth.
    private func cleanupApiKeyAuthData(for baseURL: String) {
        if let existingKey = KeychainHelper.getUserApiKey(for: baseURL),
           existingKey != AuthManager.webAuthSentinel
        {
            // Revoke the API key on the server
            let api = DiscourseAPI(baseURL: baseURL)
            Task { await api.revokeApiKey(apiKey: existingKey) }
        }
        KeychainHelper.deleteUserApiKey(for: baseURL)
        KeychainHelper.deleteRSAKeyPair(for: baseURL)
    }

    func logout(forum: ForumInstance) {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let api = DiscourseAPI(baseURL: baseURL)
        if let apiKey = KeychainHelper.getUserApiKey(for: baseURL) {
            if apiKey == AuthManager.webAuthSentinel {
                // Web login — delete server session
                if let username = usernameCache[baseURL] {
                    Task { await api.deleteSession(username: username) }
                }
            } else {
                // API key login — revoke the key
                Task { await api.revokeApiKey(apiKey: apiKey) }
            }
        }

        KeychainHelper.deleteUserApiKey(for: baseURL)
        KeychainHelper.deleteRSAKeyPair(for: baseURL)
        WebCookieStore.shared.clearCookies(for: baseURL)
        usernameCache.removeValue(forKey: baseURL)
        NotificationCenter.default.post(name: .discourseAuthDidChange, object: nil, userInfo: ["baseURL": baseURL])

        // Clear username from DB
        var forumToUpdate = forum
        forumToUpdate.username = nil
        _ = try? DatabaseManager.shared.saveForum(&forumToUpdate)
    }

    func restoreAuthState(for forum: ForumInstance) {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let username = forum.username, isAuthenticated(for: baseURL) {
            usernameCache[baseURL] = username
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted when auth method changes for a forum, so interceptors can reset cached state (e.g. CSRF token).
    static let discourseAuthDidChange = Notification.Name("discourseAuthDidChange")
}

// MARK: - Errors

enum AuthError: Error, LocalizedError {
    case keyGenerationFailed(Error)
    case invalidURL
    case browserSessionFailed(Error)
    case missingPayload
    case decryptionFailed(Error)
    case nonceMismatch
    case unknownError

    var errorDescription: String? {
        switch self {
        case .keyGenerationFailed(let error):
            return "Key generation failed: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid authentication URL"
        case .browserSessionFailed(let error):
            return "Browser session failed: \(error.localizedDescription)"
        case .missingPayload:
            return "Missing payload in callback"
        case .decryptionFailed(let error):
            return "Decryption failed: \(error.localizedDescription)"
        case .nonceMismatch:
            return "Nonce mismatch — possible replay attack"
        case .unknownError:
            return "Unknown authentication error"
        }
    }
}

// MARK: - Presentation Context Provider

private final class PresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated { anchor }
    }
}
