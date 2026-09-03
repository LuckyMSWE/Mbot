local VERSION = "4.22"

setDefaultTab("Main")

if not MbotUpdater then
  UI.Label("mBot v" .. VERSION .. "\nLuckyM")
  local errorLabel = UI.Label("Updater engine missing. Reload the bot.")
  errorLabel:setColor("#d9321f")
  UI.Separator()
  return
end

local titleLabel = UI.Label("mBot v" .. MbotUpdater.localVersion() .. "\nLuckyM")
local statusLabel = UI.Label("Updater: ready")
statusLabel:setColor("#dfdfdf")
local downloadButton
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

local function syncDownloadButton()
  if not downloadButton then
    return
  end
  local show = MbotUpdater.isAvailable() and not MbotUpdater.isBusy()
  downloadButton:setVisible(show)
  downloadButton:setEnabled(show)
end

MbotUpdater.init({
  onStatus = setStatus,
  onState = syncDownloadButton
})

downloadButton = UI.Button("Download update", function()
  MbotUpdater.download()
end)
syncDownloadButton()

UI.Separator()

MbotUpdater.start()
