local VERSION = "4.15"
local REPO = "LuckyMSWE/Mbot"
local BRANCH = "main"
local RAW_BASE = "https://raw.githubusercontent.com/" .. REPO .. "/" .. BRANCH .. "/"
local API_COMMIT = "https://api.github.com/repos/" .. REPO .. "/commits/" .. BRANCH
local API_COMPARE = "https://api.github.com/repos/" .. REPO .. "/compare/"
local CHECK_INTERVAL = 30

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

storage.mbotUpdater = storage.mbotUpdater or {}
local updaterState = storage.mbotUpdater
updaterState.lastCheck = updaterState.lastCheck or 0

local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
local botRoot = "/bot/" .. configName
local busy = false
local remoteVersion = nil
local remoteSha = nil
local updateAvailable = false
local fileQueue = {}

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

local function looksLikeHtmlError(data)
  if type(data) ~= "string" or data:len() == 0 then
    return true
  end
  local head = data:sub(1, 200):lower()
  return head:find("<!doctype", 1, true) or head:find("<html", 1, true)
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
  addUnique(files, "vBot/version.txt")
  if #files == 0 then
    return nil
  end
  return files
end

local function collectFilesFromManifest(data)
  local parsed = decodeJson(data)
  local list = parsed and (parsed.changed or parsed.files)
  if type(list) ~= "table" then
    return nil
  end
  local files = {}
  for _, path in ipairs(list) do
    addUnique(files, path)
  end
  addUnique(files, "vBot/version.txt")
  if #files == 0 then
    return nil
  end
  return files
end

setDefaultTab("Main")

local titleLabel = UI.Label("mBot v" .. localVersion() .. "\nLuckyM")
local statusLabel = UI.Label("Updater: ready")
statusLabel:setColor("#dfdfdf")
local downloadButton
local reloadButton
local statusToken = 0

local function setStatus(text, color, clearAfter)
  statusToken = statusToken + 1
  local token = statusToken
  statusLabel:setText(text)
  statusLabel:setColor(color or "#dfdfdf")
  if clearAfter then
    schedule(clearAfter, function()
      if token ~= statusToken or busy or updateAvailable then
        return
      end
      statusToken = statusToken + 1
      statusLabel:setText("Updater: ready")
      statusLabel:setColor("#dfdfdf")
    end)
  end
end

local function setBusy(state)
  busy = state
  if downloadButton then
    downloadButton:setEnabled(not state)
  end
end

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
  setStatus("New version available: v" .. remoteVersion .. extra, "#e6b800")
  if downloadButton then
    downloadButton:setEnabled(true)
  end
end

local function markUpToDate(remote, silent)
  remoteVersion = normalizeVersion(remote)
  updateAvailable = false
  updaterState.remoteVersion = remoteVersion
  if silent then
    return
  end
  setStatus("You have the latest version (v" .. localVersion() .. ")", "#98BF64", 5000)
end

local function finishDownload(ok, message)
  setBusy(false)
  if ok then
    updaterState.installedSha = remoteSha or updaterState.remoteSha
    updaterState.seenSha = updaterState.installedSha
    updaterState.installedVersion = remoteVersion or updaterState.remoteVersion or localVersion()
    updateAvailable = false
    setStatus(message or "Update complete. Reload the bot.", "#98BF64")
    if reloadButton then
      reloadButton:setEnabled(true)
    end
    info("[mBot updater] Update finished. Reload the bot.")
  else
    setStatus(message or "Download failed.", "#d9321f")
    warn("[mBot updater] " .. (message or "Download failed"))
  end
end

local function downloadFile(index, retries)
  if not busy then
    return
  end
  if index > #fileQueue then
    finishDownload(true, "Update complete (" .. #fileQueue .. " files). Reload the bot.")
    return
  end

  local path = fileQueue[index]
  setStatus("Downloading " .. index .. "/" .. #fileQueue .. ":\n" .. path, "#6cb6ff")

  HTTP.get(RAW_BASE .. path, function(data, err)
    if not busy then
      return
    end
    if err or looksLikeHtmlError(data) then
      if retries < 1 then
        schedule(200, function()
          downloadFile(index, retries + 1)
        end)
        return
      end
      finishDownload(false, "Could not download:\n" .. path)
      return
    end

    local written, writeErr = writeBotFile(path, data)
    if not written then
      finishDownload(false, "Could not save " .. path .. "\n" .. tostring(writeErr))
      return
    end

    schedule(40, function()
      downloadFile(index + 1, 0)
    end)
  end)
end

local function prioritizeFiles(files)
  local regular = {}
  local last = {}
  for _, path in ipairs(files) do
    if path == "vBot/version.txt" or path == "vBot/main.lua" then
      table.insert(last, path)
    else
      table.insert(regular, path)
    end
  end
  table.sort(last, function(a, b)
    if a == "vBot/version.txt" then
      return false
    end
    if b == "vBot/version.txt" then
      return true
    end
    return a < b
  end)
  for _, path in ipairs(last) do
    table.insert(regular, path)
  end
  return regular
end

local function startDownload(files)
  if type(files) ~= "table" or #files == 0 then
    finishDownload(false, "No files to download.")
    return
  end
  fileQueue = prioritizeFiles(files)
  downloadFile(1, 0)
end

local function requestChangedFiles(callback)
  local fromSha = updaterState.installedSha
  local toSha = remoteSha or updaterState.remoteSha

  local function fallbackManifest()
    HTTP.get(RAW_BASE .. "vBot/update_manifest.json", function(manifestData, manifestErr)
      callback(not manifestErr and collectFilesFromManifest(manifestData) or nil)
    end)
  end

  if fromSha and toSha and fromSha ~= toSha then
    HTTP.get(API_COMPARE .. fromSha .. "..." .. toSha, function(data, err)
      local files = not err and collectChangedFiles(data) or nil
      if files then
        callback(files)
        return
      end
      fallbackManifest()
    end)
    return
  end

  if toSha then
    HTTP.get("https://api.github.com/repos/" .. REPO .. "/commits/" .. toSha, function(data, err)
      local files = not err and collectChangedFiles(data) or nil
      if files then
        callback(files)
        return
      end
      fallbackManifest()
    end)
    return
  end

  fallbackManifest()
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

local function applyVersionResult(remote, sha, silent)
  updaterState.lastCheck = os.time()
  updaterState.remoteVersion = normalizeVersion(remote)
  updaterState.remoteSha = sha
  if normalizeVersion(remote) == "" then
    if not silent then
      setStatus("Could not read the remote version.", "#d9321f", 5000)
    end
    return
  end
  if isRemoteNewer(remote, localVersion()) then
    markUpdateAvailable(remote, sha)
  else
    if sha then
      updaterState.seenSha = sha
    end
    markUpToDate(remote, silent)
  end
end

local function checkForUpdate(silent)
  if busy then
    return
  end

  if not silent then
    setStatus("Checking GitHub for updates...", "#6cb6ff")
  end
  HTTP.get(RAW_BASE .. "vBot/version.txt", function(data, err)
    if err or looksLikeHtmlError(data) then
      setStatus("Could not check version:\n" .. tostring(err or "empty response"), "#d9321f")
      warn("[mBot updater] Unable to check version: " .. tostring(err or "empty response"))
      return
    end

    local version = normalizeVersion(data)
    applyVersionResult(version, nil, silent)
    HTTP.get(API_COMMIT, function(commitData, commitErr)
      if commitErr then
        return
      end
      local parsed = decodeJson(commitData)
      if parsed and type(parsed.sha) == "string" then
        applyVersionResult(version, parsed.sha, silent)
      end
    end)
  end)
end

local function downloadUpdate()
  if busy then
    return
  end
  local installed = localVersion()
  local remote = normalizeVersion(remoteVersion or updaterState.remoteVersion)
  if remote == "" then
    setStatus("Waiting for GitHub check...", "#e6b800")
    checkForUpdate(false)
    return
  end
  if not isRemoteNewer(remote, installed) then
    setStatus("No new version (local v" .. installed .. ", remote v" .. remote .. ")", "#e6b800", 5000)
    return
  end
  setBusy(true)
  setStatus("Fetching changed files from GitHub...", "#6cb6ff")
  requestFileListAndDownload()
end

downloadButton = UI.Button("Download update", function()
  downloadUpdate()
end)

reloadButton = UI.Button("Reload bot", function()
  reload()
end)
reloadButton:setEnabled(false)

UI.Separator()

if updaterState.remoteVersion and isRemoteNewer(updaterState.remoteVersion, localVersion()) then
  markUpdateAvailable(updaterState.remoteVersion, updaterState.remoteSha)
end

local function autoCheck()
  checkForUpdate(true)
  schedule(CHECK_INTERVAL * 1000, autoCheck)
end

schedule(1500, function()
  checkForUpdate(false)
  schedule(CHECK_INTERVAL * 1000, autoCheck)
end)
