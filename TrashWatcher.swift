// TrashWatcher — watch every macOS-style trash location via FSEvents and
// classify newly-trashed items.
//
// We watch:
//   * ~/.Trash                                                — local user Trash
//   * ~/Library/Mobile Documents/com~apple~CloudDocs/.Trash   — iCloud Drive's
//                                                               local staging
//                                                               area (when the
//                                                               user has iCloud
//                                                               Desktop & Docs
//                                                               sync turned on,
//                                                               Finder routes
//                                                               deletes here
//                                                               instead of the
//                                                               local ~/.Trash)
//
// Privacy: we read filename + size + extension only. Never the file content.
// We never delete or modify anything in Trash; we only observe it.

import Foundation

/// What we extracted about a single item that just got trashed.
struct TrashMeal {
    let path: String
    let ext: String           // lowercased extension, no dot ("py", "png", ""=none)
    let size: Int64           // -1 if unknown
    let category: Category
    let when: Date

    enum Category: String {
        case code, image, video, audio, doc, archive, app, junk, other
    }

    /// Short user-facing label for the speech bubble.
    var label: String {
        if ext.isEmpty { return category.rawValue }
        return ".\(ext)"
    }
}

private extension TrashMeal.Category {
    static func classify(ext: String, name: String) -> TrashMeal.Category {
        // Junk patterns by name
        let n = name.lowercased()
        if n == ".ds_store" || n == "thumbs.db" || n.hasSuffix(".log") || n.hasSuffix(".tmp") {
            return .junk
        }
        if n == "node_modules" || n == ".cache" || n == ".next" || n == "dist" || n == "build" || n == "__pycache__" {
            return .junk
        }
        switch ext {
        case "py", "js", "ts", "tsx", "jsx", "go", "rs", "rb", "java", "kt", "swift",
             "c", "cpp", "h", "hpp", "cs", "php", "sh", "zsh", "lua", "vim", "sql":
            return .code
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "svg", "psd", "ai", "sketch", "fig":
            return .image
        case "mp4", "mov", "mkv", "avi", "webm", "m4v", "flv":
            return .video
        case "mp3", "wav", "flac", "aac", "ogg", "m4a":
            return .audio
        case "pdf", "doc", "docx", "txt", "md", "rtf", "epub", "pptx", "xlsx", "csv":
            return .doc
        case "zip", "tar", "gz", "tgz", "bz2", "7z", "rar", "dmg", "iso":
            return .archive
        case "app", "pkg":
            return .app
        default:
            return .other
        }
    }
}

final class TrashWatcher {
    typealias Handler = (TrashMeal) -> Void

    private let handler: Handler
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "mochi.trash.watcher")
    private var pollTimer: DispatchSourceTimer?

    /// All Trash locations we monitor.
    private let urls: [URL]

    /// Per-URL "last seen" filename set, so we can diff each location independently.
    private var seen: [URL: Set<String>] = [:]

    init(handler: @escaping Handler, urls: [URL]? = nil) {
        self.handler = handler
        self.urls = urls ?? Self.defaultURLs()
    }

    /// Default Trash locations to watch. Filtered to those that actually exist
    /// (e.g. iCloud Trash only exists if the user has iCloud Drive set up).
    static func defaultURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".Trash", isDirectory: true),
            home.appendingPathComponent(
                "Library/Mobile Documents/com~apple~CloudDocs/.Trash",
                isDirectory: true)
        ]
        return candidates.filter { url in
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// Can we read ~/.Trash right now? Used to drive the onboarding flow.
    /// (Onboarding is gated on the local Trash specifically — iCloud Trash
    /// inherits CloudDocs entitlements and is harder to predict.)
    static func canReadTrash() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    func start() {
        // Probe: can we read each Trash location? Log the bad ones, keep the good.
        var watchablePaths: [String] = []
        for url in urls {
            let probe = (try? FileManager.default.contentsOfDirectory(atPath: url.path))
            if probe == nil {
                NSLog("Mochi: cannot read \(url.path) — grant Full Disk Access if this is the local Trash, or this iCloud location is empty/missing.")
            } else {
                watchablePaths.append(url.path)
                seen[url] = Set(probe ?? [])
                NSLog("Mochi: watching \(url.path) (seeded with \(seen[url]?.count ?? 0) entries)")
            }
        }
        guard !watchablePaths.isEmpty else {
            NSLog("Mochi: no Trash locations are readable; staying idle until permission is granted.")
            return
        }

        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let cfPaths = watchablePaths as CFArray
        let flags: UInt32 = UInt32(kFSEventStreamCreateFlagFileEvents
                                   | kFSEventStreamCreateFlagNoDefer
                                   | kFSEventStreamCreateFlagUseCFTypes)

        guard let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, eventPaths, _, _ in
                guard let info = info else { return }
                let watcher = Unmanaged<TrashWatcher>.fromOpaque(info).takeUnretainedValue()
                guard let arr = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                watcher.handleEvent(paths: arr, count: count)
            },
            &ctx,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        ) else {
            NSLog("Mochi: failed to create FSEventStream")
            return
        }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        self.stream = s

        // Belt-and-suspenders: FSEvents misses Finder's delete-to-Trash on some
        // macOS versions (especially the iCloud staging dir). Poll every 3s
        // so we never miss a meal.
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 3.0, repeating: 3.0, leeway: .milliseconds(500))
        t.setEventHandler { [weak self] in
            self?.handleEvent(paths: [], count: 0)
        }
        t.resume()
        self.pollTimer = t
    }

    func stop() {
        pollTimer?.cancel()
        pollTimer = nil
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }

    // MARK: - Internal

    private func currentEntries(at url: URL) -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return Set(names)
    }

    private func handleEvent(paths: [String], count: Int) {
        for url in urls {
            // Skip URLs that weren't seeded (couldn't read at start).
            guard seen[url] != nil else { continue }
            diff(at: url, fsEventCount: count)
        }
    }

    private func diff(at url: URL, fsEventCount count: Int) {
        let now = currentEntries(at: url)
        let prev = seen[url] ?? []
        let added = now.subtracting(prev)
        let removed = prev.subtracting(now)
        if !added.isEmpty || !removed.isEmpty {
            let src = count > 0 ? "fs(\(count))" : "poll"
            let tag = url.lastPathComponent == ".Trash" && url.path.contains("CloudDocs") ? "iCloud" : "local"
            NSLog("Mochi[\(src)/\(tag)]: now=\(now.count) prev=\(prev.count) +\(added.count) -\(removed.count)")
        }
        seen[url] = now

        if !removed.isEmpty {
            NSLog("Mochi: \(removed.count) item(s) left Trash at \(url.lastPathComponent) (restore or empty)")
            // Heuristic: a single batch ≥ 100 is almost always "Empty Trash"
            // — give the user a feast bonus instead of counting it as 100 restores.
            if removed.count >= 100 {
                NotificationCenter.default.post(name: .mochiFeast, object: removed.count)
            } else {
                NotificationCenter.default.post(name: .mochiRestoreEvent, object: removed.count)
            }
        }
        guard !added.isEmpty else { return }

        for name in added {
            let full = url.appendingPathComponent(name)
            let ext = (name as NSString).pathExtension.lowercased()
            let size = fileSize(at: full)
            let cat = TrashMeal.Category.classify(ext: ext, name: name)
            let meal = TrashMeal(path: full.path, ext: ext, size: size, category: cat, when: Date())
            NSLog("Mochi: meal — \(name) [\(cat.rawValue)] \(size >= 0 ? "\(size)B" : "?B")")
            handler(meal)
        }
    }

    private func fileSize(at url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        if let n = attrs?[.size] as? NSNumber { return n.int64Value }
        return -1
    }
}
