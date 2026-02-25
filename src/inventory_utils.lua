-- @version 1.0
-- @location /libs/

local inventory = {}

function inventory.getItemInHotbar(id)
    for slot = 0, 8 do
        local item = player.inventory.getStack(slot)
        if item and item.skyblock_id == id then
            return slot
        end
    end
    return nil
end

function inventory.findItemInHotbar(id)
    for slot = 0, 8 do
        local item = player.inventory.getStack(slot)
        if item and item.skyblock_id and string.find(item.skyblock_id, id) then
            return slot
        end
    end
    return nil
end

function inventory.findItemByDisplayNameInHotbar(name)
    for slot = 0, 8 do
        local item = player.inventory.getStack(slot)
        if item and item.display_name and string.find(string.lower(item.display_name), string.lower(name)) then
            return slot
        end
    end
    return -1
end

return inventory
