import AuthenticationServices
import Foundation

@Observable
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

    func login(forum: ForumInstance, presentationAnchor: ASPresentationAnchor) async throws {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

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

        print("[AuthManager] Auth URL: \(authURL.absoluteString)")

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
        print("[AuthManager] Callback URL: \(callbackURL.absoluteString)")
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let payload = components.queryItems?.first(where: { $0.name == "payload" })?.value
        else {
            print("[AuthManager] ERROR: Missing payload in callback URL")
            KeychainHelper.deleteRSAKeyPair(for: baseURL)
            throw AuthError.missingPayload
        }

        print("[AuthManager] Payload length: \(payload.count)")

        // 6. Decrypt payload
        let authPayload: RSACrypto.AuthPayload
        do {
            authPayload = try RSACrypto.decryptPayload(payload, with: privateKey)
        } catch {
            print("[AuthManager] ERROR: Decryption failed: \(error)")
            KeychainHelper.deleteRSAKeyPair(for: baseURL)
            throw AuthError.decryptionFailed(error)
        }

        print("[AuthManager] Decrypted nonce: \(authPayload.nonce)")
        print("[AuthManager] Expected nonce: \(nonce)")

        // 7. Verify nonce
        guard authPayload.nonce == nonce else {
            print("[AuthManager] ERROR: Nonce mismatch")
            KeychainHelper.deleteRSAKeyPair(for: baseURL)
            throw AuthError.nonceMismatch
        }

        print("[AuthManager] Auth success! Key length: \(authPayload.key.count)")

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
        let api = DiscourseAPI(baseURL: baseURL)
        do {
            let currentUser = try await api.fetchNotifications()
            usernameCache[baseURL] = currentUser.username

            // Persist username to DB
            if var forumToUpdate = forum as ForumInstance? {
                forumToUpdate.username = currentUser.username
                _ = try? DatabaseManager.shared.saveForum(&forumToUpdate)
            }
        } catch {
            // Login succeeded but we couldn't fetch username — not fatal
            // The API key is already saved, user is authenticated
        }
    }

    func logout(forum: ForumInstance) {
        let baseURL = forum.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Revoke the API key on the server (best-effort, fire-and-forget)
        if let apiKey = KeychainHelper.getUserApiKey(for: baseURL) {
            let api = DiscourseAPI(baseURL: baseURL)
            Task { await api.revokeApiKey(apiKey: apiKey) }
        }

        KeychainHelper.deleteUserApiKey(for: baseURL)
        KeychainHelper.deleteRSAKeyPair(for: baseURL)
        usernameCache.removeValue(forKey: baseURL)

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
