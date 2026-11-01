import Foundation

/// Small debug log in ~/.blip/debug.log (rotated at 256 KB).
/// Show it with `blip log`.
public enum BlipLog {
    public static var file: URL { BlipPaths.base.appendingPathComponent("debug.log") }

    public static func write(_ source: String, _ message: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: BlipPaths.base, withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int), size > 256 * 1024 {
            let old = BlipPaths.base.appendingPathComponent("debug.old.log")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: file, to: old)
        }
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current,
                                                formatOptions: [.withTime, .withColonSeparatorInTime])
        let line = "\(stamp) [\(source)] \(message)\n"
        if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil) }
        if let handle = try? FileHandle(forWritingTo: file) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        }
    }
}
