import Foundation
import EventKit
import SwiftUI
import AppKit

struct DayEvent: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let allDay: Bool
    let color: Color
}

@MainActor
final class CalendarService: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var revision = 0

    var onUpcoming: ((DayEvent, Int) -> Void)?

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    private var alerted: Set<String> = []
    private var cache: [Date: [DayEvent]] = [:]
    private let isDemo: Bool

    init(demo: Bool = false) {
        isDemo = demo
        if demo { access = .granted } else { refreshAccess() }
    }

    func start() {
        guard !isDemo else { return }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.cache.removeAll()
                self?.revision += 1
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkUpcoming() }
        }
    }

    private func refreshAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .denied, .restricted, .writeOnly: access = .denied
        default: access = .unknown
        }
    }

    func requestAccess() {
        if access == .denied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        Task { @MainActor in
            let granted = (try? await store.requestFullAccessToEvents()) ?? false
            access = granted ? .granted : .denied
            cache.removeAll()
            revision += 1
        }
    }

    func events(on day: Date) -> [DayEvent] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        if isDemo { return demoEvents(start) }
        guard access == .granted else { return [] }
        if let hit = cache[start] { return hit }
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let list = store.events(matching: predicate)
            .sorted { ($0.startDate ?? start) < ($1.startDate ?? start) }
            .map { event in
                DayEvent(id: event.eventIdentifier ?? UUID().uuidString,
                         title: event.title ?? "",
                         start: event.startDate ?? start,
                         end: event.endDate ?? start,
                         allDay: event.isAllDay,
                         color: Color(cgColor: event.calendar?.cgColor ?? CGColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)))
            }
        cache[start] = list
        return list
    }

    func hasEvents(on day: Date) -> Bool { !events(on: day).isEmpty }

    private func checkUpcoming() {
        let settings = Settings.shared
        guard settings.calendarEnabled, settings.calendarAlerts, access == .granted else { return }
        let lead = Double(max(1, settings.calendarAlertMinutes) * 60)
        let now = Date()
        for event in events(on: now) where !event.allDay {
            let gap = event.start.timeIntervalSince(now)
            if gap > 0, gap <= lead + 20, !alerted.contains(event.id) {
                alerted.insert(event.id)
                onUpcoming?(event, max(1, Int((gap / 60).rounded())))
            }
        }
    }

    private func demoEvents(_ day: Date) -> [DayEvent] {
        let calendar = Calendar.current
        guard calendar.isDateInToday(day) else { return [] }
        func at(_ h: Int, _ m: Int) -> Date { calendar.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day }
        return [
            DayEvent(id: "1", title: tr("Diseño de la app", "App design"), start: at(10, 0), end: at(11, 0), allDay: false, color: .orbitBlue),
            DayEvent(id: "2", title: tr("Almuerzo con Ana", "Lunch with Ana"), start: at(13, 30), end: at(14, 30), allDay: false, color: .orbitGreen),
            DayEvent(id: "3", title: tr("Gimnasio", "Gym"), start: at(18, 0), end: at(19, 0), allDay: false, color: .orange)
        ]
    }
}
