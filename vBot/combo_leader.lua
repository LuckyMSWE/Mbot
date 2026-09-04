setDefaultTab("Main")

if not storage.NewComboLeader then
  storage.NewComboLeader = {}
end

local settings = storage.NewComboLeader

if settings.enabled == nil then
  settings.enabled = true
end

if not settings.sdMissle then
  settings.sdMissle = 32
end

if not settings.AttackEnemiesHK then
  settings.AttackEnemiesHK = "f5"
end

UI.Separator()

local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Combo Leader')

  Button
    id: setup
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])
ui:setId("comboLeader")

local window = UI.createWindow("ComboLeaderWindow")
window:hide()
window.closeButton.onClick = function()
  window:hide()
end

ui.title:setOn(settings.enabled)
ui.title.onClick = function(widget)
  settings.enabled = not settings.enabled
  widget:setOn(settings.enabled)
end

ui.setup.onClick = function()
  window:show()
  window:raise()
  window:focus()
end

local rightPanel = window.content.right
local leftPanel = window.content.left

local addItem = function(id, title, defaultItem, dest, tooltip)
  local widget = UI.createWidget("ComboLeaderItem", dest)
  widget.text:setText(title)
  widget.text:setTooltip(tooltip)
  widget.item:setTooltip(tooltip)
  widget.item:setItemId(settings[id] or defaultItem)
  widget.item.onItemChange = function(itemWidget)
    settings[id] = itemWidget:getItemId()
  end
  settings[id] = settings[id] or defaultItem
end

local addTextEdit = function(id, title, defaultValue, dest, tooltip)
  local widget = UI.createWidget("ComboLeaderTextEdit", dest)
  widget.text:setText(title)
  widget.text:setTooltip(tooltip)
  widget.textEdit:setText(settings[id] or defaultValue or "")
  widget.textEdit.onTextChange = function(_, text)
    settings[id] = text
  end
  settings[id] = settings[id] or defaultValue or ""
end

local function leaderName()
  return (settings.LeaderName or ""):lower()
end

local function enemyList()
  return storage.playerList and storage.playerList.enemyList
end

local function friendList()
  return storage.playerList and storage.playerList.friendList
end

local m_leaderTarget = macro(10000, "Leader Target", function() end, leftPanel)
local m_comboSD = macro(10000, "Combo Rune", function() end, leftPanel)
local m_comboSpell = macro(10000, "Combo UE", function() end, leftPanel)

hotkey(settings.AttackEnemiesHK, "Attack Enemy Listed", function()
  if not settings.enabled then return end
  if g_game.isAttacking() then return end

  local list = enemyList()
  if type(list) ~= "table" then return end

  local enemies = {}
  for _, enemyName in ipairs(list) do
    local enemy = getCreatureByName(enemyName)
    if enemy then
      local epos = enemy:getPosition()
      local tile = epos and g_map.getTile(epos)
      if tile and tile:canShoot() then
        table.insert(enemies, enemy)
      end
    end
  end

  table.sort(enemies, function(a, b)
    return getDistanceBetween(a:getPosition(), pos()) < getDistanceBetween(b:getPosition(), pos())
  end)

  if enemies[1] then
    g_game.attack(enemies[1])
  end
end, leftPanel)

addTextEdit("LeaderName", "Leader Name", settings.LeaderName or "name", rightPanel)
addTextEdit("LeaderSpell", "Leader UE", settings.LeaderSpell or "exevo gran mas frigo", rightPanel)
addTextEdit("UE", "Your UE", settings.UE or "exevo gran mas frigo", rightPanel)
addTextEdit("AttackEnemiesHK", "Attack Enemies HK", "f5", rightPanel)
addItem("SD", "Rune", 3155, leftPanel, "")

local m_configRune = macro(10000, "Config Rune", function() end, leftPanel)

local hint = UI.createWidget("Label", leftPanel)
hint:setText("Enable Config Rune and have the leader shoot a rune at a target. Do not attack.")
hint:setTextWrap(true)

onMissle(function(missle)
  if not settings.enabled then return end
  local leader = leaderName()
  if leader == "" then return end

  local src = missle:getSource()
  if not src or src.z ~= posz() then return end

  local from = g_map.getTile(src)
  local to = g_map.getTile(missle:getDestination())
  if not from or not to then return end

  local fromCreatures = from:getCreatures()
  local toCreatures = to:getCreatures()
  if #fromCreatures ~= 1 or #toCreatures ~= 1 then return end

  local c1 = fromCreatures[1]
  local t1 = toCreatures[1]
  local targetName = t1:getName()
  if not targetName then return end
  if targetName:lower() == leader then return end

  local friends = friendList()
  if type(friends) == "table" and table.find(friends, targetName, true) then return end

  if c1:getName():lower() ~= leader then return end

  if m_configRune:isOn() then
    settings.sdMissle = missle:getId()
    modules.game_textmessage.displayGameMessage("Rune Combo Configured.")
    m_configRune:setOff()
    return
  end

  if m_leaderTarget:isOn() then
    local target = g_game.getAttackingCreature()
    if not target or target ~= t1 then
      g_game.attack(t1)
      schedule(1000, function()
        g_game.cancelAttackAndFollow()
      end)
    end
  end

  if m_comboSD:isOn() and missle:getId() == settings.sdMissle then
    useWith(settings.SD, t1)
  end
end)

onTalk(function(name, level, mode, text)
  if not settings.enabled then return end
  if not m_comboSpell:isOn() then return end
  local leader = leaderName()
  local leaderSpell = (settings.LeaderSpell or ""):lower()
  local ue = settings.UE
  if leader == "" or leaderSpell == "" or not ue or ue == "" then return end
  if name:lower() == leader and text:lower() == leaderSpell then
    say(ue)
  end
end)
