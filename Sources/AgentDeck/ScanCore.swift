import Foundation

/// Shared helpers for reading jsonl session files cheaply.
enum ScanCore {
    static let fm = FileManager.default
    static let home = NSHomeDirectory()

    /// Recursively list files under `root` matching `suffix`, modified after `cutoff`.
    static func recentFiles(root: String, suffix: String, cutoff: Date) -> [(path: String, mtime: Date)] {
        guard let en = fm.enumerator(at: URL(fileURLWithPath: root),
                                     includingPropertiesForKeys: [.contentModificationDateKey],
                                     options: [.skipsHiddenFiles]) else { return [] }
        var out: [(String, Date)] = []
        for case let url as URL in en {
            guard url.path.hasSuffix(suffix) else { continue }
            guard let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  m > cutoff else { continue }
            out.append((url.path, m))
        }
        return out
    }

    /// Read up to `bytes` from the start of the file, split into complete lines.
    static func headLines(_ path: String, bytes: Int) -> [String] {
        guard let fh = FileHandle(forReadingAtPath: path),
              let data = try? fh.read(upToCount: bytes) else { return [] }
        try? fh.close()
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        if data.count == bytes, !lines.isEmpty { lines.removeLast() } // drop truncated line
        return lines.filter { !$0.isEmpty }
    }

    /// Read up to `bytes` from the end of the file, split into complete lines.
    static func tailLines(_ path: String, bytes: Int) -> [String] {
        guard let fh = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? fh.close() }
        guard let size = try? fh.seekToEnd() else { return [] }
        let offset = size > UInt64(bytes) ? size - UInt64(bytes) : 0
        try? fh.seek(toOffset: offset)
        guard let data = try? fh.readToEnd() else { return [] }
        var lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        if offset > 0, !lines.isEmpty { lines.removeFirst() } // drop truncated line
        return lines.filter { !$0.isEmpty }
    }

    static func json(_ line: String) -> [String: Any]? {
        guard let d = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    static func clean(_ s: String, max: Int = 80) -> String {
        var t = s.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count > max { t = String(t.prefix(max)) + "…" }
        return t
    }

    /// Overlay time-based status on top of a content-derived one.
    static func finalStatus(contentSaysWorking: Bool, mtime: Date, now: Date = Date()) -> ThreadStatus {
        let age = now.timeIntervalSince(mtime)
        if age < Config.workingWindow { return .working }
        if age > Config.idleAfter { return .idle }
        // ponytail: mid-tool-call with no writes for 3min = likely stuck on a
        // permission prompt -> surface as ready so the user gets pinged.
        if contentSaysWorking { return age < 180 ? .working : .ready }
        return .ready
    }
}
