import SwiftUI
import AppKit
import HearthCore
import ServiceManagement
import UniformTypeIdentifiers

struct CaregiverRoot: View {
    @ObservedObject var model: HearthModel
    let onClose: () -> Void

    var body: some View {
        if model.canEdit { CaregiverView(model: model, onClose: onClose) } else { PinGateView(model: model) }
    }
}

struct PinGateView: View {
    @ObservedObject var model: HearthModel
    @Local private var pin = ""
    @Local private var message = ""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 40)).foregroundStyle(.secondary)
            Text("Caregiver settings").font(.title2.bold())
            Text("Enter the caregiver PIN to change Hearth.").foregroundStyle(.secondary)
            SecureField("PIN", text: $pin).textFieldStyle(.roundedBorder).frame(width: 160).onSubmit(submit)
            Text(message).foregroundStyle(.red).frame(height: 20)
            Button("Unlock", action: submit).keyboardShortcut(.defaultAction).disabled(pin.isEmpty).controlSize(.large)
        }
        .padding(40)
        .frame(width: 420, height: 340)
    }

    func submit() {
        switch model.unlockCaregiver(pin: pin) {
        case .unlocked, .noPinSet: message = ""
        case .wrong(let left): message = "That PIN isn't right. \(left) \(left == 1 ? "try" : "tries") left."
        case .lockedOut(let s): message = "Too many tries. Please wait \(s) seconds."
        }
        pin = ""
    }
}

enum AddKind: String, Identifiable {
    case app, website, video, call, message, email, photos
    var id: String { rawValue }
    var title: String {
        switch self {
        case .app: return "Add an app"
        case .website: return "Add a website"
        case .video: return "Add a video call button"
        case .call: return "Add a phone call button"
        case .message: return "Add a text message button"
        case .email: return "Add an email button"
        case .photos: return "Add a photo slideshow"
        }
    }
}

struct CaregiverView: View {
    @ObservedObject var model: HearthModel
    let onClose: () -> Void
    @Local private var adding: AddKind?
    @Local private var newPin = ""
    @Local private var info = ""

    func bind<T>(_ kp: WritableKeyPath<HearthConfig, T>) -> Binding<T> {
        Binding(get: { model.config[keyPath: kp] }, set: { v in model.update { $0[keyPath: kp] = v } })
    }

    func person(_ id: UUID) -> Binding<Person> {
        Binding(get: { model.config.people.first { $0.id == id } ?? Person(name: "", handle: "") },
                set: { v in model.update { c in if let i = c.people.firstIndex(where: { $0.id == id }) { c.people[i] = v } } })
    }

    func reminder(_ id: UUID) -> Binding<Reminder> {
        Binding(get: { model.config.reminders.first { $0.id == id } ?? Reminder(text: "", hour: 9) },
                set: { v in model.update { c in if let i = c.reminders.firstIndex(where: { $0.id == id }) { c.reminders[i] = v } } })
    }

    func card<Content: View>(_ title: String, _ subtitle: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            if let s = subtitle { Text(s).font(.callout).foregroundStyle(.secondary) }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                titleBar
                ownerCard
                peopleCard
                tilesCard
                remindersCard
                lookCard
                safetyCard
                shareCard
                if !info.isEmpty { Text(info).font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(24)
        }
        .frame(minWidth: 700, minHeight: 640)
        .sheet(item: $adding) { kind in AddTileSheet(model: model, kind: kind) { adding = nil } }
    }

    // MARK: sections

    var titleBar: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(red: 0.86, green: 0.40, blue: 0.14))
                Image(systemName: "house.fill").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            }.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.config.setupComplete ? "Hearth caregiver settings" : "Let's set up Hearth").font(.title2.bold())
                Text(model.config.setupComplete ? "Changes appear on the home screen straight away."
                     : "A calm, simple home screen with big buttons. You can change everything later.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.hasPin && model.config.setupComplete { Button("Lock") { model.lockCaregiver(); onClose() } }
            Button(model.config.setupComplete ? "Done" : "Finish setup") {
                if !model.config.setupComplete { model.completeSetup() }
                onClose()
            }
            .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
        }
    }

    var ownerCard: some View {
        card("Who is this Mac for?") {
            TextField("Their first name, e.g. Dorothy", text: bind(\.ownerName)).textFieldStyle(.roundedBorder).frame(maxWidth: 320)
        }
    }

    var peopleCard: some View {
        card("People they can call", "The main helper is who the “I need help” button calls. Use a phone number or an Apple ID email.") {
            ForEach(model.config.people) { p in
                let b = person(p.id)
                HStack(spacing: 10) {
                    TextField("Name", text: b.name).textFieldStyle(.roundedBorder).frame(width: 130)
                    TextField("Phone or email", text: b.handle).textFieldStyle(.roundedBorder).frame(width: 190)
                    TextField("e.g. daughter", text: b.relation).textFieldStyle(.roundedBorder).frame(width: 110)
                    Toggle("Main helper", isOn: Binding(get: { b.wrappedValue.isHelper },
                                                       set: { v in model.update { c in for i in c.people.indices { c.people[i].isHelper = v && c.people[i].id == p.id } } }))
                        .toggleStyle(.checkbox)
                    Button { model.update { $0.removePerson(id: p.id) } } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(p.name)")
                }
                if !p.handle.isEmpty && Launching.normalizeHandle(p.handle) == nil {
                    Text("“\(p.handle)” doesn't look like a phone number or an email address.").font(.caption).foregroundStyle(.red)
                }
            }
            Button { adding = .video } label: { Label("Add a person", systemImage: "person.badge.plus") }
        }
    }

    var tilesCard: some View {
        card("Buttons on the home screen", "Keep it short: six to eight big buttons is plenty. The order here is the order they appear.") {
            ForEach(Array(model.config.tiles.enumerated()), id: \.element.id) { i, t in
                HStack(spacing: 10) {
                    Circle().fill(Theme.of(.light).tileFill(t.color)).frame(width: 14, height: 14)
                    Text(t.title).frame(width: 190, alignment: .leading)
                    Text(kindLabel(t.kind)).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
                    Spacer()
                    Button { model.update { $0.moveTile(from: i, to: i - 1) } } label: { Image(systemName: "arrow.up") }
                        .disabled(i == 0).buttonStyle(.borderless).accessibilityLabel("Move \(t.title) up")
                    Button { model.update { $0.moveTile(from: i, to: i + 1) } } label: { Image(systemName: "arrow.down") }
                        .disabled(i == model.config.tiles.count - 1).buttonStyle(.borderless).accessibilityLabel("Move \(t.title) down")
                    Button { model.update { c in c.tiles.removeAll { $0.id == t.id } } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless).accessibilityLabel("Remove \(t.title)")
                }
            }
            HStack {
                Menu {
                    Button("An app…") { adding = .app }
                    Button("A website…") { adding = .website }
                    Button("Family photos slideshow…") { adding = .photos }
                    Divider()
                    Button("Video call a person…") { adding = .video }
                    Button("Phone call a person…") { adding = .call }
                    Button("Text message a person…") { adding = .message }
                    Button("Email a person…") { adding = .email }
                } label: { Label("Add a button", systemImage: "plus.circle.fill") }
                    .menuStyle(.borderlessButton).fixedSize()
                Button("Add the everyday apps") { addEverydayApps() }
                    .help("Messages, Mail, Safari, Photos, Calendar and so on, if they are installed")
            }
        }
    }

    func kindLabel(_ k: TileKind) -> String {
        switch k {
        case .app: return "App"; case .website: return "Website"; case .video: return "Video call"; case .call: return "Phone call"
        case .message: return "Text message"; case .email: return "Email"; case .photos: return "Photo slideshow"
        }
    }

    func addEverydayApps() {
        let installed = Set(AppCatalog.installed().map(\.bundleID))
        let have = Set(model.config.tiles.filter { $0.kind == .app }.map(\.target))
        model.update { c in
            for r in AppCatalog.recommended where installed.contains(r.bundleID) && !have.contains(r.bundleID) && c.tiles.count < 12 {
                c.tiles.append(.app(r.bundleID, r.title, color: r.color))
            }
        }
    }

    var remindersCard: some View {
        card("Reminders", "A big message appears and is read aloud at these times. Good for tablets, appointments and phone calls.") {
            ForEach(model.config.reminders) { r in
                let b = reminder(r.id)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        TextField("What should it say?", text: b.text).textFieldStyle(.roundedBorder)
                        DatePicker("", selection: timeBinding(r.id), displayedComponents: .hourAndMinute).labelsHidden().frame(width: 100)
                        Toggle("Read aloud", isOn: b.speak).toggleStyle(.checkbox)
                        Button { model.update { c in c.reminders.removeAll { $0.id == r.id } } } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless).accessibilityLabel("Remove reminder")
                    }
                    HStack(spacing: 6) {
                        ForEach(1...7, id: \.self) { d in
                            let on = r.weekdays.isEmpty || r.weekdays.contains(d)
                            Button(Calendar.current.veryShortWeekdaySymbols[d - 1]) { toggleDay(r.id, d) }
                                .buttonStyle(.bordered).tint(on ? .accentColor : .gray).controlSize(.small)
                                .accessibilityLabel(Calendar.current.weekdaySymbols[d - 1] + (on ? ", on" : ", off"))
                        }
                        Text(r.weekdays.isEmpty ? "every day" : "").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Divider()
            }
            Button { model.update { $0.reminders.append(Reminder(text: "", hour: 9)) } } label: { Label("Add a reminder", systemImage: "bell.badge") }
        }
    }

    func timeBinding(_ id: UUID) -> Binding<Date> {
        Binding(get: {
            let r = model.config.reminders.first { $0.id == id } ?? Reminder(text: "", hour: 9)
            return Calendar.current.date(bySettingHour: r.hour, minute: r.minute, second: 0, of: Date()) ?? Date()
        }, set: { d in
            let c = Calendar.current.dateComponents([.hour, .minute], from: d)
            model.update { cfg in if let i = cfg.reminders.firstIndex(where: { $0.id == id }) { cfg.reminders[i].hour = c.hour ?? 9; cfg.reminders[i].minute = c.minute ?? 0 } }
        })
    }

    func toggleDay(_ id: UUID, _ day: Int) {
        model.update { c in
            guard let i = c.reminders.firstIndex(where: { $0.id == id }) else { return }
            var days = Set(c.reminders[i].weekdays.isEmpty ? Array(1...7) : c.reminders[i].weekdays)
            if days.contains(day) { days.remove(day) } else { days.insert(day) }
            c.reminders[i].weekdays = (days.count == 7 || days.isEmpty) ? [] : days.sorted()
        }
    }

    var lookCard: some View {
        card("How it looks") {
            HStack {
                Text("Text size").frame(width: 90, alignment: .leading)
                Picker("", selection: bind(\.textSize)) { ForEach(TextSize.allCases, id: \.self) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
            }
            HStack {
                Text("Colours").frame(width: 90, alignment: .leading)
                Picker("", selection: bind(\.theme)) { ForEach(ThemeChoice.allCases, id: \.self) { Text($0.label).tag($0) } }
                    .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 360)
            }
            Toggle("Fill the whole screen when Hearth opens", isOn: bind(\.fillScreen))
            Toggle("Open Hearth automatically when this Mac starts", isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in do { if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() } }
                       catch { info = "Couldn't change the start-up setting. Move Hearth to the Applications folder first." } }))
        }
    }

    var safetyCard: some View {
        card("Keeping things safe") {
            Toggle("Only allow the apps on the home screen", isOn: bind(\.strictMode))
            Text("If something else comes to the front (for example from a pop-up), Hearth sends them back home with a friendly note. Password prompts and system alerts are never blocked. While you are in these settings the rule is paused.")
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            HStack {
                SecureField(model.hasPin ? "New PIN (4–8 digits)" : "Choose a PIN (4–8 digits)", text: $newPin).textFieldStyle(.roundedBorder).frame(width: 220)
                Button(model.hasPin ? "Change PIN" : "Set PIN") {
                    if model.setPin(newPin) { info = "PIN saved. You'll need it to open these settings or to quit Hearth."; newPin = "" }
                    else { info = "A PIN is 4 to 8 digits." }
                }.disabled(newPin.isEmpty)
            }
            Text("The PIN keeps accidents out of the settings. It is not a vault: for real enforcement also use a separate standard Mac account for them.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    var shareCard: some View {
        card("Share this setup", "Set Hearth up on your own Mac, save the file, and send it to them. The PIN is never included.") {
            HStack {
                Button("Save a setup file…") { exportSetup() }
                Button("Use a setup file…") { importSetup() }
            }
        }
    }

    func exportSetup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(model.config.ownerName.isEmpty ? "Hearth" : model.config.ownerName) setup.hearth"
        panel.allowedContentTypes = [UTType.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.exportSetup().write(to: url); info = "Saved. Send that file to them and choose “Use a setup file…” on their Mac." }
        catch { info = "Couldn't save the file: \(error.localizedDescription)" }
    }

    func importSetup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        do {
            let warnings = try model.importSetup(data)
            info = warnings.isEmpty ? "Setup loaded." : "Setup loaded. " + warnings.joined(separator: " ")
        } catch { info = "\(error)" }
    }
}

// MARK: - adding a button

struct AddTileSheet: View {
    @ObservedObject var model: HearthModel
    let kind: AddKind
    let close: () -> Void

    @Local private var query = ""
    @Local private var chosenApp: AppInfo?
    @Local private var title = ""
    @Local private var address = ""
    @Local private var personID: UUID?
    @Local private var newName = ""
    @Local private var newHandle = ""
    @Local private var newRelation = ""
    @Local private var folder = ""
    @Local private var error = ""
    @Local private var color: TileColor = .blue
    private let apps = AppCatalog.installed()

    var isPersonKind: Bool { [.video, .call, .message, .email].contains(kind) }

    var filtered: [AppInfo] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty ? apps : apps.filter { $0.name.lowercased().contains(q) }
    }

    var canAdd: Bool {
        switch kind {
        case .app: return chosenApp != nil
        case .website: return !address.trimmingCharacters(in: .whitespaces).isEmpty
        case .photos: return !folder.isEmpty
        default: return personID != nil || (!newName.trimmingCharacters(in: .whitespaces).isEmpty && !newHandle.isEmpty)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(kind.title).font(.title3.bold())
            switch kind {
            case .app: appPicker
            case .website:
                TextField("Name on the button, e.g. Weather", text: $title).textFieldStyle(.roundedBorder)
                TextField("Web address, e.g. weather.com", text: $address).textFieldStyle(.roundedBorder)
            case .photos:
                TextField("Name on the button", text: $title).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Choose a folder…") { chooseFolder() }
                    Text(folder.isEmpty ? "No folder chosen" : (folder as NSString).abbreviatingWithTildeInPath).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
            default: personPicker
            }
            if kind != .app { swatches }
            Text(error).foregroundStyle(.red).font(.callout).frame(minHeight: 18)
            HStack {
                Spacer()
                Button("Cancel", action: close)
                Button("Add", action: add).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(!canAdd)
            }
        }
        .padding(24)
        .frame(width: 540)
        .onAppear { color = defaultColor; personID = model.config.people.first?.id }
    }

    var defaultColor: TileColor {
        switch kind { case .website: return .teal; case .photos: return .pink; case .app: return .blue; default: return .green }
    }

    var appPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search your apps", text: $query).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered) { a in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: a.path)).resizable().frame(width: 28, height: 28)
                            Text(a.name)
                            Spacer()
                            if chosenApp == a { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(chosenApp == a ? Color.accentColor.opacity(0.12) : Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture { chosenApp = a; title = a.name }
                    }
                }
            }
            .frame(height: 280)
            .background(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
            TextField("Name on the button", text: $title).textFieldStyle(.roundedBorder)
        }
    }

    var personPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.config.people.isEmpty {
                Picker("Who", selection: $personID) {
                    ForEach(model.config.people) { Text($0.name).tag(Optional($0.id)) }
                    Text("Someone new…").tag(Optional<UUID>.none)
                }
            }
            if personID == nil {
                TextField("Name", text: $newName).textFieldStyle(.roundedBorder)
                TextField(kind == .email ? "Email address" : "Phone number or Apple ID email", text: $newHandle).textFieldStyle(.roundedBorder)
                TextField("How are they related? e.g. grandson", text: $newRelation).textFieldStyle(.roundedBorder)
            }
        }
    }

    var swatches: some View {
        HStack(spacing: 8) {
            Text("Colour").foregroundStyle(.secondary)
            ForEach(TileColor.allCases, id: \.self) { c in
                Circle().fill(Theme.of(.light).tileFill(c)).frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.primary, lineWidth: color == c ? 3 : 0))
                    .onTapGesture { color = c }
                    .accessibilityLabel(c.rawValue)
            }
        }
    }

    func chooseFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        if p.runModal() == .OK, let u = p.url { folder = u.path; if title.isEmpty { title = "Family photos" } }
    }

    func add() {
        error = ""
        var tile: Tile?
        switch kind {
        case .app:
            guard let a = chosenApp else { return }
            tile = .app(a.bundleID, title.isEmpty ? a.name : title, color: AppCatalog.recommended.first { $0.bundleID == a.bundleID }?.color ?? color)
        case .website:
            guard Launching.normalizeWebsite(address) != nil else { error = "That doesn't look like a web address. Try something like weather.com"; return }
            tile = .website(address.trimmingCharacters(in: .whitespaces), title.isEmpty ? address : title, color: color)
        case .photos:
            tile = .photos(folder, title.isEmpty ? "Family photos" : title, color: color)
        default:
            var p = model.config.people.first { $0.id == personID }
            if p == nil {
                guard let h = Launching.normalizeHandle(newHandle) else { error = "Please enter a phone number or an email address."; return }
                if kind == .email && !Launching.isEmail(h) { error = "Please enter an email address."; return }
                let np = Person(name: newName.trimmingCharacters(in: .whitespaces), handle: h, relation: newRelation, isHelper: model.config.people.isEmpty)
                model.update { $0.people.append(np) }
                p = np
            }
            guard let person = p else { return }
            switch kind {
            case .video: tile = .video(person, color: color)
            case .call: tile = .call(person, color: color)
            case .message: tile = Tile(kind: .message, title: "Text \(person.name)", target: person.handle, personID: person.id, symbol: "message.fill", color: color)
            default: tile = Tile(kind: .email, title: "Email \(person.name)", target: person.handle, personID: person.id, symbol: "envelope.fill", color: color)
            }
        }
        if let t = tile, Launching.launch(for: t, people: model.config.people) != nil {
            model.update { $0.tiles.append(t) }
            close()
        } else if error.isEmpty { error = "That button can't be created. Please check the details." }
    }
}
