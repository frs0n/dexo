import Foundation
import WebKit

/// In-memory + persisted cookie store used for web-login sessions.
/// Cookies are keyed by "domain|name|path" for deduplication.
final class WebCookieStore {
    static let shared = WebCookieStore()

    private var jar: [String: HTTPCookie] = [:]
    private let lock = NSLock()
    private let filePath: URL

    /// The User-Agent captured from the WKWebView that completed login.
    var userAgent: String? {
        didSet { saveUserAgent() }
    }

    private let userAgentPath: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        filePath = dir.appendingPathComponent("dexo_web_cookies.json")
        userAgentPath = dir.appendingPathComponent("dexo_web_ua.txt")
        load()
        userAgent = loadUserAgent()
    }

    // MARK: - Read / Write

    func setCookies(_ cookies: [HTTPCookie]) {
        lock.lock()
        for c in cookies { jar[key(for: c)] = c }
        lock.unlock()
        save()
    }

    func cookies(for url: URL) -> [HTTPCookie] {
        lock.lock()
        defer { lock.unlock() }
        guard let host = url.host?.lowercased() else { return [] }
        let path = url.path.isEmpty ? "/" : url.path
        return jar.values.filter { cookie in
            let domain = cookie.domain.lowercased()
            let domainMatch = host == domain
                || (domain.hasPrefix(".") && (host == String(domain.dropFirst()) || host.hasSuffix(domain)))
            return domainMatch && path.hasPrefix(cookie.path)
        }
    }

    func cookieHeader(for url: URL) -> String {
        cookies(for: url).map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func mergeResponseHeaders(_ headers: [AnyHashable: Any], for url: URL) {
        var stringHeaders: [String: String] = [:]
        for (k, v) in headers { stringHeaders["\(k)"] = "\(v)" }
        let newCookies = HTTPCookie.cookies(withResponseHeaderFields: stringHeaders, for: url)
        if !newCookies.isEmpty { setCookies(newCookies) }
    }

    @MainActor
    func syncFromWebView(_ dataStore: WKWebsiteDataStore) async {
        let cookies = await withCheckedContinuation { cont in
            dataStore.httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
        setCookies(cookies)
    }

    func clearAll() {
        lock.lock()
        jar.removeAll()
        lock.unlock()
        userAgent = nil
        try? FileManager.default.removeItem(at: filePath)
    }

    func clearCookies(for baseURL: String) {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return }
        lock.lock()
        jar = jar.filter { _, cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain != host && !host.hasSuffix(domain)
        }
        lock.unlock()
        save()
    }

    // MARK: - Persistence

    private func key(for cookie: HTTPCookie) -> String {
        "\(cookie.domain)|\(cookie.name)|\(cookie.path)"
    }

    private func save() {
        let serializable: [[String: Any]] = jar.values.compactMap { cookie in
            guard let props = cookie.properties else { return nil }
            var dict: [String: Any] = [:]
            for (k, v) in props {
                if let date = v as? Date {
                    dict[k.rawValue] = date.timeIntervalSinceReferenceDate
                } else {
                    dict[k.rawValue] = v
                }
            }
            return dict
        }
        if let data = try? JSONSerialization.data(withJSONObject: serializable) {
            try? data.write(to: filePath, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: filePath),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return }
        let now = Date()
        let cookies: [HTTPCookie] = array.compactMap { dict in
            var props: [HTTPCookiePropertyKey: Any] = [:]
            for (k, v) in dict {
                let key = HTTPCookiePropertyKey(k)
                if (key == .expires || key == HTTPCookiePropertyKey("Max-Age")),
                   let ti = v as? TimeInterval {
                    props[key] = Date(timeIntervalSinceReferenceDate: ti)
                } else {
                    props[key] = v
                }
            }
            return HTTPCookie(properties: props)
        }.filter {
            $0.expiresDate.map { $0 > now } ?? true
        }
        for c in cookies { jar[key(for: c)] = c }
    }

    private func saveUserAgent() {
        if let ua = userAgent {
            try? ua.write(to: userAgentPath, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: userAgentPath)
        }
    }

    private func loadUserAgent() -> String? {
        try? String(contentsOf: userAgentPath, encoding: .utf8)
    }
}
