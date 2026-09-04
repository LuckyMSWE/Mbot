-- License gate. Talks to the mBot PHP server. Do not put this in updater.lua.
MbotLicense = MbotLicense or {}

local DEFAULT_URL = "http://127.0.0.1"
local HEARTBEAT_MS = 60000
local RETRY_MS = 30000

storage.mbotLicense = storage.mbotLicense or {}
local cfg = storage.mbotLicense
if type(cfg.url) ~= "string" or cfg.url == "" then
  cfg.url = DEFAULT_URL
end
if type(cfg.key) ~= "string" then
  cfg.key = ""
end
if type(cfg.uid) ~= "string" or not cfg.uid:match("^[A-Za-z0-9@._:-][A-Za-z0-9@._:-]+$") then
  local alphabet = "abcdefghijklmnopqrstuvwxyz0123456789"
  local uid = "mbot-"
  for _ = 1, 20 do
    local index = math.random(1, #alphabet)
    uid = uid .. alphabet:sub(index, index)
  end
  cfg.uid = uid
end

local session = {
  ok = false,
  token = nil,
  name = nil,
  expires = nil,
  busy = false,
  retry = false
}

local contents = modules.game_bot.contentsPanel
local botWindow = contents and contents:getParent() or nil
local ui

if contents then
  local children = contents.getChildren and contents:getChildren() or {}
  for _, child in ipairs(children) do
    child:setVisible(false)
  end
end
if botWindow and botWindow.setText then
  botWindow:setText("License Key")
end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizeUrl(url)
  url = trim(url)
  if url == "" then
    return DEFAULT_URL
  end
  if not url:match("^https?://") then
    url = "http://" .. url
  end
  return url:gsub("/+$", "")
end

local function botVersion()
  if MbotUpdater and MbotUpdater.localVersion then
    return MbotUpdater.localVersion()
  end
  return "4.33"
end

local function clientName()
  local ok, name = pcall(function()
    if player then
      return player:getName()
    end
    return nil
  end)
  if ok and type(name) == "string" and name:len() > 0 then
    return name:sub(1, 80)
  end
  return "OTClient"
end

local function setWindowTitle(text)
  if botWindow and botWindow.setText then
    botWindow:setText(text)
  end
end

local function setChromeVisible(visible)
  if not contents then
    return
  end
  local children = contents.getChildren and contents:getChildren() or {}
  for _, child in ipairs(children) do
    if child:getId() ~= "mbotLicenseBox" then
      child:setVisible(visible)
    end
  end
end

local function setGateVisible(showField, statusText, statusColor)
  setChromeVisible(false)
  setWindowTitle("License Key")
  if ui then
    ui:setVisible(true)
    if ui.key then
      ui.key:setVisible(showField)
    end
    if ui.activate then
      ui.activate:setVisible(showField)
    end
    if ui.status then
      ui.status:setText(statusText or "Enter your license key")
      ui.status:setColor(statusColor or "#dfdfdf")
    end
  end
end

local function revealBot()
  if ui then
    ui:hide()
  end
  setWindowTitle("Bot")
  if MbotLoadBot then
    MbotLoadBot()
  end
  setChromeVisible(true)
end

local function setStatus(text, color)
  if ui and ui.status and ui:isVisible() then
    ui.status:setText(text)
    ui.status:setColor(color or "#dfdfdf")
  end
end

function MbotLicense.ok()
  return session.ok == true
end

local function lockAutomation()
  if CaveBot and CaveBot.isOn and CaveBot.isOn() then
    CaveBot.setOff()
  end
  if TargetBot and TargetBot.isOn and TargetBot.isOn() then
    TargetBot.setOff()
  end
  if AttackBot and AttackBot.isOn and AttackBot.isOn() then
    AttackBot.setOff()
  end
end

local function parseApi(data, err)
  if type(data) == "table" then
    if data.ok == true and type(data.data) == "table" then
      return data.data
    end
    local message = data.error and data.error.message
    if type(message) == "string" and message:len() > 0 then
      return nil, message
    end
    return nil, "License request failed"
  end
  if type(err) == "string" and err:len() > 0 then
    return nil, err
  end
  return nil, "Cannot reach license server"
end

local function fail(message, canRetry)
  session.ok = false
  session.token = nil
  session.name = nil
  session.expires = nil
  session.busy = false
  session.retry = canRetry == true
  lockAutomation()
  setGateVisible(true, message or "Enter your license key", "#d9321f")
end

local function succeed(payload)
  session.ok = true
  session.token = payload.token
  session.name = payload.user and payload.user.name or nil
  session.expires = payload.license and payload.license.expires_at or nil
  session.busy = false
  session.retry = false
  cfg.key = trim(cfg.key)
  revealBot()
end

function MbotLicense.handshake()
  if session.busy then
    return
  end
  cfg.url = normalizeUrl(cfg.url)
  if ui and ui.key and ui.key:isVisible() then
    cfg.key = trim(ui.key:getText())
  else
    cfg.key = trim(cfg.key)
  end
  if cfg.key == "" then
    fail("Enter your license key")
    return
  end

  session.busy = true
  setGateVisible(false, "Checking license...", "#dfdfdf")
  local sent, sendErr = pcall(function()
    HTTP.postJSON(cfg.url .. "/api/v1/auth/handshake", {
      license_key = cfg.key,
      client_uid = cfg.uid,
      client_name = clientName(),
      version = botVersion()
    }, function(data, err)
      local payload, message = parseApi(data, err)
      if not payload or type(payload.token) ~= "string" then
        fail(message or "Invalid license", type(data) ~= "table")
        return
      end
      succeed(payload)
    end)
  end)
  if not sent then
    fail(tostring(sendErr), true)
  end
end

function MbotLicense.heartbeat()
  if not session.ok or type(session.token) ~= "string" then
    return
  end
  local sent, sendErr = pcall(function()
    HTTP.postJSON(cfg.url .. "/api/v1/auth/heartbeat", {
      token = session.token
    }, function(data, err)
      local payload, message = parseApi(data, err)
      if not payload then
        fail(message or "License session expired", type(data) ~= "table")
        return
      end
      if payload.expires_at then
        session.expires = payload.expires_at
      end
    end)
  end)
  if not sent then
    fail(tostring(sendErr), true)
  end
end

if contents then
  ui = contents:recursiveGetChildById("mbotLicenseBox")
  if not ui then
    ui = g_ui.loadUIFromString([[
Panel
  id: mbotLicenseBox
  anchors.top: parent.top
  anchors.left: parent.left
  anchors.right: parent.right
  margin-top: 10
  margin-left: 8
  margin-right: 8
  height: 92

  Label
    id: title
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    text-align: center
    text: License Key

  TextEdit
    id: key
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: prev.bottom
    margin-top: 6
    height: 20

  Button
    id: activate
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: prev.bottom
    margin-top: 6
    height: 20
    text: Activate

  Label
    id: status
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: prev.bottom
    margin-top: 6
    text-align: center
    text: Enter your license key
]], contents)
  end
end

if ui then
  ui.key:setText(cfg.key)
  ui.key.onTextChange = function(widget, text)
    cfg.key = text
  end
  ui.activate.onClick = function()
    MbotLicense.handshake()
  end
end

macro(1000, function()
  if not MbotLicense.ok() then
    lockAutomation()
  end
end)

macro(HEARTBEAT_MS, function()
  MbotLicense.heartbeat()
end)

macro(RETRY_MS, function()
  if session.retry and not session.ok and not session.busy and trim(cfg.key) ~= "" then
    MbotLicense.handshake()
  end
end)

if trim(cfg.key) ~= "" then
  setGateVisible(false, "Checking license...", "#dfdfdf")
  schedule(400, function()
    MbotLicense.handshake()
  end)
else
  setGateVisible(true, "Enter your license key", "#dfdfdf")
end
