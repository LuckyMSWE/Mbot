local VERSION = "4.36"

setDefaultTab("Main")

if not MbotUpdater then
  UI.Label("mBot v" .. VERSION .. "\nLuckyM")
  local errorLabel = UI.Label("Updater engine missing. Reload the bot.")
  errorLabel:setColor("#d9321f")
  UI.Separator()
  return
end

local titleLabel = UI.Label("mBot v" .. MbotUpdater.localVersion() .. "\nLuckyM")
if BotCache and BotCache.ok == false then
  local tamperLabel = UI.Label("mBot files were modified. Download update to restore.")
  tamperLabel:setColor("#d9321f")
end
local statusLabel = UI.Label("Updater: ready")
statusLabel:setColor("#dfdfdf")
local downloadButton
local changelogButton
local statusToken = 0

local function setStatus(text, color, clearAfter)
  statusToken = statusToken + 1
  local token = statusToken
  statusLabel:setText(text)
  statusLabel:setColor(color or "#dfdfdf")
  if clearAfter then
    schedule(clearAfter, function()
      if token ~= statusToken or MbotUpdater.isBusy() or MbotUpdater.isAvailable() then
        return
      end
      statusToken = statusToken + 1
      statusLabel:setText("Updater: ready")
      statusLabel:setColor("#dfdfdf")
    end)
  end
end

local function syncUpdateButtons()
  local busy = MbotUpdater.isBusy()
  if downloadButton then
    downloadButton:setVisible(true)
    downloadButton:setEnabled(not busy)
  end
  if changelogButton then
    changelogButton:setVisible(true)
    changelogButton:setEnabled(not busy)
  end
end

local changelogWindow = UI.createWindow("MbotChangelogWindow")
changelogWindow:hide()
changelogWindow.closeButton.onClick = function()
  changelogWindow:hide()
end

local function openChangelog()
  changelogWindow.log:setText("Loading...")
  changelogWindow:show()
  changelogWindow:raise()
  changelogWindow:focus()
  MbotUpdater.fetchChangelog(function(text)
    if text and text:len() > 0 then
      changelogWindow.log:setText(text)
    else
      changelogWindow.log:setText("Could not load changelog from GitHub.")
    end
  end)
end

MbotUpdater.init({
  onStatus = setStatus,
  onState = syncUpdateButtons
})

downloadButton = UI.Button("Download update", function()
  MbotUpdater.download()
end)

changelogButton = UI.Button("Changelog", function()
  openChangelog()
end)

syncUpdateButtons()

UI.Separator()

MbotUpdater.start()
