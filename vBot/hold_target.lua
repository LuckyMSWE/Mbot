setDefaultTab("Tools")

local targetID = nil

-- escape when attacking will reset hold target
onKeyPress(function(keys)
    if keys == "Escape" and targetID then
        targetID = nil
    end
end)

macro(100, "Hold Target", function()
    local current = target()
    if current then
        local pos = current:getPosition()
        if pos and pos.z == posz() and not current:isNpc() then
            targetID = current:getId()
        end
    elseif targetID then
        local found = false
        for i, spec in ipairs(getSpectators()) do
            local specPos = spec:getPosition()
            if specPos and specPos.z == posz() and spec:getId() == targetID then
                attack(spec)
                found = true
                break
            end
        end
        if not found then
            targetID = nil
        end
    end
end)
