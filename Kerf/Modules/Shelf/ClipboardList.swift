import SwiftUI

/// Recent clips, newest first: click one, or its copy button, to copy it again.
struct ClipboardList: View {
    private let clipboard = ClipboardModule.shared
    /// Each row's copy count, so only the copied row's icon bounces.
    @State private var copies: [UUID: Int] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if clipboard.clips.isEmpty {
                Text("Copy something and it shows up here.").font(.page(13)).foregroundStyle(.white.opacity(0.55)).frame(height: ui(36))
            }
            ForEach(clipboard.clips) { clip in
                Button {
                    clipboard.copy(clip)
                    copies[clip.id, default: 0] += 1
                } label: {
                    HStack(spacing: ui(10)) {
                        preview(clip)
                        Spacer(minLength: ui(8))
                        Image(systemName: "doc.on.doc")
                            .font(.page(13, weight: .semibold))
                            .symbolEffect(.bounce, value: copies[clip.id, default: 0])
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: ui(28), height: ui(28))
                            .background(.white.opacity(0.1), in: Circle())
                    }
                    .frame(height: ui(30))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Copy"))
            }
        }
    }

    @ViewBuilder private func preview(_ clip: ClipboardModule.Clip) -> some View {
        switch clip.content {
        case .text(let text):
            Text(verbatim: text.trimmingCharacters(in: .whitespacesAndNewlines)).font(.page(13)).lineLimit(1)
        case .image(let image):
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(height: ui(28))
                .clipShape(RoundedRectangle(cornerRadius: ui(4), style: .continuous))
        case .files(let urls):
            Image(nsImage: NSWorkspace.shared.icon(forFile: urls[0].path)).resizable().frame(width: ui(22), height: ui(22))
            Text(verbatim: urls.map(\.lastPathComponent).joined(separator: ", ")).font(.page(13)).lineLimit(1)
        }
    }
}
