import AppKit
import KerfKit

extension NSScreen {
    /// The hardware notch of a built-in display, nil on a display without one.
    var notchSize: CGSize? {
        guard safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return CGSize(width: frame.width - left.width - right.width, height: safeAreaInsets.top)
    }

    var islandStyle: IslandStyle { notchSize.map { .notch($0) } ?? .floating }

    /// The notch's left and right edge in global points; x is the same in AppKit and Quartz.
    var notchRange: ClosedRange<CGFloat>? {
        guard safeAreaInsets.top > 0, let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
        return (frame.minX + left.width)...(frame.maxX - right.width)
    }

    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}
