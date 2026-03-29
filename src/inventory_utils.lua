local inventory = {}
local player = require("player")

--- @param id string Item SkyBlock Id
--- @return number?
function inventory.getItemInHotbar(id)
    for slot = 0, 8 do
        local item = player.inventory.getStack(slot)
        if item and item.skyblock_id == id then
            return slot
        end
    end
    return nil
end

--- @param id string Item SkyBlock Id
--- @return number?
function inventory.findItemInHotbar(id)
    for slot = 0, 8 do
        local item = player.inventory.getStack(slot)
        if item and item.skyblock_id and string.find(item.skyblock_id, id) then
            return slot
        end
    end
    return nil
end

--- @param name string Item display name
--- @return number?
function inventory.findItemByDisplayNameInHotbar(name)
    for slot = 0, 8 do
        local item = player.inventory.getStack(slot)
        if item and item.display_name and string.find(string.lower(item.display_name), string.lower(name)) then
            return slot
        end
    end
    return nil
end

--- @return boolean
function inventory.isFull()
    for slot = 0, 35 do -- 0 до 4*9 включительно (всего 36 слотов)
        local item = player.inventory.getStack(slot)
        -- Если слот пустой, предмет не существует или item пуст
        if not item then
            return false
        end
    end
    return true
end

return inventory
