import Foundation
import Testing
@testable import HearthCore

final class MockLauncher: AppLauncher {
    var opened: [Launch] = []
    var hidden = 0
    var forward = 0
    func open(_ launch: Launch) { opened.append(launch) }
    func hideOtherApps() { hidden += 1 }
    func bringHomeForward() { forward += 1 }
}

final class MockSpeaker: Speaker {
    var said: [String] = []
    func say(_ text: String) { said.append(text) }
}

final class TestClock {
    var t: Date
    init(_ t: Date) { self.t = t }
    func advance(_ s: TimeInterval) { t = t.addingTimeInterval(s) }
}

@MainActor
struct Rig {
    let model: HearthModel
    let launcher = MockLauncher()
    let speaker = MockSpeaker()
    let clock: TestClock
    let anna = Person(name: "Anna", handle: "+1 555 010 0199", relation: "daughter", isHelper: true)

    init(start: Date = tuesday8am, configure: (inout HearthConfig, Person) -> Void = { _, _ in }) {
        clock = TestClock(start)
        var c = HearthConfig()
        c.ownerName = "Dorothy"
        c.people = [anna]
        c.tiles = [.video(anna), .app("com.apple.Photos", "Photos")]
        c.setupComplete = true
        configure(&c, anna)
        let l = launcher, s = speaker, ck = clock
        model = HearthModel(config: c, launcher: l, clock: { ck.t })
        model.calendar = utc
        model.speaker = s
        model.ownBundleID = "app.hearth.mac"
    }
}

@MainActor
@Suite struct ModelTests {

    // MARK: tapping things

    @Test func tappingButtonsOpensTheRightThings() {
        let r = Rig()
        r.model.open(r.model.config.tiles[0])
        r.model.open(r.model.config.tiles[1])
        #expect(r.launcher.opened == [.url(URL(string: "facetime://+15550100199")!), .app(bundleID: "com.apple.Photos")])
        #expect(r.model.statusLine == nil)
    }

    @Test func aBrokenButtonSaysWhoToAsk() {
        let r = Rig()
        r.model.open(Tile(kind: .website, title: "Broken", target: "javascript:alert(1)"))
        #expect(r.launcher.opened.isEmpty)
        #expect(r.model.statusLine?.contains("Anna") == true)
    }

    @Test func photosOpenTheSlideshowOnlyWhenThereAreOnes() throws {
        let r = Rig()
        let folder = NSTemporaryDirectory() + "/hearth-ss-\(UUID())"
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: folder) }
        r.model.open(.photos(folder))
        #expect(r.model.screen == .home && r.model.statusLine?.contains("no photos") == true)
        FileManager.default.createFile(atPath: folder + "/a.jpg", contents: Data([1]))
        r.model.open(.photos(folder))
        #expect(r.model.screen == .slideshow(folder))
        #expect(r.launcher.opened.isEmpty, "the slideshow is part of Hearth, not another app")
        r.model.closeScreen()
        #expect(r.model.screen == .home)
    }

    @Test func homeButtonCalmsTheScreen() {
        let r = Rig()
        r.model.showHelp()
        #expect(r.model.screen == .help)
        r.model.goHome()
        #expect(r.model.screen == .home && r.launcher.hidden == 1 && r.launcher.forward == 1)
    }

    @Test func helpCallsTheHelperAndCopesWithNobody() {
        let r = Rig()
        r.model.callHelper()
        r.model.callHelper(video: false)
        #expect(r.launcher.opened == [.url(URL(string: "facetime://+15550100199")!), .url(URL(string: "facetime-audio://+15550100199")!)])
        let empty = Rig { c, _ in c.people = []; c.tiles = [] }
        empty.model.callHelper()
        #expect(empty.launcher.opened.isEmpty && empty.model.statusLine != nil)
        #expect(empty.model.helperName == "your family")
    }

    // MARK: reminders

    func withReminders() -> Rig {
        Rig { c, _ in
            c.reminders = [Reminder(text: "Take the blue pill", hour: 9), Reminder(text: "Call the pharmacy", hour: 9, minute: 1, speak: false)]
        }
    }

    @Test func reminderAppearsSpeaksAndIsNotRepeated() {
        let r = withReminders()
        r.model.tick()
        #expect(r.model.activeReminder == nil)
        r.clock.t = date(2026, 11, 17, 9, 0); r.model.tick()
        #expect(r.model.activeReminder?.text == "Take the blue pill")
        #expect(r.speaker.said == ["It is time. Take the blue pill"])
        #expect(r.launcher.forward == 1, "Hearth comes to the front so it is seen")
        r.model.completeReminder()
        #expect(r.model.activeReminder == nil && r.model.isDone(r.model.config.reminders[0]))
        r.clock.advance(30); r.model.tick(); r.clock.advance(30); r.model.tick()
        #expect(r.model.activeReminder?.text == "Call the pharmacy", "the next one follows at 9:01")
        #expect(r.speaker.said.count == 1, "this one is silent")
    }

    @Test func twoRemindersAtOnceQueueUp() {
        let r = Rig { c, _ in c.reminders = [Reminder(text: "One", hour: 9), Reminder(text: "Two", hour: 9)] }
        r.clock.t = date(2026, 11, 17, 9, 0); r.model.tick()
        #expect(r.model.activeReminder?.text == "One")
        r.model.completeReminder()
        #expect(r.model.activeReminder?.text == "Two")
        r.model.completeReminder()
        #expect(r.model.activeReminder == nil)
    }

    @Test func snoozeBringsItBackLater() {
        let r = withReminders()
        r.clock.t = date(2026, 11, 17, 9, 0); r.model.tick()
        r.model.snoozeReminder(minutes: 10)
        #expect(r.model.activeReminder == nil)
        r.clock.t = date(2026, 11, 17, 9, 5); r.model.tick()
        #expect(r.model.activeReminder?.text == "Call the pharmacy", "(9:01 came due meanwhile)")
        r.model.completeReminder()
        r.clock.t = date(2026, 11, 17, 9, 11); r.model.tick()
        #expect(r.model.activeReminder?.text == "Take the blue pill")
        r.model.completeReminder()
        r.clock.t = date(2026, 11, 17, 9, 30); r.model.tick()
        #expect(r.model.activeReminder == nil)
    }

    @Test func aReminderDuringHelpBringsTheViewerBackHome() {
        let r = withReminders()
        r.model.showHelp()
        r.clock.t = date(2026, 11, 17, 9, 0); r.model.tick()
        #expect(r.model.screen == .home && r.model.activeReminder != nil)
    }

    @Test func launchingJustAfterAReminderStillShowsIt() {
        let r = Rig(start: date(2026, 11, 17, 9, 4)) { c, _ in c.reminders = [Reminder(text: "Pill", hour: 9)] }
        r.model.tick()
        #expect(r.model.activeReminder?.text == "Pill")
        let late = Rig(start: date(2026, 11, 17, 13, 0)) { c, _ in c.reminders = [Reminder(text: "Pill", hour: 9)] }
        late.model.tick()
        #expect(late.model.activeReminder == nil, "four hours late is not helpful, it is confusing")
    }

    // MARK: caregiver

    @Test func firstSetupNeedsNoPinThenEverythingIsLocked() {
        let r = Rig { c, _ in c.setupComplete = false }
        #expect(r.model.canEdit && !r.model.hasPin)
        #expect(r.model.update { $0.ownerName = "Dot" })
        #expect(r.model.setPin("4821") && r.model.hasPin)
        #expect(r.model.canEdit == false || r.model.caregiverUnlocked, "after setting a PIN the settings lock unless unlocked")
        r.model.lockCaregiver()
        #expect(!r.model.canEdit)
        #expect(r.model.update { $0.ownerName = "Hacked" } == false)
        #expect(r.model.config.ownerName == "Dot")
        #expect(!r.model.setPin("9999"), "only the caregiver can change the PIN")
    }

    @Test func wrongPinsAreCountedAndLockedOutThenForgiven() {
        let r = Rig { c, _ in c.pin = Pin.make("4821") }
        #expect(r.model.unlockCaregiver(pin: "0000") == .wrong(attemptsLeft: 4))
        #expect(r.model.unlockCaregiver(pin: "1111") == .wrong(attemptsLeft: 3))
        #expect(r.model.unlockCaregiver(pin: "2222") == .wrong(attemptsLeft: 2))
        #expect(r.model.unlockCaregiver(pin: "3333") == .wrong(attemptsLeft: 1))
        #expect(r.model.unlockCaregiver(pin: "4444") == .lockedOut(seconds: 30))
        #expect(r.model.unlockCaregiver(pin: "4821") == .lockedOut(seconds: 30), "even the right PIN waits during the lockout")
        r.clock.advance(31)
        #expect(r.model.unlockCaregiver(pin: "4821") == .unlocked)
        #expect(r.model.caregiverUnlocked && r.model.canEdit)
        r.model.lockCaregiver()
        #expect(r.model.unlockCaregiver(pin: "0000") == .wrong(attemptsLeft: 4), "the counter was reset by the success")
    }

    @Test func invalidPinsAreNotAccepted() {
        let r = Rig { c, _ in c.setupComplete = false }
        #expect(!r.model.setPin("12") && !r.model.setPin("abcd") && !r.model.hasPin)
    }

    @Test func changesArePersisted() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "/hearth-model-\(UUID())/config.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ConfigStore(url: url)
        let model = HearthModel(config: HearthConfig(), store: store)
        model.update { $0.ownerName = "Dot"; $0.textSize = .larger }
        model.completeSetup()
        let loaded = store.load()
        #expect(loaded.ownerName == "Dot" && loaded.textSize == .larger && loaded.setupComplete)
    }

    // MARK: strict mode

    @Test func strictModeSendsUnknownAppsHomeButNeverBlocksSystemOrAllowedOnes() {
        let r = Rig { c, _ in c.strictMode = true }
        #expect(r.model.frontmostChanged(bundleID: "com.apple.Photos") == false)
        #expect(r.model.frontmostChanged(bundleID: "com.apple.FaceTime") == false)
        #expect(r.model.frontmostChanged(bundleID: "app.hearth.mac") == false)
        #expect(r.model.frontmostChanged(bundleID: "com.apple.SecurityAgent") == false)
        #expect(r.model.frontmostChanged(bundleID: nil) == false)
        #expect(r.launcher.hidden == 0)
        #expect(r.model.frontmostChanged(bundleID: "com.apple.Terminal") == true)
        #expect(r.launcher.hidden == 1 && r.launcher.forward == 1)
        #expect(r.model.statusLine == "That one isn't set up for you yet. Ask Anna to add it.")
    }

    @Test func strictModeIsOffByDefaultAndDuringSetup() {
        let off = Rig()
        #expect(off.model.frontmostChanged(bundleID: "com.apple.Terminal") == false)
        let setup = Rig { c, _ in c.strictMode = true; c.setupComplete = false }
        #expect(setup.model.frontmostChanged(bundleID: "com.apple.Terminal") == false, "never lock someone in before setup is finished")
    }

    @Test func caregiverCanSuspendStrictModeToUseTheWholeMac() {
        let r = Rig { c, _ in c.strictMode = true; c.pin = Pin.make("4821") }
        r.model.pauseStrictMode(minutes: 15)
        #expect(r.model.strictPausedUntil == nil, "only after unlocking")
        _ = r.model.unlockCaregiver(pin: "4821")
        #expect(r.model.frontmostChanged(bundleID: "com.apple.systempreferences") == false, "settings are open")
        r.model.lockCaregiver()
        #expect(r.model.frontmostChanged(bundleID: "com.apple.systempreferences") == true)
        _ = r.model.unlockCaregiver(pin: "4821")
        r.model.pauseStrictMode(minutes: 15)
        r.model.lockCaregiver()
        #expect(r.model.frontmostChanged(bundleID: "com.apple.systempreferences") == false, "paused for 15 minutes")
        r.clock.advance(16 * 60); r.model.tick()
        #expect(r.model.strictPausedUntil == nil)
        #expect(r.model.frontmostChanged(bundleID: "com.apple.systempreferences") == true)
    }

    @Test func theDefaultBrowserIsAllowedWhenThereIsAWebsiteButton() {
        let r = Rig { c, _ in c.strictMode = true; c.tiles.append(.website("weather.com", "Weather")) }
        r.model.defaultBrowserID = { "org.mozilla.firefox" }
        #expect(r.model.frontmostChanged(bundleID: "org.mozilla.firefox") == false)
        #expect(r.model.frontmostChanged(bundleID: "com.google.Chrome") == true)
    }

    // MARK: setup files through the model

    @Test func importKeepsThisMacsPinAndNeedsItToChangeThings() throws {
        let src = Rig { c, _ in c.tiles.append(.website("weather.com", "Weather")); c.ownerName = "Dorothy" }
        let data = try src.model.exportSetup()
        let dst = Rig { c, _ in c.ownerName = "Someone"; c.pin = Pin.make("4821"); c.tiles = [] }
        let blocked = try dst.model.importSetup(data)
        #expect(blocked.first?.contains("PIN") == true && dst.model.config.ownerName == "Someone")
        _ = dst.model.unlockCaregiver(pin: "4821")
        let warnings = try dst.model.importSetup(data)
        #expect(warnings.isEmpty)
        #expect(dst.model.config.ownerName == "Dorothy" && dst.model.config.tiles.count == 3)
        #expect(dst.model.config.pin == Pin.make("4821", salt: dst.model.config.pin!.salt), "the PIN stayed")
        #expect(dst.model.config.setupComplete, "and so did setupComplete")
    }
}
