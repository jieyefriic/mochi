// Mochi — desktop pet that eats from your Trash and evolves.
// v0: floating transparent panel + placeholder egg sprite + drag + persistence + right-click menu.
// Real sprites land later via PixelLab pipeline.

import SwiftUI
import AppKit

// MARK: - Tunables

private enum Const {
    static let petSize: CGFloat = 96            // sprite size
    static let windowW: CGFloat = 240           // wide enough for chat bubbles
    static let windowH: CGFloat = 140           // tall enough to stack bubble above egg
    static let bubbleMaxW: CGFloat = 220
    static let posKeyX = "mochi.pos.x"
    static let posKeyY = "mochi.pos.y"
    static let edgePad: CGFloat = 8
}

// MARK: - Pet state

enum PermissionStatus { case unknown, denied, granted }

/// PixelLab returns 9 frames (0..8) per 8-frame request — frame 8 acts as a
/// loop closer.
let SPRITE_FRAME_COUNT = 9

final class PetState: ObservableObject {
    @Published var lastMeal: String? = nil
    @Published var bubbleVisible: Bool = false
    @Published var bubbleSticky: Bool = false   // hint bubbles don't auto-dismiss
    @Published var permission: PermissionStatus = .unknown

    /// Bumped whenever the persisted PetMochi state changes — gives EggSprite
    /// a single SwiftUI dependency to watch.
    @Published var spriteVersion: Int = 0

    /// Convenience read-only views into the persisted state.
    var stage: Int   { Store.shared.mochi.stage }
    var color: String? { Store.shared.mochi.color }
    var species: String? { Store.shared.mochi.species }
    var mealCount: Int { Store.shared.mochi.totalMeals }

    func feed(_ meal: TrashMeal) {
        // Persist the meal + run the engine, capture any events.
        Store.shared.appendMeal(meal)
        var events: [EvolutionEvent] = []
        Store.shared.update { m in
            events = EvolutionEngine.processMeal(meal, &m)
        }

        // Trigger feed animation overlay (EggSprite swaps to anim_feed/ for one cycle).
        NotificationCenter.default.post(name: .mochiAteSomething, object: nil)

        // .git/ folder = special bubble overrides the regular EAT line.
        let name = (meal.path as NSString).lastPathComponent
        if name == ".git" {
            let line = BubbleEngine.pick(
                tag: "SPECIAL_GIT",
                color: Store.shared.mochi.color,
                species: Store.shared.mochi.species,
                stage: Store.shared.mochi.stage
            ) ?? "…you sure about that?"
            showBubble(line, duration: 3.0)
        } else {
            // Yum bubble — personality line keyed to category, falls back to plain.
            let eatTag = "EAT_\(meal.category.rawValue)"
            let line = BubbleEngine.pick(
                tag: eatTag,
                color: Store.shared.mochi.color,
                species: Store.shared.mochi.species,
                stage: Store.shared.mochi.stage
            ) ?? "yum! a \(meal.label)"
            showBubble(line, duration: 2.4)
        }

        // Then any evolution events queued behind it.
        var delay: Double = 2.6
        for ev in events {
            let text = describe(ev)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.showBubble(text, duration: 3.4)
            }
            delay += 3.6
        }

        spriteVersion += 1
    }

    /// Called by AppDelegate when items left the Trash.
    func handleRestore(count: Int) {
        for _ in 0..<count { Store.shared.appendRestore() }
        // RESTORE bubble — only fires past S2 (engine treats S0/S1 as silent).
        let line = BubbleEngine.pick(
            tag: "RESTORE",
            color: Store.shared.mochi.color,
            species: Store.shared.mochi.species,
            stage: Store.shared.mochi.stage
        )
        if let line { showBubble(line, duration: 2.6) }
    }

    /// Called by AppDelegate when ≥ 100 items vanished at once (Empty Trash).
    func handleFeast(count: Int) {
        Store.shared.update { m in m.gp += 50 }
        showBubble("🍽 a feast! +50 GP", duration: 3.0)
        spriteVersion += 1
    }

    private func describe(_ ev: EvolutionEvent) -> String {
        switch ev {
        case .colorLocked(let c):
            return "✨ element locked: \(elementName(c))"
        case .stageEvolved(let s):
            return "→ S\(s) \(EvolutionEngine.STAGE_NAMES[s] ?? "")"
        case .speciesLocked(let sp):
            return "🥚 hatched as \(sp)!"
        }
    }

    private func elementName(_ color: String) -> String {
        switch color {
        case "red":    return "MAGMA"
        case "blue":   return "FROST"
        case "green":  return "TOXIN"
        case "purple": return "ARCANE"
        case "gold":   return "SOLAR"
        default:       return color.uppercased()
        }
    }

    /// Show a transient bubble (auto-dismisses after `duration`).
    func showBubble(_ text: String, duration: Double = 2.0) {
        lastMeal = text
        bubbleSticky = false
        bubbleVisible = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            // Only dismiss if no sticky bubble took over in the meantime
            if !self.bubbleSticky { self.bubbleVisible = false }
        }
    }

    /// Show a persistent hint bubble (stays until permission changes / user taps egg).
    func showStickyHint(_ text: String) {
        lastMeal = text
        bubbleSticky = true
        bubbleVisible = true
    }

    func clearStickyHint() {
        bubbleSticky = false
        bubbleVisible = false
    }

    func updatePermission(_ p: PermissionStatus) {
        let was = permission
        permission = p
        switch p {
        case .denied:
            if was != .denied { showStickyHint("hungry... tap me 🥚") }
        case .granted:
            if was == .denied { clearStickyHint(); showBubble("yummy! ready 🍽", duration: 2.0) }
        case .unknown: break
        }
    }
}

// MARK: - Pet view (placeholder sprite — replaced by PixelLab PNG sequences later)

struct PetView: View {
    @ObservedObject var state: PetState
    @State private var bob: CGFloat = 0

    var body: some View {
        ZStack {
            // Sprite pinned to bottom-center; auto-reflects PetMochi state.
            EggSprite(stage: state.stage, color: state.color, species: state.species)
                .frame(width: Const.petSize, height: Const.petSize)
                .offset(y: bob)
                .position(x: Const.windowW / 2,
                          y: Const.windowH - Const.petSize / 2 - 4)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                        bob = -4
                    }
                }

            // Speech bubble — centered above egg, auto-sizes to text up to bubbleMaxW
            if state.bubbleVisible, let m = state.lastMeal {
                Text(m)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.black)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: Const.bubbleMaxW)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.96))
                            .shadow(color: .black.opacity(0.28), radius: 4, y: 2)
                    )
                    .position(x: Const.windowW / 2,
                              y: Const.windowH - Const.petSize - 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(2)
            }
        }
        .frame(width: Const.windowW, height: Const.windowH)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.18), value: state.bubbleVisible)
    }
}

// PixelLab-generated sprite. Reads (stage, color, species) from a tuple key —
// when the key changes (real evolution or debug menu), SwiftUI re-renders.
// Plays the stage's idle animation if its frames are bundled; otherwise
// renders the static sprite only.
struct EggSprite: View {
    /// (stage, color, species) — passed in so the View redraws on change.
    let stage: Int
    let color: String?
    let species: String?

    @State private var frame: Int = 0
    /// True while a feed reaction overlay is playing. Drives use of feedPrefix
    /// instead of animPrefix for the duration of one cycle.
    @State private var playingFeed: Bool = false
    private static let frameMS: Double = 110
    private let ticker = Timer.publish(every: frameMS / 1000.0,
                                       on: .main, in: .common).autoconnect()

    private var staticName: String {
        EvolutionEngine.spriteName(stage: stage, color: color, species: species)
    }
    private var animPrefix: String? {
        EvolutionEngine.animPrefix(stage: stage, color: color, species: species)
    }
    private var feedPrefix: String? {
        EvolutionEngine.feedPrefix(stage: stage, color: color, species: species)
    }

    var body: some View {
        Group {
            if let img = currentImage() {
                Image(nsImage: img)
                    .interpolation(.none)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Canvas { ctx, size in
                    let r = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
                    ctx.fill(Path(ellipseIn: r),
                             with: .color(Color(red: 0.6, green: 0.55, blue: 0.5)))
                }
            }
        }
        .onReceive(ticker) { _ in
            // Feed cycle takes priority — when it finishes, fall back to idle.
            if playingFeed {
                let next = frame + 1
                if next >= SPRITE_FRAME_COUNT {
                    playingFeed = false
                    frame = 0
                } else {
                    frame = next
                }
                return
            }
            guard animPrefix != nil else { return }
            frame = (frame + 1) % SPRITE_FRAME_COUNT
        }
        .onReceive(NotificationCenter.default.publisher(for: .mochiAteSomething)) { _ in
            // Only start a feed cycle if the asset bundle actually has one.
            guard let prefix = feedPrefix, NSImage(named: "\(prefix)_0") != nil else { return }
            playingFeed = true
            frame = 0
        }
        .onChange(of: stage)   { _ in frame = 0; playingFeed = false }
        .onChange(of: color)   { _ in frame = 0; playingFeed = false }
        .onChange(of: species) { _ in frame = 0; playingFeed = false }
    }

    private func currentImage() -> NSImage? {
        if playingFeed,
           let prefix = feedPrefix,
           let img = NSImage(named: "\(prefix)_\(frame)") { return img }
        if let prefix = animPrefix,
           let img = NSImage(named: "\(prefix)_\(frame)") { return img }
        if let img = NSImage(named: staticName) { return img }
        return loadFromBundle(staticName)
    }

    private func loadFromBundle(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

// MARK: - Drag-to-move host view

final class DragHost<Content: View>: NSHostingView<Content> {
    private var dragStart: NSPoint = .zero
    private var winStart: NSPoint = .zero
    private var didDrag = false

    override func mouseDown(with event: NSEvent) {
        guard let window = self.window else { return super.mouseDown(with: event) }
        dragStart = NSEvent.mouseLocation
        winStart = window.frame.origin
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = self.window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - dragStart.x
        let dy = now.y - dragStart.y
        if abs(dx) + abs(dy) > 2 { didDrag = true }
        window.setFrameOrigin(NSPoint(x: winStart.x + dx, y: winStart.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        guard let window = self.window else { return }
        // Persist position
        let o = window.frame.origin
        UserDefaults.standard.set(Double(o.x), forKey: Const.posKeyX)
        UserDefaults.standard.set(Double(o.y), forKey: Const.posKeyY)
        // Click without drag → poke pet
        if !didDrag {
            NotificationCenter.default.post(name: .mochiPoked, object: nil)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let header = NSMenuItem(title: "Mochi v0", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Wake Up Mochi… (Setup)",
                     action: #selector(AppDelegate.openOnboarding),
                     keyEquivalent: "")
        menu.addItem(withTitle: "Reset Position",
                     action: #selector(AppDelegate.resetPosition),
                     keyEquivalent: "r")

        // ── Debug submenu (compile-time flag — off by default) ────
        #if MOCHI_DEBUG_MENU
        let dbg = NSMenu(title: "Debug")
        // Stage jump
        let stageMenu = NSMenu(title: "Set Stage")
        for s in 0...6 {
            let it = NSMenuItem(title: "S\(s) · \(EvolutionEngine.STAGE_NAMES[s] ?? "")",
                                action: #selector(AppDelegate.debugSetStage(_:)),
                                keyEquivalent: "")
            it.tag = s
            stageMenu.addItem(it)
        }
        let stageParent = NSMenuItem(title: "Set Stage", action: nil, keyEquivalent: "")
        stageParent.submenu = stageMenu
        dbg.addItem(stageParent)

        // Color jump
        let colorMenu = NSMenu(title: "Set Color")
        for c in ["red","blue","green","purple","gold"] {
            let it = NSMenuItem(title: c.uppercased(),
                                action: #selector(AppDelegate.debugSetColor(_:)),
                                keyEquivalent: "")
            it.representedObject = c
            colorMenu.addItem(it)
        }
        let colorParent = NSMenuItem(title: "Set Color", action: nil, keyEquivalent: "")
        colorParent.submenu = colorMenu
        dbg.addItem(colorParent)

        // Species jump
        let speciesMenu = NSMenu(title: "Set Species")
        for sp in ["DRAKKIN","MOCHIMA","AVIORN","FELIQ","TIDLE"] {
            let it = NSMenuItem(title: sp,
                                action: #selector(AppDelegate.debugSetSpecies(_:)),
                                keyEquivalent: "")
            it.representedObject = sp
            speciesMenu.addItem(it)
        }
        let speciesParent = NSMenuItem(title: "Set Species", action: nil, keyEquivalent: "")
        speciesParent.submenu = speciesMenu
        dbg.addItem(speciesParent)

        dbg.addItem(NSMenuItem.separator())
        let addGP = NSMenuItem(title: "+50 GP",
                               action: #selector(AppDelegate.debugAddGP(_:)),
                               keyEquivalent: "")
        addGP.tag = 50
        dbg.addItem(addGP)
        dbg.addItem(withTitle: "Reset Mochi",
                    action: #selector(AppDelegate.debugReset),
                    keyEquivalent: "")

        let dbgParent = NSMenuItem(title: "Debug…", action: nil, keyEquivalent: "")
        dbgParent.submenu = dbg
        menu.addItem(dbgParent)
        #endif

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit Mochi",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}


extension Notification.Name {
    static let mochiPoked = Notification.Name("mochi.poked")
    static let mochiTrashEvent = Notification.Name("mochi.trash.event")
    static let mochiRestoreEvent = Notification.Name("mochi.restore.event")
    static let mochiFeast = Notification.Name("mochi.feast")
    /// Fired when feed() runs — EggSprite watches this to play the feed
    /// animation once over its idle loop.
    static let mochiAteSomething = Notification.Name("mochi.ate.something")
}

// MARK: - Pet panel (the floating window itself)

final class PetPanel: NSPanel {
    init(rootView: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Const.windowW, height: Const.windowH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        self.isMovable = true
        self.isMovableByWindowBackground = false   // we drive drag manually
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.contentView = rootView
        self.acceptsMouseMovedEvents = true

        restorePosition()
    }

    override var canBecomeKey: Bool { false }     // never steals focus
    override var canBecomeMain: Bool { false }

    func restorePosition() {
        let d = UserDefaults.standard
        let hasX = d.object(forKey: Const.posKeyX) != nil
        let hasY = d.object(forKey: Const.posKeyY) != nil
        if hasX, hasY {
            setFrameOrigin(NSPoint(x: d.double(forKey: Const.posKeyX),
                                   y: d.double(forKey: Const.posKeyY)))
        } else {
            // Default: bottom-right corner of main screen
            if let visible = NSScreen.main?.visibleFrame {
                let x = visible.maxX - Const.windowW - Const.edgePad
                let y = visible.minY + Const.edgePad
                setFrameOrigin(NSPoint(x: x, y: y))
            }
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: PetPanel?
    let state = PetState()
    var watcher: TrashWatcher?
    /// Background re-probe so we catch permission grants even if the user
    /// doesn't open the onboarding window.
    private var permissionTimer: Timer?
    /// Spontaneous personality bubble timer (20-40 min random cadence).
    private var idleBubbleTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // no Dock icon by default

        // Build content view
        let content = PetView(state: state)
        let host = DragHost(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: Const.windowW, height: Const.windowH)

        // Create panel
        let p = PetPanel(rootView: host)
        p.orderFrontRegardless()
        self.panel = p

        // Initial permission probe — drives bubble copy and tap routing.
        refreshPermission()

        // Trash watcher — starts regardless; if denied today, it'll yield no
        // events until the user grants access (then we just need to relaunch
        // or re-call start(), which we do on grant via NotificationCenter).
        startWatcher()

        // Tap on egg → state-aware behavior.
        NotificationCenter.default.addObserver(
            forName: .mochiPoked, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            switch self.state.permission {
            case .denied, .unknown:
                OnboardingController.shared.show { [weak self] in
                    self?.onPermissionGranted()
                }
            case .granted:
                let hour = Calendar.current.component(.hour, from: Date())
                let idleTag: String =
                    (hour >= 22 || hour < 5)  ? "IDLE_NIGHT" :
                    (hour >= 5 && hour < 10)  ? "IDLE_MORN"  : "IDLE"
                let line = BubbleEngine.pick(
                    tag: idleTag,
                    color: self.state.color,
                    species: self.state.species,
                    stage: self.state.stage
                ) ?? "(\(self.state.mealCount) meals so far)"
                self.state.showBubble(line, duration: 2.4)
            }
        }

        // Re-probe every 5s so a background grant flips the egg back to happy
        // even without the onboarding window being open.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.refreshPermission()
        }

        // If onboarding window confirms grant, we still need to (re)start the
        // watcher and remember granted state.
        NotificationCenter.default.addObserver(
            forName: .mochiPermissionGranted, object: nil, queue: .main
        ) { [weak self] _ in
            self?.onPermissionGranted()
        }

        // Restore + feast events come from TrashWatcher — pipe them into PetState.
        NotificationCenter.default.addObserver(
            forName: .mochiRestoreEvent, object: nil, queue: .main
        ) { [weak self] note in
            let n = (note.object as? Int) ?? 1
            self?.state.handleRestore(count: n)
        }
        NotificationCenter.default.addObserver(
            forName: .mochiFeast, object: nil, queue: .main
        ) { [weak self] note in
            let n = (note.object as? Int) ?? 0
            self?.state.handleFeast(count: n)
        }

        scheduleIdleBubble()
    }

    /// Schedule the next idle bubble at a random 20-40 min offset. Reschedules
    /// itself after firing, so it runs forever as long as the app's alive.
    private func scheduleIdleBubble() {
        idleBubbleTimer?.invalidate()
        let delay = Double.random(in: 1200...2400)   // 20-40 min
        idleBubbleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.fireIdleBubble()
            self?.scheduleIdleBubble()
        }
    }

    private func fireIdleBubble() {
        // Don't talk over an existing bubble; just push the next one out.
        if state.bubbleVisible { return }
        // Skip pre-S2 — engine treats those as personality-less placeholders.
        guard state.stage >= 2 else { return }

        let hour = Calendar.current.component(.hour, from: Date())
        let tag: String =
            (hour >= 22 || hour < 5) ? "IDLE_NIGHT" :
            (hour >= 5 && hour < 10) ? "IDLE_MORN"  : "IDLE"
        if let line = BubbleEngine.pick(
            tag: tag,
            color: state.color,
            species: state.species,
            stage: state.stage
        ) {
            state.showBubble(line, duration: 2.4)
        }
    }

    private func startWatcher() {
        let w = TrashWatcher { [weak self] meal in
            DispatchQueue.main.async {
                self?.state.feed(meal)
                NotificationCenter.default.post(name: .mochiTrashEvent, object: meal)
            }
        }
        w.start()
        self.watcher = w
    }

    private func refreshPermission() {
        let granted = TrashWatcher.canReadTrash()
        state.updatePermission(granted ? .granted : .denied)
    }

    private func onPermissionGranted() {
        state.updatePermission(.granted)
        // Restart watcher so its initial seed reflects current Trash contents.
        watcher?.stop()
        watcher = nil
        startWatcher()
    }

    @objc func resetPosition() {
        UserDefaults.standard.removeObject(forKey: Const.posKeyX)
        UserDefaults.standard.removeObject(forKey: Const.posKeyY)
        panel?.restorePosition()
    }

    @objc func openOnboarding() {
        OnboardingController.shared.show { [weak self] in
            self?.onPermissionGranted()
        }
    }

    @objc func debugSetStage(_ sender: NSMenuItem) {
        let s = max(0, min(6, sender.tag))
        Store.shared.update { m in
            m.stage = s
            // Make sure color/species are sane for the new stage.
            if s >= 1 && m.color == nil { m.color = "red" }
            if s >= 3 && m.species == nil { m.species = "DRAKKIN" }
        }
        state.spriteVersion += 1
        state.showBubble("→ S\(s) \(EvolutionEngine.STAGE_NAMES[s] ?? "")", duration: 1.6)
        NSLog("Mochi: debug stage → \(s)")
    }

    @objc func debugSetColor(_ sender: NSMenuItem) {
        guard let c = sender.representedObject as? String else { return }
        Store.shared.update { $0.color = c }
        state.spriteVersion += 1
        state.showBubble("color → \(c.uppercased())", duration: 1.6)
    }

    @objc func debugSetSpecies(_ sender: NSMenuItem) {
        guard let sp = sender.representedObject as? String else { return }
        Store.shared.update { $0.species = sp }
        state.spriteVersion += 1
        state.showBubble("species → \(sp)", duration: 1.6)
    }

    @objc func debugAddGP(_ sender: NSMenuItem) {
        let n = sender.tag
        Store.shared.update { m in
            m.gp += n
            // Don't bypass daily cap — this is debug, just nudge GP forward.
            // Walk stage thresholds.
            for s in (m.stage + 1)...6 {
                if let t = EvolutionEngine.STAGE_GP[s], m.gp >= t {
                    m.stage = s
                    if s == 3 && m.species == nil { m.species = "DRAKKIN" }
                }
            }
            // Color election if hitting S1 without color yet.
            if m.stage >= 1 && m.color == nil { m.color = "red" }
        }
        state.spriteVersion += 1
        state.showBubble("+\(n) GP (now \(Store.shared.mochi.gp))", duration: 1.6)
    }

    @objc func debugReset() {
        Store.shared.reset()
        state.spriteVersion += 1
        state.showBubble("Mochi reset 🥚", duration: 1.6)
    }
}

// MARK: - Entry point

@main
struct MochiMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
