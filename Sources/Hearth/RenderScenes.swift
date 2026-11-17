import SwiftUI
import AppKit
import HearthCore

/// Renders every screen offscreen from demo data (no display or screen-recording permission needed),
/// and checks that each one really drew something.
@MainActor
enum RenderScenes {
    static func renderPNG<V: View>(_ view: V, size: CGSize, to path: String, dark: Bool = false) {
        let host = NSHostingView(rootView: view)
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: CGRect(origin: CGPoint(x: -9000, y: -9000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        win.contentView = host
        win.orderFrontRegardless()
        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        win.orderOut(nil)
    }

    /// A few pretty gradient "photos" so the slideshow has something to show.
    static func makePhotos(in dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let scenes: [(String, NSColor, NSColor, NSColor)] = [
            ("1-sunset", NSColor(red: 0.98, green: 0.62, blue: 0.30, alpha: 1), NSColor(red: 0.55, green: 0.25, blue: 0.55, alpha: 1), NSColor(red: 1, green: 0.9, blue: 0.5, alpha: 1)),
            ("2-garden", NSColor(red: 0.55, green: 0.80, blue: 0.95, alpha: 1), NSColor(red: 0.25, green: 0.60, blue: 0.30, alpha: 1), NSColor(red: 1, green: 0.95, blue: 0.7, alpha: 1)),
            ("3-beach", NSColor(red: 0.45, green: 0.75, blue: 0.95, alpha: 1), NSColor(red: 0.95, green: 0.85, blue: 0.60, alpha: 1), NSColor.white),
        ]
        for (name, top, bottom, sun) in scenes {
            let img = NSImage(size: NSSize(width: 1600, height: 1000))
            img.lockFocus()
            NSGradient(starting: top, ending: bottom)?.draw(in: NSRect(x: 0, y: 0, width: 1600, height: 1000), angle: 270)
            sun.setFill()
            NSBezierPath(ovalIn: NSRect(x: 1050, y: 560, width: 220, height: 220)).fill()
            NSColor(white: 0, alpha: 0.18).setFill()
            NSBezierPath(ovalIn: NSRect(x: -200, y: -300, width: 1200, height: 600)).fill()
            NSBezierPath(ovalIn: NSRect(x: 600, y: -380, width: 1400, height: 700)).fill()
            img.unlockFocus()
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir + "/\(name).png"))
            }
        }
    }

    static func demoConfig(photos: String) -> HearthConfig {
        let anna = Person(name: "Anna", handle: "+1 555 010 0199", relation: "daughter", isHelper: true)
        let mike = Person(name: "Mike", handle: "mike@example.com", relation: "grandson")
        var c = HearthConfig()
        c.ownerName = "Dorothy"
        c.people = [anna, mike]
        c.tiles = [.video(anna), .video(mike), .app("com.apple.MobileSMS", "Messages", color: .green), .app("com.apple.mail", "Mail", color: .blue),
                   .app("com.apple.Safari", "The Internet", color: .teal), .photos(photos, "Family photos"),
                   .app("com.apple.Photos", "Photos", color: .pink), .website("weather.com", "Weather", color: .orange)]
        c.reminders = [Reminder(text: "Take the blue pill", hour: 9), Reminder(text: "Call the pharmacy", hour: 11, minute: 30),
                       Reminder(text: "Walk in the garden", hour: 15)]
        c.setupComplete = true
        return c
    }

    static func model(_ c: HearthConfig, at hour: Int, _ minute: Int) -> HearthModel {
        let clock = TestClock(Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!)
        let m = HearthModel(config: c, clock: { clock.t })
        m.ownBundleID = "app.hearth.mac"
        m.tick()
        return m
    }

    final class TestClock { var t: Date; init(_ t: Date) { self.t = t } }

    static func pixelStats(_ path: String) -> (size: Int, colors: Int) {
        guard let data = FileManager.default.contents(atPath: path), let rep = NSBitmapImageRep(data: data) else { return (0, 0) }
        var seen = Set<UInt32>()
        let stepX = max(rep.pixelsWide / 60, 1), stepY = max(rep.pixelsHigh / 60, 1)
        for y in stride(from: 0, to: rep.pixelsHigh, by: stepY) {
            for x in stride(from: 0, to: rep.pixelsWide, by: stepX) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                seen.insert(UInt32(c.redComponent * 31) << 10 | UInt32(c.greenComponent * 31) << 5 | UInt32(c.blueComponent * 31))
            }
        }
        return (data.count, seen.count)
    }

    @discardableResult
    static func run(outDir: String) -> [String] {
        NSApplication.shared.setActivationPolicy(.accessory)
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
        let photos = outDir + "/_photos"
        makePhotos(in: photos)
        let cfg = demoConfig(photos: photos)
        let wide = CGSize(width: 1180, height: 800)
        var made: [String] = []
        func out(_ name: String) -> String { made.append(name); return outDir + "/" + name }

        let home = model(cfg, at: 10, 15)
        // 9:00 reminder was done this morning
        let done = model(cfg, at: 9, 0); done.tick(); done.completeReminder()
        renderPNG(RootView(model: home), size: wide, to: out("1-home.png"))
        renderPNG(RootView(model: done), size: wide, to: out("1b-home-after-pill.png"))

        var big = cfg; big.textSize = .largest
        renderPNG(RootView(model: model(big, at: 10, 15)), size: wide, to: out("2-home-largest-text.png"))
        var dark = cfg; dark.theme = .dark
        renderPNG(RootView(model: model(dark, at: 20, 5)), size: wide, to: out("3-home-dark.png"), dark: true)
        var hc = cfg; hc.theme = .highContrast; hc.textSize = .larger
        renderPNG(RootView(model: model(hc, at: 10, 15)), size: wide, to: out("4-home-high-contrast.png"), dark: true)

        let rem = model(cfg, at: 11, 30); rem.tick()
        renderPNG(RootView(model: rem), size: wide, to: out("5-reminder.png"))
        let help = model(cfg, at: 10, 15); help.showHelp()
        renderPNG(RootView(model: help), size: wide, to: out("6-help.png"))
        let show = model(cfg, at: 10, 15); show.open(cfg.tiles[5])
        renderPNG(RootView(model: show), size: wide, to: out("7-slideshow.png"), dark: true)

        let strict = model(cfg, at: 10, 15)
        strict.statusLine = "That one isn't set up for you yet. Ask Anna to add it."
        renderPNG(RootView(model: strict), size: wide, to: out("8-sent-home-message.png"))

        let cg = model(cfg, at: 10, 15)
        _ = cg.unlockCaregiver(pin: "")  // no PIN set: caregiver view opens directly
        renderPNG(CaregiverRoot(model: cg) {}, size: CGSize(width: 760, height: 1500), to: out("9-caregiver.png"))
        var fresh = HearthConfig(); fresh.ownerName = ""
        renderPNG(CaregiverRoot(model: model(fresh, at: 10, 15)) {}, size: CGSize(width: 760, height: 900), to: out("10-first-setup.png"))
        var pinned = cfg; pinned.pin = Pin.make("4821")
        renderPNG(CaregiverRoot(model: model(pinned, at: 10, 15)) {}, size: CGSize(width: 420, height: 340), to: out("11-pin-gate.png"))
        let barModel = model(cfg, at: 10, 15)
        let bar = BarView(model: barModel)
        renderPNG(bar, size: NSHostingView(rootView: bar).fittingSize, to: out("12-bar.png"))
        try? FileManager.default.removeItem(atPath: photos)
        return made
    }

    static func selftest(outDir: String) -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ what: String) { print(ok ? "  ✓ \(what)" : "  ✗ \(what)"); if !ok { failures += 1 } }
        print("rendering every screen")
        let made = run(outDir: outDir)
        for name in made {
            let st = pixelStats(outDir + "/" + name)
            check(st.size > 8_000 && st.colors >= 6, "\(name) drew real content (\(st.size / 1024) KB, \(st.colors) distinct colours)")
        }
        print("the Mac apps the home screen offers")
        let present = AppCatalog.recommended.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleID) != nil }
        check(present.count >= 5, "\(present.count) of \(AppCatalog.recommended.count) recommended apps are installed here: " + present.map(\.title).joined(separator: ", "))
        let installed = AppCatalog.installed()
        check(installed.count > 20, "the app catalog found \(installed.count) apps")
        check(installed.contains { $0.bundleID == "com.apple.FaceTime" }, "FaceTime is among them (call buttons need it)")
        check(HearthApp.defaultBrowser() != nil, "the default browser resolves: \(HearthApp.defaultBrowser() ?? "-")")
        print(failures == 0 ? "HEARTH SELFTEST PASSED" : "HEARTH SELFTEST FAILED (\(failures))")
        return failures == 0 ? 0 : 1
    }
}
