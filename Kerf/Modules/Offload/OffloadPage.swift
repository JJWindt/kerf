import KerfKit
import SwiftUI

/// Card → drive → project → copying → done, each step an Apple island card.
struct OffloadPage: View {
    private let offload = OffloadModule.shared
    @State private var project = ""

    var body: some View {
        Group {
            switch offload.step {
            case .card: cardStep
            case .drive: driveStep
            case .project(let drive): projectStep(drive)
            case .copying: copyingStep
            case .done: doneStep
            case .failed(let message): failedStep(message)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, ui(22))
        .padding(.top, ui(6))
    }

    static var contentHeight: CGFloat {
        let offload = OffloadModule.shared
        switch offload.step {
        case .card: return 116
        case .drive: return 96 + CGFloat(max(min(offload.drives.count, 3), 1)) * 46
        case .project: return offload.projects.isEmpty ? 136 : 178
        case .copying: return 132
        case .done: return 112
        case .failed: return 122
        }
    }

    private var cardSummary: some View {
        HStack(spacing: ui(12)) {
            Image(systemName: "sdcard.fill")
                .font(.page(22, weight: .semibold))
                .frame(width: ui(44), height: ui(44))
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: ui(10), style: .continuous))
            VStack(alignment: .leading, spacing: ui(2)) {
                Text(verbatim: offload.card?.name ?? "").font(.page(16, weight: .semibold))
                if let card = offload.card {
                    Text("\(card.mediaCount) files · \(card.totalBytes.formatted(.byteCount(style: .file)))")
                        .font(.page(14)).foregroundStyle(.white.opacity(0.55))
                }
            }
            Spacer()
        }
    }

    private var cardStep: some View {
        VStack(spacing: ui(14)) {
            cardSummary
            HStack(spacing: ui(10)) {
                IslandButton(title: "Not Now") { OffloadModule.shared.dismissCard() }
                IslandButton(title: "Offload", role: .primary) { offload.chooseDrive() }
            }
        }
    }

    private var driveStep: some View {
        VStack(alignment: .leading, spacing: ui(8)) {
            Text("Choose a drive").font(.page(15, weight: .semibold))
            if offload.drives.isEmpty {
                Text("Connect your SSD.").font(.page(14)).foregroundStyle(.white.opacity(0.55)).frame(height: ui(38))
            }
            ForEach(offload.drives.prefix(3)) { drive in
                Button { offload.pick(drive) } label: {
                    HStack(spacing: ui(10)) {
                        Image(systemName: "externaldrive.fill").font(.page(15, weight: .semibold))
                        Text(verbatim: drive.name).font(.page(14, weight: .semibold))
                        Spacer()
                        Text("\(drive.free.formatted(.byteCount(style: .file))) free").font(.page(13)).foregroundStyle(.white.opacity(0.55))
                        Image(systemName: "chevron.right").font(.page(12, weight: .semibold)).foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.horizontal, ui(14))
                    .frame(height: ui(38))
                    .background(.white.opacity(0.1), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            IslandButton(title: "Back") { offload.back() }
                .padding(.top, ui(2))
        }
    }

    private func projectStep(_ drive: OffloadModule.Drive) -> some View {
        VStack(alignment: .leading, spacing: ui(10)) {
            Text("Project on \(drive.name)").font(.page(15, weight: .semibold))
            TextField("Project name", text: $project)
                .textFieldStyle(.plain)
                .font(.page(15))
                .padding(.horizontal, ui(14))
                .frame(height: ui(36))
                .background(.white.opacity(0.1), in: Capsule())
                .onSubmit(start)
            if !offload.projects.isEmpty {
                HStack(spacing: ui(8)) {
                    ForEach(offload.projects.prefix(3), id: \.self) { name in
                        Button { project = name } label: {
                            Text(verbatim: name).font(.page(13, weight: .medium)).lineLimit(1)
                                .padding(.horizontal, ui(12)).frame(height: ui(30))
                                .background(.white.opacity(name == project ? 0.25 : 0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            HStack(spacing: ui(10)) {
                IslandButton(title: "Back") { offload.back() }
                IslandButton(title: "Start", role: .primary, action: start)
                    .disabled(project.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        // The last project on this drive is the likely one for the next card.
        .onAppear { if project.isEmpty { project = offload.projects.first ?? "" } }
    }

    private func start() {
        guard case .project(let drive) = offload.step, !project.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        offload.begin(project: project, on: drive)
    }

    private var copyingStep: some View {
        VStack(alignment: .leading, spacing: ui(10)) {
            HStack {
                Text(verbatim: offload.card?.name ?? "").font(.page(15, weight: .semibold))
                Spacer()
                Text("Copying and checking").font(.page(13)).foregroundStyle(.white.opacity(0.55))
            }
            LevelBar(value: offload.progress?.fraction ?? 0).frame(height: ui(5))
            HStack {
                if let progress = offload.progress {
                    Text("\(progress.filesDone) of \(progress.filesTotal)")
                    Spacer()
                    if progress.bytesPerSecond > 0 {
                        Text("\(Int64(progress.bytesPerSecond).formatted(.byteCount(style: .file)))/s")
                    }
                    if let left = progress.secondsLeft {
                        Text(verbatim: "·")
                        Text("\(Duration.seconds(max(left, 1)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))) left")
                    }
                } else {
                    Text("Starting…")
                    Spacer()
                }
            }
            .font(.page(12, weight: .medium).monospacedDigit())
            .foregroundStyle(.white.opacity(0.55))
            IslandButton(title: "Stop") { offload.cancel() }
        }
    }

    private var doneStep: some View {
        VStack(spacing: ui(14)) {
            HStack(spacing: ui(12)) {
                let clean = offload.report?.mismatches.isEmpty ?? true
                Image(systemName: clean ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.page(28, weight: .semibold))
                    .foregroundStyle(clean ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                VStack(alignment: .leading, spacing: ui(2)) {
                    if let report = offload.report {
                        Text("\(report.copied) files copied and checked").font(.page(15, weight: .semibold))
                        if !report.mismatches.isEmpty {
                            Text("\(report.mismatches.count) didn't match the card. Copy them again.").font(.page(13)).foregroundStyle(.white.opacity(0.6))
                        } else if report.skipped > 0 {
                            Text("\(report.skipped) were already in the project").font(.page(13)).foregroundStyle(.white.opacity(0.55))
                        } else {
                            Text(verbatim: report.cardFolder.lastPathComponent).font(.page(13)).foregroundStyle(.white.opacity(0.55))
                        }
                    }
                }
                Spacer()
            }
            HStack(spacing: ui(10)) {
                IslandButton(title: "Done") { offload.dismiss() }
                IslandButton(title: "Show in Finder", role: .primary) { offload.showInFinder() }
            }
        }
    }

    private func failedStep(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: ui(12)) {
            HStack(spacing: ui(10)) {
                Image(systemName: "exclamationmark.triangle.fill").font(.page(22, weight: .semibold)).foregroundStyle(Color(nsColor: .systemOrange))
                Text("The copy stopped").font(.page(15, weight: .semibold))
            }
            Text(verbatim: message).font(.page(13)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
            IslandButton(title: "Back") { offload.back() }
        }
    }
}

/// A ring that fills, for progress in the compact island.
struct ProgressRing: View {
    let value: Double

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 2.5)
            Circle().trim(from: 0, to: min(max(value, 0), 1))
                .stroke(.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth(duration: 0.3), value: value)
        }
        .frame(width: 15, height: 15)
    }
}
