-- config
setDefaultTab("Tools")
local defaultBp = "shopping bag"
local id = 21411

-- script

local playerContainer = nil
local depotContainer = nil
local mailContainer = nil

macro(50, "Depot Withdraw", function()
  playerContainer = nil
  depotContainer = nil
  mailContainer = nil

  for i, container in pairs(getContainers()) do
    local name = container:getName():lower()
    if name == defaultBp:lower() then
      playerContainer = container
    elseif name:find("depot", 1, true) then
      depotContainer = container
    elseif name:find("your inbox", 1, true) then
      mailContainer = container
    end
  end

  if playerContainer and containerIsFull(playerContainer) then
    for j, item in pairs(playerContainer:getItems()) do
      if item:getId() == id then
        g_game.open(item, playerContainer)
        return
      end
    end
  end

  if playerContainer and freecap() >= 200 then
    if depotContainer then
      for j, item in pairs(depotContainer:getItems()) do
        g_game.move(item, playerContainer:getSlotPosition(playerContainer:getItemsCount()), item:getCount())
        return
      end
    end

    if mailContainer then
      for j, item in pairs(mailContainer:getItems()) do
        g_game.move(item, playerContainer:getSlotPosition(playerContainer:getItemsCount()), item:getCount())
        return
      end
    end
  end
end)
