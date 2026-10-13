import SwiftUI
import AppKit
import NeuroTracCore

@main
struct NeuroTracLiveApp: App {
    init() {
        // Needed when the app is launched from the Terminal (swift run):
        // it must behave like a real application with a foreground window.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup(tr("NeuroTrac Live")) {
            ContentView()
        }
    }
}
