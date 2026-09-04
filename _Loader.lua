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

local featureFiles = {
  "main",
  "items",
  "vlib",
  "new_cavebot_lib",
  "configs",
  "extras",
  "cavebot",
  "playerlist",
  "alarms",
  "features",
  "Conditions",
  "Equipper",
  "HealBot",
  "new_healer",
  "AttackBot",
  "combo_leader",
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

local trusted = false
local mainLoaded = false
local featuresLoaded = false

function MbotLoadBot()
  if featuresLoaded then
    return
  end
  featuresLoaded = true

  for _, file in ipairs(featureFiles) do
    if file == "main" or trusted then
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

  schedule(1, function()
    if CaveBot and CaveBot.actionList then
      CaveBot.actionList:getParent():setHeight(250)
    end
  end)
end

local ok = pcall(function()
  loadScript("cache")
end)
trusted = ok and BotCache and BotCache.trusted and BotCache.trusted()
if not trusted then
  warn("[mBot] File check failed. Features disabled.")
end

loadScript("updater")
loadScript("license")
