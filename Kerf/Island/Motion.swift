import AppKit
import KerfKit
import SwiftUI

/// Springs fitted to the iPhone Dynamic Island, recorded at 60 fps in the iOS 27 simulator and
/// reproduced on a MacBook notch.
enum Motion {
    /// Idle → compact: response 0.49 s, damping 0.84 (0.6 % overshoot).
    static let appear = Spring(response: 0.49, dampingRatio: 0.84)
    /// Compact → open, both axes together: response 0.50 s, damping 0.82 (1.2 % overshoot).
    static let expand = Spring(response: 0.50, dampingRatio: 0.82)
    /// Open → compact, width: shoots 18 % past the compact width into a small pill and springs back.
    static let collapseWidth = Spring(response: 0.56, dampingRatio: 0.48)
    /// Open → compact, height: overdamped, so it never dips into the notch.
    static let collapseHeight = Spring(response: 0.28, dampingRatio: 1.12)
    /// Compact → idle, critically damped.
    static let disappear = Spring(response: 0.44, dampingRatio: 0.98)
    /// Hover feedback; not on iPhone, so small and quick.
    static let hover = Spring(response: 0.30, dampingRatio: 0.70)
    /// The bump when something new arrives, like an iPhone Live Activity update.
    static let bump = Spring(response: 0.24, dampingRatio: 0.55)

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    static func springs(from: IslandMode, to: IslandMode) -> (width: Animation, height: Animation) {
        guard !reduceMotion else { return (.easeInOut(duration: 0.2), .easeInOut(duration: 0.2)) }
        let pair: (Spring, Spring) = switch (from, to) {
        case (.expanded, .compact): (collapseWidth, collapseHeight)
        case (.expanded, _), (_, .idle): (disappear, disappear)
        case (_, .expanded): (expand, expand)
        default: (appear, appear)
        }
        return (.spring(pair.0), .spring(pair.1))
    }

    /// Content blurs away while the shape starts moving: on iPhone it is gone after 140 ms when the
    /// island closes and after 90 ms otherwise.
    static func fadeOut(from previous: IslandMode) -> Animation {
        previous == .expanded ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.13)
    }

    /// Content comes with the shape, not after it: an empty pill that fills later reads as two steps
    /// on the Mac (a design call over the iPhone timings).
    static func fadeIn(to mode: IslandMode, from previous: IslandMode) -> Animation? {
        if reduceMotion { return mode == .idle ? nil : .easeInOut(duration: 0.2) }
        return switch (previous, mode) {
        // Closing: the compact content sharpens while the open island shrinks into it.
        case (.expanded, .compact): .smooth(duration: 0.22).delay(0.18)
        case (_, .compact): .smooth(duration: 0.2).delay(0.05)
        case (_, .expanded): .smooth(duration: 0.25)
        default: nil
        }
    }
}
