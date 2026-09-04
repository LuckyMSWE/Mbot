BotCache = BotCache or {}

local _n = {
  ["_Loader.lua"] = 379177286,
  ["vBot/alarms.lua"] = 842912808,
  ["vBot/antiRs.lua"] = 2085460167,
  ["vBot/AttackBot.lua"] = 778356226,
  ["vBot/cast_food.lua"] = 2042412538,
  ["vBot/cavebot.lua"] = 924386285,
  ["vBot/cavebot_control_panel.lua"] = 1477859136,
  ["vBot/combo_leader.lua"] = 2133341383,
  ["vBot/Conditions.lua"] = 1280302441,
  ["vBot/configs.lua"] = 1789247429,
  ["vBot/Containers.lua"] = 607212360,
  ["vBot/depositer_config.lua"] = 918296827,
  ["vBot/depot_withdraw.lua"] = 1446471596,
  ["vBot/Dropper.lua"] = 393333235,
  ["vBot/eat_food.lua"] = 1064274248,
  ["vBot/equip.lua"] = 1276010619,
  ["vBot/Equipper.lua"] = 1057456640,
  ["vBot/exeta.lua"] = 1236183334,
  ["vBot/extras.lua"] = 1762841061,
  ["vBot/features.lua"] = 1719128851,
  ["vBot/HealBot.lua"] = 13565936,
  ["vBot/hold_target.lua"] = 1499664744,
  ["vBot/ingame_editor.lua"] = 649322003,
  ["vBot/items.lua"] = 996223603,
  ["vBot/main.lua"] = 1056170483,
  ["vBot/new_cavebot_lib.lua"] = 1087850326,
  ["vBot/new_healer.lua"] = 799846215,
  ["vBot/npc_talk.lua"] = 92164617,
  ["vBot/playerlist.lua"] = 160588422,
  ["vBot/quiver_label.lua"] = 1896108644,
  ["vBot/quiver_manager.lua"] = 1431915951,
  ["vBot/Sio.lua"] = 456929591,
  ["vBot/spy_level.lua"] = 1271038063,
  ["vBot/supplies.lua"] = 781127483,
  ["vBot/tools.lua"] = 85405674,
  ["vBot/updater.lua"] = 2107054753,
  ["vBot/vlib.lua"] = 2052486552,
  ["vBot/xeno_menu.lua"] = 1375460629,
  ["cavebot/actions.lua"] = 976295248,
  ["cavebot/bank.lua"] = 133391440,
  ["cavebot/buy_supplies.lua"] = 2042053823,
  ["cavebot/cavebot.lua"] = 567744481,
  ["cavebot/clear_tile.lua"] = 246530994,
  ["cavebot/config.lua"] = 478552495,
  ["cavebot/d_withdraw.lua"] = 470895599,
  ["cavebot/depositor.lua"] = 1649382949,
  ["cavebot/doors.lua"] = 1696386231,
  ["cavebot/editor.lua"] = 578680483,
  ["cavebot/example_functions.lua"] = 1571039818,
  ["cavebot/extension_template.lua"] = 1015950748,
  ["cavebot/imbuing.lua"] = 349139844,
  ["cavebot/inbox_withdraw.lua"] = 2089565323,
  ["cavebot/lure.lua"] = 2091963293,
  ["cavebot/minimap.lua"] = 714045882,
  ["cavebot/pos_check.lua"] = 103070229,
  ["cavebot/recorder.lua"] = 534993500,
  ["cavebot/sell_all.lua"] = 984222634,
  ["cavebot/stand_lure.lua"] = 2002301424,
  ["cavebot/supply_check.lua"] = 830955369,
  ["cavebot/tasker.lua"] = 641611069,
  ["cavebot/travel.lua"] = 1319725836,
  ["cavebot/walking.lua"] = 322282723,
  ["cavebot/withdraw.lua"] = 1907982252,
  ["targetbot/creature.lua"] = 1225801946,
  ["targetbot/creature_attack.lua"] = 541300278,
  ["targetbot/creature_editor.lua"] = 1194989022,
  ["targetbot/creature_priority.lua"] = 1433938059,
  ["targetbot/looting.lua"] = 1199670660,
  ["targetbot/target.lua"] = 653267092,
  ["targetbot/walking.lua"] = 1223258381
}

local function _s(data)
  if type(data) ~= "string" then
    return nil
  end
  data = data:gsub("\r\n", "\n"):gsub("\r", "\n")
  local h = 5381
  for i = 1, #data do
    h = (h * 33 + data:byte(i)) % 2147483647
  end
  return h
end

function BotCache.trusted()
  if BotCache.ok ~= nil then
    return BotCache.ok
  end
  local configName = modules.game_bot.contentsPanel.config:getCurrentOption().text
  local root = "/bot/" .. configName
  for path, expect in pairs(_n) do
    local ok, contents = pcall(function()
      return g_resources.readFileContents(root .. "/" .. path)
    end)
    if not ok or type(contents) ~= "string" or _s(contents) ~= expect then
      BotCache.ok = false
      return false
    end
  end
  BotCache.ok = true
  return true
end
