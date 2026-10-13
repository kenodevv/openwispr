import AppKit
import Foundation

/// Watches the physical Fn (🌐) key via an active CGEventTap (events pass through unchanged).
/// An active tap works with the Accessibility permission alone; listen-only taps would need Input Monitoring.
final class FnKeyMonitor {
    var onPress: ((_ withControl: Bool) -> Void)?
    var onRelease: (() -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var fnDown = false
    private static let fnKeyCode: Int64 = 63

    var isActive: Bool { tap != nil }
    private(set) var lastFailure: String?

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            monitor.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            let ax = AXIsProcessTrusted()
            let listen = CGPreflightListenEventAccess()
            lastFailure = "Fn-Tap konnte nicht erstellt werden (Bedienungshilfen: \(ax ? "ja" : "nein"), Eingabeüberwachung: \(listen ? "ja" : "nein"))"
            return false
        }
        lastFailure = nil
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.source = source
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        fnDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged, event.getIntegerValueField(.keyboardEventKeycode) == Self.fnKeyCode else { return }
        let flags = event.flags
        let isDown = flags.contains(.maskSecondaryFn)
        if isDown && !fnDown {
            fnDown = true
            let withControl = flags.contains(.maskControl)
            DispatchQueue.main.async { [weak self] in self?.onPress?(withControl) }
        } else if !isDown && fnDown {
            fnDown = false
            DispatchQueue.main.async { [weak self] in self?.onRelease?() }
        }
    }
}
