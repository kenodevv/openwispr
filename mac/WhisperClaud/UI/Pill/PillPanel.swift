import AppKit
import SwiftUI

/// Non-activating, click-through panel that floats above everything (incl. full-screen apps).
@MainActor
final class PillPanel: NSPanel {
    init(state: AppState) {
        let rect = NSRect(x: 0, y: 0, width: 560, height: 80)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSHostingView(rootView: PillView(state: state))
        host.frame = rect
        contentView = host
        alphaValue = 0
    }

    func present() {
        reposition()
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.alphaValue == 0 else { return }
                self.orderOut(nil)
            }
        })
    }

    private func reposition() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frameOnScreen = screen?.visibleFrame else { return }
        let size = frame.size
        setFrameOrigin(NSPoint(x: frameOnScreen.midX - size.width / 2, y: frameOnScreen.minY + 20))
    }
}

/// Shows/hides the pill whenever the pipeline state changes.
@MainActor
final class PillController {
    private let state: AppState
    private let settings: AppSettings
    private lazy var panel = PillPanel(state: state)
    private var visible = false

    init(state: AppState, settings: AppSettings) {
        self.state = state
        self.settings = settings
    }

    func start() {
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = state.pipeline
            _ = settings.showPill
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observe()
            }
        }
        sync()
    }

    private func sync() {
        let shouldShow = settings.showPill && state.pipeline != .idle
        guard shouldShow != visible else { return }
        visible = shouldShow
        if shouldShow { panel.present() } else { panel.dismiss() }
    }
}
