import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Item {
  id: root

  property var entity: null
  // Stable id of the settings entry this row renders. Needed because a row
  // for an entity the server no longer reports has `entity === null` and
  // would otherwise have no id at all.
  property string entryId: ""
  property string label: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property QtObject bar: null
  // Offer a Remove button for entities the server no longer reports
  // (deleted server-side): the picker cannot list them, so without this the
  // dead row could never be removed.
  property bool removable: false

  // Optimistic overrides. Cleared when the server confirms the requested
  // state (onServerOnChanged / onServerPercentChanged below), reverted at
  // once when the command fails (fail()), and force-cleared by pendingGuard
  // if neither happens — a command can succeed over HTTP while the device
  // never applies it, and the row must not show a phantom state forever.
  property int pendingOn: -1          // -1 none, 0 off, 1 on
  property int pendingPercent: -1
  property real pendingTemp: NaN      // NaN = no pending target temperature

  // Inline failure from the most recent command, shown under the row and
  // cleared as soon as the user issues another command.
  property string commandError: ""

  signal toggleRequested(string entityId, bool on)
  signal brightnessRequested(string entityId, int percent)
  signal temperatureRequested(string entityId, real temp)
  signal removeRequested(string entityId)

  readonly property string entityId: entity ? String(entity.entity_id) : entryId
  readonly property string capability: Model.capabilityOf(entity)
  readonly property bool missing: entity === null
  readonly property string displayName: label !== "" ? label : (entity ? Model.friendlyName(entity) : entityId)
  readonly property bool serverOn: Model.isOn(entity)
  readonly property int serverPercent: Model.brightnessToPercent(entity && entity.attributes ? entity.attributes.brightness : 0)
  readonly property bool serverClimateOn: Model.climateIsOn(entity)
  readonly property real serverTemp: Model.climateTargetTemp(entity)
  readonly property real serverClimateMin: Model.climateMinTemp(entity)
  readonly property real serverClimateMax: Model.climateMaxTemp(entity)
  readonly property bool on: root.capability === "climate"
    ? (root.pendingOn >= 0 ? root.pendingOn === 1 : root.serverClimateOn)
    : (root.pendingOn >= 0 ? root.pendingOn === 1 : root.serverOn)
  readonly property int percent: pendingPercent >= 0 ? pendingPercent : serverPercent
  // Fall back to the mid-point of the supported range when no target is known,
  // so the slider always has a sane starting position.
  readonly property real temp: !isNaN(root.pendingTemp) ? root.pendingTemp
    : (isNaN(root.serverTemp) ? (root.serverClimateMin + root.serverClimateMax) / 2 : root.serverTemp)

  // The optimistic value stands until the server confirms it: settling on
  // command completion instead would snap the row back to the old state and
  // make every toggle flicker.
  onServerOnChanged: if (root.pendingOn >= 0 && root.serverOn === (root.pendingOn === 1)) root.pendingOn = -1
  onServerClimateOnChanged: if (root.pendingOn >= 0 && root.serverClimateOn === (root.pendingOn === 1)) root.pendingOn = -1
  onServerPercentChanged: if (root.pendingPercent >= 0 && root.serverPercent === root.pendingPercent) root.pendingPercent = -1
  onServerTempChanged: if (!isNaN(root.pendingTemp) && Math.abs(root.serverTemp - root.pendingTemp) < 0.05) root.pendingTemp = NaN

  function settle() {
    pendingOn = -1
    pendingPercent = -1
    pendingTemp = NaN
    pendingGuard.stop()
  }

  function fail(message) {
    settle()
    commandError = message
  }

  implicitHeight: column.implicitHeight
  implicitWidth: column.implicitWidth

  Timer {
    id: pendingGuard
    interval: 8000
    repeat: false
    onTriggered: root.settle()
  }

  Timer {
    id: brightnessDebounce
    interval: 200
    repeat: false
    onTriggered: if (root.pendingPercent >= 0) root.brightnessRequested(root.entityId, root.pendingPercent)
  }

  Timer {
    id: tempDebounce
    interval: 300
    repeat: false
    onTriggered: if (!isNaN(root.pendingTemp)) root.temperatureRequested(root.entityId, root.pendingTemp)
  }

  Column {
    id: column
    width: parent.width
    spacing: Style.space(2)

    Item {
      width: parent.width
      implicitHeight: Math.max(name.implicitHeight, control.implicitHeight)

      Text {
        id: name
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - control.width - Style.space(8)
        elide: Text.ElideRight
        text: root.displayName
        // The name comes from the server: never let it render as HTML.
        textFormat: Text.PlainText
        color: root.capability === "unavailable" ? Qt.darker(root.foreground, 1.6) : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      Item {
        id: control
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        Row {
          id: row
          spacing: Style.space(6)

          Text {
            id: readout
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.missing && (root.capability === "readonly" || root.capability === "unavailable")
            text: Model.formatValue(root.entity)
            textFormat: Text.PlainText
            color: root.capability === "unavailable" ? Qt.darker(root.foreground, 1.6) : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            id: currentTemp
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.missing && root.capability === "climate"
            text: isNaN(Model.climateCurrentTemp(root.entity)) ? "—" : (Model.climateCurrentTemp(root.entity) + "°")
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          ToggleSwitch {
            id: toggle
            anchors.verticalCenter: parent.verticalCenter
            visible: !root.missing && (root.capability === "switchable" || root.capability === "dimmable" || root.capability === "climate")
            checked: root.on
            foreground: root.foreground
            onToggled: {
              // Capture the target BEFORE touching pendingOn: `root.on` is a
              // live binding on the optimistic state, so reading it after the
              // assignment would already yield the new value and send the
              // inverted command (turn_off when switching on).
              var targetOn = !root.on
              root.pendingOn = targetOn ? 1 : 0
              root.commandError = ""
              pendingGuard.restart()
              root.toggleRequested(root.entityId, targetOn)
            }
          }

          Button {
            id: remove
            anchors.verticalCenter: parent.verticalCenter
            visible: root.missing && root.removable
            text: "Remove"
            foreground: root.foreground
            onClicked: root.removeRequested(root.entityId)
          }
        }
      }
    }

    Text {
      width: parent.width
      visible: root.commandError !== ""
      text: root.commandError
      textFormat: Text.PlainText
      color: Color.urgent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    PanelSlider {
      width: parent.width
      visible: root.capability === "dimmable" && root.on
      bar: root.bar
      minimum: 1
      maximum: 100
      step: 1
      integer: true
      value: root.percent
      onMoved: function (v) { root.pendingPercent = Math.round(v) }
      onReleased: function (v) {
        root.pendingPercent = Math.round(v)
        root.commandError = ""
        pendingGuard.restart()
        // PanelSlider emits `released` for every wheel tick as well as for a
        // drag release — debounce so a wheel burst sends one brightness call
        // instead of one call per tick.
        brightnessDebounce.restart()
      }
    }

    Text {
      width: parent.width
      visible: root.capability === "climate"
      text: "Target " + (isNaN(root.temp) ? "—" : (root.temp.toFixed(1) + "°"))
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    PanelSlider {
      width: parent.width
      // Shown whenever the entity is a climate device, including while it is
      // off, so the setpoint can still be inspected and adjusted.
      visible: root.capability === "climate"
      bar: root.bar
      minimum: root.serverClimateMin
      maximum: root.serverClimateMax
      step: 0.5
      integer: false
      value: root.temp
      onMoved: function (v) { var s = Math.round(v * 2) / 2; root.pendingTemp = s }
      onReleased: function (v) {
        var s = Math.round(v * 2) / 2
        root.pendingTemp = s
        root.commandError = ""
        pendingGuard.restart()
        // Same wheel-burst debounce as the brightness slider above.
        tempDebounce.restart()
      }
    }
  }
}
