// TrashWatcher — watch ~/.Trash via FSEvents and classify newly-trashed items.
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
    /// Last-seen entries in ~/.Trash so we know what's *new*. (FSEvents tells us
    /// the directory changed, not the per-file delta.)
    private var seen: Set<String> = []
    private let trashURL: URL

    init(handler: @escaping Handler) {
        self.handler = handler
        let home = FileManager.default.homeDirectoryForCurrentUser
        self.trashURL = home.appendingPathComponent(".Trash", isDirectory: true)
    }

    /// Can we read ~/.Trash right now? Used to drive the onboarding flow.
    static func canReadTrash() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(atPath: url.path)) != nil
    }

    func start() {
        // Probe: can we even read ~/.Trash? (TCC blocks unprivileged apps.)
        let probe = (try? FileManager.default.contentsOfDirectory(atPath: trashURL.path))
        if probe == nil {
            NSLog("Mochi: cannot read \(trashURL.path) — grant Files & Folders access in "
                  + "System Settings → Privacy & Security → Files and Folders, then relaunch.")
        }
        // Seed: ignore items that already exist when the app starts up.
        seen = currentEntries()

        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        let paths = [trashURL.path] as CFArray
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
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,                             // latency seconds
            flags
        ) else {
            NSLog("Mochi: failed to create FSEventStream for \(trashURL.path)")
            return
        }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        self.stream = s
        NSLog("Mochi: watching \(trashURL.path) (seeded with \(seen.count) entries)")
    }

    func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }

    // MARK: - Internal

    private func currentEntries() -> Set<String> {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: trashURL.path)) ?? []
        return Set(names)
    }

    private func handleEvent(paths: [String], count: Int) {
        // Diff current ~/.Trash against `seen` to find newcomers.
        let now = currentEntries()
        let added = now.subtracting(seen)
        let removed = seen.subtracting(now)
        seen = now

        if !removed.isEmpty {
            NSLog("Mochi: \(removed.count) item(s) left Trash (restore or empty)")
        }
        guard !added.isEmpty else { return }

        for name in added {
            let full = trashURL.appendingPathComponent(name)
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
        // Directory: skip recursive size for now; v1 just records 0.
        return -1
    }
}
