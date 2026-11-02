import KerfKit
import SwiftUI

/// The folder names a project gets. The default: short and without numbers.
struct OffloadSettings: View {
    @State private var template = OffloadModule.shared.template

    var body: some View {
        Form {
            Section {
                TextField("Projects folder", text: $template.projectsFolder)
                TextField("Footage", text: $template.footage)
                TextField("Audio", text: $template.audio)
                TextField("Card folders", text: $template.cardPrefix)
                TextField("Also create", text: Binding(
                    get: { template.extraFolders.joined(separator: ", ") },
                    set: { template.extraFolders = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                ))
            } header: {
                Text("Folders")
            } footer: {
                Text(verbatim: "SSD/\(template.projectsFolder)/Project/\(template.footage)/Sony FX3/\(OffloadPlanner.cardFolderName(prefix: template.cardPrefix, number: 1))")
                    .font(.system(.caption, design: .monospaced))
            }
            Section {
                Text("Every file is checked against the card with xxHash64. Files already in the project are skipped. Kerf never writes to the card.")
                    .foregroundStyle(.secondary)
                Button("Use the Defaults") {
                    template = Locale.current.language.languageCode == .dutch ? .dutch : .english
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: template) { _, new in OffloadModule.shared.template = new }
    }
}
