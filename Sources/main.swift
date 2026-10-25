import AppKit

// MARK: - Persistent storage (~/Library/Application Support/Node)

/// Keeps the note on disk:
///   ~/Library/Application Support/Node/note.txt          – the note
///   ~/Library/Application Support/Node/Snapshots/*.txt   – one copy per day, last 30 days
final class Store {
    let dir: URL
    let file: URL
    let snapDir: URL
    private var lastSaved: String?
    private let dayFormat: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("Node", isDirectory: true)
        file = dir.appendingPathComponent("note.txt")
        snapDir = dir.appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: snapDir, withIntermediateDirectories: true)
    }

    private func snapshots() -> [URL] {
        let all = (try? FileManager.default.contentsOfDirectory(at: snapDir, includingPropertiesForKeys: nil)) ?? []
        return all.filter { $0.pathExtension == "txt" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Main file first; if it is missing or unreadable, fall back to the newest snapshot.
    func load() -> String {
        if FileManager.default.fileExists(atPath: file.path) {
            if let s = try? String(contentsOf: file, encoding: .utf8) { lastSaved = s; return s }
        }
        for url in snapshots() {
            if let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        }
        return ""
    }

    func save(_ text: String) {
        guard text != lastSaved, let data = text.data(using: .utf8) else { return }
        do {
            try data.write(to: file, options: .atomic)
            lastSaved = text
        } catch {
            NSLog("Node: save failed: \(error)")
            return
        }
        // One rolling snapshot per day, last 30 days kept. Empty notes never replace a snapshot.
        guard !text.isEmpty else { return }
        let snap = snapDir.appendingPathComponent("note-\(dayFormat.string(from: Date())).txt")
        try? data.write(to: snap, options: .atomic)
        for old in snapshots().dropFirst(30) { try? FileManager.default.removeItem(at: old) }
    }
}

// MARK: - Note view

final class NoteViewController: NSViewController, NSTextViewDelegate {
    let store: Store
    let textView: NSTextView
    private var pendingSave: DispatchWorkItem?

    init(store: Store) {
        self.store = store
        textView = NSTextView()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: 380))
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.borderType = .noBorder

        let tv = textView
        tv.frame = scroll.contentView.bounds
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.textContainerInset = NSSize(width: 14, height: 16)
        tv.drawsBackground = false
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.usesFindBar = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.font = .systemFont(ofSize: 14)
        tv.textColor = .labelColor
        tv.insertionPointColor = .controlAccentColor
        let para = NSMutableParagraphStyle()
        para.lineSpacing = 3
        tv.defaultParagraphStyle = para
        tv.typingAttributes = [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor,
                               .paragraphStyle: para]
        tv.setAccessibilityLabel("Note")

        tv.string = store.load()
        tv.delegate = self
        scroll.documentView = tv
        view = scroll
    }

    // Saves shortly after typing stops, so idle CPU stays at zero and nothing is lost.
    func textDidChange(_ notification: Notification) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        // Until the panel has been opened once, the text box is empty and must never overwrite the file.
        guard isViewLoaded else { return }
        store.save(textView.string)
    }
}

// MARK: - Menu bar item

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let store = Store()
    private var note: NoteViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Node")
            img?.isTemplate = true
            button.image = img
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        note = NoteViewController(store: store)
        // .transient: closes when you click elsewhere, like the Wi‑Fi and Bluetooth menus.
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 340, height: 380)
        popover.contentViewController = note
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
            return
        }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        popover.contentViewController?.view.window?.makeFirstResponder(note.textView)
    }

    func popoverDidClose(_ notification: Notification) {
        note.saveNow()
    }

    func applicationWillResignActive(_ notification: Notification) {
        note?.saveNow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        note?.saveNow()
    }

    private func showMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Show Saved Note in Finder", action: #selector(showData), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Node", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showData() {
        note.saveNow()
        NSWorkspace.shared.activateFileViewerSelecting([store.file])
    }

    /// Never shown (menu bar app), but routes ⌘C / ⌘V / ⌘Z / ⌘A / ⌘F to the text box.
    private func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Node", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "", action: nil, keyEquivalent: "").submenu = appMenu

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let find = edit.addItem(withTitle: "Find", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        find.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit
        NSApp.mainMenu = main
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // menu bar only — no Dock icon, no window
app.run()
