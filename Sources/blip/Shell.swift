import Foundation

/// Small helpers for output and external processes.
enum Shell {
    @discardableResult
    static func run(_ executable: String, _ args: [String], cwd: URL? = nil, quiet: Bool = true) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = cwd }
        let pipe = Pipe()
        if quiet {
            p.standardOutput = pipe
            p.standardError = pipe
        }
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = quiet ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// Runs a command through the login shell (so PATH is right).
    @discardableResult
    static func sh(_ command: String, quiet: Bool = true) -> (status: Int32, output: String) {
        run("/bin/zsh", ["-lc", command], quiet: quiet)
    }
}

enum Out {
    static let isTTY = isatty(STDOUT_FILENO) == 1
    static func c(_ code: String, _ s: String) -> String { isTTY ? "\u{1B}[\(code)m\(s)\u{1B}[0m" : s }

    static func step(_ s: String) { print(c("1;36", "▸") + " " + s) }
    static func ok(_ s: String) { print(c("32", "✓") + " " + s) }
    static func warn(_ s: String) { print(c("33", "!") + " " + s) }
    static func fail(_ s: String) -> Never {
        FileHandle.standardError.write(Data((c("31", "✗") + " " + s + "\n").utf8))
        exit(1)
    }
    static func dim(_ s: String) -> String { c("2", s) }
    static func bold(_ s: String) -> String { c("1", s) }
}

extension FileManager {
    func exists(_ url: URL) -> Bool { fileExists(atPath: url.path) }

    /// Replaces a file by deleting + copying (new inode).
    /// Matters on macOS: overwriting a running, signed binary in place gets it SIGKILLed.
    func replaceItem(at dest: URL, with src: URL) throws {
        try createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileExists(atPath: dest.path) { try removeItem(at: dest) }
        try copyItem(at: src, to: dest)
    }
}
