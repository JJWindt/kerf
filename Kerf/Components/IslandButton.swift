import SwiftUI

/// The island's capsule buttons, colours sampled from Apple's own Mac island (the AirDrop card):
/// secondary #4D4D4D with a white label, primary #002B58 with a #4EBBFC label.
struct IslandButton: View {
    enum Role {
        case secondary, primary
    }

    static let primaryLabel = Color(red: 0.306, green: 0.733, blue: 0.988)
    static let primaryFill = Color(red: 0, green: 0.169, blue: 0.345)

    let title: Text
    var role: Role = .secondary
    var action: () -> Void

    init(title: LocalizedStringKey, role: Role = .secondary, action: @escaping () -> Void) {
        self.title = Text(title)
        self.role = role
        self.action = action
    }

    /// Text as it is, such as an agent's own answer options.
    init(verbatim title: String, role: Role = .secondary, action: @escaping () -> Void) {
        self.title = Text(verbatim: title)
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            title
                .font(.page(15, weight: .medium))
                .foregroundStyle(role == .primary ? Self.primaryLabel : .white)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: ui(32))
                .background(role == .primary ? Self.primaryFill : Color(white: 0.302), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// A round icon button for transport controls and small actions inside the island.
struct IslandIconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var size: CGFloat = ui(20)
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size * 2, height: size * 1.4)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

/// Its content at full height up to `maxHeight`, scrolling past that: a long command stays
/// readable without pushing the buttons under it out of the island.
struct CappedScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView(.vertical) {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .scrollDisabled(height <= maxHeight)
        .scrollIndicators(height > maxHeight ? .visible : .never)
        .frame(height: min(max(height, 1), maxHeight))
    }
}
