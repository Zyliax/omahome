import QtQuick
import qs.Commons
import qs.Ui

Column {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property bool testing: false
  property string error: ""

  signal connected()
  signal cancelled()
  signal disconnectRequested()

  spacing: Style.space(8)

  function submit() {
    if (!service || urlField.text.trim() === "" || tokenField.text === "") return
    root.error = ""
    root.testing = true
    service.probe(urlField.text.trim(), tokenField.text)
  }

  Connections {
    target: root.service
    function onProbeFinished(ok, error) {
      root.testing = false
      root.error = error
      if (ok) {
        tokenField.text = ""
        root.connected()
      }
    }
  }

  Text {
    width: parent.width
    text: "Connect to Home Assistant"
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  TextField {
    id: urlField
    width: parent.width
    foreground: root.foreground
    placeholderText: "http://homeassistant.local:8123"
    text: root.service && root.service.baseUrl !== "" ? root.service.baseUrl : ""
    onAccepted: root.submit()
  }

  TextField {
    id: tokenField
    width: parent.width
    foreground: root.foreground
    password: true
    placeholderText: "Long-lived access token"
    onAccepted: root.submit()
  }

  Text {
    width: parent.width
    text: "In Home Assistant: profile → security → long-lived access tokens → create token."
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Text {
    width: parent.width
    visible: root.error !== ""
    text: root.error
    color: Color.urgent
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Row {
    spacing: Style.space(6)

    Button {
      text: root.testing ? "Connecting…" : "Connect"
      enabled: !root.testing
      foreground: root.foreground
      bordered: true
      onClicked: root.submit()
    }

    // Only offered when there is somewhere to go back to: a first-time setup
    // (no stored credential/baseUrl yet) has no dashboard behind it.
    Button {
      text: "Cancel"
      visible: root.service ? root.service.configured : false
      foreground: root.foreground
      onClicked: root.cancelled()
    }

    // Disconnect keeps the entity selection and only drops the credential
    // and the server address, so reconnecting to the same server restores
    // the dashboard as it was.
    Button {
      text: "Disconnect"
      visible: root.service ? root.service.configured : false
      foreground: root.foreground
      onClicked: root.disconnectRequested()
    }
  }
}
