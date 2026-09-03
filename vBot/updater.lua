-- Frozen update engine. Load before main.lua. Change only when the updater itself is broken.
MbotUpdater = MbotUpdater or {}

local VERSION = "4.22"
local REPO = "LuckyMSWE/Mbot"
local BRANCH = "main"
local RAW_BASE = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/"
local API_COMPARE = "https://api.github.com/repos/" .. REPO .. "/compare/"
local CHECK_INTERVAL = 60
local CHECK_RETRIES = 3
local RETRY_DELAY = 1000
local STARTUP_RETRY_MS = 2000

local ALLOWED_EXT = {
  lua = true,
  otui = true,
  ui = true,
  txt = true,
  json = true
}

local SKIP_PREFIXES = {
  "cavebot_configs/",
  "targetbot_configs/",
  "vBot_configs/",
  "storage/",
  ".git/"
}

local CORE_FILES = {
  "vBot/updater.lua",
  "_Loader.lua",
  "vBot/main.lua",
  "vBot/version.txt"
}

storage.mbotUpdater = storage.mbotUpdater or {}
local updaterState = storage.mbotUpdater
updaterState.lastCheck = updaterState.lastCheck or 0

local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
local botRoot = "/bot/" .. configName
local busy = false
local checking = false
local remoteVersion = nil
local remoteSha = nil
local updateAvailable = false
local autoRecover = false
local firstSuccess = false
local started = false
local loopToken = 0
local fileQueue = {}
local listeners = {}

local function playerOnline()
  local ok, online = pcall(function()
    return g_game.isOnline()
  end)
  if ok and online then
    return true
  end
  if player then
    return true
  end
  return false
end

local function normalizeVersion(value)
  if not value then
    return ""
  end
  return tostring(value):gsub("%s+", "")
end

local function isRemoteNewer(remote, installed)
  local function parts(value)
    local parsed = {}
    for number in tostring(value):gmatch("%d+") do
      table.insert(parsed, tonumber(number))
    end
    return parsed
  end

  local remoteParts = parts(remote)
  local localParts = parts(installed)
  local count = math.max(#remoteParts, #localParts)
  for i = 1, count do
    local remoteValue = remoteParts[i] or 0
    local localValue = localParts[i] or 0
    if remoteValue > localValue then
      return true
    end
    if remoteValue < localValue then
      return false
    end
  end
  return false
end

local function localVersion()
  local path = botRoot .. "/vBot/version.txt"
  if g_resources.fileExists(path) then
    local ok, contents = pcall(function()
      return g_resources.readFileContents(path)
    end)
    if ok and contents then
      local parsed = normalizeVersion(contents)
      if parsed:len() > 0 then
        return parsed
      end
    end
  end
  return VERSION
end

local function extensionOf(path)
  local ext = path:match("%.([%w]+)$")
  if not ext then
    return ""
  end
  return ext:lower()
end

local function startsWith(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function isAllowedPath(path)
  if type(path) ~= "string" or path:len() == 0 then
    return false
  end
  path = path:gsub("\\", "/")
  if path:sub(1, 1) == "/" then
    return false
  end
  if path:find("..", 1, true) then
    return false
  end
  for _, prefix in ipairs(SKIP_PREFIXES) do
    if startsWith(path, prefix) then
      return false
    end
  end
  if path == "_Loader.lua" then
    return true
  end
  if not (startsWith(path, "vBot/") or startsWith(path, "cavebot/") or startsWith(path, "targetbot/")) then
    return false
  end
  return ALLOWED_EXT[extensionOf(path)] == true
end

local function rawUrl(path)
  return RAW_BASE .. path .. "?t=" .. os.time()
end

local function looksLikeHtmlError(data)
  if type(data) ~= "string" or data:len() == 0 then
    return true
  end
  local head = data:sub(1, 200):lower()
  return head:find("<!doctype", 1, true) or head:find("<html", 1, true)
end

local function parseRemoteVersion(data)
  local version = normalizeVersion(data)
  if version:match("^%d+%.%d+") then
    return version
  end
  return nil
end

local function httpGet(url, triesLeft, callback)
  HTTP.get(url, function(data, err)
    if (err or looksLikeHtmlError(data)) and triesLeft > 1 then
      schedule(RETRY_DELAY, function()
        httpGet(url, triesLeft - 1, callback)
      end)
      return
    end
    if err or looksLikeHtmlError(data) then
      callback(nil, tostring(err or "empty response"))
      return
    end
    callback(data)
  end)
end

local function decodeJson(data)
  if type(data) ~= "string" or data:len() == 0 then
    return nil
  end
  local ok, parsed = pcall(function()
    return json.decode(data)
  end)
  if ok and type(parsed) == "table" then
    return parsed
  end
  return nil
end

local function emitStatus(text, color, clearAfter)
  if listeners.onStatus then
    listeners.onStatus(text, color, clearAfter)
  end
end

local function emitState()
  if listeners.onState then
    listeners.onState({
      available = updateAvailable,
      busy = busy,
      remoteVersion = remoteVersion
    })
  end
end

local function setBusy(state)
  busy = state
  emitState()
end

local function ensureDir(absDir)
  if not absDir or absDir:len() == 0 or g_resources.directoryExists(absDir) then
    return g_resources.directoryExists(absDir)
  end
  local current = ""
  for _, part in ipairs(absDir:split("/")) do
    if part and part:len() > 0 then
      current = current .. "/" .. part
      if not g_resources.directoryExists(current) then
        g_resources.makeDir(current)
      end
    end
  end
  return g_resources.directoryExists(absDir)
end

local function writeBotFile(relativePath, contents)
  if not isAllowedPath(relativePath) then
    return false, "blocked path"
  end
  local dest = botRoot .. "/" .. relativePath
  local dir = dest:match("(.+)/[^/]+$")
  if dir and not ensureDir(dir) then
    return false, "could not create " .. dir
  end
  local ok, err = pcall(function()
    g_resources.writeFileContents(dest, contents)
  end)
  if not ok then
    return false, err
  end
  return true
end

local function addUnique(files, path)
  if not isAllowedPath(path) then
    return
  end
  for _, existing in ipairs(files) do
    if existing == path then
      return
    end
  end
  table.insert(files, path)
end

local function addCoreFiles(files)
  for _, path in ipairs(CORE_FILES) do
    addUnique(files, path)
  end
end

local function addPathList(files, list)
  if type(list) ~= "table" then
    return
  end
  for _, path in ipairs(list) do
    if type(path) == "string" then
      addUnique(files, path)
    end
  end
end

local function collectChangedFiles(data)
  local parsed = decodeJson(data)
  if not parsed or type(parsed.files) ~= "table" then
    return nil
  end
  local files = {}
  for _, entry in ipairs(parsed.files) do
    if entry.status ~= "removed" and type(entry.filename) == "string" then
      addUnique(files, entry.filename)
    end
  end
  addCoreFiles(files)
  if #files == 0 then
    return nil
  end
  return files
end

local function collectFilesFromManifest(data)
  local parsed = decodeJson(data)
  if not parsed then
    return nil
  end
  local files = {}
  addPathList(files, parsed.changed or parsed.files)
  if type(parsed.releases) == "table" then
    local installed = localVersion()
    for _, release in ipairs(parsed.releases) do
      if type(release) == "table" and isRemoteNewer(release.version, installed) then
        addPathList(files, release.files or release.changed)
      end
    end
  end
  addCoreFiles(files)
  if #files == 0 then
    return nil
  end
  return files
end

local function prioritizeFiles(files)
  local present = {}
  for _, path in ipairs(files) do
    present[path] = true
  end
  local ordered = {}
  local function push(path)
    if present[path] then
      table.insert(ordered, path)
      present[path] = nil
    end
  end
  push("vBot/updater.lua")
  push("_Loader.lua")
  for _, path in ipairs(files) do
    if present[path] and path ~= "vBot/main.lua" and path ~= "vBot/version.txt" then
      table.insert(ordered, path)
      present[path] = nil
    end
  end
  push("vBot/main.lua")
  push("vBot/version.txt")
  return ordered
end

local downloadUpdate
local checkForUpdate

local function markUpdateAvailable(remote, sha)
  remoteVersion = normalizeVersion(remote)
  if remoteVersion == "" then
    remoteVersion = "?"
  end
  remoteSha = sha
  updateAvailable = true
  updaterState.remoteVersion = remoteVersion
  updaterState.remoteSha = sha
  local extra = ""
  if type(sha) == "string" and sha:len() >= 7 then
    extra = " [" .. sha:sub(1, 7) .. "]"
  end
  emitStatus("New version available: v" .. remoteVersion .. extra, "#e6b800")
  emitState()
  if autoRecover then
    downloadUpdate()
  end
end

local function markUpToDate(remote, silent)
  remoteVersion = normalizeVersion(remote)
  updateAvailable = false
  updaterState.remoteVersion = remoteVersion
  emitState()
  if silent then
    return
  end
  emitStatus("Latest version (local v" .. localVersion() .. ", GitHub v" .. remoteVersion .. ")", "#98BF64", 5000)
end

local function finishDownload(ok, message)
  if ok then
    updaterState.installedSha = remoteSha or updaterState.remoteSha
    updaterState.seenSha = updaterState.installedSha
    updaterState.installedVersion = remoteVersion or updaterState.remoteVersion or localVersion()
    updateAvailable = false
    setBusy(false)
    emitStatus(message or "Update complete. Reloading...", "#98BF64")
    schedule(400, function()
      reload()
    end)
    return
  end
  setBusy(false)
  emitStatus(message or "Download failed.", "#d9321f")
  warn("[mBot updater] " .. (message or "Download failed"))
end

local function downloadFile(index)
  if not busy then
    return
  end
  if index > #fileQueue then
    finishDownload(true, "Update complete (" .. #fileQueue .. " files). Reloading...")
    return
  end

  local path = fileQueue[index]
  emitStatus("Downloading " .. index .. "/" .. #fileQueue .. ":\n" .. path, "#6cb6ff")

  httpGet(rawUrl(path), CHECK_RETRIES, function(data)
    if not busy then
      return
    end
    if not data then
      finishDownload(false, "Could not download:\n" .. path)
      return
    end

    local written, writeErr = writeBotFile(path, data)
    if not written then
      finishDownload(false, "Could not save " .. path .. "\n" .. tostring(writeErr))
      return
    end

    schedule(40, function()
      downloadFile(index + 1)
    end)
  end)
end

local function startDownload(files)
  if type(files) ~= "table" or #files == 0 then
    finishDownload(false, "No files to download.")
    return
  end
  fileQueue = prioritizeFiles(files)
  downloadFile(1)
end

local function requestChangedFiles(callback)
  httpGet(rawUrl("vBot/update_manifest.json"), CHECK_RETRIES, function(manifestData)
    local manifestFiles = manifestData and collectFilesFromManifest(manifestData) or nil
    if manifestFiles then
      callback(manifestFiles)
      return
    end

    local fromSha = updaterState.installedSha
    local toSha = remoteSha or updaterState.remoteSha
    if fromSha and toSha and fromSha ~= toSha then
      httpGet(API_COMPARE .. fromSha .. "..." .. toSha, CHECK_RETRIES, function(data)
        callback(data and collectChangedFiles(data) or nil)
      end)
      return
    end
    callback(nil)
  end)
end

local function requestFileListAndDownload()
  requestChangedFiles(function(files)
    if not busy then
      return
    end
    if files then
      startDownload(files)
      return
    end
    finishDownload(false, "Could not fetch the changed file list from GitHub.")
  end)
end

local function applyVersionResult(remote, silent)
  updaterState.lastCheck = os.time()
  updaterState.remoteVersion = normalizeVersion(remote)
  if normalizeVersion(remote) == "" then
    if not silent and not updateAvailable then
      emitStatus("Could not read the remote version.", "#d9321f", 5000)
    end
    return
  end
  if isRemoteNewer(remote, localVersion()) then
    markUpdateAvailable(remote, updaterState.remoteSha)
  else
    markUpToDate(remote, silent)
  end
end

local function nextCheckDelay()
  if firstSuccess and playerOnline() then
    return CHECK_INTERVAL * 1000
  end
  return STARTUP_RETRY_MS
end

local function scheduleNextCheck()
  loopToken = loopToken + 1
  local token = loopToken
  schedule(nextCheckDelay(), function()
    if token ~= loopToken then
      return
    end
    checkForUpdate(firstSuccess)
  end)
end

checkForUpdate = function(silent)
  if checking then
    return
  end
  if busy then
    scheduleNextCheck()
    return
  end
  if not playerOnline() then
    firstSuccess = false
    scheduleNextCheck()
    return
  end

  checking = true
  if not silent then
    emitStatus("Checking GitHub for updates...", "#6cb6ff")
  end

  httpGet(rawUrl("vBot/version.txt"), CHECK_RETRIES, function(data)
    checking = false
    if not data then
      if firstSuccess and not updateAvailable then
        emitStatus("GitHub check failed, next try in " .. CHECK_INTERVAL .. "s", "#d9321f", 5000)
      end
      scheduleNextCheck()
      return
    end

    local version = parseRemoteVersion(data)
    if not version then
      if firstSuccess and not updateAvailable then
        emitStatus("Invalid version.txt from GitHub.", "#d9321f", 5000)
      end
      scheduleNextCheck()
      return
    end

    firstSuccess = true
    applyVersionResult(version, silent)
    scheduleNextCheck()
  end)
end

local function hookGameStart()
  pcall(function()
    connect(g_game, {
      onGameStart = function()
        firstSuccess = false
        schedule(1000, function()
          checkForUpdate(false)
        end)
      end
    })
  end)
end

downloadUpdate = function()
  if busy then
    return
  end
  local installed = localVersion()
  local remote = normalizeVersion(remoteVersion or updaterState.remoteVersion)
  if remote == "" then
    emitStatus("Waiting for GitHub check...", "#e6b800")
    checkForUpdate(false)
    return
  end
  if not isRemoteNewer(remote, installed) then
    emitStatus("No new version (local v" .. installed .. ", remote v" .. remote .. ")", "#e6b800", 5000)
    return
  end
  setBusy(true)
  emitStatus("Fetching changed files from GitHub...", "#6cb6ff")
  requestFileListAndDownload()
end

function MbotUpdater.init(opts)
  opts = opts or {}
  listeners.onStatus = opts.onStatus
  listeners.onState = opts.onState
  if updaterState.remoteVersion and isRemoteNewer(updaterState.remoteVersion, localVersion()) then
    markUpdateAvailable(updaterState.remoteVersion, updaterState.remoteSha)
  end
end

function MbotUpdater.localVersion()
  return localVersion()
end

function MbotUpdater.check(silent)
  checkForUpdate(silent and true or false)
end

function MbotUpdater.download()
  downloadUpdate()
end

function MbotUpdater.isBusy()
  return busy
end

function MbotUpdater.isAvailable()
  return updateAvailable
end

function MbotUpdater.start()
  if not started then
    started = true
    hookGameStart()
  end
  schedule(500, function()
    checkForUpdate(false)
  end)
end

function MbotUpdater.recover()
  autoRecover = true
  MbotUpdater.start()
end
