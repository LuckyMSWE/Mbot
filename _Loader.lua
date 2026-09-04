-- load all otui files, order doesn't matter
local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text

local configFiles = g_resources.listDirectoryFiles("/bot/" .. configName .. "/vBot", true, false)
for i, file in ipairs(configFiles) do
  local ext = file:split(".")
  if ext[#ext]:lower() == "ui" or ext[#ext]:lower() == "otui" then
    g_ui.importStyle(file)
  end
end

local function loadScript(name)
  return dofile("/vBot/" .. name .. ".lua")
end

-- here you can set manually order of scripts
-- libraries should be loaded first
local luaFiles = {
  "cache",
  "updater", -- bootstrap engine, before everything else
  "main",
  "items",
  "vlib",
  "new_cavebot_lib",
  "configs", -- do not change this and above
  "extras",
  "cavebot",
  "playerlist",
  "alarms",
  "features",
  "Conditions",
  "Equipper",  
  "HealBot",
  "new_healer",
  "AttackBot", -- last of major modules
  "ingame_editor",
  "Dropper",
  "Containers",
  "quiver_manager",
  "quiver_label",
  "tools",
  "antiRs",
  "depot_withdraw",
  "eat_food",
  "equip",
  "exeta",  
  "spy_level",
  "supplies",
  "depositer_config",
  "npc_talk",
  "xeno_menu",
  "hold_target",
  "cavebot_control_panel"
}

local mainLoaded = false
local trusted = false
for i, file in ipairs(luaFiles) do
  if file == "cache" then
    local ok, err = pcall(function()
      loadScript(file)
    end)
    trusted = ok and BotCache and BotCache.trusted and BotCache.trusted()
    if not trusted then
      warn("[mBot] File check failed. Features disabled.")
    end
  elseif file == "updater" or file == "main" or trusted then
    if file == "main" then
      local ok, err = pcall(function()
        loadScript(file)
      end)
      if ok then
        mainLoaded = true
      else
        warn("[mBot] main.lua failed to load: " .. tostring(err))
      end
    else
      loadScript(file)
    end
  end
end

if not mainLoaded and MbotUpdater and MbotUpdater.recover then
  MbotUpdater.recover()
end

setDefaultTab("Main")
UI.Separator()

--CaveBot action list size
schedule(1, function()
  local size = 250
  CaveBot.actionList:getParent():setHeight(size)
end)