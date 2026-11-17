import SwiftUI
import AppKit
import HearthCore

// MARK: - look

struct Theme {
    let choice: ThemeChoice
    static func of(_ c: ThemeChoice) -> Theme { Theme(choice: c) }
    var high: Bool { choice == .highContrast }

    var background: Color {
        switch choice {
        case .light: return Color(red: 0.97, green: 0.95, blue: 0.91)
        case .dark: return Color(red: 0.09, green: 0.08, blue: 0.10)
        case .highContrast: return .black
        }
    }
    var text: Color {
        switch choice {
        case .light: return Color(red: 0.11, green: 0.10, blue: 0.08)
        case .dark: return Color(red: 0.95, green: 0.94, blue: 0.91)
        case .highContrast: return .white
        }
    }
    var secondary: Color {
        switch choice {
        case .light: return Color(red: 0.33, green: 0.31, blue: 0.27)
        case .dark: return Color(red: 0.72, green: 0.70, blue: 0.65)
        case .highContrast: return .white
        }
    }
    var card: Color {
        switch choice {
        case .light: return .white
        case .dark: return Color(red: 0.16, green: 0.15, blue: 0.18)
        case .highContrast: return .black
        }
    }
    var cardBorder: Color {
        switch choice {
        case .light: return Color.black.opacity(0.08)
        case .dark: return Color.white.opacity(0.10)
        case .highContrast: return .white
        }
    }
    var tileText: Color { .white }
    var tileBorder: Color? { high ? .white : nil }
    var helpFill: Color { high ? .yellow : Color(red: 0.78, green: 0.13, blue: 0.13) }
    var helpText: Color { high ? .black : .white }
    var okFill: Color { high ? .white : Color(red: 0.09, green: 0.50, blue: 0.27) }
    var okText: Color { high ? .black : .white }

    func tileFill(_ c: TileColor) -> Color {
        if high { return .black }
        switch c {
        case .blue: return Color(red: 0.10, green: 0.38, blue: 0.82)
        case .green: return Color(red: 0.09, green: 0.50, blue: 0.27)
        case .orange: return Color(red: 0.78, green: 0.36, blue: 0.00)
        case .red: return Color(red: 0.78, green: 0.13, blue: 0.13)
        case .purple: return Color(red: 0.46, green: 0.22, blue: 0.72)
        case .teal: return Color(red: 0.00, green: 0.45, blue: 0.50)
        case .pink: return Color(red: 0.74, green: 0.16, blue: 0.45)
        case .gray: return Color(red: 0.32, green: 0.33, blue: 0.38)
        }
    }
}

func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .rounded)
}

enum AppIcons {
    nonisolated(unsafe) private static var cache: [String: NSImage] = [:]
    static func icon(bundleID: String) -> NSImage? {
        if let c = cache[bundleID] { return c }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let img = NSWorkspace.shared.icon(forFile: url.path)
        cache[bundleID] = img
        return img
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A big, plainly labelled button used for everything that is not a tile.
struct BigButton: View {
    let title: String
    var symbol: String?
    let fill: Color
    let text: Color
    let s: CGFloat
    var border: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12 * s) {
                if let symbol = symbol { Image(systemName: symbol).font(rounded(28 * s, .bold)) }
                Text(title).font(rounded(26 * s, .bold)).lineLimit(2).minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 28 * s).padding(.vertical, 18 * s)
            .frame(minHeight: 72 * s)
            .background(RoundedRectangle(cornerRadius: 20 * s, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 20 * s, style: .continuous).stroke(border ?? .clear, lineWidth: 4 * s))
            .foregroundStyle(text)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

// MARK: - root

struct RootView: View {
    @ObservedObject var model: HearthModel

    var body: some View {
        ZStack {
            switch model.screen {
            case .home: HomeView(model: model)
            case .help: HelpView(model: model)
            case .slideshow(let folder): SlideshowView(model: model, folder: folder)
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .environment(\.colorScheme, model.config.theme == .light ? .light : .dark)
    }
}

// MARK: - home

struct HomeView: View {
    @ObservedObject var model: HearthModel
    var s: CGFloat { CGFloat(model.config.textSize.scale) }
    var theme: Theme { Theme.of(model.config.theme) }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22 * s) {
                header
                if let msg = model.statusLine { StatusBanner(message: msg, theme: theme, s: s) { model.statusLine = nil } }
                if !model.todayReminders.isEmpty { TodayCard(model: model, theme: theme, s: s) }
                if model.config.tiles.isEmpty { emptyState } else { grid }
            }
            .padding(.horizontal, 40 * s).padding(.vertical, 32 * s)

            if let r = model.activeReminder { ReminderOverlay(model: model, reminder: r, theme: theme, s: s) }
        }
    }

    var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4 * s) {
                Text(model.greeting).font(rounded(46 * s, .bold)).foregroundStyle(theme.text).lineLimit(1).minimumScaleFactor(0.5)
                Text(model.dateText).font(rounded(26 * s, .medium)).foregroundStyle(theme.secondary)
            }
            Spacer(minLength: 20 * s)
            VStack(alignment: .trailing, spacing: 12 * s) {
                Text(model.clockText).font(rounded(54 * s, .bold)).foregroundStyle(theme.text)
                    .accessibilityLabel("The time is \(model.clockText)")
                BigButton(title: "I need help", symbol: "questionmark.circle.fill", fill: theme.helpFill, text: theme.helpText, s: s * 0.85,
                          border: theme.high ? .white : nil) { model.showHelp() }
            }
        }
    }

    /// Sized to fit: with a normal number of buttons everything is visible at once, so nobody has to discover scrolling.
    /// Only when there are too many buttons for the screen (or the text is huge) does it scroll.
    var grid: some View {
        GeometryReader { geo in
            let spacing = 20 * s
            let n = max(model.config.tiles.count, 1)
            let cols = max(1, min(n, Int((geo.size.width + spacing) / (210 * s + spacing))))
            let rows = Int((Double(n) / Double(cols)).rounded(.up))
            let fitH = (geo.size.height - CGFloat(rows - 1) * spacing) / CGFloat(rows)
            let minH = 150 * s
            let fits = fitH >= minH
            let tileH = min(max(fitH, minH), 260 * s)
            let columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: cols)
            ZStack(alignment: .bottom) {
                ScrollView(fits ? [] : [.vertical], showsIndicators: !fits) {
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(model.config.tiles) { tile in
                            TileView(tile: tile, people: model.config.people, theme: theme, s: s, height: tileH) { model.open(tile) }
                        }
                    }
                    .padding(.bottom, fits ? 0 : 56 * s)
                }
                if !fits {
                    Label("More buttons below — scroll down", systemImage: "arrow.down.circle.fill")
                        .font(rounded(20 * s, .bold)).padding(.horizontal, 18 * s).padding(.vertical, 10 * s)
                        .background(Capsule().fill(theme.card)).overlay(Capsule().stroke(theme.cardBorder, lineWidth: theme.high ? 3 : 1))
                        .foregroundStyle(theme.text).padding(.bottom, 6 * s)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    var emptyState: some View {
        VStack(spacing: 18 * s) {
            Spacer()
            Image(systemName: "house.fill").font(.system(size: 64 * s)).foregroundStyle(theme.secondary)
            Text("Nothing is here yet").font(rounded(34 * s, .bold)).foregroundStyle(theme.text)
            Text("Someone in your family can add your people and apps. Ask them to open the settings.")
                .font(rounded(24 * s)).foregroundStyle(theme.secondary).multilineTextAlignment(.center)
            BigButton(title: "Open settings", symbol: "gearshape.fill", fill: theme.tileFill(.blue), text: .white, s: s, border: theme.tileBorder) {
                model.requestCaregiver()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct StatusBanner: View {
    let message: String
    let theme: Theme
    let s: CGFloat
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 14 * s) {
            Image(systemName: "info.circle.fill").font(.system(size: 30 * s)).foregroundStyle(Color.orange)
            Text(message).font(rounded(24 * s, .medium)).foregroundStyle(theme.text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("OK", action: dismiss).font(rounded(22 * s, .bold)).buttonStyle(.bordered).controlSize(.large)
        }
        .padding(18 * s)
        .background(RoundedRectangle(cornerRadius: 18 * s, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18 * s, style: .continuous).stroke(Color.orange, lineWidth: 3))
    }
}

struct TodayCard: View {
    @ObservedObject var model: HearthModel
    let theme: Theme
    let s: CGFloat

    /// With big text there is little room: show just what is next.
    var compact: Bool { s >= 1.2 }
    var rows: [Reminder] {
        compact ? Array(model.todayReminders.filter { !model.isDone($0) }.prefix(1)) : Array(model.todayReminders.prefix(3))
    }
    var nextID: UUID? { rows.first { !model.isDone($0) && ($0.hour, $0.minute) >= hm(model.now) }?.id }

    func hm(_ d: Date) -> (Int, Int) {
        let c = model.calendar.dateComponents([.hour, .minute], from: d)
        return (c.hour ?? 0, c.minute ?? 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * s) {
            Text(compact ? "NEXT TO DO" : "TODAY").font(rounded(18 * s, .bold)).foregroundStyle(theme.secondary)
            if compact && rows.isEmpty {
                Label("All done for today", systemImage: "checkmark.circle.fill")
                    .font(rounded(24 * s, .bold)).foregroundStyle(theme.okFill == .white ? theme.text : theme.okFill)
            }
            ForEach(rows) { r in
                HStack(spacing: 14 * s) {
                    Image(systemName: model.isDone(r) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 28 * s)).foregroundStyle(model.isDone(r) ? theme.okFill : theme.secondary)
                    Text(Reminders.timeText(hour: r.hour, minute: r.minute)).font(rounded(24 * s, .bold)).foregroundStyle(theme.text)
                    Text(r.text).font(rounded(24 * s, r.id == nextID ? .bold : .regular)).foregroundStyle(theme.text).lineLimit(1)
                    Spacer()
                    if r.id == nextID && !compact { Text("NEXT").font(rounded(15 * s, .heavy)).padding(.horizontal, 10 * s).padding(.vertical, 4 * s)
                        .background(Capsule().fill(theme.high ? Color.yellow : theme.tileFill(.blue))).foregroundStyle(theme.high ? Color.black : Color.white) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(20 * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22 * s, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 22 * s, style: .continuous).stroke(theme.cardBorder, lineWidth: theme.high ? 3 : 1))
    }
}

struct TileView: View {
    let tile: Tile
    let people: [Person]
    let theme: Theme
    let s: CGFloat
    var height: CGFloat? = nil
    let action: () -> Void

    var person: Person? { people.first { $0.id == tile.personID } }
    var iconSize: CGFloat { height.map { min(84 * s, max(44 * s, $0 - 32 * s - 78 * s)) } ?? 84 * s }

    var spoken: String {
        switch tile.kind {
        case .video: return "Video call \(tile.title)"
        case .call: return tile.title
        case .message: return "Text \(person?.name ?? tile.title)"
        case .email: return "Email \(person?.name ?? tile.title)"
        default: return tile.title
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12 * s) {
                icon
                Text(tile.title).font(rounded(26 * s, .bold)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.75)
                if tile.kind == .video || tile.kind == .call {
                    Text(tile.kind == .video ? "Video call" : "Phone call").font(rounded(17 * s, .medium)).opacity(0.9)
                }
            }
            .padding(16 * s)
            .frame(maxWidth: .infinity, minHeight: height ?? 190 * s, maxHeight: height)
            .background(RoundedRectangle(cornerRadius: 28 * s, style: .continuous).fill(theme.tileFill(tile.color)))
            .overlay(RoundedRectangle(cornerRadius: 28 * s, style: .continuous).stroke(theme.tileBorder ?? .clear, lineWidth: 5 * s))
            .foregroundStyle(theme.tileText)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(spoken)
    }

    @ViewBuilder var icon: some View {
        switch tile.kind {
        case .app:
            if let img = AppIcons.icon(bundleID: tile.target) {
                Image(nsImage: img).resizable().interpolation(.high).frame(width: iconSize, height: iconSize)
            } else { symbol("app.fill") }
        case .video, .call, .message, .email:
            personBadge
        case .website: symbol(tile.symbol ?? "globe")
        case .photos: symbol(tile.symbol ?? "photo.on.rectangle.angled")
        }
    }

    func symbol(_ name: String) -> some View {
        Image(systemName: name).font(.system(size: iconSize * 0.74, weight: .semibold)).frame(width: iconSize, height: iconSize)
    }

    var personBadge: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let path = person?.photoPath, let img = NSImage(contentsOfFile: path) {
                    Image(nsImage: img).resizable().scaledToFill()
                } else {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.25))
                        Text(person?.initials ?? String(tile.title.prefix(1))).font(rounded(iconSize * 0.45, .bold))
                    }
                }
            }
            .frame(width: iconSize * 1.05, height: iconSize * 1.05).clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.85), lineWidth: 3 * s))
            Image(systemName: tile.symbol ?? "video.fill").font(.system(size: max(13 * s, iconSize * 0.24), weight: .bold))
                .padding(max(5 * s, iconSize * 0.09)).background(Circle().fill(Color.white)).foregroundStyle(theme.high ? Color.black : theme.tileFill(tile.color))
                .offset(x: iconSize * 0.07, y: iconSize * 0.07)
        }
    }
}

struct ReminderOverlay: View {
    @ObservedObject var model: HearthModel
    let reminder: Reminder
    let theme: Theme
    let s: CGFloat

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 26 * s) {
                Image(systemName: "bell.fill").font(.system(size: 56 * s)).foregroundStyle(Color.orange)
                Text(Reminders.timeText(hour: reminder.hour, minute: reminder.minute)).font(rounded(30 * s, .semibold)).foregroundStyle(theme.secondary)
                Text(reminder.text).font(rounded(52 * s, .bold)).multilineTextAlignment(.center).foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 20 * s) {
                    BigButton(title: "I've done it", symbol: "checkmark.circle.fill", fill: theme.okFill, text: theme.okText, s: s,
                              border: theme.high ? .white : nil) { model.completeReminder() }
                    BigButton(title: "Remind me in 10 minutes", symbol: "clock.fill", fill: theme.tileFill(.gray), text: .white, s: s,
                              border: theme.tileBorder) { model.snoozeReminder(minutes: 10) }
                }
            }
            .padding(44 * s)
            .frame(maxWidth: 900 * s)
            .background(RoundedRectangle(cornerRadius: 34 * s, style: .continuous).fill(theme.card))
            .overlay(RoundedRectangle(cornerRadius: 34 * s, style: .continuous).stroke(theme.cardBorder, lineWidth: theme.high ? 4 : 1))
            .padding(40 * s)
        }
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - help

struct HelpView: View {
    @ObservedObject var model: HearthModel
    var s: CGFloat { CGFloat(model.config.textSize.scale) }
    var theme: Theme { Theme.of(model.config.theme) }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 26 * s) {
                    BigButton(title: "Back home", symbol: "house.fill", fill: theme.tileFill(.blue), text: .white, s: s, border: theme.tileBorder) { model.goHome() }
                    Text("Do you need help?").font(rounded(48 * s, .bold)).foregroundStyle(theme.text)
                    if let h = model.config.helper { helperCard(h) } else {
                        Text("Nobody has been added to call yet. Please ask your family to set this up.")
                            .font(rounded(26 * s)).foregroundStyle(theme.text)
                    }
                    safetyCard
                }
                .padding(.horizontal, 40 * s).padding(.vertical, 32 * s)
            }
        }
    }

    func helperCard(_ h: Person) -> some View {
        VStack(alignment: .leading, spacing: 18 * s) {
            Text(h.relation.isEmpty ? h.name : "\(h.name) — your \(h.relation)").font(rounded(32 * s, .bold)).foregroundStyle(theme.text)
            HStack(spacing: 20 * s) {
                BigButton(title: "Video call \(h.name)", symbol: "video.fill", fill: theme.okFill, text: theme.okText, s: s, border: theme.high ? .white : nil) { model.callHelper(video: true) }
                BigButton(title: "Phone \(h.name)", symbol: "phone.fill", fill: theme.tileFill(.teal), text: .white, s: s, border: theme.tileBorder) { model.callHelper(video: false) }
            }
            Text("\(h.name)'s number: \(h.handle)").font(rounded(28 * s, .semibold)).foregroundStyle(theme.secondary)
        }
        .padding(24 * s).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24 * s, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 24 * s, style: .continuous).stroke(theme.cardBorder, lineWidth: theme.high ? 3 : 1))
    }

    var safetyCard: some View {
        VStack(alignment: .leading, spacing: 14 * s) {
            HStack(spacing: 12 * s) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 34 * s)).foregroundStyle(theme.high ? Color.yellow : Color.orange)
                Text("Stay safe").font(rounded(32 * s, .bold)).foregroundStyle(theme.text)
            }
            ForEach(["Nobody from Apple, Microsoft or your bank will phone you about a computer problem. If someone does, hang up.",
                     "Never let a stranger take control of this computer, and never read out a password or card number.",
                     "If you are not sure, call \(model.helperName) first. It is always fine to ask."], id: \.self) { line in
                HStack(alignment: .top, spacing: 12 * s) {
                    Text("•").font(rounded(28 * s, .bold)).foregroundStyle(theme.text)
                    Text(line).font(rounded(26 * s)).foregroundStyle(theme.text).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(24 * s).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24 * s, style: .continuous).fill(theme.high ? Color.black : Color.orange.opacity(theme.choice == .dark ? 0.18 : 0.14)))
        .overlay(RoundedRectangle(cornerRadius: 24 * s, style: .continuous).stroke(theme.high ? Color.yellow : Color.orange, lineWidth: 3))
    }
}

// MARK: - photos

struct SlideshowView: View {
    @ObservedObject var model: HearthModel
    let folder: String
    @Local private var files: [String] = []
    @Local private var index = 0
    @Local private var playing = true
    private let timer = Timer.publish(every: 8, on: .main, in: .common).autoconnect()

    var s: CGFloat { CGFloat(model.config.textSize.scale) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                ZStack {
                    if files.indices.contains(index), let img = NSImage(contentsOfFile: files[index]) {
                        Image(nsImage: img).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                            .accessibilityLabel("Photo \(index + 1) of \(files.count)")
                    } else {
                        Text("No photos to show").font(rounded(34 * s)).foregroundStyle(.white)
                    }
                }
                HStack(spacing: 18 * s) {
                    BigButton(title: "Back", symbol: "chevron.left", fill: .white, text: .black, s: s) { step(-1) }
                    BigButton(title: playing ? "Pause" : "Play", symbol: playing ? "pause.fill" : "play.fill", fill: .white.opacity(0.85), text: .black, s: s) { playing.toggle() }
                    BigButton(title: "Next", symbol: "chevron.right", fill: .white, text: .black, s: s) { step(1) }
                    Spacer()
                    Text("\(min(index + 1, max(files.count, 1))) of \(files.count)").font(rounded(24 * s, .medium)).foregroundStyle(.white.opacity(0.85))
                    BigButton(title: "Home", symbol: "house.fill", fill: Color(red: 0.10, green: 0.38, blue: 0.82), text: .white, s: s) { model.closeScreen() }
                }
                .padding(20 * s)
                .background(Color.black)
            }
        }
        .onAppear { files = Slideshow.images(in: folder); index = 0 }
        .onReceive(timer) { _ in if playing { step(1) } }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onKeyPress(.escape) { model.closeScreen(); return .handled }
    }

    func step(_ d: Int) { index = Slideshow.wrap(index, by: d, count: files.count) }
}
