import SwiftUI

/// The open island's pages are drawn at 80%, as if the display were scaled. Every size in a
/// page goes through `ui(_:)` or `Font.page`, so this one number sets them all.
nonisolated enum PageScale {
    static let factor: CGFloat = 0.8
    /// Text never gets smaller than this.
    static let smallestFont: CGFloat = 9
}

/// A page size at the page scale, on half points.
nonisolated func ui(_ value: CGFloat) -> CGFloat {
    (value * PageScale.factor * 2).rounded() / 2
}

extension Font {
    /// The system font at the page scale.
    static func page(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: max(PageScale.smallestFont, ui(size)), weight: weight, design: design)
    }
}
