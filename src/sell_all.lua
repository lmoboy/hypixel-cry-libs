local string_find = string.find

local seller = {}
local player = require("player")
-- Флаги для продажи инвентаря
local sell_inventory_now_clicked = false
local confirm_inventory_clicked = false
local inventory_timeout_counter = 0
local inventory_timeout_limit = 15
local inventory_timeout_triggered = false -- Флаг для предотвращения повторного вызова

-- Флаги для продажи мешков
local sell_sacks_now_clicked = false
local confirm_sacks_clicked = false
local sacks_timeout_counter = 0
local sacks_timeout_limit = 15
local sacks_timeout_triggered = false -- Флаг для предотвращения повторного вызова

-- Флаги для продажи всего
local sell_all_state = 0
local sell_all_delay_counter = 0
local all_timeout_counter = 0
local all_timeout_limit = 38
local all_timeout_triggered = false -- Флаг для предотвращения повторного вызова
-- 0 = не начато
-- 1 = инвентарь: нажали "Sell Inventory Now"
-- 2 = инвентарь: подтвердили
-- 3 = ждём 5 тиков перед продажей мешков
-- 4 = мешки: нажали "Sell Sacks Now"
-- 5 = мешки: подтвердили
-- 6 = завершено

local output = false

local function strip_colors(s)
    return (s:gsub("§.", ""))
end

local done_callback = nil

local function handle_timeout(ticker_name)
    -- Проверяем, не был ли уже вызван таймаут для этого тикера
    if ticker_name == "inventory" and inventory_timeout_triggered then
        return
    elseif ticker_name == "sacks" and sacks_timeout_triggered then
        return
    elseif ticker_name == "all" and all_timeout_triggered then
        return
    end

    -- Устанавливаем флаг, что таймаут уже сработал
    if ticker_name == "inventory" then
        inventory_timeout_triggered = true
    elseif ticker_name == "sacks" then
        sacks_timeout_triggered = true
    elseif ticker_name == "all" then
        all_timeout_triggered = true
    end

    if done_callback then
        done_callback()
    end

    -- Закрываем экран только если он открыт
    if string.find(player.inventory.getChestTitle(), "Bazaar") then
        player.inventory.closeScreen()
    end

    -- Сброс всех состояний в зависимости от тикера
    if ticker_name == "inventory" then
        sell_inventory_now_clicked = false
        confirm_inventory_clicked = false
        inventory_timeout_counter = 0
        unregisterClientTick(tickerInventory)
        if output then
            player.addMessage("§7[§6Hypixel Cry§7] §cThe sale was cancelled due to a timeout. (" ..
            inventory_timeout_limit .. " ticks)")
        end
    elseif ticker_name == "sacks" then
        sell_sacks_now_clicked = false
        confirm_sacks_clicked = false
        sacks_timeout_counter = 0
        unregisterClientTick(tickerSack)
        if output then
            player.addMessage("§7[§6Hypixel Cry§7] §cThe sale was cancelled due to a timeout. (" ..
            sacks_timeout_limit .. " ticks)")
        end
    elseif ticker_name == "all" then
        sell_all_state = 0
        sell_all_delay_counter = 0
        all_timeout_counter = 0
        unregisterClientTick(tickerAll)
        if output then
            player.addMessage("§7[§6Hypixel Cry§7] §cThe sale was cancelled due to a timeout. (" ..
            all_timeout_limit .. " ticks)")
        end
    end
end

local function getCoinsFromItem(item)
    if not item or not item.lore then
        return 0
    end
    local lore = item.lore
    local not_found = false
    for i, line in ipairs(lore) do
        if string_find(line, "You earn") and string_find(line, "coins") then
            local strip = strip_colors(line)
            -- Извлекаем число с запятыми и десятичными точками
            local count_string = string.match(strip, "You earn: ([%d,.]+) coins")
            if count_string then
                -- Убираем запятые для разделителей тысяч
                count_string = string.gsub(count_string, ",", "")
                -- Преобразуем в число
                return tonumber(count_string) or 0
            end
        end
    end
    return 0
end

local function ifItemLoaded(item)
    local lore = item.lore
    for i, line in ipairs(lore) do
        if string_find(line, "You earn") and string_find(line, "coins") then
            return true
        elseif string_find(line, "don't have") then
            return true
        end
    end
    return false
end

local function tickerInventory()
    -- Проверяем, не был ли уже вызван таймаут
    if inventory_timeout_triggered then
        unregisterClientTick(tickerInventory)
        return
    end

    -- Увеличиваем счетчик таймаута
    inventory_timeout_counter = inventory_timeout_counter + 1

    -- Проверяем таймаут
    if inventory_timeout_counter >= inventory_timeout_limit then
        handle_timeout("inventory")
        return
    end

    local sell_inventory_now_item = player.inventory.getStackFromContainer(47)
    if sell_inventory_now_item and string_find(sell_inventory_now_item.display_name, "Sell Inventory Now") and not sell_inventory_now_clicked then
        if getCoinsFromItem(sell_inventory_now_item) > 0 then
            player.inventory.leftClick(47)
            --player.addMessage("Selling inventory")
            sell_inventory_now_clicked = true
            inventory_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
        elseif ifItemLoaded(sell_inventory_now_item) then
            unregisterClientTick(tickerInventory)
            player.inventory.closeScreen()
            --player.addMessage("Now items for sell closing screen")
            sell_inventory_now_clicked = false
            confirm_inventory_clicked = false
            inventory_timeout_counter = 0
            inventory_timeout_triggered = false
            if done_callback then
                done_callback()
            end
        end
    else
        local confirm_item = player.inventory.getStackFromContainer(11)
        if confirm_item and string_find(confirm_item.display_name, "Selling whole inventory") and not confirm_inventory_clicked then
            player.inventory.leftClick(11)
            --player.addMessage("Confirm inventory sale")
            confirm_inventory_clicked = true
            inventory_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
        else
            if sell_inventory_now_item and string_find(sell_inventory_now_item.display_name, "Sell Inventory Now") and confirm_inventory_clicked then
                player.inventory.closeScreen()
                sell_inventory_now_clicked = false
                confirm_inventory_clicked = false
                unregisterClientTick(tickerInventory)
                if output then
                    player.addMessage("§7[§6Hypixel Cry§7] §aInventory sold successfully")
                end
                inventory_timeout_counter = 0
                inventory_timeout_triggered = false
                if done_callback then
                    done_callback()
                end
            end
        end
    end
end

local function tickerSack()
    -- Проверяем, не был ли уже вызван таймаут
    if sacks_timeout_triggered then
        unregisterClientTick(tickerSack)
        return
    end

    -- Увеличиваем счетчик таймаута
    sacks_timeout_counter = sacks_timeout_counter + 1

    -- Проверяем таймаут
    if sacks_timeout_counter >= sacks_timeout_limit then
        handle_timeout("sacks")
        return
    end

    local sell_sacks_now_item = player.inventory.getStackFromContainer(48)
    if sell_sacks_now_item and string_find(sell_sacks_now_item.display_name, "Sell Sacks Now") and not sell_sacks_now_clicked then
        if getCoinsFromItem(sell_sacks_now_item) > 0 then
            player.inventory.leftClick(48)
            --player.addMessage("Selling sacks")
            sell_sacks_now_clicked = true
            sacks_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
        elseif ifItemLoaded(sell_sacks_now_item) then
            unregisterClientTick(tickerSack)
            player.inventory.closeScreen()
            --player.addMessage("Now items for sell closing screen")
            if done_callback then
                done_callback()
            end
            sell_sacks_now_clicked = false
            confirm_sacks_clicked = false
            sacks_timeout_counter = 0
            sacks_timeout_triggered = false
        end
    elseif sell_sacks_now_item and string_find(sell_sacks_now_item.display_name, "[ ]") and not sell_sacks_now_clicked then
        unregisterClientTick(tickerSack)
        player.inventory.closeScreen()
        --player.addMessage("Now items for sell closing screen")
        if done_callback then
            done_callback()
        end
        sell_sacks_now_clicked = false
        confirm_sacks_clicked = false
        sacks_timeout_counter = 0
        sacks_timeout_triggered = false
    else
        local confirm_item = player.inventory.getStackFromContainer(11)
        if confirm_item and string_find(confirm_item.display_name, "Selling whole inventory") and not confirm_sacks_clicked then
            player.inventory.leftClick(11)
            --player.addMessage("Confirm sacks sale")
            confirm_sacks_clicked = true
            sacks_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
        else
            if sell_sacks_now_item and string_find(sell_sacks_now_item.display_name, "[ ]") and confirm_sacks_clicked then
                player.inventory.closeScreen()
                sell_sacks_now_clicked = false
                confirm_sacks_clicked = false
                unregisterClientTick(tickerSack)
                if output then
                    player.addMessage("§7[§6Hypixel Cry§7] §aSacks sold successfully")
                end
                sacks_timeout_counter = 0
                sacks_timeout_triggered = false
                if done_callback then
                    done_callback()
                end
            end
        end
    end
end

local function tickerAll()
    -- Проверяем, не был ли уже вызван таймаут
    if all_timeout_triggered then
        unregisterClientTick(tickerAll)
        return
    end

    -- Увеличиваем счетчик таймаута
    all_timeout_counter = all_timeout_counter + 1

    -- Проверяем таймаут
    if all_timeout_counter >= all_timeout_limit then
        handle_timeout("all")
        return
    end

    -- Состояние 0: Начало - проверка кнопки продажи инвентаря
    if sell_all_state == 0 then
        local sell_inventory_now_item = player.inventory.getStackFromContainer(47)
        if sell_inventory_now_item and string_find(sell_inventory_now_item.display_name, "Sell Inventory Now") then
            if getCoinsFromItem(sell_inventory_now_item) > 0 then
                player.inventory.leftClick(47)
                --player.addMessage("Selling inventory (all)")
                sell_all_state = 1
                all_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
            elseif ifItemLoaded(sell_inventory_now_item) then
                -- Если в инвентаре нечего продавать, сразу переходим к мешкам
                --player.addMessage("Inventory empty, moving to sacks immediately")
                sell_all_state = 4      -- Переходим сразу к продаже мешков
                all_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
            end
        else
            -- Если кнопка не найдена, возможно интерфейс не загрузился
            return
        end

        -- Состояние 1: Подтверждение продажи инвентаря
    elseif sell_all_state == 1 then
        local confirm_item = player.inventory.getStackFromContainer(11)
        if confirm_item and string_find(confirm_item.display_name, "Selling whole inventory") then
            player.inventory.leftClick(11)
            --player.addMessage("Confirm inventory sale (all)")
            sell_all_state = 2
            all_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
        end

        -- Состояние 2: Проверка завершения продажи инвентаря
    elseif sell_all_state == 2 then
        local sell_inventory_now_item = player.inventory.getStackFromContainer(47)
        if sell_inventory_now_item and string_find(sell_inventory_now_item.display_name, "Sell Inventory Now") then
            -- Продажа инвентаря завершена, начинаем ожидание 15 тиков
            sell_all_state = 3
            sell_all_delay_counter = 0
            all_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
            if output then
                --player.addMessage("§7[§6Hypixel Cry§7] §aInventory sold, §6waiting §c15 ticks before sacks")
            end
        end

        -- Состояние 3: Ожидание 15 тиков после продажи инвентаря
    elseif sell_all_state == 3 then
        sell_all_delay_counter = sell_all_delay_counter + 1
        if sell_all_delay_counter >= 15 then
            sell_all_state = 4
            all_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
            --player.addMessage("Starting sacks sale")
        end

        -- Состояние 4: Продажа мешков
    elseif sell_all_state == 4 then
        local sell_sacks_now_item = player.inventory.getStackFromContainer(48)
        if sell_sacks_now_item and string_find(sell_sacks_now_item.display_name, "Sell Sacks Now") then
            if getCoinsFromItem(sell_sacks_now_item) > 0 then
                player.inventory.leftClick(48)
                --player.addMessage("Selling sacks (all)")
                sell_all_state = 5
                all_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
            elseif ifItemLoaded(sell_sacks_now_item) then
                -- Если в мешках нечего продавать, завершаем
                --player.addMessage("Sacks empty, completing")
                sell_all_state = 7      -- Переходим к завершению
                all_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
            end
        elseif sell_sacks_now_item and string_find(sell_sacks_now_item.display_name, "[ ]") then
            -- Пустая кнопка мешков
            --player.addMessage("Sacks empty (empty button), completing")
            sell_all_state = 7
            all_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
        else
            -- Если кнопка не найдена, возможно интерфейс не загрузился
            return
        end

        -- Состояние 5: Подтверждение продажи мешков
    elseif sell_all_state == 5 then
        local confirm_item = player.inventory.getStackFromContainer(11)
        if confirm_item and string_find(confirm_item.display_name, "Selling whole inventory") then
            player.inventory.leftClick(11)
            --player.addMessage("Confirm sacks sale (all)")
            sell_all_state = 6
            all_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
        end

        -- Состояние 6: Проверка завершения продажи мешков
    elseif sell_all_state == 6 then
        local sell_sacks_now_item = player.inventory.getStackFromContainer(48)
        if (sell_sacks_now_item and string_find(sell_sacks_now_item.display_name, "Sell Sacks Now") or sell_sacks_now_item and string_find(sell_sacks_now_item.display_name, "[ ]")) then
            -- Продажа мешков завершена
            sell_all_state = 7
            all_timeout_counter = 0 -- Сбрасываем таймаут при успешном действии
        end

        -- Состояние 7: Завершение - закрытие интерфейса
    elseif sell_all_state == 7 then
        player.inventory.closeScreen()
        unregisterClientTick(tickerAll)
        sell_all_state = 0
        all_timeout_counter = 0
        all_timeout_triggered = false
        if output then
            player.addMessage("§7[§6Hypixel Cry§7] §aAll selling completed")
        end
        if done_callback then
            done_callback()
        end
    end
end

--- @param callback fun()
--- @param output2 boolean
function seller.startSellInventory(callback, output2)
    player.sendCommand("/bz")
    sell_inventory_now_clicked = false
    confirm_inventory_clicked = false
    inventory_timeout_counter = 0
    inventory_timeout_triggered = false -- Сбрасываем флаг таймаута
    unregisterClientTick(tickerInventory)
    unregisterClientTick(tickerSack)    -- Отписываемся от других тикеров
    unregisterClientTick(tickerAll)     -- Отписываемся от других тикеров
    registerClientTick(tickerInventory)
    done_callback = callback
    output = output2
end

--- @param callback fun()
--- @param output2 boolean
function seller.startSellSacks(callback, output2)
    player.sendCommand("/bz")
    sell_sacks_now_clicked = false
    confirm_sacks_clicked = false
    sacks_timeout_counter = 0
    sacks_timeout_triggered = false       -- Сбрасываем флаг таймаута
    unregisterClientTick(tickerSack)
    unregisterClientTick(tickerInventory) -- Отписываемся от других тикеров
    unregisterClientTick(tickerAll)       -- Отписываемся от других тикеров
    registerClientTick(tickerSack)
    done_callback = callback
    output = output2
end

--- @param callback fun()
--- @param output2 boolean
function seller.startSellAll(callback, output2)
    player.sendCommand("/bz")
    sell_all_state = 0
    sell_all_delay_counter = 0
    all_timeout_counter = 0
    all_timeout_triggered = false         -- Сбрасываем флаг таймаута
    unregisterClientTick(tickerAll)
    unregisterClientTick(tickerInventory) -- Отписываемся от других тикеров
    unregisterClientTick(tickerSack)      -- Отписываемся от других тикеров
    registerClientTick(tickerAll)
    done_callback = callback
    output = output2
end

registerSendCommandEvent(function(text)
    if text and text == "bz" then
        sell_inventory_now_clicked = false
        confirm_inventory_clicked = false
        inventory_timeout_counter = 0
        inventory_timeout_triggered = false

        sell_sacks_now_clicked = false
        confirm_sacks_clicked = false
        sacks_timeout_counter = 0
        sacks_timeout_triggered = false

        sell_all_state = 0
        all_timeout_counter = 0
        all_timeout_triggered = false
    end
end)

registerUnloadCallback(function()
    unregisterClientTick(tickerInventory)
    unregisterClientTick(tickerSack)
    unregisterClientTick(tickerAll)
end)

return seller
