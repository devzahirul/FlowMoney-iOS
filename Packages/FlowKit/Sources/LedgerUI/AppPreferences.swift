public import Foundation
public import Observation
public import SwiftUI

public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Device-local settings (not synced: app lock and notification choices are per-device by design).
@MainActor
@Observable
public final class AppPreferences {
    private let defaults: UserDefaults

    public var appearance: AppearancePreference {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    public var appLockEnabled: Bool {
        didSet { defaults.set(appLockEnabled, forKey: Keys.appLock) }
    }

    /// Blurs balances on screen (screen-sharing, public places).
    public var hideAmounts: Bool {
        didSet { defaults.set(hideAmounts, forKey: Keys.hideAmounts) }
    }

    public var remindersEnabled: Bool {
        didSet { defaults.set(remindersEnabled, forKey: Keys.reminders) }
    }

    public private(set) var readAlertIDs: Set<String> {
        didSet { defaults.set(Array(readAlertIDs.suffix(500)), forKey: Keys.readAlerts) }
    }

    public private(set) var recentSearches: [String] {
        didSet { defaults.set(recentSearches, forKey: Keys.recentSearches) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppearancePreference.init) ?? .system
        appLockEnabled = defaults.bool(forKey: Keys.appLock)
        hideAmounts = defaults.bool(forKey: Keys.hideAmounts)
        remindersEnabled = defaults.bool(forKey: Keys.reminders)
        readAlertIDs = Set(defaults.stringArray(forKey: Keys.readAlerts) ?? [])
        recentSearches = defaults.stringArray(forKey: Keys.recentSearches) ?? []
    }

    public func markRead(_ ids: some Sequence<String>) {
        readAlertIDs.formUnion(ids)
    }

    public func addRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        recentSearches = Array(([trimmed] + recentSearches.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }).prefix(8))
    }

    public func clearRecentSearches() {
        recentSearches = []
    }

    /// Wipes device-local state on sign-out so the next user starts clean.
    public func reset() {
        appLockEnabled = false
        hideAmounts = false
        remindersEnabled = false
        readAlertIDs = []
        recentSearches = []
    }

    enum Keys {
        static let appearance = "pref.appearance"
        static let appLock = "pref.appLock"
        static let hideAmounts = "pref.hideAmounts"
        static let reminders = "pref.reminders"
        static let readAlerts = "pref.readAlerts"
        static let recentSearches = "pref.recentSearches"
    }
}
