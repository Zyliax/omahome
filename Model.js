// Pure helpers shared by the QML views and the service. No Qt imports, so
// this file also loads under `node --test`.

function parseJson(text) {
  if (typeof text !== "string" || text.trim() === "") return null
  try {
    return JSON.parse(text)
  } catch (e) {
    return null
  }
}

// Requests run with `-w '\n%{http_code}'`, so the HTTP status is the last
// line of the output and everything before it is the body.
function splitStatusResponse(raw) {
  var text = typeof raw === "string" ? raw : ""
  if (text === "") return { status: 0, body: "" }
  var cut = text.lastIndexOf("\n")
  if (cut < 0) return { status: 0, body: text }
  var status = parseInt(text.slice(cut + 1), 10)
  if (isNaN(status)) {
    return { status: 0, body: text }
  }
  return { status: status, body: text.slice(0, cut) }
}

function describeFailure(exitCode, status) {
  // curl exit 63: --max-filesize exceeded (see curlArgs in HomeAssistant.qml).
  if (exitCode === 63) return "Server answer too large to process."
  if (exitCode !== 0) return "Server not reachable at this address."
  if (status === 401 || status === 403) return "Token invalid or revoked."
  if (status === 404) return "Reachable, but no Home Assistant API at this address."
  if (status >= 200 && status < 300) return ""
  if (status === 0) return "Server not reachable at this address."
  return "Server answered with status " + status + "."
}

function isHomeAssistant(body) {
  var parsed = parseJson(body)
  return !!parsed && parsed.message === "API running."
}

var SUPPORTED_DOMAINS = ["light", "switch", "sensor", "binary_sensor", "fan", "input_boolean"]
var READONLY_DOMAINS = ["sensor", "binary_sensor"]
var DEAD_STATES = ["unavailable", "unknown", ""]

function entityDomain(entityId) {
  var id = String(entityId || "")
  var dot = id.indexOf(".")
  return dot < 0 ? "" : id.slice(0, dot)
}

function isSupported(entityId) {
  return SUPPORTED_DOMAINS.indexOf(entityDomain(entityId)) >= 0
}

function attrs(entity) {
  return (entity && entity.attributes) || {}
}

function friendlyName(entity) {
  if (!entity) return ""
  var name = attrs(entity).friendly_name
  return name ? String(name) : String(entity.entity_id || "")
}

function capabilityOf(entity) {
  if (!entity) return "unavailable"
  if (DEAD_STATES.indexOf(String(entity.state || "")) >= 0) return "unavailable"
  var domain = entityDomain(entity.entity_id)
  if (READONLY_DOMAINS.indexOf(domain) >= 0) return "readonly"
  var modes = attrs(entity).supported_color_modes || []
  if (domain === "light" && modes.indexOf("onoff") < 0 && modes.length > 0) return "dimmable"
  return "switchable"
}

function isOn(entity) {
  return !!entity && String(entity.state) === "on"
}

function formatValue(entity) {
  if (!entity) return ""
  var state = String(entity.state || "")
  if (DEAD_STATES.indexOf(state) >= 0) return "unavailable"
  if (entityDomain(entity.entity_id) === "binary_sensor") return state === "on" ? "On" : "Off"
  var unit = attrs(entity).unit_of_measurement
  var num = Number(state)
  if (state !== "" && !isNaN(num)) {
    var rounded = Math.round(num * 10) / 10
    return unit ? rounded + " " + unit : String(rounded)
  }
  return unit ? state + " " + unit : state
}

function clamp(value, low, high) {
  return Math.max(low, Math.min(high, value))
}

function brightnessToPercent(brightness) {
  var raw = Number(brightness)
  if (isNaN(raw)) return 0
  return Math.round(clamp(raw, 0, 255) / 255 * 100)
}

function percentToBrightness(percent) {
  var raw = Number(percent)
  if (isNaN(raw)) return 0
  return Math.round(clamp(raw, 0, 100) / 100 * 255)
}

// Replaces angle brackets so a server-supplied string cannot be parsed as
// rich text by controls that render with Text.AutoText and offer no
// textFormat override (qs.Ui Toggle in the picker). Names that genuinely
// contain "<" or ">" show the single-guillemet lookalikes instead.
function plainText(text) {
  return String(text === undefined || text === null ? "" : text)
    .replace(/</g, "‹")
    .replace(/>/g, "›")
}

function matchesSearch(entity, query) {
  var needle = String(query || "").trim().toLowerCase()
  if (needle === "") return true
  var haystack = (friendlyName(entity) + " " + String((entity && entity.entity_id) || "")).toLowerCase()
  return haystack.indexOf(needle) >= 0
}

function sortEntities(list) {
  return (list || []).slice().sort(function (a, b) {
    return friendlyName(a).toLowerCase().localeCompare(friendlyName(b).toLowerCase())
  })
}

function statesToMap(list) {
  var map = {}
  if (!Array.isArray(list)) return map
  for (var i = 0; i < list.length; i++) {
    if (list[i] && list[i].entity_id) map[list[i].entity_id] = list[i]
  }
  return map
}

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    parseJson, splitStatusResponse, describeFailure, isHomeAssistant,
    SUPPORTED_DOMAINS, entityDomain, isSupported, friendlyName, capabilityOf,
    isOn, formatValue, brightnessToPercent, percentToBrightness,
    plainText, matchesSearch, sortEntities, statesToMap
  }
}
