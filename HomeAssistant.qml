pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Talks to the Home Assistant REST API by spawning curl. Holds no UI types.
// The access token is never passed on a command line: it lives in a mode-600
// header file inside a mode-700 directory and reaches curl as `-H @path`.
QtObject {
  id: root

  property string baseUrl: ""
  property string headerPath: Quickshell.env("HOME") + "/.config/omarchy/homeassistant/auth.header"
  readonly property string configDir: Quickshell.env("HOME") + "/.config/omarchy/homeassistant"
  readonly property string stagingPath: configDir + "/auth.header.new"

  property bool hasCredential: false
  property bool connected: false
  property bool stale: false
  property string lastError: ""
  // HTTP status from the most recent states or command response. Read this
  // instead of matching lastError text (e.g. to detect an expired token via
  // lastStatus === 401) — lastError is a human-facing string and can change
  // wording without that being a behavioural change.
  property int lastStatus: 0
  property var states: ({})
  property bool busy: false

  readonly property bool configured: baseUrl !== "" && hasCredential

  signal statesUpdated()
  signal credentialChecked(bool ok)
  signal probeFinished(bool ok, string error)
  signal commandFinished(string entityId, bool ok, string error)

  function apiUrl(path) {
    return String(baseUrl).replace(/\/+$/, "") + path
  }

  // --max-filesize caps the response body so a broken or hostile server
  // cannot exhaust the shell's memory with an endless reply. Best effort:
  // it needs a Content-Length, which Home Assistant sends. Exceeding it
  // makes curl exit 63, which describeFailure reports specifically.
  function curlArgs(url, headerFile) {
    return ["curl", "-sS", "--max-time", "5", "--max-filesize", "10485760",
      "-w", "\n%{http_code}", "-H", "@" + headerFile, url]
  }

  // ---- credential file ----

  function checkCredential() { statProc.running = true }

  function saveCredential(token) {
    writeProc.command = ["sh", "-c",
      "umask 077 && mkdir -p " + shellQuote(configDir) + " && chmod 700 " + shellQuote(configDir) +
      " && cat > " + shellQuote(stagingPath) + " && chmod 600 " + shellQuote(stagingPath)]
    // stdinEnabled must be true before `running` is set, because Process
    // decides at process-creation time (inside setRunning -> startProcessIfReady)
    // whether to close the write channel. Once a prior run has flipped this
    // back to false (see writeProc.onStarted below), it stays false as a
    // plain imperative assignment, not a live binding, so it has to be
    // re-armed here for every call.
    writeProc.stdinEnabled = true
    writeProc.pendingToken = token
    writeProc.running = true
  }

  function promoteCredential() { promoteProc.running = true }

  function deleteCredential() {
    deleteProc.running = true
    hasCredential = false
    connected = false
  }

  // Single-quote a path for `sh -c`. Paths here are built from $HOME and
  // constants, but quoting keeps a home directory with a space or quote safe.
  function shellQuote(text) {
    return "'" + String(text).replace(/'/g, "'\\''") + "'"
  }

  property Process statProc: Process {
    command: ["stat", "-c", "%a", root.headerPath]
    stdout: StdioCollector { waitForEnd: true }
    onExited: function (exitCode, exitStatus) {
      var mode = String(statProc.stdout.text || "").trim()
      root.hasCredential = exitCode === 0 && mode === "600"
      root.credentialChecked(root.hasCredential)
    }
  }

  // The token reaches this process on stdin, never as an argument, so it
  // cannot be read out of the process list.
  //
  // Verified against Quickshell's Process C++ source (process.cpp) and the
  // one real precedent in this shell (network/Panel.qml's `enterpriseConnect`,
  // which also pipes a secret over stdin): write() is a no-op while the
  // underlying QProcess doesn't exist yet, and Process only guarantees that
  // by the time `onStarted` fires. So the write has to happen there, not
  // right after setting `running = true` from the outside. Closing the
  // channel is safe to do immediately after write() in the same handler:
  // Qt's QProcess::closeWriteChannel() (which is what setting stdinEnabled
  // to false calls) only *schedules* the close — it flushes whatever was
  // just queued by write() before actually closing the pipe — so `cat`
  // still gets the full line before it sees EOF.
  property Process writeProc: Process {
    property string pendingToken: ""
    onStarted: {
      write("Authorization: Bearer " + pendingToken + "\n")
      pendingToken = ""
      stdinEnabled = false
    }
    onExited: function (exitCode, exitStatus) {
      if (exitCode !== 0) {
        root.failProbe("Could not write the credential file.")
        return
      }
      root.probeWithStaging()
    }
  }

  property Process promoteProc: Process {
    command: ["mv", "-f", root.stagingPath, root.headerPath]
    onExited: function (exitCode, exitStatus) {
      root.hasCredential = exitCode === 0
      if (exitCode !== 0) {
        root.failProbe("Could not store the credential file.")
        return
      }
      root.connected = true
      root.lastError = ""
      root.probeFinished(true, "")
    }
  }

  property Process deleteProc: Process {
    command: ["rm", "-f", root.headerPath, root.stagingPath]
  }

  // A probe that fails for any reason (write error, unreachable host, wrong
  // URL, bad token, non-Home-Assistant server, or a failed promotion mv)
  // must not leave a valid-looking token sitting in the staging file — only
  // the attempt using it failed, the token itself may be perfectly good.
  // This never touches headerPath, so a working stored credential from a
  // previous successful probe survives a later failed one untouched.
  property string pendingProbeError: ""

  function failProbe(error) {
    pendingProbeError = error
    cleanupStagingProc.running = true
  }

  property Process cleanupStagingProc: Process {
    command: ["rm", "-f", root.stagingPath]
    onExited: function (exitCode, exitStatus) {
      root.probeFinished(false, root.pendingProbeError)
      root.pendingProbeError = ""
    }
  }

  // ---- probe (setup) ----

  property string probeUrl: ""

  function probe(url, token) {
    probeUrl = String(url).replace(/\/+$/, "")
    saveCredential(token)
  }

  function probeWithStaging() {
    probeProc.command = curlArgs(probeUrl + "/api/", stagingPath)
    probeProc.running = true
  }

  property Process probeProc: Process {
    stdout: StdioCollector { waitForEnd: true }
    onExited: function (exitCode, exitStatus) {
      var parts = Model.splitStatusResponse(String(probeProc.stdout.text || ""))
      var error = Model.describeFailure(exitCode, parts.status)
      if (error === "" && !Model.isHomeAssistant(parts.body))
        error = "Reachable, but this is not a Home Assistant API."
      if (error !== "") {
        root.failProbe(error)
        return
      }
      root.baseUrl = root.probeUrl
      root.promoteCredential()
    }
  }

  // ---- states ----
  //
  // `busy` guards fetchStates() the same way `commandBusy` guards
  // callService() below, and has the same stall exposure: Quickshell's
  // Process only emits `exited` from a normal QProcess::finished. A spawn
  // failure (curl missing) goes through QProcess::errorOccurred instead and
  // emits only runningChanged, never exited — so without a settle guard a
  // failed spawn would leave `busy` stuck true forever and fetchStates()
  // would permanently no-op. `statesSettled` closes that the same way
  // `commandSettled` does below: exactly one of onExited / the
  // running-changed fallback ends up doing the finishing work per fetch.

  property bool statesSettled: true

  function fetchStates() {
    if (busy || !configured) return
    busy = true
    statesSettled = false
    statesProc.command = curlArgs(apiUrl("/api/states"), headerPath)
    statesProc.running = true
  }

  function finishStates(list, error) {
    if (statesSettled) return
    statesSettled = true
    root.busy = false
    if (error !== "") {
      root.connected = false
      root.stale = true
      root.lastError = error
      root.statesUpdated()
      return
    }
    root.states = Model.statesToMap(list)
    root.connected = true
    root.stale = false
    root.lastError = ""
    root.statesUpdated()
  }

  property Process statesProc: Process {
    stdout: StdioCollector { waitForEnd: true }
    onExited: function (exitCode, exitStatus) {
      var parts = Model.splitStatusResponse(String(statesProc.stdout.text || ""))
      root.lastStatus = parts.status
      var error = Model.describeFailure(exitCode, parts.status)
      var list = error === "" ? Model.parseJson(parts.body) : null
      if (error === "" && !Array.isArray(list)) error = "Unexpected answer from the server."
      root.finishStates(list, error)
    }
    onRunningChanged: {
      // A spawn failure never reaches a server, so any HTTP status left
      // over from an earlier fetch (e.g. a stale 401) must not linger and
      // be mistaken for this failure's cause. 0 is the honest value: no
      // HTTP response happened.
      if (!running) {
        root.lastStatus = 0
        root.finishStates(null, "Could not start curl.")
      }
    }
  }

  // ---- commands ----
  //
  // Calls queue instead of clobbering each other: toggling two devices in
  // quick succession is ordinary use of this panel, and a click that
  // silently does nothing (dropping the second call) is worse than a short
  // queueing delay. Only one commandProc is ever in flight (commandBusy);
  // each queued entry keeps its own domain/service/body, so a later call
  // can never overwrite an earlier one's in-flight request or its entityId.
  //
  // commandSettled guards against a stuck queue: Quickshell's Process only
  // emits `exited` from a normal QProcess::finished. A spawn failure (curl
  // missing) goes through QProcess::errorOccurred instead and emits only
  // runningChanged, never exited. Without this guard, a failed spawn would
  // leave commandBusy stuck true forever (the queue never drains, and every
  // later toggle/brightness change would silently do nothing) and would
  // drop that command's commandFinished entirely. finishCommand() is the
  // single place either path funnels through, so exactly one of them ends
  // up firing commandFinished and starting the next queued command.

  property string pendingEntity: ""
  property var pendingCommands: []
  property bool commandBusy: false
  property bool commandSettled: true

  function callService(domain, service, body) {
    pendingCommands.push({ domain: domain, service: service, body: body })
    runNextCommand()
  }

  function runNextCommand() {
    if (commandBusy || pendingCommands.length === 0) return
    var next = pendingCommands.shift()
    commandBusy = true
    commandSettled = false
    pendingEntity = String(next.body.entity_id || "")
    commandProc.command = ["curl", "-sS", "--max-time", "5", "--max-filesize", "10485760",
      "-w", "\n%{http_code}",
      "-H", "@" + headerPath, "-H", "Content-Type: application/json",
      "-d", JSON.stringify(next.body), apiUrl("/api/services/" + next.domain + "/" + next.service)]
    commandProc.running = true
  }

  function finishCommand(ok, error) {
    if (commandSettled) return
    commandSettled = true
    commandBusy = false
    if (error !== "") root.lastError = error
    var entity = root.pendingEntity
    root.commandFinished(entity, ok, error)
    root.runNextCommand()
  }

  property Process commandProc: Process {
    stdout: StdioCollector { waitForEnd: true }
    onExited: function (exitCode, exitStatus) {
      var parts = Model.splitStatusResponse(String(commandProc.stdout.text || ""))
      root.lastStatus = parts.status
      var error = Model.describeFailure(exitCode, parts.status)
      root.finishCommand(error === "", error)
    }
    onRunningChanged: {
      // Same reasoning as statesProc's fallback above: no HTTP response
      // happened, so any stale status from an earlier request must not
      // survive to be misread as this failure's cause.
      if (!running) {
        root.lastStatus = 0
        root.finishCommand(false, "Could not start curl.")
      }
    }
  }
}
