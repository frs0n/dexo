import Alamofire
import Foundation
import Security

/// SessionDelegate subclass that handles TLS challenges for the DoH proxy's MITM CA.
final class ProxyAwareSessionDelegate: SessionDelegate {
    nonisolated(unsafe) private static let caCert: SecCertificate? = {
        guard let data = ProxyManager.caCertificateData else { return nil }
        return SecCertificateCreateWithData(nil, data as CFData)
    }()

    // Explicit nonisolated init so we can call super.init (which is nonisolated in Alamofire)
    // without hitting the project-wide @MainActor isolation.
    nonisolated override init(fileManager: FileManager = .default) {
        super.init(fileManager: fileManager)
    }

    nonisolated override func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if !handleProxyChallenge(challenge, completionHandler: completionHandler) {
            super.urlSession(session, task: task, didReceive: challenge, completionHandler: completionHandler)
        }
    }

    // Session-level challenge — fired for proxy tunnel TLS (CONNECT)
    nonisolated func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if !handleProxyChallenge(challenge, completionHandler: completionHandler) {
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// Returns true and calls completionHandler if the challenge was handled by the proxy CA.
    @discardableResult
    private nonisolated func handleProxyChallenge(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Bool {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust,
              let caCert = Self.caCert,
              ProxyManager.shared.port > 0
        else { return false }

        let host = challenge.protectionSpace.host
        // Use basic X.509 policy (no hostname check) so the proxy's per-host leaf cert
        // is validated purely against the CA chain.
        let policy = SecPolicyCreateBasicX509()
        SecTrustSetPolicies(trust, [policy] as CFArray)
        SecTrustSetAnchorCertificates(trust, [caCert] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        var err: CFError?
        if SecTrustEvaluateWithError(trust, &err) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return true
        }

        // Not MITM'd by proxy — restore SSL policy with hostname and fall back to system store
        let sslPolicy = SecPolicyCreateSSL(true, host as CFString)
        SecTrustSetPolicies(trust, [sslPolicy] as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, false)
        if SecTrustEvaluateWithError(trust, &err) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return true
        }

        completionHandler(.cancelAuthenticationChallenge, nil)
        return true
    }
}
