import UIKit

import Perception

@Perceptible
final class FontManager {
    static let shared = FontManager()
    static let fontDidChangeNotification = Notification.Name("FontDidChange")

    private let settings = AppSettings.shared

    /// Bumped on every font-related change so `@Observable` tracking fires.
    private(set) var revision: Int = 0

    /// System Dynamic Type scale derived from the current content size category.
    private var systemScale: CGFloat = 1.0

    /// Combined scale factor (app setting × system Dynamic Type if enabled).
    var scale: CGFloat {
        _ = revision
        let base = settings.appFontScale
        return settings.followSystemFontSize ? base * systemScale : base
    }

    /// Dampened scale for layout elements (avatars, icons).
    /// Grows at half the rate of text to avoid oversized avatars at large scales.
    var layoutScale: CGFloat {
        _ = revision
        let s = settings.followSystemFontSize ? settings.appFontScale * systemScale : settings.appFontScale
        return 1 + (s - 1) * 0.5
    }

    /// Scale a base point value for layout (avatar sizes, icon sizes).
    func scaled(_ base: CGFloat) -> CGFloat {
        (base * layoutScale).rounded(.toNearestOrAwayFromZero)
    }

    // MARK: - Scaled Font Factories

    func font(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .systemFont(ofSize: size * scale, weight: weight)
    }

    func monospacedFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedSystemFont(ofSize: size * scale, weight: weight)
    }

    func monospacedDigitFont(size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        .monospacedDigitSystemFont(ofSize: size * scale, weight: weight)
    }

    // MARK: - Lifecycle

    private init() {
        updateSystemScale()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contentSizeCategoryDidChange),
            name: UIContentSizeCategory.didChangeNotification,
            object: nil
        )
    }

    /// Call after the user changes the in-app font size level or the follow-system toggle.
    func notifyChange() {
        updateSystemScale()
        revision += 1
        NotificationCenter.default.post(name: Self.fontDidChangeNotification, object: nil)
    }

    // MARK: - System Dynamic Type

    @objc private func contentSizeCategoryDidChange() {
        updateSystemScale()
        revision += 1
        NotificationCenter.default.post(name: Self.fontDidChangeNotification, object: nil)
    }

    private func updateSystemScale() {
        let category = UIApplication.shared.preferredContentSizeCategory
        systemScale = Self.scaleForCategory(category)
    }

    private static func scaleForCategory(_ category: UIContentSizeCategory) -> CGFloat {
        switch category {
        case .extraSmall:                       return 0.82
        case .small:                            return 0.88
        case .medium:                           return 0.94
        case .large:                            return 1.0   // system default
        case .extraLarge:                       return 1.06
        case .extraExtraLarge:                  return 1.12
        case .extraExtraExtraLarge:             return 1.18
        case .accessibilityMedium:              return 1.35
        case .accessibilityLarge:               return 1.53
        case .accessibilityExtraLarge:          return 1.71
        case .accessibilityExtraExtraLarge:     return 1.89
        case .accessibilityExtraExtraExtraLarge: return 2.12
        default:                                return 1.0
        }
    }
}
