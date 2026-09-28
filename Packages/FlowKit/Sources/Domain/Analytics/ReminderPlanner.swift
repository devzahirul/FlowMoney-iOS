public import Foundation

/// Decides which local notifications should be pending. Pure, so the rules are unit-tested; the platform
/// scheduler only mirrors this list (iOS caps pending requests at 64, hence `limit`).
public enum ReminderPlanner {
    public static let reminderHour = 9
    public static let horizonDays = 35

    public static func reminders(for snapshot: LedgerSnapshot, now: Date, calendar: Calendar, limit: Int = 50) -> [Reminder] {
        var reminders: [Reminder] = []
        let horizon = calendar.date(byAdding: .day, value: horizonDays, to: now) ?? now
        let currency = snapshot.currency

        for rule in snapshot.recurringRules where rule.isSubscription && !rule.isPaused && rule.kind == .expense {
            for due in rule.occurrences(from: now, through: horizon, calendar: calendar) {
                guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: due)),
                      let fire = calendar.date(bySettingHour: reminderHour, minute: 0, second: 0, of: dayBefore),
                      fire > now else { continue }
                let day = calendar.dateComponents([.year, .month, .day], from: due)
                reminders.append(Reminder(
                    id: "renewal-\(rule.id.uuidString)-\(day.year ?? 0)\(day.month ?? 0)\(day.day ?? 0)",
                    title: "\(rule.name) renews tomorrow",
                    body: "\(currency.string(rule.amount)) will be charged.",
                    fireDate: fire
                ))
            }
        }

        // Next Monday 9:00 — a nudge to review last week.
        var monday = DateComponents()
        monday.weekday = 2
        monday.hour = reminderHour
        if let next = calendar.nextDate(after: now, matching: monday, matchingPolicy: .nextTime) {
            reminders.append(Reminder(
                id: "weekly-summary",
                title: "Your weekly summary is ready",
                body: "See where your money went last week.",
                fireDate: next
            ))
        }
        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }
}
