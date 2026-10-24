import AppKit
import SwiftUI
import ServiceManagement
import NavigationCore

final class AppModel: ObservableObject {
    @Published var draft = NavigationConfig()
    @Published var message = ""
    @Published var status = "Starting…"
    @Published var permission = false
    @Published var paused = false
    @Published var launchAtLogin = false
    @Published var loginNeedsApproval = false
    let configURL: URL
    let input = InputController()
    private let configurationFile: ConfigurationFile
    private var validConfiguration = false
    private var sound: NSSound?
    var statusChanged: (() -> Void)?
    init(configURL: URL) {
        self.configURL = configURL
        configurationFile = ConfigurationFile(url: configURL)
        if let resource = Bundle.main.url(forResource: "Click", withExtension: "wav") { sound = NSSound(contentsOf: resource, byReference: true) }
        input.onStatus = { [weak self] value in self?.status = value; self?.statusChanged?() }
        input.onPermission = { [weak self] value in
            guard let self else { return }
            if self.permission != value { self.permission = value; self.statusChanged?() }
        }
        input.onClick = { [weak self] in self?.playClick() }
        reload()
        refreshLogin()
    }
    func reload() {
        do {
            let config = try configurationFile.load()
            draft = config; validConfiguration = true
            input.configure(config)
            message = !FileManager.default.fileExists(atPath: configURL.path) ? "Using built-in defaults. Save to create your TOML configuration." : "Loaded configuration."
            input.setPaused(paused)
        } catch {
            validConfiguration = false
            input.setPaused(true)
            message = error.localizedDescription
            status = "Configuration needs attention"
        }
    }
    func start() { if validConfiguration { input.start() } }
    func save() {
        do {
            let config = try configurationFile.save(draft)
            draft = config; validConfiguration = true
            input.configure(config); input.setPaused(paused); input.start()
            message = "Saved and applied."
        } catch { message = error.localizedDescription }
    }
    func togglePause() {
        guard validConfiguration else { message = "Fix or reload your configuration first."; return }
        paused.toggle(); input.setPaused(paused); statusChanged?()
    }
    func requestPermission() {
        input.checkPermission(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func refreshLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }
    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLogin()
            if loginNeedsApproval { message = "Approve Vimstride in Login Items." }
        } catch { refreshLogin(); message = "Launch at login: \(error.localizedDescription)" }
    }
    func playClick() {
        guard draft.clickSound else { return }
        sound?.stop(); sound?.volume = Float(draft.soundVolume); sound?.play()
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "cursorarrow.motionlines").font(.system(size: 32)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Vimstride").font(.title2.bold())
                    Text(model.permission ? (model.paused ? "Paused" : model.status) : "Accessibility permission required").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            TabView {
                general.tabItem { Label("General", systemImage: "slider.horizontal.3") }
                shortcuts.tabItem { Label("Keybindings", systemImage: "keyboard") }
                guide.tabItem { Label("Guide", systemImage: "questionmark.circle") }
            }.padding(.horizontal, 20)
            Divider().padding(.top, 14)
            HStack {
                Text(model.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(3)
                Spacer()
                Button("Reload TOML") { model.reload() }
                Button("Save & Apply") { model.save() }.keyboardShortcut("s", modifiers: .command).buttonStyle(.borderedProminent)
            }.padding(20)
        }.frame(width: 760, height: 650)
    }
    private var general: some View {
        Form {
            Section("Access & startup") {
                HStack {
                    Label(model.permission ? "Accessibility enabled" : "Allow control of your Mac", systemImage: model.permission ? "checkmark.shield" : "hand.raised")
                    Spacer()
                    Button(model.permission ? "Open Accessibility Settings" : "Grant Accessibility Access") { model.requestPermission() }
                }
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLogin($0) }))
                if model.loginNeedsApproval { Button("Approve in Login Items…") { SMAppService.openSystemSettingsLoginItems() } }
                Button(model.paused ? "Resume navigation" : "Pause navigation") { model.togglePause() }
            }
            Section("Pointer & feedback") {
                HStack { Text("Pointer speed"); Slider(value: $model.draft.pointerSpeed, in: 50...2000, step: 50); Text("\(Int(model.draft.pointerSpeed)) pt/s").monospacedDigit().frame(width: 85) }
                Stepper("Hint label size: \(model.draft.hintLabelSize) pt", value: $model.draft.hintLabelSize, in: 9...33, step: 2)
                Toggle("Play a subtle sound after clicking", isOn: $model.draft.clickSound)
                HStack { Text("Sound volume"); Slider(value: $model.draft.soundVolume, in: 0...1); Button("Preview") { model.playClick() } }
            }
            Section("Dotfiles") {
                Text(model.configURL.path).font(.caption.monospaced()).textSelection(.enabled)
                Text("Settings and TOML use the same configuration. Saving updates this file; reload after editing it externally.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Reveal Configuration") { NSWorkspace.shared.activateFileViewerSelecting([model.configURL]) }
                    Button("Use Super Defaults") { model.draft = NavigationConfig(); model.message = "Super defaults selected. Save & Apply to use them." }
                }
            }
        }.formStyle(.grouped).onAppear { model.refreshLogin() }
    }
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Super is Command + Control + Shift, matching your Karabiner Caps Lock mapping. Bindings accept names such as super+f, shift+tab, and right_option.").font(.callout).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(NavigationConfig.bindingOrder, id: \.self) { action in
                        HStack {
                            Text(action.replacingOccurrences(of: "_", with: " ").capitalized).frame(width: 210, alignment: .leading)
                            TextField("Shortcut", text: Binding(get: { model.draft.bindings[action] ?? "" }, set: { model.draft.bindings[action] = $0 })).textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced)).accessibilityLabel(action)
                        }
                    }
                }.padding(8)
            }
            Text("Movement and click bindings are relative to the held Super key. Global mode shortcuts include Super. Changes take effect when saved.").font(.caption).foregroundStyle(.secondary)
        }.padding(18)
    }
    private var guide: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                guideRow("Move & drag", "Hold Super and use H/J/K/L. Hold Space while moving to drag; release Space to drop. Super+R right-clicks. Releasing Super stops movement and releases a drag immediately.")
                guideRow("Click & focus", "Super+F shows labels. Release Super, then type a label to click. Tab / Shift+Tab browses targets, Return clicks, Shift+Return right-clicks, Command+Return opens a link in a new tab. Option+Return focuses without clicking. Super+V opens focus-only hints.")
                guideRow("Scroll", "Super+G, release Super, then H/J/K/L scrolls. Shift dashes faster, U/D moves half a page, T/B moves toward the top/bottom, Tab switches containers, and 1–9 selects a container. Escape exits.")
                guideRow("Precision & speed", "While moving, hold Right Control for precision or Right Shift for faster movement. These avoid your Karabiner four-modifier arrow rule. All shortcuts can be changed in Keybindings.")
                guideRow("Privacy", "Input is interpreted locally for navigation. Keystrokes, accessibility labels, and application content are never saved or sent anywhere. The app uses no network services. Secure Input and inaccessible controls can limit navigation in some apps.")
            }.padding(20)
        }
    }
    private func guideRow(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    }
}

final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model: AppModel
    private var item: NSStatusItem?
    private var window: NSWindow?
    private var statusItem: NSMenuItem?
    private var pauseItem: NSMenuItem?
    private var signals: [DispatchSourceSignal] = []
    init(configURL: URL) { model = AppModel(configURL: configURL); super.init() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item?.button?.image = NSImage(systemSymbolName: "cursorarrow.motionlines", accessibilityDescription: "Vimstride")
        let menu = NSMenu()
        statusItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: ""); menu.addItem(statusItem!)
        menu.addItem(.separator())
        add("Settings…", action: #selector(showSettings), key: ",", to: menu)
        add("Reload Configuration", action: #selector(reload), to: menu)
        pauseItem = add("Pause", action: #selector(pause), to: menu)
        add("Accessibility Settings…", action: #selector(permission), to: menu)
        menu.addItem(.separator())
        add("Quit Vimstride", action: #selector(quit), key: "q", to: menu)
        item?.menu = menu
        model.statusChanged = { [weak self] in self?.updateMenu() }
        model.start(); updateMenu()
        for code in [SIGTERM, SIGINT] {
            signal(code, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: code, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }; source.resume(); signals.append(source)
        }
        if !model.permission || ProcessInfo.processInfo.arguments.contains("--settings") || model.status == "Configuration needs attention" { showSettings() }
    }
    @discardableResult private func add(_ title: String, action: Selector, key: String = "", to menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key); entry.target = self; menu.addItem(entry); return entry
    }
    private func updateMenu() {
        statusItem?.title = model.permission ? model.status : "Accessibility permission required"
        pauseItem?.title = model.paused ? "Resume" : "Pause"
        item?.button?.appearsDisabled = model.paused || !model.permission
        item?.button?.toolTip = "Vimstride · \(statusItem?.title ?? "")"
    }
    @objc func showSettings() {
        model.input.cancelModes()
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model))
            let settings = NSWindow(contentViewController: controller)
            settings.title = "Vimstride Settings"
            settings.styleMask = [.titled, .closable, .miniaturizable]
            settings.isReleasedWhenClosed = false; settings.delegate = self
            settings.center(); window = settings
        }
        model.refreshLogin(); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    @objc private func reload() { model.reload(); updateMenu() }
    @objc private func pause() { model.togglePause(); updateMenu() }
    @objc private func permission() { model.requestPermission() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showSettings(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model.input.stop(); signals.forEach { $0.cancel() } }
}

public enum VimstrideApplication {
    public static func run() {
        let arguments = ProcessInfo.processInfo.arguments
        var url = NavigationConfig.configURL()
        if let index = arguments.firstIndex(of: "--config"), arguments.indices.contains(index + 1) { url = URL(fileURLWithPath: NSString(string: arguments[index + 1]).expandingTildeInPath) }
        if arguments.contains("--print-default-config") { print(NavigationConfig().toml, terminator: ""); return }
        if arguments.contains("--check-config") {
            do { _ = try NavigationConfig.parse(String(contentsOf: url, encoding: .utf8), source: url.path); print("Configuration is valid: \(url.path)") }
            catch { fputs("\(error.localizedDescription)\n", stderr); exit(2) }
            return
        }
        let identifier = Bundle.main.bundleIdentifier
        if let identifier, let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) { existing.activate(options: [.activateIgnoringOtherApps]); return }
        let app = NSApplication.shared
        let delegate = ApplicationDelegate(configURL: url)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
