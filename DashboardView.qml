import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property var service: null
  property var entities: []
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property QtObject bar: null

  signal addRequested()
  signal settingsRequested()
  signal removeRequested(string entityId)

  spacing: Style.space(6)

  // Mirrors EntityPicker's `onVisibleChanged: if (visible) load()`: nothing
  // else fetches states for a session that lands on the dashboard directly
  // (already configured, entities already saved from a prior visit), so
  // without this the sensors/controls sections render with stale-empty
  // rows until the first command's settle-timer refresh happens to fire.
  // Component.onCompleted covers the case where this view is already the
  // visible one at construction time, since a property's initial value
  // does not raise its own changed signal.
  function refresh() { if (root.service) root.service.fetchStates() }
  Component.onCompleted: if (root.visible) refresh()
  onVisibleChanged: if (root.visible) refresh()

  function stateFor(entityId) {
    var states = root.service ? root.service.states : {}
    return states[entityId] !== undefined ? states[entityId] : null
  }

  function partition(readonlyWanted) {
    var out = []
    for (var i = 0; i < root.entities.length; i++) {
      var entry = root.entities[i]
      var state = root.stateFor(entry.id)
      var capability = Model.capabilityOf(state)
      var isReadonly = capability === "readonly" ||
        (state === null && Model.READONLY_DOMAINS.indexOf(Model.entityDomain(entry.id)) >= 0)
      if (isReadonly === readonlyWanted) out.push(entry)
    }
    return out
  }

  readonly property var sensorEntries: partition(true)
  readonly property var controlEntries: partition(false)

  function applyToggle(entityId, on) {
    var domain = Model.entityDomain(entityId)
    root.service.callService(domain, on ? "turn_on" : "turn_off", { entity_id: entityId })
  }

  function applyBrightness(entityId, percent) {
    root.service.callService("light", "turn_on", { entity_id: entityId, brightness_pct: percent })
  }

  function rowFor(entityId) {
    for (var i = 0; i < sensorRepeater.count; i++) {
      var item = sensorRepeater.itemAt(i)
      if (item && item.entityId === entityId) return item
    }
    for (var j = 0; j < controlRepeater.count; j++) {
      var control = controlRepeater.itemAt(j)
      if (control && control.entityId === entityId) return control
    }
    return null
  }

  Connections {
    target: root.service
    // Revert the optimistic change only when the command failed, and show
    // the failure inline on the row. On success the pending value stands
    // until the next states fetch confirms it — settling here would snap
    // the row back to the old server state and make every toggle flicker.
    function onCommandFinished(entityId, ok, error) {
      if (ok) return
      var row = root.rowFor(entityId)
      if (row) row.fail(error)
    }
  }

  Text {
    width: parent.width
    visible: root.entities.length === 0
    text: "No devices yet. Choose what to show with “Add devices”."
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Row {
    width: parent.width
    visible: root.service && root.service.stale
    spacing: Style.space(6)

    Text {
      width: parent.width - retry.width - Style.space(6)
      text: root.service ? root.service.lastError : ""
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Button {
      id: retry
      text: "Retry"
      foreground: root.foreground
      onClicked: if (root.service) root.service.fetchStates()
    }
  }

  PanelSectionHeader {
    width: parent.width
    visible: root.sensorEntries.length > 0
    text: "Sensors"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Repeater {
    id: sensorRepeater
    model: root.sensorEntries
    delegate: EntityRow {
      required property var modelData
      width: root.width
      bar: root.bar
      foreground: root.foreground
      fontFamily: root.fontFamily
      entryId: String(modelData.id)
      removable: true
      label: modelData.label !== undefined ? modelData.label : ""
      entity: root.stateFor(modelData.id)
      onRemoveRequested: function (entityId) { root.removeRequested(entityId) }
    }
  }

  PanelSectionHeader {
    width: parent.width
    visible: root.controlEntries.length > 0
    text: "Controls"
    foreground: root.foreground
    fontFamily: root.fontFamily
  }

  Repeater {
    id: controlRepeater
    model: root.controlEntries
    delegate: EntityRow {
      required property var modelData
      width: root.width
      bar: root.bar
      foreground: root.foreground
      fontFamily: root.fontFamily
      entryId: String(modelData.id)
      removable: true
      label: modelData.label !== undefined ? modelData.label : ""
      entity: root.stateFor(modelData.id)
      onToggleRequested: function (entityId, on) { root.applyToggle(entityId, on) }
      onBrightnessRequested: function (entityId, percent) { root.applyBrightness(entityId, percent) }
      onRemoveRequested: function (entityId) { root.removeRequested(entityId) }
    }
  }

  PanelSeparator {
    width: parent.width
    foreground: root.foreground
  }

  Row {
    spacing: Style.space(6)

    Button {
      text: "Add devices"
      foreground: root.foreground
      onClicked: root.addRequested()
    }

    Button {
      iconText: ""
      tooltipText: "Connection settings"
      foreground: root.foreground
      onClicked: root.settingsRequested()
    }
  }
}
