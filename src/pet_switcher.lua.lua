-- @version 1.0.0
-- @location /libs

local switcher = {}

local string_match = string.match
local string_find = string.find

local require_pet_name = nil

local state = 0
local timeout_timer = 0
local timeout_active = false

local waiting_for_action = false -- Новый флаг для ожидания действия

local slots = {
    10, 11, 12, 13, 14, 15, 16,
    19, 20, 21, 22, 23, 24, 25,
    28, 29, 30, 31, 32, 33, 34,
    37, 38, 39, 40, 41, 42, 43,
}

local function getPetName(item)
    if not item then return nil end
    if item.display_name == "§f[ ]" then return nil end
    local item_name = item.display_name
    local clean_name = item_name:gsub("§.", "")
    local name = string_match(clean_name, "%]%s*(.-)%]*$")
    return name
end

local function timeoutCallback()
    if timeout_active then
        local title = player.inventory.getChestTitle()
        if title and string.find(title, "Pets") then
            player.inventory.closeScreen()
        end

        timeout_active = false
        waiting_for_action = false -- Сбрасываем флаг
        unregisterClientTick(tickerInventory)
        unregisterClientTick(timeoutTicker)
        require_pet_name = nil
    end
end

local function timeoutTicker()
    if timeout_active then
        timeout_timer = timeout_timer + 1
        if timeout_timer >= 10 then
            timeoutCallback()
        end
    end
end

local function isEquiped(item)
    local lore = item.lore
    for i, line in ipairs(lore) do
        if line and string_find(line, "Click to despawn!") then
            return true
        end
    end
    return false
end

local function tickerInventory()
    local title = player.inventory.getChestTitle()
    if title and string.find(title, "Pets") then
        for _, slot in ipairs(slots) do
            local item = player.inventory.getStackFromContainer(slot)
            local pet_name = getPetName(item)
            if pet_name and require_pet_name then
                if string_find(pet_name, require_pet_name) then
                    if not isEquiped(item) then
                        player.inventory.leftClick(slot)
                        -- После клика запускаем таймаут
                        if not waiting_for_action then
                            waiting_for_action = true
                            timeout_active = true
                            timeout_timer = 0
                            registerClientTick(timeoutTicker)
                        end
                    else
                        player.inventory.closeScreen()
                        player.addMessage("§7[§6Hypixel Cry§7] §a✔ Pet now is equiped")
                    end

                    -- Убираем тикер инвентаря, но оставляем таймаут
                    unregisterClientTick(tickerInventory)

                    -- Не вызываем callback сразу, ждем таймаут
                    require_pet_name = nil
                    done_callback = nil
                    return
                end
            end
        end
    end
end
--- @param pet_name2 string
function switcher.equipPet(pet_name2)
    -- Очищаем предыдущие регистрации
    unregisterClientTick(tickerInventory)
    unregisterClientTick(timeoutTicker)
    timeout_timer = 0
    timeout_active = false
    waiting_for_action = false -- Сбрасываем флаг

    -- Устанавливаем новые параметры
    require_pet_name = pet_name2
    if require_pet_name then
        -- Открываем меню питомцев
        player.sendCommand("/petmenu")

        -- Регистрируем только тикер инвентаря (таймаут пока не активен)
        registerClientTick(tickerInventory)
    end
end

return switcher
