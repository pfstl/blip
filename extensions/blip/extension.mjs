// Blip – Copilot CLI extension (part of the Blip plugin)
//
// Install: `copilot plugin install pfstl/blip`. The Copilot CLI starts this extension
// as its own Node process for every session.
//
// Jobs:
//   0. On start, check that the Blip app is installed and matches the plugin version –
//      otherwise build and install it in the background from the plugin's source (app-setup.mjs).
//   1. Report everything the agent does to the Blip app, live (Unix socket ~/.blip/blip-ext.sock).
//   2. Forward permission requests to Blip and pass answers from the menu bar back to Copilot.
//      The terminal still asks as usual in parallel – whoever answers first wins.
//
// Protocol (one JSON message per line):
//   Extension → App: { type: "hello" | "activity" | "permission" | "permissionDone" | "bye", sessionId, … }
//   App → Extension: { type: "decide", requestId, decision: "approve-once" | "approve-for-session" | "reject", feedback? }

import { joinSession } from "@github/copilot-sdk/extension";
import { ensureApp } from "./app-setup.mjs";
import { execFileSync } from "node:child_process";
import net from "node:net";
import os from "node:os";
import path from "node:path";

const SOCKET = path.join(os.homedir(), ".blip", "blip-ext.sock");
const MAX_TEXT = 400;

const clip = (s, n = MAX_TEXT) => {
  if (typeof s !== "string") return undefined;
  const t = s.replace(/\s+$/u, "");
  return t.length > n ? t.slice(0, n - 1) + "…" : t;
};

// ---------------------------------------------------------------------------
// Connection to the app (reconnects automatically if Blip starts later)
// ---------------------------------------------------------------------------

let socket = null;
let connected = false;
let buffer = "";
let retryMs = 1000;
const pendingPermissions = new Map(); // requestId → message (replayed on reconnect)
let lastStatus = null;

function send(message) {
  if (!connected || !socket) return;
  try {
    socket.write(JSON.stringify({ ...message, sessionId }) + "\n");
  } catch {
    /* connection lost – will reconnect */
  }
}

function connect() {
  socket = net.createConnection(SOCKET);
  socket.setEncoding("utf8");
  socket.on("connect", () => {
    connected = true;
    retryMs = 1000;
    send(hello());
    if (lastStatus) send(lastStatus);
    for (const message of pendingPermissions.values()) send(message);
  });
  socket.on("data", (chunk) => {
    buffer += chunk;
    let index;
    while ((index = buffer.indexOf("\n")) >= 0) {
      const line = buffer.slice(0, index);
      buffer = buffer.slice(index + 1);
      if (!line.trim()) continue;
      try {
        handleAppMessage(JSON.parse(line));
      } catch {
        /* ignore invalid line */
      }
    }
  });
  const retry = () => {
    if (connected) connected = false;
    socket?.destroy();
    socket = null;
    setTimeout(connect, retryMs);
    retryMs = Math.min(retryMs * 2, 15000);
  };
  socket.on("error", () => {});
  socket.on("close", retry);
}

// ---------------------------------------------------------------------------
// Which app hosts the session? (Terminal, iTerm, VS Code …) – for "Jump to session"
// ---------------------------------------------------------------------------

// The session's terminal device (e.g. /dev/ttys003) – lets Blip bring exactly this window/tab to the front.
function findTty() {
  try {
    const out = execFileSync("/bin/ps", ["-o", "tty=", "-p", String(process.ppid)], { encoding: "utf8" }).trim();
    if (out && out !== "??") return out.startsWith("/dev/") ? out : `/dev/${out}`;
  } catch {
    /* ignore */
  }
  return undefined;
}

function findHostApp() {
  try {
    let pid = process.ppid;
    for (let depth = 0; depth < 40 && pid > 1; depth++) {
      const out = execFileSync("/bin/ps", ["-o", "ppid=,comm=", "-p", String(pid)], { encoding: "utf8" }).trim();
      const match = out.match(/^(\d+)\s+(.*)$/);
      if (!match) break;
      const app = match[2].indexOf(".app/");
      if (app >= 0) return match[2].slice(0, app + 4);
      pid = Number(match[1]);
    }
  } catch {
    /* ignore */
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// Join the session
// ---------------------------------------------------------------------------

// The session's working directory. Note: the extension's process.cwd() is Copilot's internal
// session folder (~/.copilot/session-state/<id>) – not your project.
// So we ask the Copilot process (our parent) and later pick up the cwd from session events.
function findSessionCwd() {
  try {
    const out = execFileSync("/usr/sbin/lsof", ["-a", "-p", String(process.ppid), "-d", "cwd", "-Fn"], { encoding: "utf8" });
    const line = out.split("\n").find((l) => l.startsWith("n"));
    if (line && !line.includes("/.copilot/")) return line.slice(1);
  } catch {
    /* ignore */
  }
  return undefined;
}

let sessionId = "";
const hostApp = findHostApp();
const tty = findTty();
let cwd = findSessionCwd();
let title;

const session = await joinSession({
  // Registering a handler is what allows this extension to answer permission requests.
  // We don't answer here though ("no-result"): the terminal asks as usual,
  // and Blip's answer arrives later via handlePendingPermissionRequest.
  onPermissionRequest: async () => ({ kind: "no-result" }),
});
sessionId = session.sessionId;

function hello() {
  return { type: "hello", cwd, hostApp, tty, title, pid: process.pid };
}

// Check the Blip app, build/update it if needed and launch it – messages show up in the session.
try {
  ensureApp((message, level = "info") => {
    session.log?.(`Blip: ${message}`, { level })?.catch?.(() => {});
  });
} catch {
  /* A session must never fail because of Blip. */
}

connect();

// ---------------------------------------------------------------------------
// Translate events
// ---------------------------------------------------------------------------

const outputTimers = new Map(); // toolCallId → latest output (throttled)

function activity(kind, fields = {}) {
  const message = { type: "activity", kind, at: Date.now(), ...fields };
  if (["working", "idle", "error"].includes(kind)) lastStatus = message;
  send(message);
}

function describeTool(data) {
  const args = data.arguments ?? {};
  const detail = args.command ?? args.path ?? args.file_path ?? args.url ?? args.pattern ?? args.query;
  return {
    toolCallId: data.toolCallId,
    tool: data.toolName,
    title: data.toolTitle,
    intention: clip(args.description, 160),
    detail: clip(typeof detail === "string" ? detail : undefined, 300),
  };
}

function describePermission(request) {
  const r = request ?? {};
  let summary;
  let sessionApproval = null; // What "Allow for session" sends to Copilot
  switch (r.kind) {
    case "shell":
      summary = r.fullCommandText;
      if (r.canOfferSessionApproval) {
        const ids = (r.commands ?? []).map((c) => c.identifier).filter(Boolean);
        if (ids.length) sessionApproval = { approval: { kind: "commands", commandIdentifiers: ids }, label: ids.join(", ") };
      }
      break;
    case "write":
      summary = r.fileName;
      if (r.canOfferSessionApproval) sessionApproval = { approval: { kind: "write" }, label: "writing files" };
      break;
    case "read":
      summary = r.path;
      sessionApproval = { approval: { kind: "read" }, label: "reading files" };
      break;
    case "url": {
      summary = r.url;
      let domain;
      try { domain = new URL(r.url).hostname; } catch { /* ignore */ }
      if (domain) sessionApproval = { domain, label: domain };
      break;
    }
    case "mcp":
      summary = `${r.serverDisplayName ?? r.serverName}: ${r.toolTitle ?? r.toolName}`;
      sessionApproval = { approval: { kind: "mcp", serverName: r.serverName, toolName: r.toolName ?? null }, label: r.toolTitle ?? r.toolName };
      break;
    case "custom-tool":
      summary = r.toolName;
      sessionApproval = { approval: { kind: "custom-tool", toolName: r.toolName }, label: r.toolName };
      break;
    case "memory":
      summary = "Store a memory";
      sessionApproval = { approval: { kind: "memory" }, label: "memories" };
      break;
    default:
      summary = r.intention ?? r.kind;
  }
  return {
    kind: r.kind ?? "unknown",
    summary: clip(summary, 500),
    intention: clip(r.intention, 200),
    toolCallId: r.toolCallId,
    sessionLabel: sessionApproval?.label,
    sessionApproval,
  };
}

const permissionDetails = new Map(); // requestId → describePermission(…)

session.on((event) => {
  const type = event?.type;
  const data = event?.data ?? {};
  // The real project cwd is in the hook events (sessionStart, userPromptSubmitted …).
  const eventCwd = data.input?.cwd ?? data.cwd;
  if (typeof eventCwd === "string" && eventCwd && !eventCwd.includes("/.copilot/") && eventCwd !== cwd) {
    cwd = eventCwd;
    send(hello());
  }

  switch (type) {
    case "user.message":
      activity("user", { text: clip(data.content) });
      activity("working");
      break;
    case "assistant.turn_start":
      activity("working");
      break;
    case "tool.execution_start":
      activity("toolStart", describeTool(data));
      break;
    case "tool.shell_output": {
      // Batch output: at most one message per tool every 400 ms.
      const id = data.toolCallId;
      const entry = outputTimers.get(id) ?? { text: "", timer: null };
      entry.text += data.text ?? "";
      if (!entry.timer) {
        entry.timer = setTimeout(() => {
          activity("toolOutput", { toolCallId: id, text: clip(entry.text.split("\n").slice(-6).join("\n"), 600) });
          entry.timer = null;
          entry.text = "";
        }, 400);
      }
      outputTimers.set(id, entry);
      break;
    }
    case "tool.execution_complete":
      activity("toolEnd", {
        toolCallId: data.toolCallId,
        success: data.success !== false,
        exitCode: data.shellExecution?.exitCode,
      });
      break;
    case "assistant.message":
      if (typeof data.content === "string" && data.content.trim()) {
        activity("assistant", { text: clip(data.content), final: data.phase === "final_answer" });
      }
      break;
    case "session.idle":
      activity("idle");
      break;
    case "session.error":
      activity("error", { text: clip(data.message ?? data.error ?? "Error") });
      break;
    case "session.title_changed":
      title = clip(data.title, 120);
      send({ type: "title", title });
      break;
    case "permission.requested": {
      const id = data.requestId;
      const details = describePermission(data.permissionRequest);
      permissionDetails.set(id, details);
      const { sessionApproval, ...shown } = details;
      const message = { type: "permission", requestId: id, ...shown };
      pendingPermissions.set(id, message);
      send(message);
      break;
    }
    case "permission.completed": {
      const id = data.requestId;
      pendingPermissions.delete(id);
      permissionDetails.delete(id);
      send({ type: "permissionDone", requestId: id, result: data.result?.kind });
      break;
    }
    case "session.shutdown":
      send({ type: "bye" });
      break;
    default:
      break;
  }
});

// ---------------------------------------------------------------------------
// Answers from the menu bar
// ---------------------------------------------------------------------------

async function handleAppMessage(message) {
  if (message?.type !== "decide") return;
  const id = message.requestId;
  const details = permissionDetails.get(id);
  let result;
  switch (message.decision) {
    case "approve-once":
      result = { kind: "approve-once", approvedInteractively: true };
      break;
    case "approve-for-session":
      result = details?.sessionApproval
        ? { kind: "approve-for-session", ...details.sessionApproval, label: undefined }
        : { kind: "approve-once", approvedInteractively: true };
      break;
    case "reject":
      result = { kind: "reject", feedback: message.feedback ?? "Denied via Blip." };
      break;
    default:
      return;
  }
  delete result.label;
  try {
    await session.rpc.permissions.handlePendingPermissionRequest({ requestId: id, result });
  } catch (error) {
    // e.g. already answered in the terminal – permission.completed follows anyway.
    send({ type: "decideFailed", requestId: id, error: String(error?.message ?? error) });
  }
}
