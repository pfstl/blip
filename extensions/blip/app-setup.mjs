// Makes sure the Blip app is installed on the Mac, matches the plugin version and is running.
//
// The app is built locally from the plugin's source (Swift package in the plugin folder) – that's why
// it needs no Apple signature. The build runs once (and again after a plugin update) in the
// background and never blocks the Copilot session. Sessions starting at the same time
// coordinate through a lock file, so the app is only built once.

import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HOME = os.homedir();
const BLIP_DIR = path.join(HOME, ".blip");
const BUILD_DIR = path.join(BLIP_DIR, "build");
const BUILD_LOG = path.join(BLIP_DIR, "build.log");
const LOCK = path.join(BLIP_DIR, "build.lock");
const BUNDLE_ID = "io.github.blip-agents";
const APP_CANDIDATES = [path.join(HOME, "Applications", "Blip.app"), "/Applications/Blip.app"];

/** Plugin root: extensions/blip/app-setup.mjs → two levels up. */
export const PLUGIN_ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..");

function pluginVersion() {
  try {
    return JSON.parse(fs.readFileSync(path.join(PLUGIN_ROOT, ".plugin", "plugin.json"), "utf8")).version;
  } catch {
    return undefined;
  }
}

function findApp() {
  return APP_CANDIDATES.find((p) => fs.existsSync(path.join(p, "Contents", "Info.plist")));
}

function appVersion(appPath) {
  try {
    const plist = fs.readFileSync(path.join(appPath, "Contents", "Info.plist"), "utf8");
    return plist.match(/<key>CFBundleShortVersionString<\/key>\s*<string>([^<]+)<\/string>/)?.[1];
  } catch {
    return undefined;
  }
}

function commandLineToolsInstalled() {
  try {
    execFileSync("/usr/bin/xcode-select", ["-p"], { stdio: "ignore" });
    return fs.existsSync("/usr/bin/swift");
  } catch {
    return false;
  }
}

function isAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

/** Is a build running right now (from this or another session)? */
function buildRunning() {
  try {
    const pid = Number(fs.readFileSync(LOCK, "utf8").trim());
    if (pid && isAlive(pid)) return true;
    fs.rmSync(LOCK, { force: true }); // stale
  } catch {
    /* no lock */
  }
  return false;
}

function launchApp(appPath) {
  // -g: launch in the background without stealing focus. Does nothing if it's already running.
  spawn("/usr/bin/open", ["-g", appPath], { stdio: "ignore", detached: true }).unref();
}

/** Runs build + install as a detached background process (survives the end of the session). */
function startBuild() {
  fs.mkdirSync(BLIP_DIR, { recursive: true });
  const q = (s) => `'${s.replaceAll("'", "'\\''")}'`;
  const swiftArgs = `-c release --package-path ${q(PLUGIN_ROOT)} --scratch-path ${q(BUILD_DIR)}`;
  const script = [
    "set -e",
    `trap 'rm -f ${q(LOCK)}' EXIT`,
    `echo "=== Blip build $(date) – source: ${PLUGIN_ROOT.replaceAll('"', "")}"`,
    `/usr/bin/swift build ${swiftArgs}`,
    `BIN="$(/usr/bin/swift build ${swiftArgs} --show-bin-path)"`,
    `"$BIN/blip" install --build-dir "$BIN" --source ${q(PLUGIN_ROOT)}`,
    `echo "=== done"`,
  ].join("\n");
  const log = fs.openSync(BUILD_LOG, "w");
  const child = spawn("/bin/zsh", ["-c", script], { stdio: ["ignore", log, log], detached: true, cwd: BLIP_DIR });
  fs.writeFileSync(LOCK, String(child.pid));
  child.unref();
}

/**
 * Checks the app and builds/launches it when needed.
 * @param {(message: string, level?: "info" | "warning" | "error") => void} notify  message in the Copilot session
 */
export function ensureApp(notify) {
  if (process.platform !== "darwin") return;

  const wanted = pluginVersion();
  const app = findApp();
  const installed = app ? appVersion(app) : undefined;

  if (app && (!wanted || installed === wanted)) {
    launchApp(app);
    return;
  }

  if (buildRunning()) {
    notify("Blip is being set up (in another session) – it'll show up in the menu bar shortly.");
    watchBuild(notify, wanted);
    return;
  }

  if (!fs.existsSync(path.join(PLUGIN_ROOT, "Package.swift"))) {
    notify(`Can't build the Blip app: source code missing in ${PLUGIN_ROOT}.`, "error");
    return;
  }

  if (!commandLineToolsInstalled()) {
    notify(
      "Blip needs the Xcode Command Line Tools. The installer opens in its own window now – " +
        "just start a new Copilot session afterwards.",
      "warning",
    );
    try {
      spawn("/usr/bin/xcode-select", ["--install"], { stdio: "ignore", detached: true }).unref();
    } catch {
      /* ignore */
    }
    return;
  }

  notify(
    app
      ? `Updating Blip to version ${wanted} (in the background) …`
      : "Setting up Blip once – building the app locally (about 1–2 minutes, in the background) …",
  );
  try {
    startBuild();
  } catch (error) {
    notify(`Couldn't start the Blip build: ${error?.message ?? error}`, "error");
    return;
  }
  watchBuild(notify, wanted);
}

/** Reports back as soon as the background build has finished. */
function watchBuild(notify, wanted) {
  const started = Date.now();
  const timer = setInterval(() => {
    if (buildRunning()) {
      if (Date.now() - started > 15 * 60 * 1000) {
        clearInterval(timer); // give up after 15 minutes; the build may keep running
      }
      return;
    }
    clearInterval(timer);
    const app = findApp();
    if (app && (!wanted || appVersion(app) === wanted)) {
      notify("Blip is ready ✓ – look for it in your menu bar.");
    } else {
      notify(`Blip build failed. Details: ${BUILD_LOG}`, "error");
    }
  }, 2000);
  timer.unref?.();
}
