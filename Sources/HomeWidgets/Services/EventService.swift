import AppKit
import EventKit
import SwiftUI
import Combine

/// Calendar events and reminders via EventKit.
final class EventService: ObservableObject {
    static let shared = EventService()

    enum Access: Equatable {
        case unknown, granted, denied, unavailable
    }

    struct Event: Identifiable, Equatable {
        let id: String
        let title: String
        let start: Date
        let end: Date
        let isAllDay: Bool
        let color: Color
        let location: String?
    }

    struct Reminder: Identifiable, Equatable {
        let id: String
        let title: String
        let due: Date?
        let color: Color
        let list: String
        let priority: Int

        var isOverdue: Bool {
            guard let due else { return false }
            return due < Date() && !Calendar.current.isDateInToday(due)
        }
    }

    @Published private(set) var eventAccess: Access = .unknown
    @Published private(set) var reminderAccess: Access = .unknown
    @Published private(set) var events: [Event] = []
    @Published private(set) var reminders: [Reminder] = []

    private let store = EKEventStore()
    private var eventClients = 0
    private var reminderClients = 0
    private var cancellables = Set<AnyCancellable>()

    init() {
        NotificationCenter.default.publisher(for: .EKEventStoreChanged, object: store)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        Timer.publish(every: 300, tolerance: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: .NSCalendarDayChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.reload() }
            .store(in: &cancellables)
    }

    // MARK: Subscriptions

    func retainEvents() {
        eventClients += 1
        if eventClients == 1 { requestEventAccess() }
    }

    func releaseEvents() {
        eventClients = max(0, eventClients - 1)
    }

    func retainReminders() {
        reminderClients += 1
        if reminderClients == 1 { requestReminderAccess() }
    }

    func releaseReminders() {
        reminderClients = max(0, reminderClients - 1)
    }

    func reload() {
        if eventClients > 0 { reloadEvents() }
        if reminderClients > 0 { reloadReminders() }
    }

    // MARK: Access

    private var canAsk: Bool { Shell.isBundled }

    func requestEventAccess() {
        guard canAsk, Shell.hasUsageDescription("NSCalendarsFullAccessUsageDescription") else {
            eventAccess = .unavailable
            return
        }
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            eventAccess = .granted
            reloadEvents()
        case .notDetermined:
            store.requestFullAccessToEvents { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.eventAccess = granted ? .granted : .denied
                    if granted { self?.reloadEvents() }
                }
            }
        default:
            eventAccess = .denied
        }
    }

    func requestReminderAccess() {
        guard canAsk, Shell.hasUsageDescription("NSRemindersFullAccessUsageDescription") else {
            reminderAccess = .unavailable
            return
        }
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess:
            reminderAccess = .granted
            reloadReminders()
        case .notDetermined:
            store.requestFullAccessToReminders { [weak self] granted, _ in
                DispatchQueue.main.async {
                    self?.reminderAccess = granted ? .granted : .denied
                    if granted { self?.reloadReminders() }
                }
            }
        default:
            reminderAccess = .denied
        }
    }

    // MARK: Loading

    private func reloadEvents() {
        guard eventAccess == .granted else { return }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 8, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let items = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(80)
            .map { event -> Event in
                let identifier = event.eventIdentifier ?? UUID().uuidString
                return Event(id: "\(identifier)-\(event.startDate.timeIntervalSince1970)",
                             title: event.title ?? "Untitled",
                             start: event.startDate,
                             end: event.endDate,
                             isAllDay: event.isAllDay,
                             color: Color(nsColor: event.calendar?.color ?? .systemRed),
                             location: event.location)
            }
        let list = Array(items)
        if list != events { events = list }
    }

    private func reloadReminders() {
        guard reminderAccess == .granted else { return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        _ = store.fetchReminders(matching: predicate) { [weak self] found in
            let calendar = Calendar.current
            let items = (found ?? []).map { reminder -> Reminder in
                let due = reminder.dueDateComponents.flatMap { calendar.date(from: $0) }
                return Reminder(id: reminder.calendarItemIdentifier,
                                title: reminder.title ?? "",
                                due: due,
                                color: Color(nsColor: reminder.calendar?.color ?? .systemOrange),
                                list: reminder.calendar?.title ?? "",
                                priority: reminder.priority)
            }
            let sorted = items.sorted { lhs, rhs in
                switch (lhs.due, rhs.due) {
                case let (left?, right?): return left < right
                case (.some, .none): return true
                case (.none, .some): return false
                default: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if sorted != self.reminders { self.reminders = sorted }
            }
        }
    }

    // MARK: Actions

    func complete(_ reminderID: String) {
        guard let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
            reminders.removeAll { $0.id == reminderID }
        } catch {
            NSSound.beep()
        }
    }

    // MARK: Samples for the gallery

    static var sampleEvents: [Event] {
        let start = Calendar.current.startOfDay(for: Date())
        return [
            Event(id: "1", title: "Bible Study", start: start.addingTimeInterval(19 * 3600), end: start.addingTimeInterval(20 * 3600),
                  isAllDay: false, color: .orange, location: nil),
            Event(id: "2", title: "Basketball Practice", start: start.addingTimeInterval(40 * 3600), end: start.addingTimeInterval(42 * 3600),
                  isAllDay: false, color: .blue, location: "Gym"),
            Event(id: "3", title: "Math Test", start: start.addingTimeInterval(57 * 3600), end: start.addingTimeInterval(58 * 3600),
                  isAllDay: false, color: .purple, location: nil),
        ]
    }

    static var sampleReminders: [Reminder] {
        [
            Reminder(id: "1", title: "Finish history essay", due: Date().addingTimeInterval(3600), color: .orange, list: "School", priority: 1),
            Reminder(id: "2", title: "Call grandma", due: nil, color: .blue, list: "Personal", priority: 0),
            Reminder(id: "3", title: "Push widget code", due: Date().addingTimeInterval(86400), color: .green, list: "Projects", priority: 0),
            Reminder(id: "4", title: "Return library book", due: nil, color: .orange, list: "School", priority: 0),
        ]
    }
}
