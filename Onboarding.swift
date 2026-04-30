// Onboarding — small SwiftUI window that walks the user through granting
// Full Disk Access (the only path that lets us watch ~/.Trash on modern macOS).
//
// Flow:
//   1. User taps the egg → openOnboarding() shows this window.
//   2. User clicks "Open System Settings" → deeplink to Full Disk Access pane.
//   3. User clicks "Reveal Mochi.app in Finder" → Finder highlights the bundle so
//      it can be drag-dropped into the FDA list.
//   4. We poll TrashWatcher.canReadTrash() every 1.5s while the window is open;
//      when it flips true we celebrate and close ourselves.

import SwiftUI
import AppKit

final class OnboardingController {
    static let shared = OnboardingController()
    private var window: NSWindow?
    private var pollTimer: Timer?
    private var onGranted: (() -> Void)?

    func show(onGranted: @escaping () -> Void) {
        self.onGranted = onGranted

        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(
            onOpenSettings: { Self.openFullDiskAccess() },
            onRevealApp:    { Self.revealAppInFinder() },
            onCheckAgain:   { [weak self] in self?.probeOnce() },
            onClose:        { [weak self] in self?.close() }
        )
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Wake Mochi up"
        w.styleMask = [.titled, .closable]
        w.setContentSize(NSSize(width: 420, height: 480))
        w.center()
        w.isReleasedWhenClosed = false
        w.delegate = WindowCloseProxy.shared
        WindowCloseProxy.shared.onClose = { [weak self] in self?.cleanup() }
        window = w

        NSApp.setActivationPolicy(.regular)         // show in Dock while window open
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)

        startPolling()
    }

    func close() {
        window?.close()
    }

    private func cleanup() {
        pollTimer?.invalidate()
        pollTimer = nil
        window = nil
        NSApp.setActivationPolicy(.accessory)       // back to no-Dock-icon
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probeOnce() }
        }
    }

    private func probeOnce() {
        guard TrashWatcher.canReadTrash() else { return }
        // Granted! Celebrate, fire callback, auto-close after a moment.
        pollTimer?.invalidate()
        pollTimer = nil
        onGranted?()
        // Small delay so the user sees the green checkmark flash
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.close()
        }
        // Also flip the SwiftUI status by posting a notification the view watches.
        NotificationCenter.default.post(name: .mochiPermissionGranted, object: nil)
    }

    // MARK: - macOS deeplinks

    static func openFullDiskAccess() {
        // The Privacy_AllFiles anchor jumps straight into the Full Disk Access pane.
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    static func revealAppInFinder() {
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }
}

extension Notification.Name {
    static let mochiPermissionGranted = Notification.Name("mochi.permission.granted")
}

// NSWindow needs a delegate to know when it closes. We use a tiny shared proxy
// instead of conforming OnboardingController, to keep main-actor semantics clean.
final class WindowCloseProxy: NSObject, NSWindowDelegate {
    static let shared = WindowCloseProxy()
    var onClose: (() -> Void)?
    func windowWillClose(_ notification: Notification) { onClose?() }
}

// MARK: - SwiftUI view

private struct OnboardingView: View {
    let onOpenSettings: () -> Void
    let onRevealApp: () -> Void
    let onCheckAgain: () -> Void
    let onClose: () -> Void

    @State private var status: Status = .waiting
    enum Status { case waiting, granted }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack(spacing: 12) {
                Text("🥚")
                    .font(.system(size: 40))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wake Mochi up")
                        .font(.system(size: 18, weight: .semibold))
                    Text("One-time setup")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Why
            VStack(alignment: .leading, spacing: 6) {
                Text("Mochi grows by quietly watching what you throw away.")
                    .font(.system(size: 13))
                Text("Privacy: filename + size only. Never reads contents. Never uploads. Local only.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            // Steps
            VStack(alignment: .leading, spacing: 10) {
                stepRow(num: "1", text: "Open System Settings → Full Disk Access")
                Button(action: onOpenSettings) {
                    Label("Open System Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                stepRow(num: "2", text: "Drag Mochi.app from Finder into the list, flip the switch")
                Button(action: onRevealApp) {
                    Label("Reveal Mochi.app in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
            }

            Divider()

            // Status row — auto-updates via timer
            HStack(spacing: 8) {
                if status == .waiting {
                    ProgressView().scaleEffect(0.7)
                    Text("Waiting for permission…")
                        .foregroundColor(.secondary)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                    Text("Access granted! Mochi is waking up…")
                        .foregroundColor(.green)
                }
                Spacer()
                Button("Check again", action: onCheckAgain)
                    .controlSize(.small)
                    .disabled(status == .granted)
            }
            .font(.system(size: 12))

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 420, height: 480, alignment: .topLeading)
        .onReceive(NotificationCenter.default.publisher(for: .mochiPermissionGranted)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { status = .granted }
        }
    }

    @ViewBuilder
    private func stepRow(num: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.accentColor))
            Text(text)
                .font(.system(size: 12))
        }
    }
}
