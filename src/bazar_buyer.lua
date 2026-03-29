-- @version 1.0.0
-- @location /libs

local bayer = {}
local player = require("player")
local buy_item = ""
local buy_count = 0
local done_callback = nil

local timeout_timer = 0
local timeout_active = false

local slots = {
    11, 12, 13, 14, 16,
    20, 21, 22, 23, 24,
    29, 30, 31, 32, 33,
    38, 39, 40, 41, 42,
}

local buy_instaltly_clicked = false
local sign_clicked = false
local sign_entered = false
local sign_timer = 0

local function timeoutCallback()
    if timeout_active then
        local title = player.inventory.getChestTitle()
        if title and string.find(title, "Bazaar") or player.inventory.isSignOpened() then
            player.inventory.closeScreen()
        end

        buy_instaltly_clicked = false
        sign_clicked = false
        sign_entered = false
        sign_timer = 0

        timeout_active = false
        unregisterClientTick(tickerInventory)
        unregisterClientTick(timeoutTicker)
        if done_callback then
            done_callback(false)
        end
        done_callback = nil
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

local function strip_colors(s)
    return (s:gsub("§.", ""))
end

local function trimDisplayName(name)
    if not name or type(name) ~= "string" then
        return ""
    end

    -- Удаляем цветовой код §6 и открывающую скобку [ в начале
    -- и закрывающую скобку ] в конце
    local result = name

    -- Удаляем §6[ в начале, если есть
    result = result:sub(5)

    -- Удаляем ] в конце, если есть
    if result:sub(-1) == "]" then
        result = result:sub(1, -2)
    end

    return result
end

local function tickerInventory()
    local title = player.inventory.getChestTitle()
    if title and string.find(title, "Bazaar") then
        for _, slot in ipairs(slots) do
            local item = player.inventory.getStackFromContainer(slot)
            if strip_colors(trimDisplayName(item.display_name)) == buy_item then
                player.inventory.leftClick(slot)
                timeout_timer = 0
                return
            end
        end
    end
    if title and string.find(title, buy_item) then
        if not buy_instaltly_clicked then
            player.inventory.leftClick(10)
            timeout_timer = 0
            buy_instaltly_clicked = true
        end
    end
    if title and string.find(title, "Instant Buy") and not string.find(title, "Confirm") then
        if not sign_clicked then
            if buy_count == 1 then
                player.inventory.leftClick(10)
                player.inventory.closeScreen()
                unregisterClientTick(timeoutTicker)
                unregisterClientTick(tickerInventory)
                if done_callback then
                    done_callback(true)
                end
                buy_item = ""
                buy_count = 0
            elseif buy_count == 64 then
                player.inventory.leftClick(12)
                player.inventory.closeScreen()
                unregisterClientTick(timeoutTicker)
                unregisterClientTick(tickerInventory)
                if done_callback then
                    done_callback(true)
                end
                buy_item = ""
                buy_count = 0
            else
                player.inventory.leftClick(16)
                timeout_timer = 0
                sign_clicked = true
            end
        end
    end
    if player.inventory.isSignOpened() then
        if not sign_entered then
            player.inventory.setSignText(0, tostring(buy_count))
            player.inventory.doneSign()
            timeout_timer = 0
            sign_entered = true
            return
        end
    end
    if sign_entered and string.find(title, "Instant Buy") and string.find(title, "Confirm") then
        player.inventory.leftClick(13)
        player.inventory.closeScreen()
        unregisterClientTick(timeoutTicker)
        unregisterClientTick(tickerInventory)
        if done_callback then
            done_callback(true)
        end
        buy_item = ""
        buy_count = 0
    end
end

--- @param item string
---@param count number
--- @param callback fun()
function bayer.buyFromName(item, count, callback)
    -- Очищаем предыдущие регистрации
    unregisterClientTick(tickerInventory)
    unregisterClientTick(timeoutTicker)

    buy_item = item
    buy_count = count
    done_callback = callback

    timeout_timer = 0
    timeout_active = true

    -- Открываем меню питомцев
    player.sendCommand("/bz " .. item)

    -- Регистрируем тикеры
    registerClientTick(tickerInventory)
    registerClientTick(timeoutTicker)
end

return bayer
