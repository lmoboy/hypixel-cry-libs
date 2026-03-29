-- @version 1.1
-- @location /libs/
-- @description UI widget library for creating rendered overlay windows with entries

---@class Widgets
---@field ENTRY_TYPES table Available entry type configurations
---@field loadImage function(path: string): userdata|nil Load an image from file path
---@field disposeAllImages function() Release all loaded images
---@field releaseImage function(img: userdata) Release a specific loaded image
---@field createImage function(path: string): userdata|nil Alias for loadImage
---@field createWindow function(id: string, config: table): table Create a new window
---@field removeWindow function(windowId: string) Remove a window from rendering
---@field addEntry function(windowId: string, key: string, value: any, entryType?: string, image?: userdata, group?: string) Add an entry to a window
---@field updateEntry function(windowId: string, key: string, value: any, entryType?: string, image?: userdata, group?: string) Update an entry
---@field updateEntryImage function(windowId: string, key: string, image: userdata, group?: string) Update entry image
---@field updateValue function(windowId: string, key: string, value: any, entryType?: string, group?: string) Update entry value
---@field removeEntry function(windowId: string, key: string, group?: string) Remove an entry from a window
---@field addGroup function(windowId: string, groupName: string, expanded?: boolean) Add a collapsible group
---@field toggleGroup function(windowId: string, groupName: string) Toggle group expansion
---@field setGroupExpanded function(windowId: string, groupName: string, expanded: boolean) Set group expansion state
---@field isGroupExpanded function(windowId: string, groupName: string): boolean Check if group is expanded
---@field getGroupEntries function(windowId: string, groupName: string): table Get group entries
---@field setStatus function(windowId: string, text: string) Set window status text
---@field setPosition function(windowId: string, x: number, y: number) Set window position
---@field setSize function(windowId: string, width: number, height: number) Set window size
---@field getWindow function(windowId: string): table|nil Get window by ID
---@field getWindows function(): table Get all windows
---@field setCornerImage function(windowId: string, image: userdata, size?: number) Set window corner image
---@field setWindowStyle function(windowId: string, style: string, value: boolean) Set a window style
---@field setWindowStyles function(windowId: string, styles: table) Set multiple window styles
---@field register function() Register the widget renderer (call once)

---@class WindowConfig
---@field title string Window title text
---@field x number|nil Window X position
---@field y number|nil Window Y position
---@field width number|nil Window width
---@field height number|nil Window height
---@field padding number|nil Window padding
---@field bgColor table|nil Background color {r, g, b, a}
---@field titleColor table|nil Title color {r, g, b, a}
---@field keyColor table|nil Key text color {r, g, b, a}
---@field statusText string|nil Status text to display
---@field cornerImage userdata|nil Corner image
---@field cornerSize number|nil Corner image size

local IRender         = require("IRender")
local imgui           = require("imgui")
local tween           = require("tween")

local smarrtieUtils = require("smarrtieUtils")
local widgets = {}
local windows = {}
local loadedImages = {}
local windowOrder  = {}

local DEFAULT_PADDING = 20
local DEFAULT_MARGIN  = 10
local TITLE_HEIGHT    = 30
local ROW_HEIGHT      = 20
local BADGE_SIZE      = 18

local DEFAULT_STYLES = {
    border            = true,
    roundedCorners    = true,
    divider           = true,
    collapsibleGroups = true,
}

local ENTRY_TYPES = {
    default = { icon = "›",  valueColor = { r = 0,   g = 255, b = 0,   a = 255 }, image = nil },
    number  = { icon = "#",  valueColor = { r = 100, g = 200, b = 255, a = 255 }, image = nil },
    bool    = { icon = "?",  valueColor = nil, image = nil },
    warning = { icon = "!",  valueColor = { r = 255, g = 180, b = 0,   a = 255 }, image = nil },
    error   = { icon = "x",  valueColor = { r = 255, g = 60,  b = 60,  a = 255 }, image = nil },
    ok      = { icon = "✓",  valueColor = { r = 60,  g = 255, b = 100, a = 255 }, image = nil },
    ping    = { icon = "~",  valueColor = { r = 180, g = 100, b = 255, a = 255 }, image = nil },
}

widgets.ENTRY_TYPES = ENTRY_TYPES

local function recalcHeight(windowId, context)
    local win = windows[windowId]
    if not win then return end

    local totalRows = #win.order
    local maxTextWidth = 0

    if context then
        local titleW = context.getTextWidth(win.title) * 1.5
        maxTextWidth = math.max(maxTextWidth, titleW + win.padding * 2)

        for _, key in ipairs(win.order) do
            local entry = win.elements[key]
            if entry then
                local keyW = context.getTextWidth(key .. " :") * 1.5
                local valW = context.getTextWidth(entry.value)
                maxTextWidth = math.max(maxTextWidth, keyW + valW + win.padding * 2 + 10)
            end
        end

        for _, groupName in ipairs(win.groupOrder) do
            totalRows = totalRows + 1
            local group = win.groups[groupName]
            if group and group.order then
                local titleW = context.getTextWidth(groupName .. " [+]")
                maxTextWidth = math.max(maxTextWidth, titleW + win.padding * 2 + 20)
                if win.groupState[groupName] then
                    for _, key in ipairs(group.order) do
                        local entry = group[key]
                        if entry then
                            totalRows = totalRows + 1
                            local keyW = context.getTextWidth(key .. " :") * 1.5
                            local valW = context.getTextWidth(entry.value)
                            maxTextWidth = math.max(maxTextWidth, keyW + valW + win.padding * 2 + 35)
                        end
                    end
                end
            end
        end
    else
        for _, groupName in ipairs(win.groupOrder) do
            totalRows = totalRows + 1
            if win.groupState[groupName] and win.groups[groupName] and win.groups[groupName].order then
                for _ in ipairs(win.groups[groupName].order) do
                    totalRows = totalRows + 1
                end
            end
        end
    end

    local footer = win.statusText and (ROW_HEIGHT + DEFAULT_MARGIN * 2) or DEFAULT_MARGIN
    local targetHeight = TITLE_HEIGHT + DEFAULT_MARGIN + (totalRows * (ROW_HEIGHT + DEFAULT_MARGIN)) + footer

    if maxTextWidth > 0 then
        tween.new(1, win.size, { height = targetHeight, width = maxTextWidth }, "outQuad"):update(smarrtieUtils.deltaTime()*10)
    else
        tween.new(1, win.size, { height = targetHeight }, "outQuad"):update(smarrtieUtils.deltaTime()*10)
    end
end


local function pulseAlpha(period)
    local t = (os.clock() * 60) % period / period
    return math.floor(150 + 105 * (0.5 - 0.5 * math.cos(t * 2 * math.pi)))
end

local function boolColor(val)
    if val == "true"  then return { r = 60,  g = 255, b = 100, a = 255 } end
    if val == "false" then return { r = 255, g = 60,  b = 60,  a = 255 } end
    return { r = 200, g = 200, b = 200, a = 255 }
end

local function detectEntryType(value)
    if value == "true" or value == "false" then return "bool"
    elseif tonumber(value) then return "number" end
    return "default"
end

local ANIM_DURATION = 0.3


---Load an image from file path for use in widgets
---@param path string Path to the image file
---@return userdata|nil The loaded image object, or nil if failed
function widgets.loadImage(path)
    local img = imgui.createImageObject()
    local result = img.loadImage(path)
    if result then
        loadedImages[img] = true
        return img
    end
    return nil
end

---Release all loaded images from memory
function widgets.disposeAllImages()
    for img, _ in pairs(loadedImages) do
        img.release()
    end
    loadedImages = {}
end

---Release a specific loaded image
---@param img userdata The image object to release
function widgets.releaseImage(img)
    if img and loadedImages[img] then
        img.release()
        loadedImages[img] = nil
    end
end

---Create an image (alias for loadImage)
---@param path string Path to the image file
---@return userdata|nil The loaded image object, or nil if failed
function widgets.createImage(path)
    return widgets.loadImage(path)
end

---Create a new window for displaying entries
---@param id string Unique identifier for the window
---@param config WindowConfig|nil Configuration table for the window
---@return table The created window object
function widgets.createWindow(id, config)
    config = config or {}
    windows[id] = {
        title       = config.title or id,
        position    = { x = config.x or 100, y = config.y or 100 },
        size        = { width = config.width or 260, height = config.height or 300 },
        padding     = config.padding or DEFAULT_PADDING,
        bgColor     = config.bgColor     or { r = 10,  g = 10,  b = 15,  a = 200 },
        titleColor  = config.titleColor  or { r = 255, g = 220, b = 0,   a = 255 },
        keyColor    = config.keyColor    or { r = 144, g = 255, b = 20,  a = 255 },
        statusText  = config.statusText  or nil,
        cornerImage = config.cornerImage or nil,
        cornerSize  = config.cornerSize  or 24,
        elements    = {},
        order       = {},
        groups      = {},
        groupOrder  = {},
        groupState  = {},
        styles      = {},
        anim        = 0,
    }

    for k, v in pairs(DEFAULT_STYLES) do
        windows[id].styles[k] = config[k] ~= nil and config[k] or v
    end

    windowOrder[#windowOrder + 1] = id

    return windows[id]
end
---Remove a window from rendering
---@param windowId string The window ID to remove
function widgets.removeWindow(windowId)
    windows[windowId] = nil
    for i, id in ipairs(windowOrder) do
        if id == windowId then
            table.remove(windowOrder, i)
            break
        end
    end
end

---Add an entry (key-value pair) to a window
---@param windowId string The window ID
---@param key string The entry key/name
---@param value any The entry value (converted to string)
---@param entryType string|nil Entry type: "default", "number", "bool", "warning", "error", "ok", "ping"
---@param image userdata|nil Optional image to display
---@param group string|nil Optional group name to add entry to
function widgets.addEntry(windowId, key, value, entryType, image, group)
    local win = windows[windowId]
    if not win then return end

    local strVal = tostring(value)
    if not entryType then entryType = detectEntryType(strVal) end

    local entry = {
        value  = strVal,
        kind   = entryType,
        image  = image,
        anim   = 0,
    }

    if group then
        if not win.groups[group] then
            win.groups[group] = { order = {} }
            win.groupOrder[#win.groupOrder + 1] = group
            win.groupState[group] = true
        end
        if not win.groups[group][key] then
            win.groups[group].order[#win.groups[group].order + 1] = key
        end
        win.groups[group][key] = entry
    else
        if not win.elements[key] then
            win.order[#win.order + 1] = key
        end
        win.elements[key] = entry
    end

    recalcHeight(windowId)
end

---Update an entry's value, type, and image
---@param windowId string The window ID
---@param key string The entry key
---@param value any The new value
---@param entryType string|nil Optional entry type
---@param image userdata|nil Optional image
---@param group string|nil Optional group name
function widgets.updateEntry(windowId, key, value, entryType, image, group)
    local win = windows[windowId]
    if not win then return end

    local strVal = tostring(value)
    local entry

    if group and win.groups[group] then
        entry = win.groups[group][key]
    else
        entry = win.elements[key]
    end

    if not entry then return end

    entry.value = strVal
    if entryType then entry.kind = entryType end
    if image ~= nil then entry.image = image end
end

---Update just the image for an entry
---@param windowId string The window ID
---@param key string The entry key
---@param image userdata The image to set
---@param group string|nil Optional group name
function widgets.updateEntryImage(windowId, key, image, group)
    local win = windows[windowId]
    if not win then return end

    local entry
    if group and win.groups[group] then
        entry = win.groups[group][key]
    else
        entry = win.elements[key]
    end

    if entry then entry.image = image end
end

---Update only the value of an entry
---@param windowId string The window ID
---@param key string The entry key
---@param value any The new value
---@param entryType string|nil Optional entry type
---@param group string|nil Optional group name
function widgets.updateValue(windowId, key, value, entryType, group)
    local win = windows[windowId]
    if not win then return end

    local strVal = tostring(value)
    local entry

    if group and win.groups[group] then
        entry = win.groups[group][key]
    else
        entry = win.elements[key]
    end

    if entry then
        entry.value = strVal
        if entryType then entry.kind = entryType end
    end
end

---Remove an entry from a window
---@param windowId string The window ID
---@param key string The entry key to remove
---@param group string|nil Optional group name
function widgets.removeEntry(windowId, key, group)
    local win = windows[windowId]
    if not win then return end

    if group and win.groups[group] then
        win.groups[group][key] = nil
        for i, k in ipairs(win.groups[group].order) do
            if k == key then table.remove(win.groups[group].order, i) break end
        end
    else
        win.elements[key] = nil
        for i, k in ipairs(win.order) do
            if k == key then table.remove(win.order, i) break end
        end
    end

    recalcHeight(windowId)
end

---Add a collapsible group to a window
---@param windowId string The window ID
---@param groupName string Name of the group
---@param expanded boolean|nil Whether the group starts expanded (default true)
function widgets.addGroup(windowId, groupName, expanded)
    local win = windows[windowId]
    if not win then return end

    if not win.groups[groupName] then
        win.groups[groupName] = { order = {} }
        win.groupOrder[#win.groupOrder + 1] = groupName
    end
    win.groupState[groupName] = expanded ~= false
end

---Toggle a group's expanded state
---@param windowId string The window ID
---@param groupName string The group name
function widgets.toggleGroup(windowId, groupName)
    local win = windows[windowId]
    if not win or not win.groupState then return end
    win.groupState[groupName] = not win.groupState[groupName]
    recalcHeight(windowId)
end

---Set a group's expanded state
---@param windowId string The window ID
---@param groupName string The group name
---@param expanded boolean Whether the group should be expanded
function widgets.setGroupExpanded(windowId, groupName, expanded)
    local win = windows[windowId]
    if not win or not win.groupState then return end
    win.groupState[groupName] = expanded
end

---Check if a group is expanded
---@param windowId string The window ID
---@param groupName string The group name
---@return boolean True if expanded
function widgets.isGroupExpanded(windowId, groupName)
    local win = windows[windowId]
    if not win or not win.groupState then return true end
    return win.groupState[groupName] ~= false
end

---Get all entries in a group
---@param windowId string The window ID
---@param groupName string The group name
---@return table Table of group entries
function widgets.getGroupEntries(windowId, groupName)
    local win = windows[windowId]
    if not win or not win.groups[groupName] then return {} end
    return win.groups[groupName]
end

---Set the status text at the bottom of a window
---@param windowId string The window ID
---@param text string The status text to display
function widgets.setStatus(windowId, text)
    local win = windows[windowId]
    if not win then return end
    win.statusText = text
    recalcHeight(windowId)
end

---Set the window position
---@param windowId string The window ID
---@param x number X position
---@param y number Y position
function widgets.setPosition(windowId, x, y)
    local win = windows[windowId]
    if not win then return end
    win.position.x = x
    win.position.y = y
end

---Set the window size
---@param windowId string The window ID
---@param width number Width
---@param height number Height
function widgets.setSize(windowId, width, height)
    local win = windows[windowId]
    if not win then return end
    win.size.width = width
    win.size.height = height
end

---Get a window by its ID
---@param windowId string The window ID
---@return table|nil The window object
function widgets.getWindow(windowId)
    return windows[windowId]
end

---Get all windows
---@return table Table of all windows
function widgets.getWindows()
    return windows
end

---Set a corner image for a window
---@param windowId string The window ID
---@param image userdata The image to use
---@param size number|nil Optional size for the corner image
function widgets.setCornerImage(windowId, image, size)
    local win = windows[windowId]
    if not win then return end
    win.cornerImage = image
    if size then win.cornerSize = size end
end

---Set a single window style property
---@param windowId string The window ID
---@param style string Style name: "border", "roundedCorners", "divider", "collapsibleGroups"
---@param value boolean The style value
function widgets.setWindowStyle(windowId, style, value)
    local win = windows[windowId]
    if win and DEFAULT_STYLES[style] ~= nil then
        win.styles[style] = value
    end
end

---Set multiple window style properties
---@param windowId string The window ID
---@param styles table Table of style key-value pairs
function widgets.setWindowStyles(windowId, styles)
    local win = windows[windowId]
    if not win then return end
    for k, v in pairs(DEFAULT_STYLES) do
        win.styles[k] = styles[k] ~= nil and styles[k] or v
    end
end



local function easeOutQuad(t)
    return t * (2 - t)
end

local function drawEntry(context, win, entry, key, x, y, isGroupHeader, isGroupEntry)
    local anim = entry.anim or 0
    if anim < 1 then
        entry.anim = math.min(1, anim + (1 / (ANIM_DURATION / 0.014)))
    end
    local t = easeOutQuad(entry.anim)

    local kind = entry.kind or "default"
    local def = ENTRY_TYPES[kind] or ENTRY_TYPES.default

    local alpha = isGroupHeader and 255 or math.floor(80 + 175 * t)
    local badgeColor = def.valueColor or boolColor(entry.value)
    local valueColor = def.valueColor or boolColor(entry.value)

    local badgeAlpha = math.floor(alpha * 0.3)
    local actualBadgeColor = { r = badgeColor.r, g = badgeColor.g, b = badgeColor.b, a = badgeAlpha }

    if entry.image then
        imgui.dl.renderImage(
             entry.image.getId(),
            x+ win.padding - 15, y,
             x+ win.padding, y+BADGE_SIZE,
            0, 0, 1,1
        )
    else

        local rect = IRender.renderRoundedRect(x+ win.padding - 15, y, BADGE_SIZE, BADGE_SIZE, 3, actualBadgeColor)
        imgui.dl.renderPolygon(rect.points, rect.red, rect.green, rect.blue, rect.alpha)

        imgui.dl.renderText(
            x + win.padding - 10, y,
            def.icon,
            badgeColor.r, badgeColor.g, badgeColor.b, alpha
        )
    end

    local keyText = isGroupHeader and entry.value or (key .. " :")
    local keyW = context.getTextWidth(keyText) * 1.5

    if isGroupHeader then
        local indicator = win.groupState[entry.value] and "[-]" or "[+]"
        imgui.dl.renderText(
            x + win.padding + 4, y,
             entry.value .. " " .. indicator,
             win.titleColor.r,  win.titleColor.g, win.titleColor.b, 255
        )
    else
        imgui.dl.renderText(
            x + win.padding + 4, y,
             keyText,
             win.keyColor.r, win.keyColor.g,  win.keyColor.b,  win.keyColor.a
        )
    end

    local valAlpha = (kind == "ping") and pulseAlpha(60) or math.floor(valueColor.a * t)

    if not isGroupHeader then
        imgui.dl.renderText(
             x + win.padding + 4 + keyW + 6, y,
             entry.value,
             valueColor.r, valueColor.g,  valueColor.b, valAlpha
        )
    end

    return y + ROW_HEIGHT + DEFAULT_MARGIN
end

---Register the widget renderer (must be called once to start rendering windows)
function widgets.register()
    local lastTime = os.clock()

    register2DRenderer(function(context)
        local currentTime = os.clock()
        local deltaTime = currentTime - lastTime
        lastTime = currentTime

        for _, winId in ipairs(windowOrder) do
            local win = windows[winId]
            if not win then goto skipWindow end
                recalcHeight(winId, context)

            local x = win.position.x
            local y = win.position.y
            local w = win.size.width
            local h = win.size.height
            local pad = win.padding

            if win.anim < 1 then
                win.anim = math.min(1, win.anim + deltaTime / ANIM_DURATION)
            end

            local bgColor = { r = win.bgColor.r, g = win.bgColor.g, b = win.bgColor.b, a = math.floor(win.bgColor.a * win.anim) }
            local outlineColor = { r = 255, g = 255, b = 255, a = math.floor(25 * win.anim) }
            local dividerColor = { r = 255, g = 255, b = 255, a = 40 }

            if win.styles.roundedCorners then
                local rect = IRender.renderRoundedRect(x, y, w, h, 10, bgColor)
                imgui.dl.renderPolygon(rect.points, rect.red, rect.green, rect.blue, rect.alpha)
            else
                local rect = IRender.renderRect(x, y, w, h, bgColor)
                imgui.dl.renderPolygon(rect.points, rect.red, rect.green, rect.blue, rect.alpha)
            end

            if win.styles.border then
                if win.styles.roundedCorners then
                    local rect = IRender.renderRoundedRectOutline(x, y, w, h, 10, outlineColor, { thickness = 2 })
                    imgui.dl.renderPolygon(rect.points, rect.red, rect.green, rect.blue, rect.alpha)
                else
                    local rect = IRender.renderRectOutline(x, y, w, h, outlineColor, { thickness = 2 })
                    imgui.dl.renderPolygon(rect.points, rect.red, rect.green, rect.blue, rect.alpha)
                end
            end

            if win.cornerImage then
                local ciSize = win.cornerSize or 24
                imgui.dl.renderImage(
                    win.cornerImage.getId(),
                    x + 6, y + 4,
                    ciSize, ciSize,
                    0, 0, 1, 1
                )
            end

            local titleStr = win.title
            local titleW = context.getTextWidth(titleStr) * 1.5
            local titleOffset = win.cornerImage and (win.cornerSize + 16) or 0
            local titleX = x + (w / 2) - (titleW / 2) + titleOffset

            imgui.dl.renderText(
                titleX,
                y + DEFAULT_MARGIN,
                titleStr,
                win.titleColor.r, win.titleColor.g,win.titleColor.b, math.floor(win.titleColor.a * win.anim)
            )

            if win.styles.divider then
                local dividerY = y + TITLE_HEIGHT
                imgui.dl.renderLine(
                    x + pad, dividerY,
                    x + w - pad, dividerY,
                    dividerColor.r, dividerColor.g, dividerColor.b,  dividerColor.a
                )
            end

            local currentY = y + TITLE_HEIGHT + DEFAULT_MARGIN

            for _, key in ipairs(win.order) do
                local entry = win.elements[key]
                if not entry then goto continue end

                currentY = drawEntry(context, win, entry, key, x, currentY, false, false)

                ::continue::
            end

            for _, groupName in ipairs(win.groupOrder) do
                local group = win.groups[groupName]
                if not group then goto groupContinue end

                local isExpanded = win.groupState[groupName] ~= false

                local groupEntry = { value = groupName, kind = "default", image = nil, anim = 1 }
                currentY = drawEntry(context, win, groupEntry, groupName, x, currentY, true, false)

                if isExpanded and group.order then
                    for _, key in ipairs(group.order) do
                        local entry = group[key]
                        if not entry then goto entryContinue end

                        currentY = drawEntry(context, win, entry, key, x + 15, currentY, false, true)

                        ::entryContinue::
                    end
                end

                ::groupContinue::
            end

            if win.statusText then
                local footerY = y + h - ROW_HEIGHT - DEFAULT_MARGIN
                imgui.dl.renderLine(
                    x + pad, footerY - 6,
                    x + w - pad, footerY - 6,
                    255, 255, 255, 20
                )
                local alpha = pulseAlpha(90)
                imgui.dl.renderText(
                    x + pad, footerY,
                    "» " .. win.statusText,
                    180, 180, 255, alpha
                )
            end

            ::skipWindow::
        end
    end)
end

return widgets