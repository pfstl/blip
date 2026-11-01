import Foundation
import BlipShared

let usage = """
\(Out.bold("blip")) \(BlipInfo.version) – shows what your Copilot CLI agents are doing in the menu bar
and lets you approve permission requests right there.

\(Out.bold("Commands"))
  install      Set up the app and autostart (the plugin normally does this for you)
               --no-autostart   don't launch at login
  start        Start the app
  stop         Quit the app
  restart      Restart the app
  status       Show state and active sessions
  doctor       Check the installation
  demo         Play two fake sessions incl. a test permission request
  log          Show the debug log (last 40 lines)
  update       How to update via the Copilot plugin
  uninstall    Remove everything
  version      Show the version
"""

var args = Array(CommandLine.arguments.dropFirst())
let command = args.isEmpty ? "help" : args.removeFirst()

func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

switch command {
case "log":
    let lines = (try? String(contentsOf: BlipLog.file, encoding: .utf8))?.split(separator: "\n").suffix(40) ?? []
    print(lines.isEmpty ? "No entries in \(BlipPaths.pretty(BlipLog.file)) yet." : lines.joined(separator: "\n"))
case "install":
    Commands.install(buildDir: option("--build-dir"), source: option("--source"),
                     autostart: !args.contains("--no-autostart"))
case "start":
    Commands.startApp()
    if Commands.waitForApp(running: true) { Out.ok("App is running.") } else { Out.fail("Couldn't start the app.") }
case "stop":
    Commands.stopApp()
    Out.ok("App stopped.")
case "restart":
    Commands.stopApp()
    Commands.startApp()
    if Commands.waitForApp(running: true) { Out.ok("App is running again.") }
case "status":
    Commands.status()
case "doctor":
    Commands.doctor()
case "demo":
    Commands.demo()
case "update":
    Commands.update()
case "uninstall":
    Commands.uninstall()
case "version", "--version", "-v":
    print(BlipInfo.version)
case "help", "--help", "-h":
    print(usage)
default:
    print(usage)
    exit(1)
}
