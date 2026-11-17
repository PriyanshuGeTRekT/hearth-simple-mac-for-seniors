import Foundation

// MARK: - installed apps

public struct AppInfo: Equatable, Identifiable, Hashable {
    public var id: String { bundleID }
    public let bundleID: String
    public let name: String
    public let path: String
}

public enum AppCatalog {
    public static var defaultRoots: [String] {
        ["/Applications", "/System/Applications", "/System/Applications/Utilities", NSHomeDirectory() + "/Applications"]
    }

    /// The handful of apps most people actually want, in the order they appear on a fresh setup.
    public static let recommended: [(bundleID: String, title: String, color: TileColor)] = [
        ("com.apple.MobileSMS", "Messages", .green),
        ("com.apple.mail", "Mail", .blue),
        ("com.apple.Safari", "The Internet", .teal),
        ("com.apple.Photos", "Photos", .pink),
        ("com.apple.iCal", "Calendar", .red),
        ("com.apple.Notes", "Notes", .orange),
        ("com.apple.Maps", "Maps", .green),
        ("com.apple.Music", "Music", .purple),
        ("com.apple.weather", "Weather", .blue),
    ]

    public static func installed(roots: [String] = defaultRoots) -> [AppInfo] {
        var out: [AppInfo] = []
        var seen = Set<String>()
        let fm = FileManager.default
        for root in roots {
            guard let items = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for item in items where item.hasSuffix(".app") {
                let path = root + "/" + item
                guard let info = NSDictionary(contentsOfFile: path + "/Contents/Info.plist") as? [String: Any],
                      let id = info["CFBundleIdentifier"] as? String, !seen.contains(id) else { continue }
                if (info["LSUIElement"] as? Bool) == true || (info["LSBackgroundOnly"] as? Bool) == true { continue }
                seen.insert(id)
                let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? String(item.dropLast(4))
                out.append(AppInfo(bundleID: id, name: name, path: path))
            }
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

extension HearthConfig {
    /// A sensible first screen: the helper to call, then the everyday apps that are installed.
    public static func starter(owner: String, helper: Person?, installed: Set<String>, maxTiles: Int = 8) -> HearthConfig {
        var c = HearthConfig()
        c.ownerName = owner
        if var h = helper {
            h.isHelper = true
            c.people = [h]
            c.tiles.append(.video(h))
        }
        for r in AppCatalog.recommended where installed.contains(r.bundleID) && c.tiles.count < maxTiles {
            c.tiles.append(.app(r.bundleID, r.title, color: r.color))
        }
        return c
    }
}

// MARK: - setup files (a family member prepares it on their own Mac and sends it over)

public enum SetupError: Error, CustomStringConvertible {
    case notASetupFile
    case tooNew(Int)
    public var description: String {
        switch self {
        case .notASetupFile: return "That file is not a Hearth setup file."
        case .tooNew(let v): return "That setup file (version \(v)) was made by a newer Hearth. Please update Hearth first."
        }
    }
}

public struct ImportResult {
    public var config: HearthConfig
    public var warnings: [String]
}

public enum SetupIO {
    public static let format = "hearth-setup"
    public static let currentVersion = 1
    public static let maxTiles = 30, maxPeople = 12, maxReminders = 30

    struct Envelope: Codable {
        var format: String
        var version: Int
        var config: HearthConfig
    }

    /// The PIN never travels: whoever receives the file sets their own.
    public static func export(_ c: HearthConfig) throws -> Data {
        var c = c
        c.pin = nil
        c.setupComplete = false
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(Envelope(format: format, version: currentVersion, config: c))
    }

    /// Parses and *sanitises* a setup file: unusable entries are dropped (and reported), never trusted.
    public static func read(_ data: Data) throws -> ImportResult {
        guard let env = try? JSONDecoder().decode(Envelope.self, from: data), env.format == format else { throw SetupError.notASetupFile }
        guard env.version <= currentVersion else { throw SetupError.tooNew(env.version) }
        var warnings: [String] = []
        var c = env.config
        c.pin = nil
        c.setupComplete = false
        c.version = currentVersion
        c.ownerName = String(c.ownerName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))

        var people: [Person] = []
        for var p in c.people.prefix(maxPeople) {
            p.name = String(p.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            guard !p.name.isEmpty, let h = Launching.normalizeHandle(p.handle) else {
                warnings.append("Skipped a person without a usable name or number: “\(p.name)”.")
                continue
            }
            p.handle = h
            p.relation = String(p.relation.prefix(40))
            if let ph = p.photoPath, !ph.hasPrefix("/") { p.photoPath = nil }
            people.append(p)
        }
        if c.people.count > maxPeople { warnings.append("Only the first \(maxPeople) people were kept.") }
        c.people = people

        var tiles: [Tile] = []
        for var t in c.tiles.prefix(maxTiles) {
            t.title = String(t.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            if t.title.isEmpty { warnings.append("Skipped a button without a name."); continue }
            if Launching.launch(for: t, people: people) == nil {
                warnings.append("Skipped “\(t.title)”: it does not point to anything usable.")
                continue
            }
            tiles.append(t)
        }
        if c.tiles.count > maxTiles { warnings.append("Only the first \(maxTiles) buttons were kept.") }
        c.tiles = tiles

        var reminders: [Reminder] = []
        for var r in c.reminders.prefix(maxReminders) {
            r.text = String(r.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
            guard !r.text.isEmpty, (0...23).contains(r.hour), (0...59).contains(r.minute) else {
                warnings.append("Skipped a reminder with an invalid time or text.")
                continue
            }
            r.weekdays = Array(Set(r.weekdays.filter { (1...7).contains($0) })).sorted()
            reminders.append(r)
        }
        c.reminders = reminders
        return ImportResult(config: c, warnings: warnings)
    }
}

// MARK: - photos

public enum Slideshow {
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "bmp", "webp"]

    /// Pictures in a folder and up to two levels of sub-folders (for example Year/Month), in name order.
    public static func images(in folder: String, limit: Int = 400) -> [String] {
        guard let en = FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var out: [String] = []
        for case let u as URL in en {
            if en.level > 3 { en.skipDescendants(); continue }
            if imageExtensions.contains(u.pathExtension.lowercased()) { out.append(u.path) }
            if out.count >= limit { break }
        }
        return out.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public static func wrap(_ index: Int, by delta: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((index + delta) % count + count) % count
    }
}
