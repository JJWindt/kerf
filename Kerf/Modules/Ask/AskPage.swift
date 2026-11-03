import KerfKit
import SwiftUI

/// One field like Spotlight on Apple's Mac island: a question goes to Claude, a few words to Google.
struct AskPage: View {
    @Bindable private var ask = AskModule.shared
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ui(10)) {
            field
            if ask.hasAnswer {
                answer
            } else {
                recent
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, ui(18))
        .padding(.top, ui(6))
        .onAppear { focused = true }
    }

    static var contentHeight: CGFloat {
        let ask = AskModule.shared
        let field: CGFloat = 54
        if ask.hasAnswer {
            let lines = ask.answer.split(separator: "\n", omittingEmptySubsequences: false)
                .reduce(0) { $0 + max(1, Int(ceil(Double($1.count) / 58))) }
            return field + 60 + min(CGFloat(max(lines, 1)) * 18, 230)
        }
        return field + CGFloat(min(ask.history.count, 3)) * 34 + (ask.history.isEmpty ? 0 : 8)
    }

    private var field: some View {
        HStack(spacing: ui(10)) {
            Image(systemName: ask.route == .claude ? "sparkle" : "magnifyingglass")
                .font(.page(15, weight: .semibold))
                .foregroundStyle(ask.route == .claude ? Color(nsColor: .systemOrange) : .white.opacity(0.7))
                .contentTransition(.symbolEffect(.replace))
            TextField(ask.hasAnswer ? "Ask a follow-up" : "Ask Claude or search Google", text: $ask.text)
                .textFieldStyle(.plain)
                .font(.page(16))
                .focused($focused)
                .onSubmit { ask.submit() }
                .onKeyPress(.tab) {
                    ask.toggleRoute()
                    return .handled
                }
            Text(verbatim: ask.route == .claude ? "Claude" : "Google")
                .font(.page(11, weight: .semibold))
                .padding(.horizontal, ui(8))
                .frame(height: ui(20))
                .background(.white.opacity(0.14), in: Capsule())
                .foregroundStyle(.white.opacity(0.8))
                .help(Text("Tab switches"))
        }
        .padding(.horizontal, ui(14))
        .frame(height: ui(40))
        .background(.white.opacity(0.1), in: Capsule())
    }

    private var answer: some View {
        VStack(alignment: .leading, spacing: ui(6)) {
            Text(verbatim: ask.question).font(.page(13, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            Group {
                    if let failure = ask.failure {
                        Text(verbatim: failure).foregroundStyle(Color(nsColor: .systemOrange))
                    } else if ask.answer.isEmpty {
                        Text(ask.usingTool.map { "Using \($0)…" } ?? "Thinking…").foregroundStyle(.white.opacity(0.5))
                    } else {
                        Text(markdown)
                    }
                }
            .font(.page(14))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: ui(14)) {
                if ask.isRunning {
                    ProgressView().controlSize(.small).tint(.white)
                    Button("Stop") { ask.cancel() }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button("Copy") { ask.copyAnswer() }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.7)).disabled(ask.answer.isEmpty)
                Button("New") { ask.newConversation() }.buttonStyle(.plain).foregroundStyle(.white.opacity(0.7))
            }
            .font(.page(12, weight: .semibold))
        }
    }

    private var markdown: AttributedString {
        (try? AttributedString(markdown: ask.answer, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(ask.answer)
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: ui(2)) {
            ForEach(ask.history.prefix(3)) { conversation in
                Button { ask.show(conversation) } label: {
                    HStack(spacing: ui(8)) {
                        Image(systemName: "clock.arrow.circlepath").font(.page(12, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                        Text(verbatim: conversation.question).font(.page(13)).lineLimit(1)
                        Spacer()
                        Text(conversation.date, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                            .font(.page(11)).foregroundStyle(.white.opacity(0.4))
                    }
                    .frame(height: ui(28))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ui(6))
    }
}
