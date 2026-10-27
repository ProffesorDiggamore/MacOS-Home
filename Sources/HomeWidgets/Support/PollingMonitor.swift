import Foundation
import Combine
import SwiftUI

/// Base class for anything that samples the system on a timer.
///
/// Monitors only run while at least one visible widget is using them, so a
/// CPU graph you never added costs nothing. Widgets call `retain()` when they
/// appear and `release()` when they go away (see `.monitoring(...)`).
class PollingMonitor: ObservableObject {
    private var clients = 0
    private var timer: AnyCancellable?
    private var intervalObserver: AnyCancellable?

    /// Seconds between samples. Subclasses can override.
    var interval: TimeInterval { AppearanceSettings.shared.refreshInterval }

    var isActive: Bool { clients > 0 }

    func retain() {
        clients += 1
        if clients == 1 { start() }
    }

    func release() {
        clients = max(0, clients - 1)
        if clients == 0 { stop() }
    }

    /// Take a sample right now (e.g. after a user action).
    func refresh() {
        if isActive { sample() }
    }

    private func start() {
        sample()
        schedule()
        intervalObserver = AppearanceSettings.shared.$refreshInterval
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.schedule() }
    }

    /// Picks up a changed `interval` (e.g. a player that started or stopped playing).
    func reschedule() {
        if isActive { schedule() }
    }

    private func schedule() {
        let every = max(0.5, interval)
        // Generous tolerance lets macOS fire several monitors' timers in one wake-up.
        timer = Timer.publish(every: every, tolerance: every * 0.3, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sample() }
    }

    private func stop() {
        timer = nil
        intervalObserver = nil
        didStop()
    }

    /// Override to collect data. Always called on the main thread.
    func sample() {}

    /// Override to clean up when nobody is watching anymore.
    func didStop() {}
}

/// Keeps a rolling window of samples for sparkline graphs.
struct MetricHistory: Equatable {
    var capacity = 60
    private(set) var values: [Double] = []

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    var peak: Double { values.max() ?? 0 }
}

/// Holds a monitor only while the widget is both on screen *and* not covered by windows.
/// Before, a CPU graph hidden behind a full-screen browser kept sampling every second.
private struct MonitorSubscription: ViewModifier {
    let monitors: [PollingMonitor]
    @Environment(\.widgetIsVisible) private var visible
    @State private var appeared = false
    @State private var holding = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                appeared = true
                update()
            }
            .onDisappear {
                appeared = false
                update()
            }
            .onChange(of: visible) { _, _ in update() }
    }

    private func update() {
        let want = appeared && visible && !monitors.isEmpty
        guard want != holding else { return }
        holding = want
        monitors.forEach { want ? $0.retain() : $0.release() }
    }
}

extension View {
    /// Keeps the given monitors running while this view is on screen.
    func monitoring(_ monitors: PollingMonitor...) -> some View {
        modifier(MonitorSubscription(monitors: monitors))
    }

    /// Like `monitoring`, but only when `condition` is true (e.g. not in gallery previews).
    func monitoring(if condition: Bool, _ monitors: PollingMonitor...) -> some View {
        modifier(MonitorSubscription(monitors: condition ? monitors : []))
    }
}
