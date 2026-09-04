setDefaultTab("Main")
local panelName = "features"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Features')

  Button
    id: edit
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Edit

]])
ui:setId(panelName)

if not storage[panelName] then
  storage[panelName] = {}
end

local config = storage[panelName]

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
end

local window = UI.createWindow("FeaturesWindow")
window:hide()

ui.edit.onClick = function()
  window:show()
  window:raise()
  window:focus()
end

Features = Features or {}

function Features.enabled()
  return config.enabled == true
end

function Features.isOn(id)
  return config.enabled == true and type(config[id]) == "table" and config[id].enabled == true
end

function Features.add(id, title, defaultValue, tooltip)
  local widget = UI.createWidget("FeatureCheckBox", window.list)
  widget:setId(id)

  if type(config[id]) ~= "table" then
    config[id] = { enabled = defaultValue == true }
  end

  widget.tick:setText(title)
  widget.tick:setChecked(config[id].enabled)
  widget.tick:setTooltip(tooltip)
  widget.tick.onClick = function()
    config[id].enabled = not config[id].enabled
    widget.tick:setChecked(config[id].enabled)
  end
end
