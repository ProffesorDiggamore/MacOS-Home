import AppKit
import SwiftUI

/// The desktop grid every widget lives on, like the Home Screen on an iPhone.
///
/// Version 2 only nudged widgets toward their neighbours, so two widgets could
/// still end up on top of each other. Now every widget occupies whole cells:
/// a drag shows where it will land, and it always lands in free space.
struct DesktopGrid {
    static let pitch = WidgetSize.unit + WidgetSize.spacing
    static let margin: CGFloat = 20

    let bounds: CGRect // the screen's visible frame (AppKit coordinates, y up)
    let columns: Int
    let rows: Int

    init(bounds: CGRect) {
        self.bounds = bounds
        let area = bounds.insetBy(dx: Self.margin, dy: Self.margin)
        columns = max(1, Int((area.width + WidgetSize.spacing) / Self.pitch))
        rows = max(1, Int((area.height + WidgetSize.spacing) / Self.pitch))
    }

    private var originX: CGFloat { bounds.minX + Self.margin }

    private var topY: CGFloat { bounds.maxY - Self.margin }

    struct Cell: Hashable {
        var column: Int
        var row: Int
    }

    func rect(at cell: Cell, size: WidgetSize) -> CGRect {
        let dimensions = size.dimensions
        return CGRect(x: originX + CGFloat(cell.column) * Self.pitch,
                      y: topY - CGFloat(cell.row) * Self.pitch - dimensions.height,
                      width: dimensions.width,
                      height: dimensions.height)
    }

    func fits(_ cell: Cell, size: WidgetSize) -> Bool {
        let span = size.cells
        return cell.column >= 0 && cell.row >= 0 && cell.column + span.columns <= columns && cell.row + span.rows <= rows
    }

    /// The cell whose slot is closest to where the rect is now.
    func nearestCell(to rect: CGRect, size: WidgetSize) -> Cell {
        let span = size.cells
        let column = Int(((rect.minX - originX) / Self.pitch).rounded())
        let row = Int(((topY - rect.maxY) / Self.pitch).rounded())
        return Cell(column: min(max(0, column), max(0, columns - span.columns)),
                    row: min(max(0, row), max(0, rows - span.rows)))
    }

    func isFree(_ cell: Cell, size: WidgetSize, occupied: [CGRect]) -> Bool {
        guard fits(cell, size: size) else { return false }
        let candidate = rect(at: cell, size: size).insetBy(dx: 2, dy: 2)
        return !occupied.contains { $0.intersects(candidate) }
    }

    /// The free slot nearest to `wanted` (by distance between slots), if any.
    func nearestFree(to wanted: Cell, size: WidgetSize, occupied: [CGRect]) -> Cell? {
        if isFree(wanted, size: size, occupied: occupied) { return wanted }
        var best: (Cell, Int)?
        for row in 0..<rows {
            for column in 0..<columns {
                let cell = Cell(column: column, row: row)
                let distance = (column - wanted.column) * (column - wanted.column) + (row - wanted.row) * (row - wanted.row)
                if let current = best, distance >= current.1 { continue }
                if isFree(cell, size: size, occupied: occupied) { best = (cell, distance) }
            }
        }
        return best?.0
    }

    /// First free slot reading down each column from the top-left, like Apple's desktop widgets.
    func firstFree(size: WidgetSize, occupied: [CGRect]) -> Cell? {
        for column in 0..<columns {
            for row in 0..<rows {
                let cell = Cell(column: column, row: row)
                if isFree(cell, size: size, occupied: occupied) { return cell }
            }
        }
        return nil
    }

    static func screen(containing rect: CGRect) -> NSScreen? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.screens.max { $0.frame.intersection(rect).area < $1.frame.intersection(rect).area }
    }

    /// The screen below the menu bar, including the strip beside a bottom Dock, so the
    /// bottom row can sit next to the Dock. Widgets on the desktop layer stay behind it.
    static func area(of screen: NSScreen?) -> CGRect {
        guard let screen else { return CGRect(x: 0, y: 0, width: 1440, height: 900) }
        let visible = screen.visibleFrame
        return CGRect(x: visible.minX, y: screen.frame.minY, width: visible.width, height: visible.maxY - screen.frame.minY)
    }

    static func forRect(_ rect: CGRect) -> DesktopGrid {
        DesktopGrid(bounds: area(of: screen(containing: rect) ?? NSScreen.main ?? NSScreen.screens.first))
    }

    /// Where a widget of `size` near `rect` should go, avoiding `occupied`.
    /// Falls back to the main screen, then to staying put, so nothing ever disappears.
    static func place(_ rect: CGRect, size: WidgetSize, occupied: [CGRect]) -> CGRect {
        let grid = forRect(rect)
        if let cell = grid.nearestFree(to: grid.nearestCell(to: rect, size: size), size: size, occupied: occupied) {
            return grid.rect(at: cell, size: size)
        }
        for screen in NSScreen.screens {
            let other = DesktopGrid(bounds: area(of: screen))
            if let cell = other.firstFree(size: size, occupied: occupied) { return other.rect(at: cell, size: size) }
        }
        return rect
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

/// The soft "it'll go here" slot shown under a widget while you drag it.
@MainActor
final class DropGhost {
    static let shared = DropGhost()

    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        let host = NSHostingView(rootView: GhostSlot())
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }()

    private var shown = false

    func show(_ rect: CGRect, below window: NSWindow) {
        panel.level = window.level
        if !shown {
            panel.setFrame(rect, display: true)
            panel.alphaValue = 0
            panel.order(.below, relativeTo: window.windowNumber)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel.animator().alphaValue = 1
            }
            shown = true
        } else if panel.frame != rect {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(rect, display: true)
            }
            panel.order(.below, relativeTo: window.windowNumber)
        }
    }

    func hide() {
        guard shown else { return }
        shown = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            MainActor.assumeIsolated { panel.orderOut(nil) }
        })
    }
}

private struct GhostSlot: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        shape
            .fill(Color.white.opacity(0.10))
            .overlay(shape.strokeBorder(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])))
            .background(shape.fill(.ultraThinMaterial).opacity(0.5))
            .padding(1)
    }
}
