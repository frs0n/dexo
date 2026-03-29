import Network
import UIKit
import WebKit

/// Presents a WKWebView so users can log in to a Discourse forum via their browser.
/// Supports Cloudflare-protected forums (proxy routes traffic through DoH+ECH).
/// Fires onSuccess once the Discourse session cookie `_t` is detected.
final class WebLoginViewController: UIViewController {
    private let targetURL: URL
    private let onSuccess: ([HTTPCookie], String?) -> Void

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        // Set proxy BEFORE creating WKWebView — iOS requires this to take effect
        if #available(iOS 17, *) {
            let port = ProxyManager.shared.port
            if port > 0, let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) {
                let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: nwPort)
                config.websiteDataStore.proxyConfigurations = [ProxyConfiguration(httpCONNECTProxy: endpoint)]
            }
        }
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = coordinator
        wv.uiDelegate = coordinator
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
        wv.translatesAutoresizingMaskIntoConstraints = false
        return wv
    }()

    private lazy var coordinator = Coordinator(targetURL: targetURL, onCookiesReady: { [weak self] cookies in
        self?.handleCookiesReady(cookies)
    })

    private lazy var progressView: UIProgressView = {
        let pv = UIProgressView(progressViewStyle: .bar)
        pv.translatesAutoresizingMaskIntoConstraints = false
        return pv
    }()

    private var progressObservation: NSKeyValueObservation?

    init(targetURL: URL, onSuccess: @escaping ([HTTPCookie], String?) -> Void) {
        self.targetURL = targetURL
        self.onSuccess = onSuccess
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "weblogin.title")
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: String(localized: "weblogin.done"), style: .done, target: self, action: #selector(doneTapped)
        )

        view.addSubview(webView)
        view.addSubview(progressView)
        NSLayoutConstraint.activate([
            progressView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            progressView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progressView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: progressView.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        progressObservation = webView.observe(\.estimatedProgress, options: .new) { [weak self] wv, _ in
            self?.progressView.progress = Float(wv.estimatedProgress)
            self?.progressView.isHidden = wv.estimatedProgress >= 1.0
        }

        coordinator.attach(to: webView.configuration.websiteDataStore)
        webView.load(URLRequest(url: targetURL))
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    /// Manual fallback: user taps Done after logging in through the webview.
    @objc private func doneTapped() {
        coordinator.collectAndFireIfPossible(from: webView, force: true)
    }

    private func handleCookiesReady(_ cookies: [HTTPCookie]) {
        Task { @MainActor in
            await WebCookieStore.shared.syncFromWebView(webView.configuration.websiteDataStore)
            if let ua = try? await webView.evaluateJavaScript("navigator.userAgent") as? String {
                WebCookieStore.shared.userAgent = ua
            }
            let ua = WebCookieStore.shared.userAgent
            dismiss(animated: true) {
                self.onSuccess(cookies, ua)
            }
        }
    }

    // MARK: - Coordinator / WKNavigationDelegate

    private final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
        private let targetHost: String
        private let onCookiesReady: ([HTTPCookie]) -> Void
        private(set) var didCallback = false

        // Captured at init time (on MainActor) to avoid crossing actor boundary in challenge callback
        private let caCert: SecCertificate?
        private let proxyRunning: Bool

        init(targetURL: URL, onCookiesReady: @escaping ([HTTPCookie]) -> Void) {
            self.targetHost = targetURL.host ?? ""
            self.onCookiesReady = onCookiesReady
            if let data = ProxyManager.caCertificateData {
                caCert = SecCertificateCreateWithData(nil, data as CFData)
            } else {
                caCert = nil
            }
            proxyRunning = ProxyManager.shared.port > 0
        }

        func attach(to dataStore: WKWebsiteDataStore) {
            dataStore.httpCookieStore.add(self)
        }

        // Trust the proxy's MITM CA so WKWebView can load HTTPS through the proxy
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust
            else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            if let caCert = caCert, proxyRunning {
                SecTrustSetAnchorCertificates(trust, [caCert] as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, false)
                var err: CFError?
                if SecTrustEvaluateWithError(trust, &err) {
                    completionHandler(.useCredential, URLCredential(trust: trust))
                    return
                }
            }
            completionHandler(.performDefaultHandling, nil)
        }

        /// Collect cookies and fire if success conditions are met.
        /// `force` = true when user taps Done (accept whatever cookies exist).
        func collectAndFireIfPossible(from webView: WKWebView, force: Bool = false) {
            guard !didCallback else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.didCallback else { return }
                let relevant = cookies.filter { $0.domain.contains(self.targetHost) }
                // Success condition: Discourse session token (_t) is present, OR forced by user
                let hasSession = relevant.contains { $0.name == "_t" }
                guard hasSession || force else { return }
                self.didCallback = true
                DispatchQueue.main.async { self.onCookiesReady(relevant) }
            }
        }

        // WKHTTPCookieStoreObserver — called on every cookie change
        nonisolated func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                cookieStore.getAllCookies { cookies in
                    guard !self.didCallback else { return }
                    let relevant = cookies.filter { $0.domain.contains(self.targetHost) }
                    let hasSession = relevant.contains { $0.name == "_t" }
                    guard hasSession else { return }
                    self.didCallback = true
                    DispatchQueue.main.async { self.onCookiesReady(relevant) }
                }
            }
        }

        // WKNavigationDelegate — also check on page finish as a belt-and-suspenders
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            collectAndFireIfPossible(from: webView)
        }
    }
}
