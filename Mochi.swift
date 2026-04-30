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

final class PetState: ObservableObject {
    @Published var stage: Stage = .egg
    @Published var lastMeal: String? = nil
    @Published var bubbleVisible: Bool = false
    @Published var bubbleSticky: Bool = false   // hint bubbles don't auto-dismiss
    @Published var mealCount: Int = 0
    @Published var permission: PermissionStatus = .unknown

    enum Stage: String { case egg, hatchling, coder, artist, scholar, junk, media }

    func feed(_ meal: TrashMeal) {
        mealCount += 1
        showBubble("yum! a \(meal.label)", duration: 2.4)
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
            // Egg pinned to bottom-center
            EggSprite()
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

// Pixel-art egg drawn in Canvas. Throwaway — gets replaced by PixelLab sprite sheets.
struct EggSprite: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let px = s / 16  // 16x16 pixel grid
            let shell = Color(red: 0.98, green: 0.93, blue: 0.78)
            let shadow = Color(red: 0.85, green: 0.76, blue: 0.55)
            let outline = Color.black

            // hand-painted 16x16 egg (0=empty, 1=outline, 2=shell, 3=shadow)
            let pixels: [[Int]] = [
                [0,0,0,0,0,0,1,1,1,1,0,0,0,0,0,0],
                [0,0,0,0,1,1,2,2,2,2,1,1,0,0,0,0],
                [0,0,0,1,2,2,2,2,2,2,2,2,1,0,0,0],
                [0,0,1,2,2,2,2,2,2,2,2,2,3,1,0,0],
                [0,1,2,2,2,2,2,2,2,2,2,2,3,3,1,0],
                [0,1,2,2,2,2,2,2,2,2,2,2,2,3,1,0],
                [1,2,2,2,2,2,2,2,2,2,2,2,2,3,3,1],
                [1,2,2,2,2,2,2,2,2,2,2,2,2,2,3,1],
                [1,2,2,2,2,2,2,2,2,2,2,2,2,2,3,1],
                [1,2,2,2,2,2,2,2,2,2,2,2,2,3,3,1],
                [1,2,2,2,2,2,2,2,2,2,2,2,3,3,3,1],
                [0,1,2,2,2,2,2,2,2,2,2,3,3,3,1,0],
                [0,1,2,2,2,2,2,2,2,2,3,3,3,3,1,0],
                [0,0,1,2,2,2,2,2,2,3,3,3,3,1,0,0],
                [0,0,0,1,1,2,2,2,3,3,3,1,1,0,0,0],
                [0,0,0,0,0,1,1,1,1,1,1,0,0,0,0,0],
            ]
            for (y, row) in pixels.enumerated() {
                for (x, v) in row.enumerated() {
                    guard v != 0 else { continue }
                    let rect = CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)
                    let color: Color = v == 1 ? outline : (v == 2 ? shell : shadow)
                    ctx.fill(Path(rect), with: .color(color))
                }
            }
        }
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
                self.state.showBubble("(\(self.state.mealCount) meals so far)", duration: 1.8)
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
