import AppKit
import SwiftUI

/// Owns the History and Onboarding windows (plain NSWindows hosting SwiftUI).
@MainActor
final class WindowManager {
    private unowned let container: AppContainer
    private var history: NSWindow?
    private var onboarding: NSWindow?

    init(container: AppContainer) {
        self.container = container
    }

    func showHistory() {
        if history == nil {
            let view = HistoryView()
                .environment(container.state)
                .environment(container.settings)
                .modelContainer(container.store.container)
            history = makeWindow(title: "History", size: NSSize(width: 960, height: 620), root: view)
        }
        bringFront(history)
    }

    func showOnboarding() {
        if onboarding == nil {
            let view = OnboardingView(onFinish: { [weak self] in self?.onboarding?.close() })
                .environment(container.state)
                .environment(container.settings)
            onboarding = makeWindow(title: "Set up OpenWispr", size: NSSize(width: 640, height: 560), root: view)
            onboarding?.styleMask.remove(.resizable)
        }
        bringFront(onboarding)
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func makeWindow<V: View>(title: String, size: NSSize, root: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.contentView = NSHostingView(rootView: root)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func bringFront(_ window: NSWindow?) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
