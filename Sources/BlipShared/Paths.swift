import Foundation

public enum BlipInfo {
    /// Must match the version in .plugin/plugin.json – that's how the extension knows the app needs a rebuild.
    public static let version = "0.3.1"
    public static let appName = "Blip"
    public static let bundleId = "io.github.blip-agents"
    public static let launchAgentLabel = "io.github.blip-agents"
}

/// Every place Blip touches. Everything lives in your home folder – no sudo needed.
public enum BlipPaths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// ~/.blip – socket, PID, status snapshot, logs
    public static var base: URL { home.appendingPathComponent(".blip", isDirectory: true) }
    public static var pidFile: URL { base.appendingPathComponent("blip.pid") }
    public static var stateFile: URL { base.appendingPathComponent("sessions.json") }
    public static var sourceFile: URL { base.appendingPathComponent("source-path") }

    /// ~/.local/bin/blip
    public static var binDir: URL { home.appendingPathComponent(".local/bin", isDirectory: true) }
    public static var cli: URL { binDir.appendingPathComponent("blip") }

    /// ~/Applications/Blip.app
    public static var appBundle: URL {
        home.appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("\(BlipInfo.appName).app", isDirectory: true)
    }
    public static var appExecutable: URL { appBundle.appendingPathComponent("Contents/MacOS/BlipApp") }

    /// ~/.copilot or $COPILOT_HOME
    public static var copilotHome: URL {
        if let custom = ProcessInfo.processInfo.environment["COPILOT_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath, isDirectory: true)
        }
        return home.appendingPathComponent(".copilot", isDirectory: true)
    }
    /// Where the Copilot CLI installs plugins (including Blip and its extension).
    public static var installedPlugins: URL { copilotHome.appendingPathComponent("installed-plugins", isDirectory: true) }
    public static var extensionsDir: URL { copilotHome.appendingPathComponent("extensions", isDirectory: true) }
    /// Socket the extension(s) use to talk to the app (stream, one JSON message per line)
    public static var extensionSocket: URL { base.appendingPathComponent("blip-ext.sock") }

    /// Leftovers of the predecessor "Nudge" – cleaned up by `install`.
    public enum Legacy {
        public static let label = "io.github.nudge-agents"
        public static var base: URL { home.appendingPathComponent(".nudge", isDirectory: true) }
        public static var pidFile: URL { base.appendingPathComponent("nudge.pid") }
        public static var all: [URL] {
            [home.appendingPathComponent("Library/LaunchAgents/\(label).plist"),
             home.appendingPathComponent("Applications/Nudge.app", isDirectory: true),
             binDir.appendingPathComponent("nudge"),
             copilotHome.appendingPathComponent("extensions/nudge", isDirectory: true),
             copilotHome.appendingPathComponent("extensions/nudge-spike", isDirectory: true),
             copilotHome.appendingPathComponent("hooks/nudge.json")]
        }
    }

    public static var launchAgent: URL {
        home.appendingPathComponent("Library/LaunchAgents/\(BlipInfo.launchAgentLabel).plist")
    }

    /// Path for display, with ~ instead of the home folder.
    public static func pretty(_ url: URL) -> String {
        let h = home.path
        return url.path.hasPrefix(h) ? "~" + url.path.dropFirst(h.count) : url.path
    }
}
