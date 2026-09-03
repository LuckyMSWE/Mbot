-- tools tab
setDefaultTab("Tools")

if type(storage.moneyItems) ~= "table" then
  storage.moneyItems = {3031, 3035}
end

local function moneyItemId(entry)
  if type(entry) == "number" then
    return entry
  end
  if type(entry) == "table" then
    return entry.id
  end
end

macro(1000, "Exchange money", function()
  if not storage.moneyItems[1] then return end
  local containers = g_game.getContainers()
  for index, container in pairs(containers) do
    if not container.lootContainer then -- ignore monster containers
      for i, item in ipairs(container:getItems()) do
        if item:getCount() == 100 then
          for m, moneyEntry in ipairs(storage.moneyItems) do
            if item:getId() == moneyItemId(moneyEntry) then
              return g_game.use(item)            
            end
          end
        end
      end
    end
  end
end)

local moneyContainer = UI.Container(function(widget, items)
  storage.moneyItems = items
end, true)
moneyContainer:setHeight(65)
moneyContainer:setItems(storage.moneyItems)

UI.Separator()

storage.autoTradeMessage = storage.autoTradeMessage or "I'm using OTClientV8!"

macro(60000, "Send message on trade", function()
  local trade = getChannelId("advertising")
  if not trade then
    trade = getChannelId("trade")
  end
  if trade and storage.autoTradeMessage:len() > 0 then    
    sayChannel(trade, storage.autoTradeMessage)
  end
end)
UI.TextEdit(storage.autoTradeMessage, function(widget, text)    
  storage.autoTradeMessage = text
end)

UI.Separator()
