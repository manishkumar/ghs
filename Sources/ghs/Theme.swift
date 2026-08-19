import SwiftUI

/// The visual system: a review queue is metal left outdoors. Age is rendered as
/// oxidation — patina teal when fresh, through brass and oxide, to rust when a
/// PR has been sitting long enough to be embarrassing.
///
/// Deliberately not a green→red traffic light: the progression reads as a
/// material aging, which is what review debt actually feels like.
enum Theme {

    // MARK: Oxidation ramp

    private struct Stop {
        let position: Double
        let light: (r: Double, g: Double, b: Double)
        let dark: (r: Double, g: Double, b: Double)
    }

    private static let stops: [Stop] = [
        Stop(position: 0.00, light: (0.247, 0.561, 0.486), dark: (0.353, 0.694, 0.608)),  // patina
        Stop(position: 0.35, light: (0.725, 0.608, 0.180), dark: (0.827, 0.706, 0.278)),  // brass
        Stop(position: 0.70, light: (0.761, 0.369, 0.165), dark: (0.855, 0.475, 0.259)),  // oxide
        // Rust is the hot end of the ramp, so it must not be the dimmest thing
        // on it. The original #9E2B1C was darker and duller than oxide, which
        // made the most urgent state read as the least urgent and turned the
        // thin glyph strokes muddy on a translucent menu bar. Held at oxide's
        // luminance and pushed on chroma instead, so the step from oxide is a
        // step *up*.
        Stop(position: 1.00, light: (0.753, 0.204, 0.110), dark: (0.949, 0.388, 0.290)),  // rust
    ]

    /// 0 = just opened, 1 = past the urgency threshold.
    static func oxidation(_ t: Double, scheme: ColorScheme) -> Color {
        let t = min(max(t, 0), 1)
        var lower = stops[0], upper = stops[stops.count - 1]
        for (a, b) in zip(stops, stops.dropFirst()) where t >= a.position && t <= b.position {
            lower = a
            upper = b
            break
        }
        let span = upper.position - lower.position
        let f = span <= 0 ? 0 : (t - lower.position) / span
        let a = scheme == .dark ? lower.dark : lower.light
        let b = scheme == .dark ? upper.dark : upper.light
        return Color(
            red: a.r + (b.r - a.r) * f,
            green: a.g + (b.g - a.g) * f,
            blue: a.b + (b.b - a.b) * f
        )
    }

    static func oxidation(forAge age: TimeInterval, threshold days: Double, scheme: ColorScheme) -> Color {
        oxidation(fraction(forAge: age, threshold: days), scheme: scheme)
    }

    /// Eased so freshly-opened PRs hold their calm colour for a while and the
    /// shift happens across the middle of the range, where it carries meaning.
    static func fraction(forAge age: TimeInterval, threshold days: Double) -> Double {
        let span = max(1, days) * 86_400
        return pow(min(max(age / span, 0), 1), 0.72)
    }

    // MARK: Type

    /// Uppercase mono, widely tracked. Used only for structural labels, never
    /// for content.
    static let eyebrow = Font.system(size: 10, weight: .semibold, design: .monospaced)
    static let title = Font.system(size: 13, weight: .medium)
    static let meta = Font.system(size: 11, weight: .regular)
    /// Every number in the interface is monospaced, so digits line up in a
    /// column and the eye can compare ages without reading them.
    static let numeric = Font.system(size: 11, weight: .semibold, design: .monospaced)
    static let numericLarge = Font.system(size: 22, weight: .medium, design: .monospaced)

    // MARK: Metrics

    static let popoverWidth: CGFloat = 420
    static let railWidth: CGFloat = 3

    // MARK: Settled rows

    /// How far a row you have already reviewed steps back. Deliberately a
    /// recession, not a removal: the PR is still blocked and still the team's
    /// problem, it is just no longer yours. Low enough that the eye skips it
    /// running down the list, high enough to stay readable when looked at.
    static let settledRail: Double = 0.28
    static let settledContent: Double = 0.58
    static let gutter: CGFloat = 14
}

extension View {
    func eyebrowStyle() -> some View {
        font(Theme.eyebrow)
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }
}
