import Foundation
import Combine

public protocol Speaker: AnyObject {
    func say(_ text: String)
}

public enum UnlockResult: Equatable {
    case unlocked
    case noPinSet
    case wrong(attemptsLeft: Int)
    case lockedOut(seconds: Int)
}

/// Everything the home screen *does*. The views only display this and forward taps to it.
@MainActor
public final class HearthModel: ObservableObject {
    public enum Screen: Equatable {
        case home
        case help
        case slideshow(String)
    }

    @Published public private(set) var config: HearthConfig
    @Published public var screen: Screen = .home
    /// A short, kind sentence shown on the home screen ("That one isn't set up for you yet…").
    @Published public var statusLine: String?
    @Published public private(set) var activeReminder: Reminder?
    @Published public private(set) var caregiverUnlocked = false
    @Published public private(set) var strictPausedUntil: Date?
    @Published public private(set) var now: Date

    public let store: ConfigStore?
    public weak var launcher: AppLauncher?
    public weak var speaker: Speaker?
    public var clock: () -> Date
    public var calendar = Calendar.current
    public var defaultBrowserID: () -> String? = { nil }
    public var ownBundleID: String? = Bundle.main.bundleIdentifier
    /// Set by the app: opens the (PIN-protected) caregiver settings.
    public var onRequestCaregiver: (() -> Void)?

    private var lastTick: Date
    private var doneOn: [UUID: Date] = [:]
    private var snoozedUntil: [UUID: Date] = [:]
    private var queue: [Reminder] = []
    private var failedPins = 0
    private var lockedUntil: Date?

    public init(config: HearthConfig, store: ConfigStore? = nil, launcher: AppLauncher? = nil,
                clock: @escaping () -> Date = { Date() }) {
        self.config = config
        self.store = store
        self.launcher = launcher
        self.clock = clock
        let t = clock()
        self.now = t
        self.lastTick = t.addingTimeInterval(-600) // a reminder that came due a few minutes before launch still shows
    }

    // MARK: words

    public var helperName: String { config.helper?.name ?? "your family" }
    public var greeting: String { Words.greeting(name: config.ownerName, now: now, calendar: calendar) }
    public var dateText: String { Words.longDate(now) }
    public var clockText: String { Words.clock(now) }

    // MARK: buttons

    public func open(_ tile: Tile) {
        guard let l = Launching.launch(for: tile, people: config.people) else {
            statusLine = "That button isn't set up properly. Please ask \(helperName)."
            return
        }
        statusLine = nil
        if case .slideshow(let folder) = l {
            if Slideshow.images(in: folder, limit: 1).isEmpty { statusLine = "There are no photos in that folder yet."; return }
            screen = .slideshow(folder)
            return
        }
        launcher?.open(l)
    }

    /// The Home button: calm the screen and come back to the start.
    public func goHome() {
        screen = .home
        statusLine = nil
        launcher?.hideOtherApps()
        launcher?.bringHomeForward()
    }

    public func showHelp() { screen = .help; statusLine = nil }
    public func requestCaregiver() { onRequestCaregiver?() }
    public func closeScreen() { screen = .home }

    public func callHelper(video: Bool = true) {
        guard let h = config.helper else { statusLine = "Nobody has been added to call yet."; return }
        open(video ? .video(h) : .call(h))
    }

    // MARK: reminders

    /// Call about once a second.
    public func tick() {
        let t = clock()
        now = t
        if let p = strictPausedUntil, t >= p { strictPausedUntil = nil }
        var due = Reminders.due(config.reminders, after: lastTick, upTo: t, calendar: calendar)
        lastTick = t
        for (id, until) in snoozedUntil where until <= t {
            if let r = config.reminders.first(where: { $0.id == id }) { due.append(r) }
            snoozedUntil[id] = nil
        }
        let today = calendar.startOfDay(for: t)
        for r in due where doneOn[r.id] != today && activeReminder?.id != r.id && !queue.contains(where: { $0.id == r.id }) {
            queue.append(r)
        }
        presentNextReminderIfIdle()
    }

    private func presentNextReminderIfIdle() {
        guard activeReminder == nil, !queue.isEmpty else { return }
        let r = queue.removeFirst()
        activeReminder = r
        screen = .home
        launcher?.bringHomeForward()
        if r.speak { speaker?.say("It is time. \(r.text)") }
    }

    public func completeReminder() {
        if let r = activeReminder { doneOn[r.id] = calendar.startOfDay(for: clock()) }
        activeReminder = nil
        presentNextReminderIfIdle()
    }

    public func snoozeReminder(minutes: Int = 10) {
        if let r = activeReminder { snoozedUntil[r.id] = clock().addingTimeInterval(Double(minutes) * 60) }
        activeReminder = nil
        presentNextReminderIfIdle()
    }

    public func isDone(_ r: Reminder) -> Bool { doneOn[r.id] == calendar.startOfDay(for: now) }

    public var todayReminders: [Reminder] { Reminders.today(config.reminders, now: now, calendar: calendar) }

    // MARK: caregiver

    public var hasPin: Bool { config.pin != nil }

    public func unlockCaregiver(pin: String) -> UnlockResult {
        guard let rec = config.pin else { caregiverUnlocked = true; return .noPinSet }
        let t = clock()
        if let until = lockedUntil, t < until { return .lockedOut(seconds: Int(until.timeIntervalSince(t).rounded(.up))) }
        if Pin.verify(pin, against: rec) {
            failedPins = 0; lockedUntil = nil; caregiverUnlocked = true
            return .unlocked
        }
        failedPins += 1
        if failedPins >= 5 {
            failedPins = 0; lockedUntil = t.addingTimeInterval(30)
            return .lockedOut(seconds: 30)
        }
        return .wrong(attemptsLeft: 5 - failedPins)
    }

    public func lockCaregiver() { caregiverUnlocked = false }

    /// Changes are allowed while setting up (no PIN yet) or after the caregiver unlocked.
    public var canEdit: Bool { caregiverUnlocked || config.pin == nil }

    @discardableResult
    public func update(_ change: (inout HearthConfig) -> Void) -> Bool {
        guard canEdit else { return false }
        var c = config
        change(&c)
        config = c
        try? store?.save(c)
        return true
    }

    @discardableResult
    public func setPin(_ pin: String) -> Bool {
        guard Pin.isValidFormat(pin), canEdit else { return false }
        return update { $0.pin = Pin.make(pin) }
    }

    public func completeSetup() { update { $0.setupComplete = true } }

    /// For when the caregiver needs the whole Mac (System Settings, an update…) while strict mode is on.
    public func pauseStrictMode(minutes: Int) {
        guard caregiverUnlocked else { return }
        strictPausedUntil = clock().addingTimeInterval(Double(minutes) * 60)
    }

    // MARK: strict mode

    /// Called whenever another app comes to the front. Returns true if the person was sent home.
    @discardableResult
    public func frontmostChanged(bundleID: String?) -> Bool {
        guard config.strictMode, config.setupComplete, !caregiverUnlocked, strictPausedUntil == nil else { return false }
        let policy = StrictPolicy(allowed: StrictPolicy.allowedBundleIDs(config: config, defaultBrowser: defaultBrowserID()))
        guard policy.shouldReturnHome(frontmost: bundleID, ownBundleID: ownBundleID) else { return false }
        goHome()
        statusLine = "That one isn't set up for you yet. Ask \(helperName) to add it."
        return true
    }

    // MARK: setup files

    public func exportSetup() throws -> Data { try SetupIO.export(config) }

    /// Replaces buttons, people, reminders and look-and-feel; keeps this Mac's PIN. Returns what was skipped.
    @discardableResult
    public func importSetup(_ data: Data) throws -> [String] {
        let r = try SetupIO.read(data)
        guard canEdit else { return ["The caregiver PIN is needed to change the setup."] }
        update { c in
            let pin = c.pin, done = c.setupComplete
            c = r.config
            c.pin = pin
            c.setupComplete = done
        }
        return r.warnings
    }
}
