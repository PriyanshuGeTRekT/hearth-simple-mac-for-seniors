import AppKit
import SwiftUI
import AVFoundation
import HearthCore

// MARK: - the always-visible Home / Help bar

struct BarView: View {
    @ObservedObject var model: HearthModel
    var s: CGFloat { CGFloat(model.config.textSize.scale) }

    func button(_ title: String, _ symbol: String, _ fill: Color, _ text: Color, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8 * s) {
                Image(systemName: symbol).font(rounded(26 * s, .bold))
                Text(title).font(rounded(24 * s, .bold))
            }
            .padding(.horizontal, 20 * s).padding(.vertical, 12 * s)
            .background(RoundedRectangle(cornerRadius: 16 * s, style: .continuous).fill(fill))
            .foregroundStyle(text)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }

    var body: some View {
        let t = Theme.of(model.config.theme)
        HStack(spacing: 10 * s) {
            button("Home", "house.fill", t.high ? .white : t.tileFill(.blue), t.high ? .black : .white) { model.goHome() }
            button("Help", "questionmark.circle.fill", t.helpFill, t.helpText) { model.showHelp(); model.launcher?.bringHomeForward() }
        }
        .padding(10 * s)
        .background(RoundedRectangle(cornerRadius: 24 * s, style: .continuous).fill(Color.black.opacity(0.82)))
        .padding(6)
    }
}

/// Floats above every other app so that "Home" and "Help" are always one click away.
@MainActor
final class BarPanel: NSPanel {
    let host: NSHostingView<BarView>

    init(model: HearthModel) {
        host = NSHostingView(rootView: BarView(model: model))
        super.init(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        contentView = host
        setContentSize(host.fittingSize)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func place() {
        setContentSize(host.fittingSize)
        guard let f = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: f.minX + 14, y: f.maxY - frame.height - 8))
    }
}

// MARK: - application

@MainActor
final class HearthApp: NSObject, NSApplicationDelegate, NSWindowDelegate, AppLauncher, Speaker {
    let store = ConfigStore.standard()
    var model: HearthModel!
    var home: NSWindow!
    var caregiverWindow: NSWindow?
    var bar: BarPanel?
    var timer: Timer?
    let windowed: Bool
    let synth = AVSpeechSynthesizer()
    var observers: [NSObjectProtocol] = []

    init(windowed: Bool) { self.windowed = windowed }

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)
        model = HearthModel(config: store.load(), store: store, launcher: self)
        model.speaker = self
        model.defaultBrowserID = { HearthApp.defaultBrowser() }
        model.onRequestCaregiver = { [weak self] in self?.openCaregiver() }
        buildMenu()
        buildHomeWindow()
        bar = BarPanel(model: model)

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.tick() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            let id = (n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated { self?.model.frontmostChanged(bundleID: id) }
        })
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.bar?.orderOut(nil) }
        })
        observers.append(nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self, self.model.config.setupComplete else { return }
                self.bar?.place()
                self.bar?.orderFrontRegardless()
            }
        })

        if !model.config.setupComplete { openCaregiver() }
        else if model.config.fillScreen && !windowed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.enterFullScreen() }
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: windows

    func buildHomeWindow() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 800),
                         styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.collectionBehavior = [.fullScreenPrimary]
        let host = NSHostingView(rootView: RootView(model: model))
        host.sizingOptions = []
        w.contentView = host
        w.contentMinSize = NSSize(width: 640, height: 480)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        w.makeKeyAndOrderFront(nil)
        home = w
    }

    func enterFullScreen() {
        if !home.styleMask.contains(.fullScreen) { home.toggleFullScreen(nil) }
    }

    func openCaregiver() {
        if let w = caregiverWindow {
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            return
        }
        if home.styleMask.contains(.fullScreen) { home.toggleFullScreen(nil) }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 860), styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "Hearth — caregiver settings"
        let host = NSHostingView(rootView: CaregiverRoot(model: model) { [weak self] in self?.closeCaregiver() })
        host.sizingOptions = []
        w.contentView = host
        w.contentMinSize = NSSize(width: 700, height: 560)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        caregiverWindow = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeCaregiver() {
        guard let w = caregiverWindow else { return }
        caregiverWindow = nil
        w.delegate = nil
        w.close()
        model.lockCaregiver()
        if model.config.setupComplete && model.config.fillScreen && !windowed { enterFullScreen() }
        model.goHome()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === home { return false } // the person cannot close their home by accident
        return true
    }

    func windowWillClose(_ n: Notification) {
        if let w = n.object as? NSWindow, w === caregiverWindow { closeCaregiver() }
    }

    // MARK: quitting needs the caregiver PIN once setup is done

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model.config.setupComplete, model.hasPin, !model.caregiverUnlocked else { return .terminateNow }
        return askForPin() ? .terminateNow : .terminateCancel
    }

    func askForPin() -> Bool {
        var message = "Enter the caregiver PIN to close Hearth."
        while true {
            let alert = NSAlert()
            alert.messageText = "Close Hearth?"
            alert.informativeText = message
            alert.addButton(withTitle: "Close Hearth")
            alert.addButton(withTitle: "Cancel")
            let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
            alert.accessoryView = field
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            switch model.unlockCaregiver(pin: field.stringValue) {
            case .unlocked, .noPinSet: return true
            case .wrong(let left): message = "That PIN isn't right. \(left) \(left == 1 ? "try" : "tries") left."
            case .lockedOut(let s): message = "Too many tries. Please wait \(s) seconds."
            }
        }
    }

    // MARK: menu

    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let m = NSMenu()
        m.addItem(withTitle: "About Hearth", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        m.addItem(.separator())
        let cg = NSMenuItem(title: "Caregiver Settings…", action: #selector(openCaregiverAction), keyEquivalent: ",")
        cg.target = self
        m.addItem(cg)
        let h = NSMenuItem(title: "Go Home", action: #selector(goHomeAction), keyEquivalent: "h")
        h.keyEquivalentModifierMask = [.command, .shift]
        h.target = self
        m.addItem(h)
        m.addItem(.separator())
        m.addItem(withTitle: "Quit Hearth", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = m

        let editItem = NSMenuItem(); main.addItem(editItem)
        let e = NSMenu(title: "Edit")
        e.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        e.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        e.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        e.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        e.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = e
        NSApp.mainMenu = main
    }

    @objc func openCaregiverAction() { openCaregiver() }
    @objc func goHomeAction() { model.goHome() }

    // MARK: AppLauncher

    func open(_ launch: Launch) {
        switch launch {
        case .app(let id):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
                model.statusLine = "That app isn't on this computer. Please ask \(model.helperName)."
                return
            }
            let cfg = NSWorkspace.OpenConfiguration()
            cfg.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: cfg) { [weak self] _, error in
                guard error != nil else { return }
                Task { @MainActor in
                    guard let self = self else { return }
                    self.model.statusLine = "That app wouldn't open. Please ask \(self.model.helperName)."
                }
            }
        case .url(let u):
            NSWorkspace.shared.open(u)
        case .slideshow:
            break
        }
    }

    /// Hides, never quits: nothing the person was working on can be lost.
    func hideOtherApps() {
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != me {
            app.hide()
        }
    }

    func bringHomeForward() {
        NSApp.activate(ignoringOtherApps: true)
        home?.makeKeyAndOrderFront(nil)
    }

    // MARK: Speaker

    func say(_ text: String) {
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synth.speak(u)
    }

    static func defaultBrowser() -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!) else { return nil }
        return Bundle(url: url)?.bundleIdentifier
    }
}
