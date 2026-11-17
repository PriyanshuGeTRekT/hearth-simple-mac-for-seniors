import Foundation
import Testing
@testable import HearthCore

let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

// 2026-11-17 is a Tuesday (weekday 3).
let tuesday8am = date(2026, 11, 17, 8, 0)

@Suite struct LaunchingTests {
    @Test func phoneNumbersAreNormalisedAndJunkIsRejected() {
        #expect(Launching.normalizeHandle("+1 (555) 123-4567") == "+15551234567")
        #expect(Launching.normalizeHandle("555.0100") == "5550100")
        #expect(Launching.normalizeHandle("+44 20 7946 0958") == "+442079460958")
        #expect(Launching.normalizeHandle("12345") == nil, "too short to be a phone number")
        #expect(Launching.normalizeHandle("555-CALL-NOW") == nil)
        #expect(Launching.normalizeHandle("1; rm -rf /") == nil)
        #expect(Launching.normalizeHandle("1234567890123456") == nil, "more than 15 digits")
    }

    @Test func emailsAreAcceptedWhenTheyLookLikeEmails() {
        #expect(Launching.normalizeHandle("  Anna@Example.COM ") == "anna@example.com")
        #expect(Launching.isEmail("a@b.co"))
        for bad in ["a@b", "@b.co", "a b@c.de", "a@@b.co", "a@.co", "a@b.", "plain"] { #expect(!Launching.isEmail(bad), "\(bad)") }
    }

    @Test func websitesMustBeRealWebAddresses() {
        #expect(Launching.normalizeWebsite("weather.com")?.absoluteString == "https://weather.com")
        #expect(Launching.normalizeWebsite("http://example.org/news")?.absoluteString == "http://example.org/news")
        for bad in ["javascript:alert(1)", "file:///etc/passwd", "ftp://example.com", "has space.com", "localhost", "https://", "", "data:text/html,hi"] {
            #expect(Launching.normalizeWebsite(bad) == nil, "\(bad) must be refused")
        }
    }

    @Test func eachKindOfButtonBuildsTheRightLink() {
        let anna = Person(name: "Anna", handle: "+1 555 123 4567", isHelper: true)
        let mike = Person(name: "Mike", handle: "mike@example.com")
        let people = [anna, mike]
        func l(_ t: Tile) -> Launch? { Launching.launch(for: t, people: people) }
        #expect(l(.video(anna)) == .url(URL(string: "facetime://+15551234567")!))
        #expect(l(.call(anna)) == .url(URL(string: "facetime-audio://+15551234567")!))
        #expect(l(.video(mike)) == .url(URL(string: "facetime://mike@example.com")!))
        #expect(l(Tile(kind: .message, title: "Text Anna", target: "", personID: anna.id)) == .url(URL(string: "sms:+15551234567")!))
        #expect(l(Tile(kind: .message, title: "Text Mike", target: "", personID: mike.id)) == .url(URL(string: "imessage://mike@example.com")!))
        #expect(l(Tile(kind: .email, title: "Mail Mike", target: "", personID: mike.id)) == .url(URL(string: "mailto:mike@example.com")!))
        #expect(l(Tile(kind: .email, title: "Mail Anna", target: "", personID: anna.id)) == nil, "a phone number is not an email address")
        #expect(l(.app("com.apple.Safari", "Internet")) == .app(bundleID: "com.apple.Safari"))
        #expect(l(.app("nonsense", "Bad")) == nil)
        #expect(l(.website("weather.com", "Weather")) == .url(URL(string: "https://weather.com")!))
        #expect(l(.photos("/Users/dot/Pictures/Family")) == .slideshow(folder: "/Users/dot/Pictures/Family"))
        #expect(l(.photos("relative/path")) == nil)
    }

    @Test func aPersonsButtonFollowsTheirCurrentNumber() {
        var anna = Person(name: "Anna", handle: "5550100", isHelper: true)
        let tile = Tile.video(anna)
        anna.handle = "5550199" // the family updated her number
        #expect(Launching.launch(for: tile, people: [anna]) == .url(URL(string: "facetime://5550199")!))
    }

    @Test func buttonsDeclareWhichAppsTheyNeed() {
        #expect(Launching.supportingBundleIDs(for: .app("com.apple.Photos", "P")) == ["com.apple.Photos"])
        #expect(Launching.supportingBundleIDs(for: .video(Person(name: "A", handle: "5550100"))) == ["com.apple.FaceTime"])
        #expect(Launching.supportingBundleIDs(for: .website("a.com", "A")).isEmpty)
    }
}

@Suite struct PinTests {
    @Test func formatAndVerification() {
        #expect(Pin.isValidFormat("1234") && Pin.isValidFormat("12345678"))
        for bad in ["", "123", "123456789", "12a4", "١٢٣٤", "12 4"] { #expect(!Pin.isValidFormat(bad), "\(bad)") }
        let r = Pin.make("4821")
        #expect(Pin.verify("4821", against: r))
        #expect(!Pin.verify("4822", against: r))
        #expect(Pin.make("4821").hash != r.hash, "every PIN gets its own salt")
        #expect(!r.hash.contains("4821"))
    }
}

@Suite struct ReminderTests {
    let blue = Reminder(text: "Take the blue pill", hour: 9, minute: 0)

    @Test func comesDueExactlyOnce() {
        let before = date(2026, 11, 17, 8, 59), after = date(2026, 11, 17, 9, 0)
        #expect(Reminders.due([blue], after: date(2026, 11, 17, 8, 58), upTo: before, calendar: utc).isEmpty)
        #expect(Reminders.due([blue], after: before, upTo: after, calendar: utc).map(\.text) == ["Take the blue pill"])
        #expect(Reminders.due([blue], after: after, upTo: date(2026, 11, 17, 9, 1), calendar: utc).isEmpty, "not again a minute later")
    }

    @Test func weekdayFilter() {
        let mwf = Reminder(text: "Walk", hour: 10, weekdays: [2, 4, 6])
        #expect(Reminders.due([mwf], after: date(2026, 11, 17, 9, 59), upTo: date(2026, 11, 17, 10, 0), calendar: utc).isEmpty, "Tuesday")
        #expect(Reminders.due([mwf], after: date(2026, 11, 18, 9, 59), upTo: date(2026, 11, 18, 10, 0), calendar: utc).count == 1, "Wednesday")
    }

    @Test func staleRemindersAreDroppedAfterTheMacWasAsleep() {
        // asleep from 22:00 to 07:30: the 21:00 reminder from last night is not shown at breakfast
        let evening = Reminder(text: "Evening tablet", hour: 21)
        let morning = Reminder(text: "Morning tablet", hour: 7)
        let due = Reminders.due([evening, morning], after: date(2026, 11, 16, 22, 0), upTo: date(2026, 11, 17, 7, 30), calendar: utc)
        #expect(due.map(\.text) == ["Morning tablet"])
    }

    @Test func nextAndToday() {
        let rs = [Reminder(text: "B", hour: 14), Reminder(text: "A", hour: 9), Reminder(text: "Sat only", hour: 8, weekdays: [7])]
        #expect(Reminders.today(rs, now: tuesday8am, calendar: utc).map(\.text) == ["A", "B"])
        let n = Reminders.next(rs, after: tuesday8am, calendar: utc)
        #expect(n?.reminder.text == "A" && n?.at == date(2026, 11, 17, 9, 0))
        #expect(Reminders.next(rs, after: date(2026, 11, 17, 15, 0), calendar: utc)?.reminder.text == "A", "tomorrow morning")
        #expect(Reminders.next([], after: tuesday8am, calendar: utc) == nil)
    }
}

@Suite struct StrictTests {
    func config() -> HearthConfig {
        var c = HearthConfig()
        let anna = Person(name: "Anna", handle: "5550100", isHelper: true)
        c.people = [anna]
        c.tiles = [.video(anna), .app("com.apple.Photos", "Photos"), .website("weather.com", "Weather"), .photos("/tmp")]
        return c
    }

    @Test func allowedAppsComeFromTheButtons() {
        let s = StrictPolicy.allowedBundleIDs(config: config(), defaultBrowser: "com.apple.Safari")
        #expect(s == ["com.apple.FaceTime", "com.apple.Photos", "com.apple.Safari"])
        #expect(StrictPolicy.allowedBundleIDs(config: config(), defaultBrowser: nil) == ["com.apple.FaceTime", "com.apple.Photos"])
    }

    @Test func decisions() {
        let p = StrictPolicy(allowed: ["com.apple.Photos"])
        #expect(!p.shouldReturnHome(frontmost: "com.apple.Photos", ownBundleID: "app.hearth.mac"))
        #expect(!p.shouldReturnHome(frontmost: "app.hearth.mac", ownBundleID: "app.hearth.mac"))
        #expect(!p.shouldReturnHome(frontmost: "com.apple.SecurityAgent", ownBundleID: "app.hearth.mac"), "password prompts must never be blocked")
        #expect(!p.shouldReturnHome(frontmost: "com.apple.dock", ownBundleID: nil))
        #expect(!p.shouldReturnHome(frontmost: nil, ownBundleID: nil))
        #expect(p.shouldReturnHome(frontmost: "com.apple.Terminal", ownBundleID: "app.hearth.mac"))
        #expect(p.shouldReturnHome(frontmost: "com.apple.systempreferences", ownBundleID: "app.hearth.mac"))
    }
}

@Suite struct SetupTests {
    func sample() -> HearthConfig {
        let anna = Person(name: "Anna", handle: "+1 555 010 0199", relation: "daughter", isHelper: true)
        var c = HearthConfig.starter(owner: "Dorothy", helper: anna, installed: ["com.apple.Photos", "com.apple.mail", "com.apple.Safari"])
        c.reminders = [Reminder(text: "Blue pill", hour: 9)]
        c.pin = Pin.make("4821")
        c.setupComplete = true
        c.strictMode = true
        return c
    }

    @Test func exportNeverCarriesThePin() throws {
        let data = try SetupIO.export(sample())
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("salt") && !text.contains("\"pin\""))
        let back = try SetupIO.read(data)
        #expect(back.warnings.isEmpty)
        #expect(back.config.pin == nil && back.config.setupComplete == false)
        #expect(back.config.ownerName == "Dorothy")
        #expect(back.config.tiles.map(\.title) == ["Anna", "Mail", "The Internet", "Photos"])
        #expect(back.config.reminders.count == 1 && back.config.strictMode)
    }

    @Test func importRefusesOtherFilesAndNewerVersions() throws {
        #expect(throws: SetupError.self) { try SetupIO.read(Data("{}".utf8)) }
        #expect(throws: SetupError.self) { try SetupIO.read(Data("not json".utf8)) }
        var env = String(decoding: try SetupIO.export(sample()), as: UTF8.self)
        env = env.replacingOccurrences(of: "\"version\" : 1\n}", with: "\"version\" : 99\n}")
        #expect(throws: SetupError.self) { try SetupIO.read(Data(env.utf8)) }
    }

    @Test func importDropsEverythingUnsafeAndSaysSo() throws {
        var c = sample()
        let evil = Person(name: "Evil", handle: "1; rm -rf /")
        c.people.append(evil)
        c.tiles.append(Tile(kind: .website, title: "Bank", target: "javascript:alert(1)"))
        c.tiles.append(Tile(kind: .website, title: "Local file", target: "file:///etc/passwd"))
        c.tiles.append(Tile(kind: .app, title: "Bad app", target: "not a bundle id; rm -rf"))
        c.tiles.append(Tile(kind: .photos, title: "Relative", target: "../../etc"))
        c.tiles.append(Tile(kind: .website, title: "   ", target: "ok.com"))
        c.reminders.append(Reminder(text: "Late", hour: 25))
        c.reminders.append(Reminder(text: "", hour: 9))
        c.reminders.append(Reminder(text: "Odd days", hour: 8, weekdays: [0, 3, 3, 9, 1]))
        let r = try SetupIO.read(try SetupIO.export(c))
        #expect(r.config.people.map(\.name) == ["Anna"])
        #expect(r.config.tiles.count == 4, "only the four good buttons survive")
        #expect(r.config.reminders.count == 2)
        #expect(r.config.reminders.last?.weekdays == [1, 3])
        #expect(r.warnings.count == 8, "\(r.warnings)")
    }

    @Test func importCapsTheSizeOfEverything() throws {
        var c = HearthConfig()
        c.ownerName = String(repeating: "x", count: 500)
        for i in 0..<80 { c.tiles.append(.website("site\(i).com", "Site \(i)")) }
        let r = try SetupIO.read(try SetupIO.export(c))
        #expect(r.config.tiles.count == SetupIO.maxTiles)
        #expect(r.config.ownerName.count == 40)
    }

    @Test func starterSetupUsesOnlyInstalledApps() {
        let anna = Person(name: "Anna", handle: "5550100")
        let c = HearthConfig.starter(owner: "Dot", helper: anna, installed: ["com.apple.Photos", "com.apple.Safari", "com.apple.Notes"])
        #expect(c.tiles.map(\.title) == ["Anna", "The Internet", "Photos", "Notes"])
        #expect(c.people.first?.isHelper == true)
        let many = HearthConfig.starter(owner: "", helper: nil, installed: Set(AppCatalog.recommended.map(\.bundleID)), maxTiles: 4)
        #expect(many.tiles.count == 4)
    }

    @Test func catalogReadsRealBundleLayoutsAndHidesBackgroundHelpers() throws {
        let root = NSTemporaryDirectory() + "/hearth-apps-\(UUID())"
        defer { try? FileManager.default.removeItem(atPath: root) }
        func makeApp(_ name: String, _ plist: [String: Any]) throws {
            let dir = root + "/\(name).app/Contents"
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try (plist as NSDictionary).write(to: URL(fileURLWithPath: dir + "/Info.plist"))
        }
        try makeApp("Zebra", ["CFBundleIdentifier": "org.test.zebra", "CFBundleName": "Zebra"])
        try makeApp("Alpha", ["CFBundleIdentifier": "org.test.alpha", "CFBundleName": "Alpha", "CFBundleDisplayName": "Alpha Pro"])
        try makeApp("Helper", ["CFBundleIdentifier": "org.test.helper", "LSUIElement": true])
        try makeApp("Dup", ["CFBundleIdentifier": "org.test.alpha"])
        try makeApp("NoName", ["CFBundleIdentifier": "org.test.noname"])
        let apps = AppCatalog.installed(roots: [root, root + "/missing"])
        #expect(apps.map(\.name) == ["Alpha Pro", "NoName", "Zebra"])
        #expect(!apps.contains { $0.bundleID == "org.test.helper" })
    }
}

@Suite struct SlideshowTests {
    @Test func findsPicturesInNaturalOrderAndSkipsEverythingElse() throws {
        let unique = "hearth-photos-\(UUID())"
        let root = NSTemporaryDirectory() + "/" + unique
        defer { try? FileManager.default.removeItem(atPath: root) }
        let fm = FileManager.default
        try fm.createDirectory(atPath: root + "/2025/summer/deep", withIntermediateDirectories: true)
        for f in ["img10.jpg", "img2.JPG", "img1.png", "notes.txt", ".hidden.jpg", "2025/a.heic", "2025/summer/b.jpeg", "2025/summer/deep/too-deep.jpg"] {
            fm.createFile(atPath: root + "/" + f, contents: Data([1]))
        }
        // /var is a symlink to /private/var, so compare what comes after the unique folder name
        let imgs = Slideshow.images(in: root).map { $0.components(separatedBy: unique + "/").last! }
        #expect(imgs == ["2025/a.heic", "2025/summer/b.jpeg", "img1.png", "img2.JPG", "img10.jpg"])
        #expect(Slideshow.images(in: root, limit: 2).count == 2)
        #expect(Slideshow.images(in: root + "/nope").isEmpty)
    }

    @Test func wrapAround() {
        #expect(Slideshow.wrap(0, by: -1, count: 5) == 4)
        #expect(Slideshow.wrap(4, by: 1, count: 5) == 0)
        #expect(Slideshow.wrap(2, by: 7, count: 5) == 4)
        #expect(Slideshow.wrap(0, by: 1, count: 0) == 0)
    }
}

@Suite struct WordsAndConfigTests {
    @Test func greetings() {
        #expect(Words.greeting(name: "Dot", now: date(2026, 11, 17, 8), calendar: utc) == "Good morning, Dot")
        #expect(Words.greeting(name: "", now: date(2026, 11, 17, 14), calendar: utc) == "Good afternoon")
        #expect(Words.greeting(name: " Dot ", now: date(2026, 11, 17, 19), calendar: utc) == "Good evening, Dot")
        #expect(Words.greeting(name: "Dot", now: date(2026, 11, 17, 3), calendar: utc) == "Hello, Dot")
    }

    @Test func configRoundTripAndOldFilesLoad() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "/hearth-cfg-\(UUID())/config.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigStore(url: url)
        #expect(!store.exists)
        var c = HearthConfig(); c.ownerName = "Dot"; c.textSize = .largest; c.pin = Pin.make("1234")
        try store.save(c)
        #expect(store.exists && store.load() == c)
        try Data(#"{"ownerName":"Old"}"#.utf8).write(to: url)
        let old = store.load()
        #expect(old.ownerName == "Old" && old.textSize == .large && old.fillScreen && !old.strictMode, "missing keys use defaults")
        try Data("garbage".utf8).write(to: url)
        #expect(store.load() == HearthConfig(), "a damaged file never crashes the app")
    }

    @Test func tilesAndPeopleEditing() {
        let a = Person(name: "Anna", handle: "5550100", isHelper: true), b = Person(name: "Bo", handle: "5550101")
        var c = HearthConfig()
        c.people = [a, b]
        c.tiles = [.video(a), .video(b), .app("com.apple.Photos", "Photos"), .call(b)]
        c.moveTile(from: 2, to: 0)
        #expect(c.tiles.map(\.title) == ["Photos", "Anna", "Bo", "Phone Bo"])
        c.moveTile(from: 9, to: 0); c.moveTile(from: 0, to: 9)
        #expect(c.tiles.count == 4)
        c.removePerson(id: b.id)
        #expect(c.tiles.map(\.title) == ["Photos", "Anna"] && c.people.count == 1, "their buttons go with them")
        #expect(c.helper?.name == "Anna")
        #expect(Person(name: "Mary Ann Smith", handle: "5").initials == "MA")
    }
}
