import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Don't boot the real pipeline while running as a unit-test host.
        guard NSClassFromString("XCTestCase") == nil else { return }
        AppContainer.shared.boot()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
