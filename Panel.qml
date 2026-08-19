import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "io.github.zyliax.omahome"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string view: "setup"

  // `root.settings.entities`, when it arrives freshly loaded from
  // shell.json on disk rather than assigned in-session, is a QVariantList
  // marshaled into this engine's JS context: it behaves like an array
  // (numeric indices, .length, JSON.stringify) but fails Array.isArray, so
  // that check alone silently drops a saved selection on every restart.
  // Duck-type on `.length` instead so both the in-session (real JS Array,
  // from EntityPicker's push()) and reload-from-disk cases are recognized.
  // `typeof === "object"` excludes strings, which also have a numeric
  // `.length` and would otherwise pass through and get iterated character
  // by character by DashboardView.partition().
  readonly property var entities: (root.settings.entities
      && typeof root.settings.entities === "object"
      && typeof root.settings.entities.length === "number")
    ? root.settings.entities : []
  readonly property bool connected: service.connected
  readonly property bool configured: service.configured

  readonly property string statusText: {
    if (!service.configured) return "Home Assistant — not connected"
    if (service.lastError !== "") return "Home Assistant — " + service.lastError
    return "Home Assistant"
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  // Mirrors the first-party clock panel: apply locally so the UI redraws on
  // the click, then let the same value come back through shell.json.
  function persistSettings(values) {
    var entry = { id: root.moduleName }
    for (var existing in root.settings) if (existing !== "id") entry[existing] = root.settings[existing]
    for (var key in values) entry[key] = values[key]

    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function saveEntities(list) { persistSettings({ entities: list }) }

  function removeEntity(entityId) {
    var next = []
    for (var i = 0; i < root.entities.length; i++)
      if (root.entities[i].id !== entityId) next.push(root.entities[i])
    saveEntities(next)
  }

  // Per the spec: disconnecting deletes the header file and clears baseUrl,
  // but keeps the entity selection, so reconnecting to the same server
  // restores the dashboard as it was.
  function disconnect() {
    service.deleteCredential()
    root.persistSettings({ baseUrl: "" })
    root.showView("setup")
  }

  function showView(name) { root.view = name }

  function resolveView() {
    root.view = service.configured ? (root.entities.length === 0 ? "picker" : "dashboard") : "setup"
  }

  HomeAssistant {
    id: service
    baseUrl: root.settings.baseUrl !== undefined ? root.settings.baseUrl : ""
    onCredentialChecked: root.resolveView()
  }

  Component.onCompleted: service.checkCredential()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        SetupView {
          width: parent.width
          visible: root.view === "setup"
          service: service
          foreground: root.barForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onConnected: {
            root.persistSettings({ baseUrl: service.baseUrl })
            root.showView(root.entities.length === 0 ? "picker" : "dashboard")
          }
          onCancelled: root.showView("dashboard")
          onDisconnectRequested: root.disconnect()
        }

        EntityPicker {
          id: picker
          width: parent.width
          visible: root.view === "picker"
          service: service
          selected: root.entities
          foreground: root.barForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onSaved: function (list) {
            root.saveEntities(list)
            root.showView("dashboard")
          }
          onCancelled: root.showView(root.entities.length === 0 ? "setup" : "dashboard")
          onVisibleChanged: if (visible) load()
        }

        DashboardView {
          width: parent.width
          visible: root.view === "dashboard"
          service: service
          bar: root.bar
          entities: root.entities
          foreground: root.barForeground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          onAddRequested: root.showView("picker")
          onSettingsRequested: root.showView("setup")
          onRemoveRequested: function (entityId) { root.removeEntity(entityId) }
        }
      }
    }
  }

  Timer {
    id: settleTimer
    interval: 400
    repeat: false
    onTriggered: service.fetchStates()
  }

  Connections {
    target: service
    function onCommandFinished(entityId, ok, error) { settleTimer.restart() }
  }

  // 5 s while the panel is open, 60 s when closed. A closed panel only needs
  // enough contact with the server to keep the bar icon honest.
  Timer {
    id: pollTimer
    interval: root.opened ? 5000 : 60000
    repeat: true
    running: service.configured
    triggeredOnStart: true
    onTriggered: service.fetchStates()
  }

  // A 401 on the most recent request means the stored token is no longer
  // accepted by the server (revoked, expired, or rotated). The credential
  // file itself is left alone here — only saving a fresh token through
  // SetupView replaces it, per the deliberate design in HomeAssistant.qml.
  //
  // A single 401 is not trusted on its own: a Home Assistant restart or a
  // proxy hiccup can surface one transiently while the token is still
  // perfectly valid, and evicting the user from their dashboard over that
  // is a trap they can only escape by re-entering a token. Require two
  // consecutive states-fetches to report 401 before switching the view.
  // Any other outcome — a successful fetch, or a failure that is not a
  // 401 — breaks the streak and resets the count.
  property int consecutive401Count: 0

  Connections {
    target: service
    function onStatesUpdated() {
      if (service.lastStatus === 401) {
        root.consecutive401Count += 1
        if (root.consecutive401Count >= 2) root.showView("setup")
      } else {
        root.consecutive401Count = 0
      }
    }
  }
}
