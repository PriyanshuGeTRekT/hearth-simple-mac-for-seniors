import Foundation
import CryptoKit

// MARK: - PIN

/// The caregiver PIN keeps well-meaning mistakes out of the settings. It is a convenience lock, not a security
/// boundary: anyone with access to the user account can edit the config file.
public struct PinRecord: Codable, Equatable {
    public var salt: String
    public var hash: String
}

public enum Pin {
    public static func isValidFormat(_ pin: String) -> Bool {
        (4...8).contains(pin.count) && pin.allSatisfy { $0.isASCII && $0.isNumber }
    }

    static func digest(_ pin: String, salt: String) -> String {
        SHA256.hash(data: Data((salt + ":" + pin).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func make(_ pin: String, salt: String? = nil) -> PinRecord {
        let s = salt ?? UUID().uuidString
        return PinRecord(salt: s, hash: digest(pin, salt: s))
    }

    public static func verify(_ pin: String, against r: PinRecord) -> Bool {
        digest(pin, salt: r.salt) == r.hash
    }
}

// MARK: - what a button does

public enum Launch: Equatable {
    case app(bundleID: String)
    case url(URL)
    case slideshow(folder: String)
}

public protocol AppLauncher: AnyObject {
    func open(_ launch: Launch)
    /// Hide (never quit) every other app so the screen is calm again.
    func hideOtherApps()
    func bringHomeForward()
}

public enum Launching {
    public static func isEmail(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count <= 254, !t.contains(" ") else { return false }
        let parts = t.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix(".") else { return false }
        return true
    }

    /// Phone numbers become digits (with an optional leading +); emails are lower-cased. Anything else is rejected.
    public static func normalizeHandle(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if isEmail(t) { return t.lowercased() }
        var out = ""
        for (i, ch) in t.enumerated() {
            if ch == "+" && i == 0 { out.append(ch) }
            else if ch.isASCII && ch.isNumber { out.append(ch) }
            else if " -().".contains(ch) { continue }
            else { return nil }
        }
        let digits = out.filter { $0.isNumber }.count
        return (7...15).contains(digits) ? out : nil
    }

    /// Adds https:// when missing; only http(s) addresses with a real host are accepted.
    public static func normalizeWebsite(_ s: String) -> URL? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(" ") else { return nil }
        if !t.contains("://") { t = "https://" + t }
        guard let u = URL(string: t), let scheme = u.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = u.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        return u
    }

    public static func isPlausibleBundleID(_ s: String) -> Bool {
        s.range(of: #"^[A-Za-z0-9][A-Za-z0-9.\-_]{2,127}$"#, options: .regularExpression) != nil && s.contains(".")
    }

    public static func launch(for tile: Tile, people: [Person]) -> Launch? {
        let handle = people.first { $0.id == tile.personID }?.handle ?? tile.target
        switch tile.kind {
        case .app:
            return isPlausibleBundleID(tile.target) ? .app(bundleID: tile.target) : nil
        case .website:
            return normalizeWebsite(tile.target).map { .url($0) }
        case .video:
            return normalizeHandle(handle).flatMap { URL(string: "facetime://" + $0) }.map { .url($0) }
        case .call:
            return normalizeHandle(handle).flatMap { URL(string: "facetime-audio://" + $0) }.map { .url($0) }
        case .message:
            guard let h = normalizeHandle(handle) else { return nil }
            return (isEmail(h) ? URL(string: "imessage://" + h) : URL(string: "sms:" + h)).map { .url($0) }
        case .email:
            guard let h = normalizeHandle(handle), isEmail(h) else { return nil }
            return URL(string: "mailto:" + h).map { .url($0) }
        case .photos:
            return tile.target.hasPrefix("/") ? .slideshow(folder: tile.target) : nil
        }
    }

    /// Apps that must be allowed to come to the front for these buttons to work.
    public static func supportingBundleIDs(for tile: Tile) -> [String] {
        switch tile.kind {
        case .app: return [tile.target]
        case .video, .call: return ["com.apple.FaceTime"]
        case .message: return ["com.apple.MobileSMS"]
        case .email: return ["com.apple.mail"]
        case .website, .photos: return []
        }
    }
}

// MARK: - reminders

public enum Reminders {
    public static func isActive(_ r: Reminder, on day: Date, calendar: Calendar = .current) -> Bool {
        r.weekdays.isEmpty || r.weekdays.contains(calendar.component(.weekday, from: day))
    }

    public static func scheduledDate(_ r: Reminder, on day: Date, calendar: Calendar = .current) -> Date? {
        calendar.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: day)
    }

    /// Reminders that came due in (after, upTo]. Ones that are older than `grace` are dropped: if the Mac was asleep
    /// overnight, nobody wants yesterday's tablet reminder at breakfast.
    public static func due(_ rs: [Reminder], after: Date, upTo: Date, grace: TimeInterval = 3 * 3600,
                           calendar: Calendar = .current) -> [Reminder] {
        guard upTo > after else { return [] }
        var out: [Reminder] = []
        var day = calendar.startOfDay(for: after)
        let last = calendar.startOfDay(for: upTo)
        var n = 0
        while day <= last && n < 4 {
            for r in rs where isActive(r, on: day, calendar: calendar) {
                if let s = scheduledDate(r, on: day, calendar: calendar), s > after, s <= upTo, upTo.timeIntervalSince(s) <= grace {
                    out.append(r)
                }
            }
            guard let nd = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nd; n += 1
        }
        return out
    }

    public static func next(_ rs: [Reminder], after: Date, calendar: Calendar = .current) -> (reminder: Reminder, at: Date)? {
        var best: (Reminder, Date)?
        var day = calendar.startOfDay(for: after)
        for _ in 0..<8 {
            for r in rs where isActive(r, on: day, calendar: calendar) {
                if let s = scheduledDate(r, on: day, calendar: calendar), s > after, best == nil || s < best!.1 { best = (r, s) }
            }
            if best != nil { break }
            guard let nd = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nd
        }
        return best.map { (reminder: $0.0, at: $0.1) }
    }

    public static func timeText(hour: Int, minute: Int) -> String {
        var c = DateComponents(); c.hour = hour; c.minute = minute
        guard let d = Calendar.current.date(from: c) else { return String(format: "%d:%02d", hour, minute) }
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: d)
    }

    /// Today's reminders in time order, for the "Today" card.
    public static func today(_ rs: [Reminder], now: Date, calendar: Calendar = .current) -> [Reminder] {
        rs.filter { isActive($0, on: now, calendar: calendar) }.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }
}

// MARK: - strict mode

public struct StrictPolicy {
    /// System components that legitimately come to the front (password prompts, notifications, the Dock…).
    public static let systemUI: Set<String> = [
        "com.apple.dock", "com.apple.loginwindow", "com.apple.UserNotificationCenter", "com.apple.notificationcenterui",
        "com.apple.controlcenter", "com.apple.SecurityAgent", "com.apple.CoreServicesUIAgent", "com.apple.universalaccessd",
        "com.apple.systemuiserver", "com.apple.accessibility.universalAccessAuthWarn", "com.apple.screencaptureui",
        "com.apple.ScreenSaver.Engine", "com.apple.wifi.WiFiAgent", "com.apple.bluetoothUIServer", "com.apple.print.add",
    ]

    public var allowed: Set<String>
    public init(allowed: Set<String>) { self.allowed = allowed }

    public static func allowedBundleIDs(config: HearthConfig, defaultBrowser: String?) -> Set<String> {
        var s = Set<String>()
        for t in config.tiles {
            s.formUnion(Launching.supportingBundleIDs(for: t))
            if t.kind == .website, let b = defaultBrowser { s.insert(b) }
        }
        return s
    }

    public func shouldReturnHome(frontmost bundleID: String?, ownBundleID: String?) -> Bool {
        guard let b = bundleID else { return false }
        if b == ownBundleID || StrictPolicy.systemUI.contains(b) || allowed.contains(b) { return false }
        return true
    }
}

// MARK: - words

public enum Words {
    public static func greeting(name: String, now: Date, calendar: Calendar = .current) -> String {
        let h = calendar.component(.hour, from: now)
        let part = h < 5 ? "Hello" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening"
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? part : "\(part), \(n)"
    }

    public static func longDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMMM d"
        return f.string(from: d)
    }

    public static func clock(_ d: Date) -> String {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: d)
    }
}
