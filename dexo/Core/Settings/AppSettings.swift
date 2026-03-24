import UIKit

@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    // MARK: - Appearance

    enum AppearanceMode: Int, CaseIterable {
        case system = 0
        case light = 1
        case dark = 2

        var title: String {
            switch self {
            case .system: return String(localized: "appearance.system")
            case .light: return String(localized: "appearance.light")
            case .dark: return String(localized: "appearance.dark")
            }
        }

        var userInterfaceStyle: UIUserInterfaceStyle {
            switch self {
            case .system: return .unspecified
            case .light: return .light
            case .dark: return .dark
            }
        }
    }

    var appearanceMode: AppearanceMode {
        get { AppearanceMode(rawValue: defaults.integer(forKey: "appearanceMode")) ?? .system }
        set {
            defaults.set(newValue.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }

    func applyAppearance() {
        let style = appearanceMode.userInterfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }

    // MARK: - General

    var autoOpenLastForum: Bool {
        get { defaults.bool(forKey: "autoOpenLastForum") }
        set { defaults.set(newValue, forKey: "autoOpenLastForum") }
    }

    var lastOpenedForumId: Int64? {
        get {
            guard defaults.object(forKey: "lastOpenedForumId") != nil else { return nil }
            return Int64(defaults.integer(forKey: "lastOpenedForumId"))
        }
        set {
            if let value = newValue {
                defaults.set(Int(value), forKey: "lastOpenedForumId")
            } else {
                defaults.removeObject(forKey: "lastOpenedForumId")
            }
        }
    }

    var hasShownAutoOpenPrompt: Bool {
        get { defaults.bool(forKey: "hasShownAutoOpenPrompt") }
        set { defaults.set(newValue, forKey: "hasShownAutoOpenPrompt") }
    }

    // MARK: - DNS over HTTPS

    enum DoHProvider: Int, CaseIterable {
        case cloudflare = 0
        case google = 1
        case quad9 = 2
        case alidns = 3
        case custom = 4

        var title: String {
            switch self {
            case .cloudflare: return "Cloudflare (1.1.1.1)"
            case .google: return "Google (8.8.8.8)"
            case .quad9: return "Quad9 (9.9.9.9)"
            case .alidns: return "AliDNS (223.5.5.5)"
            case .custom: return String(localized: "doh.provider.custom")
            }
        }

        var url: String {
            switch self {
            case .cloudflare: return "https://1.1.1.1/dns-query"
            case .google: return "https://8.8.8.8/resolve"
            case .quad9: return "https://9.9.9.9:5053/dns-query"
            case .alidns: return "https://dns.alidns.com/resolve"
            case .custom: return ""
            }
        }
    }

    var dohEnabled: Bool {
        get { defaults.bool(forKey: "dohEnabled") }
        set { defaults.set(newValue, forKey: "dohEnabled") }
    }

    var dohProvider: DoHProvider {
        get { DoHProvider(rawValue: defaults.integer(forKey: "dohProvider")) ?? .cloudflare }
        set { defaults.set(newValue.rawValue, forKey: "dohProvider") }
    }

    var dohCustomURL: String {
        get { defaults.string(forKey: "dohCustomURL") ?? "" }
        set { defaults.set(newValue, forKey: "dohCustomURL") }
    }

    var dohServerURL: String {
        if dohProvider == .custom {
            return dohCustomURL
        }
        return dohProvider.url
    }
}
