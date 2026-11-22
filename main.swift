import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

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
    "quit": ("Quit", "Çık"),
]

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
    var xs: [CGFloat] = []   // in view coordinates
    var lineHeight: CGFloat = 0
    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        (dark ? NSColor(white: 1, alpha: 0.32) : NSColor(white: 0, alpha: 0.22)).setFill()
        for x in xs {
            NSBezierPath(roundedRect: NSRect(x: x - 0.5, y: (bounds.height - lineHeight) / 2, width: 1, height: lineHeight),
                         xRadius: 0.5, yRadius: 0.5).fill()
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
        // shortcut: horizontal (bottom) Dock only; a left/right Dock needs Y-based gaps.
        guard AXIsProcessTrusted(), let dock = readDock(), dock.list.width > dock.list.height else {
            window.orderOut(nil); return
        }
        let xs = dividerXs(dock.items)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = NSRect(x: dock.list.minX, y: primaryHeight - dock.list.maxY,
                           width: dock.list.width, height: dock.list.height)
        // Autohidden Dock: its frame sits off every screen.
        guard !xs.isEmpty, NSScreen.screens.contains(where: { $0.frame.intersects(frame.insetBy(dx: 0, dy: 4)) }) else {
            window.orderOut(nil); return
        }
        let iconHeight = dock.items.map(\.frame.height).max() ?? frame.height
        if window.frame != frame { window.setFrame(frame, display: false) }
        view.xs = xs.map { $0 - dock.list.minX }
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

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    let overlay = Overlay()
    let menu = NSMenu()

    func applicationDidFinishLaunching(_ n: Notification) {
        status.button?.image = NSImage(systemSymbolName: "poweron", accessibilityDescription: "Dock Dividers")
        menu.delegate = self
        status.menu = menu
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(withTitle: t("edit"), action: #selector(showEditor), keyEquivalent: "e").target = self
        menu.addItem(.separator())
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: t("grant"), action: #selector(openAccessibility), keyEquivalent: "").target = self
        }
        let login = menu.addItem(withTitle: t("login"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let langMenu = NSMenu()
        for (code, title) in [("system", t("system")), ("en", "English"), ("tr", "Türkçe")] {
            let item = langMenu.addItem(withTitle: title, action: #selector(setLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = (UserDefaults.standard.string(forKey: "lang") ?? "system") == code ? .on : .off
        }
        menu.addItem(withTitle: t("language"), action: nil, keyEquivalent: "").submenu = langMenu
        menu.addItem(withTitle: t("quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    var editor: NSWindow?
    let model = EditorModel()

    @objc func showEditor() {
        model.load()
        if editor == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 540),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Dock Dividers"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: EditorView(model: model))
            w.center()
            editor = w
        }
        NSApp.activate(ignoringOtherApps: true)
        editor?.makeKeyAndOrderFront(nil)
    }

    // Opening the app again from Finder/Launchpad shows the editor.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showEditor(); return false
    }

    @objc func setLanguage(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? String, forKey: "lang")
        // Rebuild the editor so its texts switch language.
        let wasOpen = editor?.isVisible ?? false
        editor?.close(); editor = nil
        if wasOpen { showEditor() }
    }

    @objc func openAccessibility() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        do { try s.status == .enabled ? s.unregister() : s.register() }
        catch { NSAlert(error: error).runModal() }
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
