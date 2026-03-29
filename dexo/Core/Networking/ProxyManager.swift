import DohProxy
import Foundation
import os.log

private let logger = Logger(subsystem: "com.eilgnaw.dexo", category: "ProxyManager")

/// Manages the lifecycle of the local DoH+ECH HTTP CONNECT proxy.
/// Start it once on launch; Alamofire sessions route through it when running.
final class ProxyManager {
    static let shared = ProxyManager()

    private(set) var port: Int32 = 0

    private init() {}

    // MARK: - Lifecycle

    func start() {
        let settings = AppSettings.shared
        guard settings.dohEnabled else { return }
        guard !DohProxy.shared.isRunning else { return }
        do {
            let config = buildConfig(settings: settings)
            port = try DohProxy.shared.start(configJSON: config)
            logger.info("[Proxy] started on port \(self.port)")
        } catch {
            logger.error("[Proxy] failed to start: \(error)")
        }
    }

    func stop() {
        guard DohProxy.shared.isRunning else { return }
        DohProxy.shared.stop()
        port = 0
        logger.info("[Proxy] stopped")
    }

    /// Stop and restart with current settings (e.g. after user changes DoH provider).
    func restart() {
        stop()
        start()
    }

    /// Called when dohEnabled is toggled off — stop proxy and invalidate port.
    func disable() {
        stop()
    }

    // MARK: - URLSession proxy config

    /// Returns a ConnectionProxyDictionary for URLSessionConfiguration when the proxy is running.
    var proxyConfiguration: [AnyHashable: Any]? {
        guard DohProxy.shared.isRunning, port > 0 else { return nil }
        return [
            "HTTPEnable": 1,
            "HTTPProxy": "127.0.0.1",
            "HTTPPort": port,
            "HTTPSEnable": 1,
            "HTTPSProxy": "127.0.0.1",
            "HTTPSPort": port,
        ]
    }

    /// The CA certificate data for the proxy's MITM cert, loaded from the app bundle.
    static var caCertificateData: Data? {
        guard let url = Bundle.main.url(forResource: "DohProxyCA", withExtension: "der") else { return nil }
        return try? Data(contentsOf: url)
    }

    // MARK: - Private

    private func buildConfig(settings: AppSettings) -> String {
        let serverURL = settings.dohServerURL
        let escaped = serverURL.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {
          \"bind_addr\": \"127.0.0.1\",
          \"bind_port\": 0,
          \"enable_doh\": true,
          \"doh_server\": \"\(escaped)\",
          \"prefer_ipv6\": false,
          \"timeout_secs\": 30
        }
        """
    }
}
