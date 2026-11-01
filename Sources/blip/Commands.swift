import Foundation
import Darwin
import BlipShared

enum Commands {
    static let fm = FileManager.default
    static var guiDomain: String { "gui/\(getuid())" }

    // MARK: - install

    static func install(buildDir override: String?, source: String?, autostart: Bool) {
        guard let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
            Out.fail("Couldn't determine my own path.")
        }
        let buildDir = override.map { URL(fileURLWithPath: $0) } ?? exe.deletingLastPathComponent()
        let appBinary = buildDir.appendingPathComponent("BlipApp")
        guard fm.exists(appBinary) else {
            Out.fail("App binary not found at \(appBinary.path).\n  Run `make install` in the source folder.")
        }

        print(Out.bold("Installing Blip \(BlipInfo.version)\n"))

        // Source folder (plugin folder or git checkout): passed in, otherwise derived from the build folder.
        let sourceDir = source.map { URL(fileURLWithPath: $0) }
            ?? buildDir.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

        removeNudge()

        if runningPid() != nil {
            Out.step("Stopping running app …")
            stopApp()
        }

        do {
            try fm.createDirectory(at: BlipPaths.base, withIntermediateDirectories: true)

            // 1. CLI to ~/.local/bin
            if exe.path != BlipPaths.cli.resolvingSymlinksInPath().path {
                try fm.replaceItem(at: BlipPaths.cli, with: exe)
            }
            Out.ok("Command-line tool → \(BlipPaths.pretty(BlipPaths.cli))")

            // 2. Assemble the app bundle
            try buildAppBundle(from: appBinary)
            Out.ok("App → \(BlipPaths.pretty(BlipPaths.appBundle))")

            // 3. Remember the source folder
            try sourceDir.path.write(to: BlipPaths.sourceFile, atomically: true, encoding: .utf8)

            // 4. Launch at login
            if autostart {
                try writeLaunchAgent()
                Out.ok("Launch at login enabled")
            } else if fm.exists(BlipPaths.launchAgent) {
                Shell.run("/bin/launchctl", ["bootout", guiDomain, BlipPaths.launchAgent.path])
                try? fm.removeItem(at: BlipPaths.launchAgent)
            }
        } catch {
            Out.fail("Installation failed: \(error.localizedDescription)")
        }

        startApp()
        if waitForApp(running: true) { Out.ok("App is running – check your menu bar 👀") }

        if !pathContainsBinDir() {
            print("")
            Out.warn("\(BlipPaths.pretty(BlipPaths.binDir)) isn't on your PATH. Add this to ~/.zshrc:")
            print("    export PATH=\"$HOME/.local/bin:$PATH\"")
        }
        print("\nTry it: " + Out.bold("blip demo"))
        if !pluginInstalled() {
            print(Out.dim("For the live feed and approvals, install the Copilot plugin: copilot plugin install pfstl/blip"))
        }
    }

    /// Cleans up the predecessor "Nudge" (quit the app, delete app/tool/autostart/extension/data).
    static func removeNudge() {
        let legacy = BlipPaths.Legacy.self
        guard legacy.all.contains(where: { fm.exists($0) }) || fm.exists(legacy.base) else { return }
        Out.step("Removing the old version “Nudge” …")
        Shell.run("/bin/launchctl", ["bootout", "\(guiDomain)/\(legacy.label)"])
        if let s = try? String(contentsOf: legacy.pidFile, encoding: .utf8),
           let pid = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGTERM)
        }
        for url in legacy.all + [legacy.base] where fm.exists(url) {
            try? fm.removeItem(at: url)
            Out.ok("removed: \(BlipPaths.pretty(url))")
        }
    }

    static func buildAppBundle(from binary: URL) throws {
        let contents = BlipPaths.appBundle.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        try fm.createDirectory(at: contents.appendingPathComponent("Resources"), withIntermediateDirectories: true)
        try fm.replaceItem(at: BlipPaths.appExecutable, with: binary)

        let info: [String: Any] = [
            "CFBundleExecutable": "BlipApp",
            "CFBundleIdentifier": BlipInfo.bundleId,
            "CFBundleName": BlipInfo.appName,
            "CFBundleDisplayName": BlipInfo.appName,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": BlipInfo.version,
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "14.0",
            "LSUIElement": true,
            "NSHighResolutionCapable": true,
            // For "Jump to session": have Terminal/iTerm show the right tab via AppleScript.
            "NSAppleEventsUsageDescription": "Blip uses this to bring the terminal window of your Copilot session to the front.",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))

        // Ad-hoc signature for the whole bundle (no Apple account needed).
        Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", BlipInfo.bundleId, BlipPaths.appBundle.path])
    }

    static func writeLaunchAgent() throws {
        let plist: [String: Any] = [
            "Label": BlipInfo.launchAgentLabel,
            "ProgramArguments": [BlipPaths.appExecutable.path],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
            "LimitLoadToSessionType": "Aqua",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try fm.createDirectory(at: BlipPaths.launchAgent.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: BlipPaths.launchAgent)
    }

    // MARK: - start / stop

    static func startApp() {
        guard fm.exists(BlipPaths.appBundle) else {
            Out.fail("App not installed. Run `blip install` or `make install` first.")
        }
        if runningPid() != nil { return }
        if fm.exists(BlipPaths.launchAgent) {
            let r = Shell.run("/bin/launchctl", ["bootstrap", guiDomain, BlipPaths.launchAgent.path])
            if r.status != 0 {
                // Already loaded (e.g. the app was quit from its menu) → just start it.
                Shell.run("/bin/launchctl", ["kickstart", "\(guiDomain)/\(BlipInfo.launchAgentLabel)"])
            }
        } else {
            Shell.run("/usr/bin/open", [BlipPaths.appBundle.path])
        }
    }

    static func stopApp() {
        if fm.exists(BlipPaths.launchAgent) {
            Shell.run("/bin/launchctl", ["bootout", "\(guiDomain)/\(BlipInfo.launchAgentLabel)"])
        }
        if !waitForApp(running: false), let pid = runningPid() {
            kill(pid, SIGTERM)
            _ = waitForApp(running: false)
        }
    }

    static func runningPid() -> pid_t? {
        guard let s = try? String(contentsOf: BlipPaths.pidFile, encoding: .utf8),
              let pid = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)),
              kill(pid, 0) == 0 else { return nil }
        return pid
    }

    @discardableResult
    static func waitForApp(running: Bool, timeout: TimeInterval = 3) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if (runningPid() != nil) == running { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return (runningPid() != nil) == running
    }

    // MARK: - status

    static func status() {
        func line(_ label: String, _ ok: Bool, _ detail: String) {
            let mark = ok ? Out.c("32", "✓") : Out.c("31", "✗")
            print("  \(mark) \(label.padding(toLength: 12, withPad: " ", startingAt: 0)) \(Out.dim(detail))")
        }
        print(Out.bold("Blip \(BlipInfo.version)"))
        line("App", fm.exists(BlipPaths.appBundle), BlipPaths.pretty(BlipPaths.appBundle))
        let pid = runningPid()
        line("Running", pid != nil, pid.map { "PID \($0)" } ?? "blip start")
        line("Plugin", pluginInstalled(), "copilot plugin list")
        line("Login item", fm.exists(BlipPaths.launchAgent), BlipPaths.pretty(BlipPaths.launchAgent))
        line("PATH", pathContainsBinDir(), BlipPaths.pretty(BlipPaths.binDir))

        guard pid != nil,
              let data = try? Data(contentsOf: BlipPaths.stateFile),
              let sessions = try? JSONDecoder().decode([SessionSnapshot].self, from: data) else { return }
        print("\n" + Out.bold("Sessions"))
        if sessions.isEmpty { print(Out.dim("  none")) }
        for s in sessions {
            let color: String = switch s.state {
            case "needsInput": "33"
            case "working": "36"
            case "done": "32"
            case "error": "31"
            default: "2"
            }
            let ago = Int(Date().timeIntervalSince1970 - s.since)
            print("  \(Out.c(color, "●")) \(s.project.padding(toLength: 22, withPad: " ", startingAt: 0)) \(s.detail) \(Out.dim("· \(ago)s"))")
        }
    }

    // MARK: - update / uninstall

    static func update() {
        print("""
        Blip is updated through the Copilot plugin:
            copilot plugin update blip
        The next time a Copilot session starts, the extension rebuilds the app automatically.
        """)
    }

    static func uninstall() {
        Out.step("Removing Blip …")
        stopApp()
        for url in [BlipPaths.launchAgent, BlipPaths.appBundle, BlipPaths.cli, BlipPaths.base] {
            if fm.exists(url) {
                try? fm.removeItem(at: url)
                Out.ok("removed: \(BlipPaths.pretty(url))")
            }
        }
        print("Bye 👋")
        if pluginInstalled() {
            print(Out.dim("Remove the Copilot plugin with: copilot plugin uninstall blip"))
        }
    }

    // MARK: - doctor

    static func doctor() {
        print(Out.bold("Blip – diagnostics\n"))
        let v = ProcessInfo.processInfo.operatingSystemVersion
        check(v.majorVersion >= 14, "macOS \(v.majorVersion).\(v.minorVersion)", fix: "macOS 14 (Sonoma) or later required")

        let copilot = Shell.sh("command -v copilot >/dev/null && copilot --version")
        check(copilot.status == 0,
              "Copilot CLI: \(copilot.output.split(separator: "\n").first.map(String.init) ?? "–")",
              fix: "Not found – Blip only works with the Copilot CLI.", optional: true)

        check(pluginInstalled(), "Copilot plugin “blip” installed", fix: "copilot plugin install pfstl/blip")
        check(fm.isExecutableFile(atPath: BlipPaths.cli.path), "Tool at \(BlipPaths.pretty(BlipPaths.cli))", fix: "make install")
        check(runningPid() != nil, "App running", fix: "blip start")
        check(fm.exists(BlipPaths.extensionSocket), "Extension-Socket \(BlipPaths.pretty(BlipPaths.extensionSocket))", fix: "blip restart")

        print("""

        \(Out.bold("Notes"))
          • Blip ships as a Copilot CLI plugin. Its extension starts with every session (see /extensions),
            builds the app when needed (log: ~/.blip/build.log) and launches it.
          • Restart Copilot sessions that were already running during installation.
        """)
    }

    private static func check(_ ok: Bool, _ label: String, fix: String, optional: Bool = false) {
        if ok { Out.ok(label) }
        else if optional { Out.warn("\(label) – \(fix)") }
        else { print(Out.c("31", "✗") + " \(label) " + Out.dim("→ \(fix)")) }
    }

    // MARK: - demo

    /// Plays two made-up Copilot sessions – exactly the way the real extension reports them.
    /// Session 2 sends a real permission request: answer it in the menu bar!
    static func demo() {
        guard runningPid() != nil else { Out.fail("App isn't running. Run `blip start` first.") }
        guard let web = LineSocketClient(path: BlipPaths.extensionSocket.path),
              let api = LineSocketClient(path: BlipPaths.extensionSocket.path) else {
            Out.fail("No connection to the app (\(BlipPaths.pretty(BlipPaths.extensionSocket))).")
        }
        let webId = "demo-website", apiId = "demo-api"
        func say(_ c: LineSocketClient, _ id: String, _ msg: [String: Any], wait: Double = 0) {
            var m = msg
            m["sessionId"] = id
            c.send(m)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
        }
        func act(_ c: LineSocketClient, _ id: String, _ kind: String, _ fields: [String: Any] = [:], wait: Double = 0) {
            var m = fields
            m["type"] = "activity"
            m["kind"] = kind
            say(c, id, m, wait: wait)
        }

        Out.step("Session 1 starting …")
        say(web, webId, ["type": "hello", "cwd": "/demo/website", "title": "Rework navbar"], wait: 0.3)
        act(web, webId, "user", ["text": "Make the navbar collapsible on mobile"])
        act(web, webId, "working", wait: 1.5)
        act(web, webId, "toolStart", ["toolCallId": "w1", "tool": "view", "title": "Viewing file", "detail": "src/components/Navbar.tsx"], wait: 1)
        act(web, webId, "toolEnd", ["toolCallId": "w1", "success": true])
        act(web, webId, "toolStart", ["toolCallId": "w2", "tool": "edit", "title": "Editing file", "detail": "src/components/Navbar.tsx"], wait: 1.4)
        act(web, webId, "toolEnd", ["toolCallId": "w2", "success": true])

        Out.step("Session 2 starting …")
        say(api, apiId, ["type": "hello", "cwd": "/demo/api-server", "title": "Fix tests"], wait: 0.3)
        act(api, apiId, "user", ["text": "Run the tests and fix any failures"])
        act(api, apiId, "working", wait: 1.2)
        act(api, apiId, "toolStart", ["toolCallId": "a1", "tool": "bash", "title": "Running command",
                                      "intention": "Run the test suite", "detail": "npm test"], wait: 0.3)

        Out.step("Session 2 needs you – answer in the menu bar (30 s) …")
        let requestId = UUID().uuidString
        say(api, apiId, ["type": "permission", "requestId": requestId, "kind": "shell",
                         "summary": "npm test -- --coverage", "intention": "Run the test suite",
                         "toolCallId": "a1", "sessionLabel": "npm"])
        var answer = "none (timed out)"
        let end = Date().addingTimeInterval(30)
        while Date() < end {
            guard let msg = api.readLine(timeout: end.timeIntervalSinceNow) else { break }
            guard msg["type"] as? String == "decide", msg["requestId"] as? String == requestId else { continue }
            let decision = msg["decision"] as? String ?? "?"
            answer = ["approve-once": "allowed ✓", "approve-for-session": "allowed for the session ✓",
                      "reject": "denied ✗"][decision] ?? decision
            break
        }
        Out.ok("Your answer: \(answer)")
        let approved = answer.contains("✓")
        say(api, apiId, ["type": "permissionDone", "requestId": requestId, "result": approved ? "approved" : "denied-interactively-by-user"])
        if approved {
            act(api, apiId, "toolOutput", ["toolCallId": "a1", "text": "PASS  src/user.test.ts\nFAIL  src/order.test.ts\n  ✕ calculates total (12 ms)"], wait: 1.2)
            act(api, apiId, "toolEnd", ["toolCallId": "a1", "success": false, "exitCode": 1], wait: 0.5)
        }

        Out.step("Done!")
        act(web, webId, "assistant", ["text": "The navbar now collapses below 768 px. I added a burger button.", "final": true])
        act(web, webId, "idle", wait: 2.5)
        act(api, apiId, "error", ["text": "Tests failed (1 of 48)"], wait: 6)

        say(web, webId, ["type": "bye"], wait: 0.3)
        say(api, apiId, ["type": "bye"])
        Out.ok("Demo over.")
    }

    // MARK: - helpers

    /// Is there a plugin named "blip" anywhere under ~/.copilot/installed-plugins?
    static func pluginInstalled() -> Bool {
        guard let walker = fm.enumerator(at: BlipPaths.installedPlugins, includingPropertiesForKeys: nil) else { return false }
        for case let url as URL in walker {
            if walker.level > 4 { walker.skipDescendants(); continue }
            guard url.lastPathComponent == "plugin.json",
                  let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if json["name"] as? String == "blip" { return true }
        }
        return false
    }

    static func pathContainsBinDir() -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let bin = BlipPaths.binDir.path
        return path.split(separator: ":").contains { $0 == bin || $0 == bin + "/" }
    }
}
