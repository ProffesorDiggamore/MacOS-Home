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

    private func schedule() {
        let every = max(0.5, interval)
        timer = Timer.publish(every: every, tolerance: every * 0.15, on: .main, in: .common)
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

private struct MonitorSubscription: ViewModifier {
    let monitors: [PollingMonitor]

    func body(content: Content) -> some View {
        content
            .onAppear { monitors.forEach { $0.retain() } }
            .onDisappear { monitors.forEach { $0.release() } }
    }
}

extension View {
    /// Keeps the given monitors running while this view is on screen.
    func monitoring(_ monitors: PollingMonitor...) -> some View {
        modifier(MonitorSubscription(monitors: monitors))
    }
}
