const test = require("node:test")
const assert = require("node:assert")
const M = require("../Model.js")

test("parseJson returns the parsed value for valid JSON", () => {
  assert.deepStrictEqual(M.parseJson('{"a":1}'), { a: 1 })
})

test("parseJson returns null for malformed input", () => {
  assert.strictEqual(M.parseJson("{not json"), null)
  assert.strictEqual(M.parseJson(""), null)
  assert.strictEqual(M.parseJson(undefined), null)
})

test("splitStatusResponse separates body from the trailing status line", () => {
  assert.deepStrictEqual(M.splitStatusResponse('{"message":"API running."}\n200'),
    { status: 200, body: '{"message":"API running."}' })
})

test("splitStatusResponse handles an empty body", () => {
  assert.deepStrictEqual(M.splitStatusResponse("\n401"), { status: 401, body: "" })
})

test("splitStatusResponse handles a multi-line body", () => {
  assert.deepStrictEqual(M.splitStatusResponse("line1\nline2\n200"),
    { status: 200, body: "line1\nline2" })
})

test("splitStatusResponse reports status 0 when nothing came back", () => {
  assert.deepStrictEqual(M.splitStatusResponse(""), { status: 0, body: "" })
})

test("splitStatusResponse preserves entire body when trailing segment is not a status", () => {
  assert.deepStrictEqual(M.splitStatusResponse("line1\nline2"), { status: 0, body: "line1\nline2" })
})

test("splitStatusResponse preserves body with trailing newline before valid status", () => {
  assert.deepStrictEqual(M.splitStatusResponse("body\n\n200"), { status: 200, body: "body\n" })
})

test("describeFailure names an unreachable host for curl connection errors", () => {
  assert.strictEqual(M.describeFailure(7, 0), "Server not reachable at this address.")
  assert.strictEqual(M.describeFailure(6, 0), "Server not reachable at this address.")
  assert.strictEqual(M.describeFailure(28, 0), "Server not reachable at this address.")
})

test("describeFailure names an invalid token for 401 and 403", () => {
  assert.strictEqual(M.describeFailure(0, 401), "Token invalid or revoked.")
  assert.strictEqual(M.describeFailure(0, 403), "Token invalid or revoked.")
})

test("describeFailure reports other statuses with the code", () => {
  assert.strictEqual(M.describeFailure(0, 502), "Server answered with status 502.")
})

test("describeFailure returns an empty string on success", () => {
  assert.strictEqual(M.describeFailure(0, 200), "")
})

test("isHomeAssistant accepts only the Home Assistant API greeting", () => {
  assert.strictEqual(M.isHomeAssistant('{"message":"API running."}'), true)
  assert.strictEqual(M.isHomeAssistant('{"message":"something else"}'), false)
  assert.strictEqual(M.isHomeAssistant("<html>hello</html>"), false)
})

const dimmable = {
  entity_id: "light.xiaomi_monitor_licht_light_bar",
  state: "on",
  attributes: {
    friendly_name: "Monitor Bar",
    brightness: 128,
    supported_color_modes: ["brightness"]
  }
}

const plainLight = {
  entity_id: "light.hallway",
  state: "off",
  attributes: { friendly_name: "Hallway", supported_color_modes: ["onoff"] }
}

const temperature = {
  entity_id: "sensor.h5100_3f19_temperature",
  state: "29.14",
  attributes: {
    friendly_name: "H5100 3F19 Temperature",
    unit_of_measurement: "°C",
    device_class: "temperature"
  }
}

test("entityDomain extracts the domain", () => {
  assert.strictEqual(M.entityDomain("light.hallway"), "light")
  assert.strictEqual(M.entityDomain("nodots"), "")
})

test("isSupported accepts the six supported domains and rejects others", () => {
  assert.strictEqual(M.isSupported("light.hallway"), true)
  assert.strictEqual(M.isSupported("input_boolean.guest"), true)
  assert.strictEqual(M.isSupported("binary_sensor.door"), true)
  assert.strictEqual(M.isSupported("media_player.tv"), false)
  assert.strictEqual(M.isSupported("automation.wakeup"), false)
})

test("friendlyName falls back to the entity id", () => {
  assert.strictEqual(M.friendlyName(dimmable), "Monitor Bar")
  assert.strictEqual(M.friendlyName({ entity_id: "light.x", attributes: {} }), "light.x")
})

test("capabilityOf classifies by domain and attributes", () => {
  assert.strictEqual(M.capabilityOf(dimmable), "dimmable")
  assert.strictEqual(M.capabilityOf(plainLight), "switchable")
  assert.strictEqual(M.capabilityOf(temperature), "readonly")
  assert.strictEqual(M.capabilityOf({ entity_id: "switch.pump", state: "on", attributes: {} }), "switchable")
  assert.strictEqual(M.capabilityOf({ entity_id: "binary_sensor.door", state: "on", attributes: {} }), "readonly")
})

test("capabilityOf reports unavailable states before anything else", () => {
  assert.strictEqual(M.capabilityOf({ entity_id: "light.x", state: "unavailable", attributes: {} }), "unavailable")
  assert.strictEqual(M.capabilityOf({ entity_id: "light.x", state: "unknown", attributes: {} }), "unavailable")
  assert.strictEqual(M.capabilityOf(null), "unavailable")
})

test("isOn is true only for the on state", () => {
  assert.strictEqual(M.isOn(dimmable), true)
  assert.strictEqual(M.isOn(plainLight), false)
  assert.strictEqual(M.isOn(null), false)
})

test("formatValue appends the unit and rounds to one decimal", () => {
  assert.strictEqual(M.formatValue(temperature), "29.1 °C")
})

test("formatValue leaves non-numeric states alone", () => {
  assert.strictEqual(M.formatValue({ entity_id: "sensor.mode", state: "auto", attributes: {} }), "auto")
})

test("formatValue renders binary sensors as On and Off", () => {
  assert.strictEqual(M.formatValue({ entity_id: "binary_sensor.door", state: "on", attributes: {} }), "On")
  assert.strictEqual(M.formatValue({ entity_id: "binary_sensor.door", state: "off", attributes: {} }), "Off")
})

test("formatValue reports unavailable entities", () => {
  assert.strictEqual(M.formatValue({ entity_id: "sensor.x", state: "unavailable", attributes: {} }), "unavailable")
})

test("brightness converts between 0-255 and percent in both directions", () => {
  assert.strictEqual(M.brightnessToPercent(255), 100)
  assert.strictEqual(M.brightnessToPercent(128), 50)
  assert.strictEqual(M.brightnessToPercent(0), 0)
  assert.strictEqual(M.brightnessToPercent(undefined), 0)
  assert.strictEqual(M.percentToBrightness(100), 255)
  assert.strictEqual(M.percentToBrightness(0), 0)
  assert.strictEqual(M.percentToBrightness(150), 255)
  assert.strictEqual(M.percentToBrightness(-10), 0)
})

test("matchesSearch matches friendly name and entity id case-insensitively", () => {
  assert.strictEqual(M.matchesSearch(dimmable, "monitor"), true)
  assert.strictEqual(M.matchesSearch(dimmable, "XIAOMI"), true)
  assert.strictEqual(M.matchesSearch(dimmable, ""), true)
  assert.strictEqual(M.matchesSearch(dimmable, "kitchen"), false)
})

test("sortEntities orders by friendly name without mutating the input", () => {
  const input = [dimmable, plainLight]
  const sorted = M.sortEntities(input)
  assert.deepStrictEqual(sorted.map(e => e.entity_id), ["light.hallway", "light.xiaomi_monitor_licht_light_bar"])
  assert.strictEqual(input[0], dimmable)
})

test("statesToMap keys entities by id", () => {
  const map = M.statesToMap([dimmable, plainLight])
  assert.strictEqual(map["light.hallway"], plainLight)
})

test("statesToMap tolerates a non-array", () => {
  assert.deepStrictEqual(M.statesToMap(null), {})
})

test("capabilityOf handles light with missing supported_color_modes", () => {
  assert.strictEqual(M.capabilityOf({ entity_id: "light.x", state: "on", attributes: {} }), "switchable")
})

test("capabilityOf handles light with empty supported_color_modes array", () => {
  assert.strictEqual(M.capabilityOf({ entity_id: "light.x", state: "on", attributes: { supported_color_modes: [] } }), "switchable")
})

test("formatValue renders numeric state without unit as rounded string", () => {
  assert.strictEqual(M.formatValue({ entity_id: "sensor.x", state: "42", attributes: {} }), "42")
  assert.strictEqual(M.formatValue({ entity_id: "sensor.x", state: "3.14159", attributes: {} }), "3.1")
})

test("brightness round-trip invariant: percent to brightness and back", () => {
  var testPercents = [1, 33, 50, 99, 100]
  for (var i = 0; i < testPercents.length; i++) {
    var percent = testPercents[i]
    var brightness = M.percentToBrightness(percent)
    var roundTrip = M.brightnessToPercent(brightness)
    assert.strictEqual(roundTrip, percent, "Round-trip failed for " + percent + "%")
  }
})

test("percentToBrightness handles undefined and null", () => {
  assert.strictEqual(M.percentToBrightness(undefined), 0)
  assert.strictEqual(M.percentToBrightness(null), 0)
})

test("describeFailure names an oversized answer for curl exit 63", () => {
  assert.strictEqual(M.describeFailure(63, 0), "Server answer too large to process.")
})

test("plainText neutralizes angle brackets so names cannot render as HTML", () => {
  assert.strictEqual(M.plainText('<img src="https://evil.example/x">'), '‹img src="https://evil.example/x"›')
  assert.strictEqual(M.plainText("<b>bold</b>"), "‹b›bold‹/b›")
  assert.strictEqual(M.plainText("Monitor Bar"), "Monitor Bar")
  assert.strictEqual(M.plainText(null), "")
  assert.strictEqual(M.plainText(undefined), "")
})
