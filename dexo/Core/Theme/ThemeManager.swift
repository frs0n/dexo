import UIKit

// MARK: - Theme Definition

struct ThemeDefinition: Equatable, Identifiable {
    let id: String
    let name: String
    /// Accent / tint color hex for light mode
    let lightAccentHex: String
    /// Accent / tint color hex for dark mode
    let darkAccentHex: String
    /// Page background hex for light mode (systemGroupedBackground equivalent)
    let lightBackgroundHex: String
    /// Page background hex for dark mode
    let darkBackgroundHex: String
    /// Card / cell background hex for light mode (secondarySystemGroupedBackground equivalent)
    let lightCardBackgroundHex: String
    /// Card / cell background hex for dark mode
    let darkCardBackgroundHex: String
}

extension ThemeDefinition {
    static let presets: [ThemeDefinition] = [
        ThemeDefinition(
            id: "default",
            name: String(localized: "theme.default"),
            lightAccentHex: "007AFF",
            darkAccentHex: "0A84FF",
            lightBackgroundHex: "F2F2F7",
            darkBackgroundHex: "000000",
            lightCardBackgroundHex: "FFFFFF",
            darkCardBackgroundHex: "1C1C1E"
        ),
        ThemeDefinition(
            id: "forest",
            name: String(localized: "theme.forest"),
            lightAccentHex: "34A853",
            darkAccentHex: "4ECB71",
            lightBackgroundHex: "E3EDE5",
            darkBackgroundHex: "0A1A0F",
            lightCardBackgroundHex: "F0F5F1",
            darkCardBackgroundHex: "1A2E1F"
        ),
        ThemeDefinition(
            id: "ocean",
            name: String(localized: "theme.ocean"),
            lightAccentHex: "0077B6",
            darkAccentHex: "48CAE4",
            lightBackgroundHex: "D6ECF2",
            darkBackgroundHex: "03071E",
            lightCardBackgroundHex: "EDF6F9",
            darkCardBackgroundHex: "14213D"
        ),
        ThemeDefinition(
            id: "sunset",
            name: String(localized: "theme.sunset"),
            lightAccentHex: "E85D04",
            darkAccentHex: "F48C06",
            lightBackgroundHex: "FFE8CC",
            darkBackgroundHex: "1A0A00",
            lightCardBackgroundHex: "FFF3E6",
            darkCardBackgroundHex: "2D1800"
        ),
        ThemeDefinition(
            id: "violet",
            name: String(localized: "theme.violet"),
            lightAccentHex: "7C3AED",
            darkAccentHex: "A78BFA",
            lightBackgroundHex: "E6E0FF",
            darkBackgroundHex: "0D0726",
            lightCardBackgroundHex: "F3F0FF",
            darkCardBackgroundHex: "1E1340"
        ),
        ThemeDefinition(
            id: "rose",
            name: String(localized: "theme.rose"),
            lightAccentHex: "E11D48",
            darkAccentHex: "FB7185",
            lightBackgroundHex: "FFE0E3",
            darkBackgroundHex: "1A0008",
            lightCardBackgroundHex: "FFF1F2",
            darkCardBackgroundHex: "2D0013"
        ),
    ]
}

// MARK: - Custom Theme Scheme

struct CustomThemeScheme: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    var lightAccentHex: String
    var darkAccentHex: String
    var lightBackgroundHex: String
    var darkBackgroundHex: String
    var lightCardBackgroundHex: String
    var darkCardBackgroundHex: String

    init(
        id: String = UUID().uuidString,
        name: String = "",
        lightAccentHex: String = "007AFF",
        darkAccentHex: String = "0A84FF",
        lightBackgroundHex: String = "F2F2F7",
        darkBackgroundHex: String = "000000",
        lightCardBackgroundHex: String = "FFFFFF",
        darkCardBackgroundHex: String = "1C1C1E"
    ) {
        self.id = id
        self.name = name
        self.lightAccentHex = lightAccentHex
        self.darkAccentHex = darkAccentHex
        self.lightBackgroundHex = lightBackgroundHex
        self.darkBackgroundHex = darkBackgroundHex
        self.lightCardBackgroundHex = lightCardBackgroundHex
        self.darkCardBackgroundHex = darkCardBackgroundHex
    }

    func toThemeDefinition() -> ThemeDefinition {
        ThemeDefinition(
            id: "custom_\(id)",
            name: name,
            lightAccentHex: lightAccentHex,
            darkAccentHex: darkAccentHex,
            lightBackgroundHex: lightBackgroundHex,
            darkBackgroundHex: darkBackgroundHex,
            lightCardBackgroundHex: lightCardBackgroundHex,
            darkCardBackgroundHex: darkCardBackgroundHex
        )
    }
}

// MARK: - Theme Manager

@Observable
final class ThemeManager {
    static let shared = ThemeManager()
    static let themeDidChangeNotification = Notification.Name("ThemeDidChange")

    private let settings = AppSettings.shared

    /// Stored property — bumped on every theme change so `withObservationTracking` fires.
    private(set) var revision: Int = 0

    var currentTheme: ThemeDefinition {
        _ = revision
        let selectedId = settings.selectedThemeId
        if selectedId.hasPrefix("custom_") {
            let schemeId = String(selectedId.dropFirst("custom_".count))
            if let scheme = settings.customThemeScheme(id: schemeId) {
                return scheme.toThemeDefinition()
            }
        }
        return ThemeDefinition.presets.first { $0.id == selectedId }
            ?? ThemeDefinition.presets[0]
    }

    // MARK: - Dynamic Colors

    /// Accent / tint color that adapts to light/dark mode
    var accentColor: UIColor {
        dynamicColor(light: currentTheme.lightAccentHex, dark: currentTheme.darkAccentHex)
    }

    /// Page background (replaces systemGroupedBackground)
    var backgroundColor: UIColor {
        dynamicColor(light: currentTheme.lightBackgroundHex, dark: currentTheme.darkBackgroundHex)
    }

    /// Card / cell background (replaces secondarySystemGroupedBackground)
    var cardBackgroundColor: UIColor {
        dynamicColor(light: currentTheme.lightCardBackgroundHex, dark: currentTheme.darkCardBackgroundHex)
    }

    /// Code block / quote background — accent at very low opacity over card background
    var codeBackgroundColor: UIColor {
        UIColor { [self] traitCollection in
            let accent = accentColor.resolvedColor(with: traitCollection)
            let card = cardBackgroundColor.resolvedColor(with: traitCollection)
            return accent.blended(into: card, ratio: 0.08)
        }
    }

    /// Blockquote / quote left bar — accent at medium opacity
    var quoteBarColor: UIColor {
        accentColor.withAlphaComponent(0.4)
    }

    // MARK: - Apply

    func applyToAllWindows() {
        let tint = accentColor
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.tintColor = tint
            }
        }
    }

    func apply(to window: UIWindow) {
        window.tintColor = accentColor
    }

    func selectTheme(id: String) {
        settings.selectedThemeId = id
        revision += 1
        applyToAllWindows()
        NotificationCenter.default.post(name: Self.themeDidChangeNotification, object: nil)
    }

    /// Call after modifying custom color properties on AppSettings.
    func notifyChange() {
        revision += 1
        applyToAllWindows()
        NotificationCenter.default.post(name: Self.themeDidChangeNotification, object: nil)
    }

    // MARK: - Helpers

    private func dynamicColor(light lightHex: String, dark darkHex: String) -> UIColor {
        UIColor { traitCollection in
            switch traitCollection.userInterfaceStyle {
            case .dark:
                return UIColor(hex: darkHex) ?? .systemBackground
            default:
                return UIColor(hex: lightHex) ?? .systemBackground
            }
        }
    }
}

// MARK: - UIColor + Hex

extension UIColor {
    /// Accepts 6-char (RRGGBB) or 8-char (RRGGBBAA) hex strings.
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let int = UInt64(hex, radix: 16) else { return nil }
        switch hex.count {
        case 6:
            let r = CGFloat((int >> 16) & 0xFF) / 255
            let g = CGFloat((int >> 8) & 0xFF) / 255
            let b = CGFloat(int & 0xFF) / 255
            self.init(red: r, green: g, blue: b, alpha: 1)
        case 8:
            let r = CGFloat((int >> 24) & 0xFF) / 255
            let g = CGFloat((int >> 16) & 0xFF) / 255
            let b = CGFloat((int >> 8) & 0xFF) / 255
            let a = CGFloat(int & 0xFF) / 255
            self.init(red: r, green: g, blue: b, alpha: a)
        default:
            return nil
        }
    }

    /// Returns RRGGBB when fully opaque, RRGGBBAA when translucent.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        if a >= 0.999 {
            return String(format: "%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
        }
        return String(format: "%02X%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
    }

    /// Blend `self` into `base` at the given ratio (0 = all base, 1 = all self).
    func blended(into base: UIColor, ratio: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        base.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 * ratio + r2 * (1 - ratio),
            green: g1 * ratio + g2 * (1 - ratio),
            blue: b1 * ratio + b2 * (1 - ratio),
            alpha: a1 * ratio + a2 * (1 - ratio)
        )
    }
}
