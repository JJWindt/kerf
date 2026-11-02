import AppKit
import SwiftUI

// The app binary doubles as the `kerf` command for hooks and scripts: a known subcommand runs
// and exits before any UI starts.
if let status = CommandLineTool.run(CommandLine.arguments) {
    exit(status)
}
KerfApp.main()
