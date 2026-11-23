import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI
import Combine

// Dock Dividers: adds Apple's own small spacer tiles to the Dock and draws a thin
// native-looking line over each one, so app groups can be split anywhere.

let dockDomain = "com.apple.dock" as CFString
let spacerType = "small-spacer-tile"

// MARK: - Language (English + Turkish), same scheme as Check Updates

/// "system" follows the Mac's language; "en" / "tr" force one.
func isTurkish() -> Bool {
    switch UserDefaults.standard.string(forKey: "lang") ?? "system" {
    case "tr": return true
    case "en": return false
    default: return Locale.preferredLanguages.first?.hasPrefix("tr") ?? false
    }
}

let strings: [String: (en: String, tr: String)] = [
    "divider": ("Divider", "Ayraç"),
    "removeDivider": ("Remove divider", "Ayracı kaldır"),
    "hint": ("Drag to reorder. Left to right = top to bottom.", "Sürükleyip sırala. Soldan sağa = yukarıdan aşağıya."),
    "addDivider": ("Add Divider", "Ayraç Ekle"),
    "revert": ("Revert", "Geri Al"),
    "apply": ("Apply to Dock", "Dock'a Uygula"),
    "edit": ("Edit…", "Düzenle…"),
    "grant": ("Grant Accessibility Access…", "Erişilebilirlik İzni Ver…"),
    "login": ("Open at Login", "Girişte Başlat"),
    "language": ("Language", "Dil"),
    "system": ("System", "Sistem"),
    "quit": ("Quit Dock Dividers", "Dock Dividers'tan Çık"),
    "settings": ("Settings…", "Ayarlar…"),
    "about": ("About Dock Dividers", "Dock Dividers Hakkında"),
    "hide": ("Hide Dock Dividers", "Dock Dividers'ı Gizle"),
    "window": ("Window", "Pencere"),
    "close": ("Close", "Kapat"),
    "minimize": ("Minimize", "Küçült"),
    "editorWindow": ("Dividers", "Ayraçlar"),
    "accessibility": ("Accessibility", "Erişilebilirlik"),
    "granted": ("Granted — lines are drawn", "Verildi, çizgiler çiziliyor"),
    "notGranted": ("Not granted — lines can't be drawn", "Verilmedi, çizgiler çizilemiyor"),
    "openSettings": ("Open System Settings…", "Sistem Ayarları'nı Aç…"),
    "background": ("Keep Lines After Quitting", "Çıkınca Çizgiler Kalsın"),
    "backgroundHelp": ("Quit closes the window but keeps drawing lines in the background. Quit fully from the menu bar icon.",
                       "Çık deyince pencere kapanır, çizgiler arka planda kalır. Tamamen çıkmak için menü çubuğu simgesini kullan."),
    "quitFully": ("Quit Completely", "Tamamen Çık"),
    "loginHelp": ("Keeps the lines visible after a restart.", "Mac yeniden başlayınca da çizgiler görünür kalır."),
]

/// On by default: quitting only closes windows so the lines stay.
func keepRunning() -> Bool { UserDefaults.standard.object(forKey: "keepRunning") as? Bool ?? true }

func t(_ key: String) -> String { strings[key].map { isTurkish() ? $0.tr : $0.en } ?? key }

// MARK: - Dock preferences

func persistentApps() -> [Any] {
    CFPreferencesCopyAppValue("persistent-apps" as CFString, dockDomain) as? [Any] ?? []
}

func isSpacer(_ item: Any) -> Bool {
    (item as? [String: Any])?["tile-type"] as? String == spacerType
}

func savePersistentApps(_ apps: [Any]) {
    CFPreferencesSetAppValue("persistent-apps" as CFString, apps as CFArray, dockDomain)
    CFPreferencesAppSynchronize(dockDomain)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
    p.arguments = ["Dock"]
    try? p.run()
}

// MARK: - Where to draw (pure, self-tested)

struct DockItem { var frame: CGRect; var subrole: String }

/// X centres for divider lines: spacer items if the Dock exposes them, otherwise
/// gaps between neighbours wider than a third of an icon (the spacer's hole).
func dividerXs(_ items: [DockItem]) -> [CGFloat] {
    let sorted = items.sorted { $0.frame.minX < $1.frame.minX }
    var xs: [CGFloat] = []
    for (i, it) in sorted.enumerated() {
        if it.subrole.localizedCaseInsensitiveContains("spacer") { xs.append(it.frame.midX); continue }
        guard i + 1 < sorted.count else { continue }
        let next = sorted[i + 1]
        if it.subrole.contains("Separator") || next.subrole.contains("Separator")
            || next.subrole.localizedCaseInsensitiveContains("spacer") { continue }
        if next.frame.minX - it.frame.maxX > it.frame.width / 3 {
            xs.append((it.frame.maxX + next.frame.minX) / 2)
        }
    }
    return xs
}

func selfTest() {
    let a = CGRect(x: 0, y: 0, width: 60, height: 60)
    func at(_ x: CGFloat) -> CGRect { a.offsetBy(dx: x, dy: 0) }
    let app = "AXApplicationDockItem"
    assert(dividerXs([DockItem(frame: at(0), subrole: app), DockItem(frame: at(60), subrole: app)]) == [])
    assert(dividerXs([DockItem(frame: at(0), subrole: app), DockItem(frame: at(90), subrole: app)]) == [75])
    assert(dividerXs([DockItem(frame: at(0), subrole: app), DockItem(frame: at(60), subrole: "AXSpacerDockItem"),
                      DockItem(frame: at(90), subrole: app)]) == [90])
    assert(dividerXs([DockItem(frame: at(0), subrole: app), DockItem(frame: at(90), subrole: "AXSeparatorDockItem")]) == [])
    print("selftest ok")
}

// MARK: - Reading the Dock via Accessibility

func axValue<T>(_ el: AXUIElement, _ attr: String) -> T? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
    return v as? T
}

func axFrame(_ el: AXUIElement) -> CGRect? {
    guard let p: AXValue = axValue(el, kAXPositionAttribute), let s: AXValue = axValue(el, kAXSizeAttribute) else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p, .cgPoint, &pt); AXValueGetValue(s, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}

/// Dock list frame and its items, in AX (top-left origin) coordinates.
func readDock() -> (list: CGRect, items: [DockItem])? {
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    else { return nil }
    let app = AXUIElementCreateApplication(pid)
    guard let kids: [AXUIElement] = axValue(app, kAXChildrenAttribute),
          let list = kids.first(where: { (axValue($0, kAXRoleAttribute) as String?) == kAXListRole }),
          let listFrame = axFrame(list),
          let items: [AXUIElement] = axValue(list, kAXChildrenAttribute) else { return nil }
    return (listFrame, items.compactMap { el in
        axFrame(el).map { DockItem(frame: $0, subrole: axValue(el, kAXSubroleAttribute) ?? "") }
    })
}

// MARK: - Overlay

final class LinesView: NSView {
    var xs: [CGFloat] = []   // in view coordinates; Y positions when vertical
    var lineHeight: CGFloat = 0
    var vertical = false     // left/right Dock: horizontal lines
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor(white: 1, alpha: 0.32) : NSColor(white: 0, alpha: 0.22)).setFill()
        for x in xs {
            let r = vertical
                ? NSRect(x: (bounds.width - lineHeight) / 2, y: x - 0.5, width: lineHeight, height: 1)
                : NSRect(x: x - 0.5, y: (bounds.height - lineHeight) / 2, width: 1, height: lineHeight)
            NSBezierPath(roundedRect: r, xRadius: 0.5, yRadius: 0.5).fill()
        }
    }
}

final class Overlay {
    let window: NSWindow
    let view = LinesView()

    init() {
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        // No .fullScreenAuxiliary: the Dock is hidden in full-screen spaces, so the lines should be too.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.contentView = view
    }

    func refresh() {
        guard AXIsProcessTrusted(), let dock = readDock() else { window.orderOut(nil); return }
        // Left/right Dock: swap axes so the same gap logic works top to bottom.
        let vertical = dock.list.height > dock.list.width
        let items = !vertical ? dock.items : dock.items.map {
            DockItem(frame: CGRect(x: $0.frame.minY, y: $0.frame.minX, width: $0.frame.height, height: $0.frame.width),
                     subrole: $0.subrole)
        }
        let xs = dividerXs(items)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = NSRect(x: dock.list.minX, y: primaryHeight - dock.list.maxY,
                           width: dock.list.width, height: dock.list.height)
        // Autohidden Dock: its frame sits off every screen.
        guard !xs.isEmpty, NSScreen.screens.contains(where: { $0.frame.intersects(frame.insetBy(dx: vertical ? 4 : 0, dy: vertical ? 0 : 4)) }) else {
            window.orderOut(nil); return
        }
        let iconHeight = items.map(\.frame.height).max() ?? frame.height
        if window.frame != frame { window.setFrame(frame, display: false) }
        // AX Y grows downward, view Y upward.
        view.xs = vertical ? xs.map { dock.list.maxY - $0 } : xs.map { $0 - dock.list.minX }
        view.vertical = vertical
        view.lineHeight = iconHeight * 0.6
        view.needsDisplay = true
        window.orderFrontRegardless()
    }
}

// MARK: - Editor window

struct Tile: Identifiable { let id = UUID(); let raw: Any }

final class EditorModel: ObservableObject {
    @Published var tiles: [Tile] = []
    @Published var dirty = false
    func load() { tiles = persistentApps().map { Tile(raw: $0) }; dirty = false }
    func apply() { savePersistentApps(tiles.map(\.raw)); dirty = false }
    func addDivider() {
        tiles.append(Tile(raw: ["tile-type": spacerType, "tile-data": [String: Any]()])); dirty = true
    }
    func remove(_ t: Tile) { tiles.removeAll { $0.id == t.id }; dirty = true }
}

struct TileRow: View {
    let tile: Tile
    let onRemove: () -> Void
    @AppStorage("lang") private var lang = "system"
    var data: [String: Any] { (tile.raw as? [String: Any])?["tile-data"] as? [String: Any] ?? [:] }
    var path: String? {
        ((data["file-data"] as? [String: Any])?["_CFURLString"] as? String).flatMap { URL(string: $0)?.path }
    }
    var body: some View {
        if isSpacer(tile.raw) {
            HStack {
                Rectangle().fill(.secondary).frame(width: 2, height: 22).frame(width: 28)
                Text(t("divider")).foregroundStyle(.secondary)
                Spacer()
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help(t("removeDivider"))
            }
        } else {
            HStack {
                if let path { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: 28, height: 28) }
                else { Image(systemName: "square.dashed").frame(width: 28, height: 28) }
                Text(data["file-label"] as? String ?? "?")
            }
        }
    }
}

struct EditorView: View {
    @ObservedObject var model: EditorModel
    @AppStorage("lang") private var lang = "system"
    var body: some View {
        VStack(spacing: 0) {
            Text(t("hint"))
                .font(.caption).foregroundStyle(.secondary).padding(8)
            List {
                ForEach(model.tiles) { t in TileRow(tile: t) { model.remove(t) } }
                    .onMove { model.tiles.move(fromOffsets: $0, toOffset: $1); model.dirty = true }
            }
            HStack {
                Button(t("addDivider")) { model.addDivider() }
                Spacer()
                Button(t("revert")) { model.load() }.disabled(!model.dirty)
                Button(t("apply")) { model.apply() }.keyboardShortcut(.defaultAction).disabled(!model.dirty)
            }.padding(10)
        }
        .frame(minWidth: 280, minHeight: 360)
    }
}

// MARK: - Settings window

func setLanguage(_ code: String) {
    UserDefaults.standard.set(code, forKey: "lang")
    (NSApp.delegate as? AppDelegate)?.buildMainMenu()
}

struct SettingsView: View {
    @AppStorage("lang") private var lang = "system"
    @State private var login = SMAppService.mainApp.status == .enabled
    @State private var trusted = AXIsProcessTrusted()
    @AppStorage("keepRunning") private var keep = true
    let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Picker(t("language"), selection: Binding(get: { lang }, set: { setLanguage($0) })) {
                Text(t("system")).tag("system")
                Text("English").tag("en")
                Text("Türkçe").tag("tr")
            }
            Toggle(isOn: Binding(get: { login }, set: { on in
                let s = SMAppService.mainApp
                do { try on ? s.register() : s.unregister() } catch { NSAlert(error: error).runModal() }
                login = s.status == .enabled
            })) {
                Text(t("login"))
                Text(t("loginHelp"))
            }
            Toggle(isOn: $keep) {
                Text(t("background"))
                Text(t("backgroundHelp"))
            }
            LabeledContent(t("accessibility")) {
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(t(trusted ? "granted" : "notGranted"))
                    if !trusted { Button(t("openSettings")) { openAccessibility() } }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
        .onReceive(tick) { _ in trusted = AXIsProcessTrusted() }
    }
}

func openAccessibility() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
}

// MARK: - App

/// A normal app (Dock icon, menu bar) while a window is open; only the menu bar icon otherwise.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let overlay = Overlay()
    let statusMenu = NSMenu()
    let model = EditorModel()
    var editor: NSWindow?
    var settings: NSWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        status.button?.image = NSImage(systemSymbolName: "poweron", accessibilityDescription: "Dock Dividers")
        statusMenu.delegate = self
        status.menu = statusMenu
        buildMainMenu()
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }
        // shortcut: polls 3×/s so lines follow Dock changes and magnification with a small lag.
        Timer.scheduledTimer(withTimeInterval: 0.33, repeats: true) { [weak self] _ in self?.overlay.refresh() }
        overlay.refresh()
        // shortcut: relies on the login-item Apple Event flag; if a login launch still opens the window, drop this.
        let ev = NSAppleEventManager.shared().currentAppleEvent
        if ev?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue != keyAELaunchedAsLogInItem { showEditor() }
    }

    func buildMainMenu() {
        let main = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: t("about"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: t("settings"), action: #selector(showSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: t("hide"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: t("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "Dock Dividers", action: nil, keyEquivalent: "").submenu = app

        let window = NSMenu(title: t("window"))
        window.addItem(withTitle: t("editorWindow"), action: #selector(showEditor), keyEquivalent: "e").target = self
        window.addItem(.separator())
        window.addItem(withTitle: t("minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: t("close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: t("window"), action: nil, keyEquivalent: "").submenu = window
        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: t("edit"), action: #selector(showEditor), keyEquivalent: "").target = self
        menu.addItem(withTitle: t("settings"), action: #selector(showSettings), keyEquivalent: "").target = self
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: t("grant"), action: #selector(grantAccess), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: t(keepRunning() ? "quitFully" : "quit"), action: #selector(quitFully), keyEquivalent: "")
    }

    @objc func showEditor() {
        if !model.dirty { model.load() }
        if editor == nil {
            editor = makeWindow("Dock Dividers", NSHostingView(rootView: EditorView(model: model)),
                                size: NSSize(width: 320, height: 540), resizable: true)
        }
        present(editor!)
    }

    @objc func showSettings() {
        if settings == nil {
            let host = NSHostingView(rootView: SettingsView())
            settings = makeWindow(t("settings").replacingOccurrences(of: "…", with: ""), host, size: host.fittingSize, resizable: false)
        }
        present(settings!)
    }

    var forceQuit = false
    @objc func quitFully() { forceQuit = true; NSApp.terminate(nil) }

    // ⌘Q / Dock "Quit" only close the windows; logout, restart and "Quit Completely" really quit.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let ev = NSAppleEventManager.shared().currentAppleEvent
        let systemQuit = ev?.attributeDescriptor(forKeyword: kAEQuitReason) != nil || ev?.paramDescriptor(forKeyword: kAEQuitReason) != nil
        guard keepRunning(), !forceQuit, !systemQuit else { return .terminateNow }
        [editor, settings].forEach { $0?.close() }
        NSApp.setActivationPolicy(.accessory)
        return .terminateCancel
    }

    @objc func grantAccess() { openAccessibility() }

    func makeWindow(_ title: String, _ view: NSView, size: NSSize, resizable: Bool) -> NSWindow {
        let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                         styleMask: resizable ? [.titled, .closable, .miniaturizable, .resizable] : [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = title
        w.isReleasedWhenClosed = false
        w.contentView = view
        w.delegate = self
        w.center()
        return w
    }

    func present(_ w: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    // The Dock may have changed while the editor was in the background.
    func windowDidBecomeKey(_ n: Notification) {
        if n.object as? NSWindow === editor, !model.dirty { model.load() }
    }

    func windowWillClose(_ n: Notification) {
        let others = [editor, settings].compactMap { $0 }.filter { $0 !== n.object as? NSWindow && $0.isVisible }
        if others.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }

    // Opening the app again from Finder/Launchpad/Dock shows the editor.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showEditor(); return false
    }
}

@main
enum Main {
    static func main() {
        if CommandLine.arguments.contains("--selftest") { selfTest(); return }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
