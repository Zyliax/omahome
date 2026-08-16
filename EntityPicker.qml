import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

Column {
  id: root

  property var service: null
  property var selected: []
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property string query: ""
  property var working: []

  signal saved(var list)
  signal cancelled()

  spacing: Style.space(6)

  function load() {
    root.working = (root.selected || []).slice()
    if (root.service) root.service.fetchStates()
  }

  function isSelected(entityId) {
    for (var i = 0; i < root.working.length; i++) if (root.working[i].id === entityId) return true
    return false
  }

  function toggleEntity(entityId) {
    var next = []
    var found = false
    for (var i = 0; i < root.working.length; i++) {
      if (root.working[i].id === entityId) found = true
      else next.push(root.working[i])
    }
    if (!found) next.push({ id: entityId, label: "" })
    root.working = next
  }

  readonly property var candidates: {
    var out = []
    var states = root.service ? root.service.states : {}
    for (var id in states) {
      if (!Model.isSupported(id)) continue
      if (!Model.matchesSearch(states[id], root.query)) continue
      out.push(states[id])
    }
    return Model.sortEntities(out)
  }

  Text {
    width: parent.width
    text: "Add devices"
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.subtitle
    font.bold: true
  }

  TextField {
    id: search
    width: parent.width
    foreground: root.foreground
    placeholderText: "Search name or entity id"
    onTextChanged: root.query = text
  }

  Text {
    width: parent.width
    visible: root.candidates.length === 0
    text: root.service && root.service.stale ? root.service.lastError : "No matching devices."
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  // Capped so a server with hundreds of entities cannot grow the panel past
  // the screen; the search field is how you reach the rest.
  ListView {
    width: parent.width
    height: Math.min(contentHeight, Style.space(260))
    clip: true
    model: root.candidates
    spacing: Style.space(2)

    delegate: Toggle {
      required property var modelData
      width: ListView.view.width
      foreground: root.foreground
      fontFamily: root.fontFamily
      // Toggle renders with Text.AutoText and offers no textFormat override,
      // so a server-supplied name would be parsed as HTML (img tags included)
      // — neutralize the angle brackets.
      label: Model.plainText(Model.friendlyName(modelData))
      // Toggle's description Text wraps but does not elide, and an entity id
      // has no whitespace for WordWrap to break on — it would overflow the
      // card. Insert zero-width spaces after "." and "_" so long ids wrap.
      description: String(modelData.entity_id).replace(/[._]/g, "$&​")
      checked: root.isSelected(modelData.entity_id)
      onClicked: root.toggleEntity(modelData.entity_id)
    }
  }

  Row {
    spacing: Style.space(6)

    Button {
      text: "Save"
      foreground: root.foreground
      bordered: true
      onClicked: root.saved(root.working)
    }

    Button {
      text: "Cancel"
      foreground: root.foreground
      onClicked: root.cancelled()
    }
  }
}
