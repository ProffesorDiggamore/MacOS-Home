import AppKit
import SwiftUI
import Combine

/// A borderless panel that sits on the desktop and hosts one widget.
///
/// Dragging is handled here instead of with `isMovableByWindowBackground` so that
/// clicks on buttons still work, drags never trigger buttons, and we know exactly
/// when a drag ends (to snap the widget into place).
final class WidgetPanel: NSPanel {
    var isLocked = false
    var onDragEnded: (() -> Void)?

    private var mouseDownScreenPoint: NSPoint?
    private var frameAtMouseDown: NSRect = .zero
    private var isDragging = false
    private var mouseDownWasInText = false

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownScreenPoint = NSEvent.mouseLocation
            frameAtMouseDown = frame
            isDragging = false
            mouseDownWasInText = Self.isTextView(contentView?.hitTest(event.locationInWindow))
            super.sendEvent(event)

        case .leftMouseDragged:
            guard let start = mouseDownScreenPoint, !isLocked, !mouseDownWasInText else {
                super.sendEvent(event)
                return
            }
            let now = NSEvent.mouseLocation
            if !isDragging {
                guard hypot(now.x - start.x, now.y - start.y) > 4 else {
                    super.sendEvent(event)
                    return
                }
                isDragging = true
                cancelContentTracking(for: event)
                NSCursor.closedHand.push()
            }
            setFrameOrigin(NSPoint(x: frameAtMouseDown.origin.x + now.x - start.x,
                                   y: frameAtMouseDown.origin.y + now.y - start.y))

        case .leftMouseUp:
            mouseDownScreenPoint = nil
            if isDragging {
                isDragging = false
                NSCursor.pop()
                onDragEnded?()
            } else {
                super.sendEvent(event)
            }

        default:
            super.sendEvent(event)
        }
    }

    /// Sends a mouse-up far outside the widget so any pressed button cancels instead of firing.
    private func cancelContentTracking(for event: NSEvent) {
        guard let cancel = NSEvent.mouseEvent(with: .leftMouseUp,
                                              location: NSPoint(x: -10_000, y: -10_000),
                                              modifierFlags: [],
                                              timestamp: event.timestamp,
                                              windowNumber: windowNumber,
                                              context: nil,
                                              eventNumber: event.eventNumber,
                                              clickCount: 1,
                                              pressure: 0) else { return }
        super.sendEvent(cancel)
    }

    /// Text fields, sliders and other AppKit controls handle their own dragging.
    private static func isTextView(_ view: NSView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is NSText || candidate is NSControl { return true }
            current = candidate.superview
        }
        return false
    }
}

/// Lets the very first click on an inactive widget go straight to its buttons.
final class WidgetHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Owns the panel for one widget and keeps it in sync with the model and settings.
@MainActor
final class WidgetPanelController {
    let model: WidgetModel
    let panel: WidgetPanel
    private var cancellables = Set<AnyCancellable>()
    private let appearance = AppearanceSettings.shared

    init(model: WidgetModel) {
        self.model = model
        panel = WidgetPanel(contentRect: model.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        panel.title = model.kind.title

        let host = WidgetHostingView(rootView: WidgetView(model: model))
        host.sizingOptions = []
        panel.contentView = host

        panel.onDragEnded = { [weak self] in
            self?.dragEnded()
        }

        model.$size
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.sizeChanged() }
            .store(in: &cancellables)
        model.$styleOverride
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)
        // Pause animations while the widget is covered by windows or hidden.
        NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification, object: panel)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateVisibility() }
            .store(in: &cancellables)

        applySettings()
    }

    func show() {
        applySettings()
        if !appearance.hidden {
            panel.orderFrontRegardless()
        }
        refreshShadow()
    }

    func close() {
        cancellables.removeAll()
        panel.orderOut(nil)
        panel.close()
    }

    func applySettings() {
        panel.level = appearance.layer.windowLevel
        panel.isLocked = appearance.locked
        let style = model.styleOverride ?? appearance.style
        panel.hasShadow = appearance.showShadow && style != .clear
        if appearance.hidden {
            panel.orderOut(nil)
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
        refreshShadow()
    }

    private func updateVisibility() {
        let visible = panel.isVisible && panel.occlusionState.contains(.visible)
        if model.runtime.isOnScreen != visible {
            model.runtime.isOnScreen = visible
        }
    }

    /// The window shadow is computed from the widget's shape, so recompute it after the content draws.
    private func refreshShadow() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.panel.invalidateShadow()
        }
    }

    private func sizeChanged() {
        let dimensions = model.size.dimensions
        let rect = CGRect(x: model.topLeft.x, y: model.topLeft.y - dimensions.height,
                          width: dimensions.width, height: dimensions.height)
        let bounds = screenBounds(for: rect)
        let fitted = Placement.clamp(rect, to: bounds)
        panel.setFrame(fitted, display: true)
        model.topLeft = CGPoint(x: fitted.minX, y: fitted.maxY)
        refreshShadow()
    }

    private func dragEnded() {
        let current = panel.frame
        let others = AppController.shared.widgetFrames(excluding: model.id)
        let snapped = Placement.snap(current, others: others, bounds: screenBounds(for: current))
        if snapped.origin != current.origin {
            move(to: snapped, animated: true)
        }
        model.topLeft = CGPoint(x: snapped.minX, y: snapped.maxY)
    }

    func move(to rect: CGRect, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(rect, display: true)
            }
        } else {
            panel.setFrame(rect, display: true)
        }
        model.topLeft = CGPoint(x: rect.minX, y: rect.maxY)
    }

    /// Makes sure the widget is on a connected screen (after unplugging a display, say).
    func ensureVisible(fallback: () -> CGPoint) {
        let rect = model.frame
        let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(rect.insetBy(dx: 30, dy: 30)) }
        if !onScreen {
            let topLeft = fallback()
            let dimensions = model.size.dimensions
            move(to: CGRect(x: topLeft.x, y: topLeft.y - dimensions.height, width: dimensions.width, height: dimensions.height),
                 animated: false)
        }
    }

    private func screenBounds(for rect: CGRect) -> CGRect {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? panel.screen ?? NSScreen.main
        return screen?.visibleFrame ?? rect
    }
}

/// Grid placement and snapping, like Apple's desktop widgets.
enum Placement {
    static let gap = WidgetSize.spacing
    static let margin: CGFloat = 20

    /// First free spot scanning columns from the top-left of the screen.
    static func freeTopLeft(for size: CGSize, in bounds: CGRect, occupied: [CGRect]) -> CGPoint {
        let area = bounds.insetBy(dx: margin, dy: margin)
        let step = (WidgetSize.unit + gap) / 2
        var x = area.minX
        while x + size.width <= area.maxX + 0.5 {
            var top = area.maxY
            while top - size.height >= area.minY - 0.5 {
                let candidate = CGRect(x: x, y: top - size.height, width: size.width, height: size.height)
                let blocked = occupied.contains { $0.insetBy(dx: -(gap - 1), dy: -(gap - 1)).intersects(candidate) }
                if !blocked { return CGPoint(x: x, y: top) }
                top -= step
            }
            x += step
        }
        return CGPoint(x: area.midX - size.width / 2, y: area.midY + size.height / 2)
    }

    /// Nudges a rect so it lines up with nearby widgets and screen edges.
    static func snap(_ rect: CGRect, others: [CGRect], bounds: CGRect, threshold: CGFloat = 14) -> CGRect {
        var xs: [CGFloat] = [bounds.minX + margin, bounds.maxX - margin - rect.width]
        var tops: [CGFloat] = [bounds.maxY - margin, bounds.minY + margin + rect.height]
        for other in others {
            xs += [other.minX, other.maxX + gap, other.minX - gap - rect.width, other.maxX - rect.width]
            tops += [other.maxY, other.minY - gap, other.maxY + gap + rect.height, other.minY + rect.height]
        }
        func nearest(_ value: CGFloat, _ candidates: [CGFloat]) -> CGFloat {
            guard let best = candidates.min(by: { abs($0 - value) < abs($1 - value) }),
                  abs(best - value) <= threshold else { return value }
            return best
        }
        let x = nearest(rect.minX, xs)
        let top = nearest(rect.maxY, tops)
        return clamp(CGRect(x: x, y: top - rect.height, width: rect.width, height: rect.height), to: bounds)
    }

    static func clamp(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        var result = rect
        result.origin.x = min(max(result.minX, bounds.minX), max(bounds.minX, bounds.maxX - rect.width))
        result.origin.y = min(max(result.minY, bounds.minY), max(bounds.minY, bounds.maxY - rect.height))
        return result
    }
}
