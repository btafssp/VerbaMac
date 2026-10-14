import Foundation
import SwiftUI

/// Dictionary-style content text size for analyses pane + lexicon article.
/// Stored as body base points (article CSS / analyses lemma). Chrome and About are unaffected.
enum ContentTextSize {
    static let storageKey = "verba.contentTextSize"

    /// Matches current article CSS `font: 15px/...`.
    static let defaultPoints: Double = 15
    static let minPoints: Double = 11
    static let maxPoints: Double = 24
    static let step: Double = 1

    static func stored() -> Double {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: storageKey) == nil {
            return defaultPoints
        }
        return clamp(defaults.double(forKey: storageKey))
    }

    static func setStored(_ points: Double) {
        let value = clamp(points)
        UserDefaults.standard.set(value, forKey: storageKey)
        NotificationCenter.default.post(name: .verbaContentTextSizeChanged, object: value)
    }

    static func increase() {
        setStored(stored() + step)
    }

    static func decrease() {
        setStored(stored() - step)
    }

    static func reset() {
        setStored(defaultPoints)
    }

    static var canIncrease: Bool { stored() < maxPoints - 0.001 }
    static var canDecrease: Bool { stored() > minPoints + 0.001 }

    static func clamp(_ points: Double) -> Double {
        min(maxPoints, max(minPoints, points.rounded()))
    }

    // MARK: - Derived sizes (analyses pane)

    /// Scale relative to the article/body default (15 pt).
    static func scale(for points: Double) -> CGFloat {
        CGFloat(clamp(points) / defaultPoints)
    }

    static func lemmaSize(_ points: Double) -> CGFloat { CGFloat(clamp(points)) }

    static func morphologySize(_ points: Double) -> CGFloat {
        max(10, CGFloat(clamp(points)) * 0.87)
    }

    static func captionSize(_ points: Double) -> CGFloat {
        max(9, CGFloat(clamp(points)) * 0.73)
    }

    static func emptyIconSize(_ points: Double) -> CGFloat {
        max(20, 28 * scale(for: points))
    }

    static func headlineSize(_ points: Double) -> CGFloat {
        max(12, CGFloat(clamp(points)) * 1.13)
    }

    static func subheadlineSize(_ points: Double) -> CGFloat {
        max(11, CGFloat(clamp(points)) * 0.93)
    }
}

extension Notification.Name {
    static let verbaContentTextSizeChanged = Notification.Name("verbaContentTextSizeChanged")
}
