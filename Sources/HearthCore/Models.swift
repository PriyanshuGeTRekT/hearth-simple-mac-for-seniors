import Foundation

public enum TileKind: String, Codable, CaseIterable {
    case app, website, video, call, message, email, photos
}

public enum TileColor: String, Codable, CaseIterable {
    case blue, green, orange, red, purple, teal, pink, gray
}

public enum ThemeChoice: String, Codable, CaseIterable {
    case light, dark, highContrast
    public var label: String {
        switch self { case .light: return "Light"; case .dark: return "Dark"; case .highContrast: return "High contrast" }
    }
}

public enum TextSize: String, Codable, CaseIterable {
    case large, larger, largest
    public var scale: Double {
        switch self { case .large: return 1.0; case .larger: return 1.25; case .largest: return 1.5 }
    }
    public var label: String {
        switch self { case .large: return "Large"; case .larger: return "Larger"; case .largest: return "Largest" }
    }
}

public struct Person: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    /// A phone number (kept as digits, with a leading + if given) or an Apple ID / email address.
    public var handle: String
    /// "daughter", "neighbour"… shown under the name on the Help screen.
    public var relation: String
    public var photoPath: String?
    public var isHelper: Bool

    public init(id: UUID = UUID(), name: String, handle: String, relation: String = "", photoPath: String? = nil, isHelper: Bool = false) {
        self.id = id; self.name = name; self.handle = handle; self.relation = relation
        self.photoPath = photoPath; self.isHelper = isHelper
    }

    public var initials: String {
        let parts = name.split(separator: " ").prefix(2).compactMap { $0.first }
        return String(parts).uppercased()
    }
}

public struct Tile: Codable, Identifiable, Equatable {
    public var id: UUID
    public var kind: TileKind
    public var title: String
    /// bundle identifier (app) · web address (website) · phone/email (video, call, message, email) · folder (photos)
    public var target: String
    public var personID: UUID?
    public var symbol: String?
    public var color: TileColor

    public init(id: UUID = UUID(), kind: TileKind, title: String, target: String, personID: UUID? = nil,
                symbol: String? = nil, color: TileColor = .blue) {
        self.id = id; self.kind = kind; self.title = title; self.target = target
        self.personID = personID; self.symbol = symbol; self.color = color
    }

    public static func app(_ bundleID: String, _ title: String, color: TileColor = .blue) -> Tile {
        Tile(kind: .app, title: title, target: bundleID, color: color)
    }
    public static func website(_ url: String, _ title: String, color: TileColor = .teal) -> Tile {
        Tile(kind: .website, title: title, target: url, symbol: "globe", color: color)
    }
    public static func video(_ p: Person, color: TileColor = .green) -> Tile {
        Tile(kind: .video, title: p.name, target: p.handle, personID: p.id, symbol: "video.fill", color: color)
    }
    public static func call(_ p: Person, color: TileColor = .green) -> Tile {
        Tile(kind: .call, title: "Phone \(p.name)", target: p.handle, personID: p.id, symbol: "phone.fill", color: color)
    }
    public static func photos(_ folder: String, _ title: String = "Family photos", color: TileColor = .pink) -> Tile {
        Tile(kind: .photos, title: title, target: folder, symbol: "photo.on.rectangle.angled", color: color)
    }
}

public struct Reminder: Codable, Identifiable, Equatable {
    public var id: UUID
    public var text: String
    public var hour: Int
    public var minute: Int
    /// Calendar weekdays (1 = Sunday … 7 = Saturday). Empty means every day.
    public var weekdays: [Int]
    public var speak: Bool

    public init(id: UUID = UUID(), text: String, hour: Int, minute: Int = 0, weekdays: [Int] = [], speak: Bool = true) {
        self.id = id; self.text = text; self.hour = hour; self.minute = minute; self.weekdays = weekdays; self.speak = speak
    }
}

public struct HearthConfig: Codable, Equatable {
    public var version = 1
    public var ownerName = ""
    public var people: [Person] = []
    public var tiles: [Tile] = []
    public var reminders: [Reminder] = []
    public var textSize: TextSize = .large
    public var theme: ThemeChoice = .light
    /// Open the home screen full-screen.
    public var fillScreen = true
    /// Only the apps on the home screen may come to the front; anything else is politely sent back home.
    public var strictMode = false
    public var pin: PinRecord?
    public var setupComplete = false

    public init() {}

    enum CodingKeys: String, CodingKey {
        case version, ownerName, people, tiles, reminders, textSize, theme, fillScreen, strictMode, pin, setupComplete
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = HearthConfig()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        ownerName = try c.decodeIfPresent(String.self, forKey: .ownerName) ?? d.ownerName
        people = try c.decodeIfPresent([Person].self, forKey: .people) ?? d.people
        tiles = try c.decodeIfPresent([Tile].self, forKey: .tiles) ?? d.tiles
        reminders = try c.decodeIfPresent([Reminder].self, forKey: .reminders) ?? d.reminders
        textSize = try c.decodeIfPresent(TextSize.self, forKey: .textSize) ?? d.textSize
        theme = try c.decodeIfPresent(ThemeChoice.self, forKey: .theme) ?? d.theme
        fillScreen = try c.decodeIfPresent(Bool.self, forKey: .fillScreen) ?? d.fillScreen
        strictMode = try c.decodeIfPresent(Bool.self, forKey: .strictMode) ?? d.strictMode
        pin = try c.decodeIfPresent(PinRecord.self, forKey: .pin)
        setupComplete = try c.decodeIfPresent(Bool.self, forKey: .setupComplete) ?? d.setupComplete
    }

    public var helper: Person? { people.first { $0.isHelper } ?? people.first }

    public func person(id: UUID?) -> Person? {
        guard let id = id else { return nil }
        return people.first { $0.id == id }
    }

    public mutating func moveTile(from: Int, to: Int) {
        guard tiles.indices.contains(from), to >= 0, to < tiles.count, from != to else { return }
        let t = tiles.remove(at: from)
        tiles.insert(t, at: to)
    }

    public mutating func removePerson(id: UUID) {
        people.removeAll { $0.id == id }
        tiles.removeAll { ($0.kind == .video || $0.kind == .call || $0.kind == .message) && $0.personID == id }
    }
}

/// Where the setup lives on disk. `HEARTH_HOME` overrides it (tests, demos).
public struct ConfigStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static func standard() -> ConfigStore {
        if let env = ProcessInfo.processInfo.environment["HEARTH_HOME"], !env.isEmpty {
            return ConfigStore(url: URL(fileURLWithPath: env, isDirectory: true).appendingPathComponent("config.json"))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ConfigStore(url: base.appendingPathComponent("Hearth/config.json"))
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func load() -> HearthConfig {
        guard let data = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(HearthConfig.self, from: data) else {
            return HearthConfig()
        }
        return c
    }

    public func save(_ c: HearthConfig) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(c).write(to: url, options: .atomic)
    }
}
