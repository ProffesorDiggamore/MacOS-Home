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
    var onDragStarted: (() -> Void)?
    var onDragMoved: (() -> Void)?
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
                onDragStarted?()
            }
            setFrameOrigin(NSPoint(x: frameAtMouseDown.origin.x + now.x - start.x,
                                   y: frameAtMouseDown.origin.y + now.y - start.y))
            onDragMoved?()

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

/// Tells a widget when the pointer is over it, even though widgets are never the active window.
final class HoverTracker: NSResponder {
    var onChange: ((Bool) -> Void)?

    func attach(to view: NSView) {
        view.addTrackingArea(NSTrackingArea(rect: .zero,
                                            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                            owner: self,
                                            userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onChange?(true) }
    override func mouseExited(with event: NSEvent) { onChange?(false) }
}

/// True while any widget is being dragged, so see-through widgets can show their edges.
final class DragState: ObservableObject {
    static let shared = DragState()
    @Published var isDragging = false
}

/// Owns the panel for one widget and keeps it in sync with the model and settings.
@MainActor
final class WidgetPanelController {
    let model: WidgetModel
    let panel: WidgetPanel
    private var cancellables = Set<AnyCancellable>()
    private let appearance = AppearanceSettings.shared
    private let hover = HoverTracker()
    private var hideWork: DispatchWorkItem?
    private var lastGhost: CGRect?
    private var lastCell: CGRect?

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
        panel.collectionBehavior = Self.behavior(allDesktops: appearance.allDesktops)
        panel.title = model.kind.title

        let host = WidgetHostingView(rootView: WidgetView(model: model))
        host.sizingOptions = []
        panel.contentView = host
        hover.attach(to: host)
        hover.onChange = { [weak model] inside in
            if model?.runtime.isHovered != inside { model?.runtime.isHovered = inside }
        }

        panel.onDragStarted = { [weak self] in self?.dragStarted() }
        panel.onDragMoved = { [weak self] in self?.dragMoved() }
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

    /// Windows on every Space are only drawn once a Space switch finishes, so by default
    /// widgets belong to one desktop and slide in with it like regular windows.
    private static func behavior(allDesktops: Bool) -> NSWindow.CollectionBehavior {
        allDesktops ? [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
                    : [.stationary, .ignoresCycle, .fullScreenNone]
    }

    func applySettings() {
        let behavior = Self.behavior(allDesktops: appearance.allDesktops)
        if panel.collectionBehavior != behavior {
            panel.collectionBehavior = behavior
            // Re-showing moves a widget onto the desktop you're looking at.
            if panel.isVisible { panel.orderOut(nil) }
        }
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

    /// Becoming visible is instant; going invisible waits a moment, because Spaces
    /// and Mission Control flicker occlusion during their animations. Pausing and
    /// restarting every widget on each flicker is what made them slow to come back.
    private func updateVisibility() {
        let visible = panel.isVisible && panel.occlusionState.contains(.visible)
        hideWork?.cancel()
        if visible {
            if !model.runtime.isOnScreen { model.runtime.isOnScreen = true }
        } else if model.runtime.isOnScreen {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                if !(self.panel.isVisible && self.panel.occlusionState.contains(.visible)) {
                    self.model.runtime.isOnScreen = false
                }
            }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
        }
    }

    /// Called when you switch Spaces (three-finger swipe, leaving a full-screen app).
    /// Widgets are told they're visible right away instead of waiting for the window
    /// server's occlusion update, which only arrives after the swipe animation ends.
    func spaceChanged() {
        guard !appearance.hidden else { return }
        hideWork?.cancel()
        if !model.runtime.isOnScreen { model.runtime.isOnScreen = true }
        if !panel.isVisible { panel.orderFrontRegardless() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            MainActor.assumeIsolated { self?.updateVisibility() }
        }
    }

    /// The window shadow is computed from the widget's shape, so recompute it after the content draws.
    private func refreshShadow() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            self?.panel.invalidateShadow()
        }
    }

    /// A new size keeps the same top-left corner when there's room, otherwise the nearest free slot.
    private func sizeChanged() {
        let dimensions = model.size.dimensions
        let rect = CGRect(x: model.topLeft.x, y: model.topLeft.y - dimensions.height,
                          width: dimensions.width, height: dimensions.height)
        let placed = DesktopGrid.place(rect, size: model.size, occupied: AppController.shared.widgetFrames(excluding: model.id))
        panel.setFrame(placed, display: true)
        model.topLeft = CGPoint(x: placed.minX, y: placed.maxY)
        refreshShadow()
    }

    private func dragStarted() {
        model.runtime.isDragging = true
        DragState.shared.isDragging = true
        lastGhost = nil
        lastCell = nil
        AppController.shared.beginDrag(model.id)
    }

    private func dragMoved() {
        // Only re-plan when the pointer crosses into a different grid slot.
        let grid = DesktopGrid.forRect(panel.frame)
        let cell = grid.rect(at: grid.nearestCell(to: panel.frame, size: model.size), size: model.size)
        guard cell != lastCell else { return }
        lastCell = cell
        let target = AppController.shared.reflow(dragging: panel.frame, size: model.size)
        guard target != lastGhost else { return }
        lastGhost = target
        DropGhost.shared.show(target, below: panel)
    }

    private func dragEnded() {
        let target = AppController.shared.reflow(dragging: panel.frame, size: model.size)
        AppController.shared.endDrag()
        DropGhost.shared.hide()
        move(to: target, animated: true)
        model.runtime.isDragging = false
        DragState.shared.isDragging = false
        lastGhost = nil
        lastCell = nil
    }

    /// Slides the panel during someone else's drag without saving the position.
    func preview(at rect: CGRect) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(rect, display: true)
        }
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
    func ensureVisible(occupied: [CGRect]) {
        let rect = model.frame
        let onScreen = NSScreen.screens.contains { DesktopGrid.area(of: $0).intersects(rect.insetBy(dx: 30, dy: 30)) }
        if !onScreen {
            move(to: DesktopGrid.place(rect, size: model.size, occupied: occupied), animated: false)
        }
    }
}
