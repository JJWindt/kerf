import CoreGraphics

/// How much of the menu bar beside the notch is free. An app with many menus runs them right up
/// to the notch on both sides (macOS wraps them around it), and the island's wings must not
/// cover them.
public enum MenuBarRoom {
    /// The free width on the tighter side of the notch, in points. `items` are menu titles and
    /// status items in screen points; only x matters. Items behind the notch are hidden by the
    /// hardware, so they don't count.
    public static func free(notchMinX: CGFloat, notchMaxX: CGFloat, items: [CGRect]) -> CGFloat {
        let middle = (notchMinX + notchMaxX) / 2
        let visible = items.filter { $0.maxX <= notchMinX || $0.minX >= notchMaxX }
        let left = visible.filter { $0.midX < middle }.map(\.maxX).max().map { notchMinX - $0 } ?? .infinity
        let right = visible.filter { $0.midX >= middle }.map(\.minX).min().map { $0 - notchMaxX } ?? .infinity
        return max(0, min(left, right))
    }

    /// Whether wings this wide fit: the concave ears and a hair of air come on top.
    public static func fits(wings: CGFloat, in room: CGFloat) -> Bool {
        wings + IslandGeometry.ear + 2 <= room
    }
}
