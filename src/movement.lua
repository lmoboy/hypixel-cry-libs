-- @version 1.0.0
-- @location /libs

local player = require("player")
local json = require("json")

local movement = {}

local recordData = nil
local tick = 1
local isPlaying = false
local isPaused = false

local allowRotate = true
local allowSlot = false
local allowCommands = true

local currentTickCommand = nil

local recordingDataWrite = {
    data = {}
}
local isRecording = false
local currentTickWrite = 1

local function readAll(file)
    local f = io.open(file, "r")
    if not f then
        print("Error opening file: " .. file)
        return nil
    end
    local content = f:read("*a")
    f:close()
    return content
end

function movement.play()
    tick = 1
    isPlaying = true
    isPaused = false
end

function movement.pause()
    if isPlaying then
        isPaused = true
    end
end

function movement.resume()
    if isPlaying and isPaused then
        isPaused = false
    end
end

function movement.loadMovement(path)
    local data = readAll(path)
    if not data then
        print("Failed to read file: " .. path)
        return false
    end

    recordData = json.parse(data)
    if not recordData then
        print("Failed to parse JSON data")
        return false
    end

    print("Loaded recording with " .. #recordData.data .. " ticks")
    return true
end

function movement.stop()
    isPlaying = false
    isPaused = false
    tick = 1
end

--- @param allow boolean
function movement.setAllowRotate(allow)
    allowRotate = allow
end

--- @return boolean
function movement.isAllowRotate()
    return isAllowRotate
end

--- @param allow boolean
function movement.setAllowSlotChaning(allow)
    allowSlot = allow
end

--- @return boolean
function movement.isAllowSlotChaning()
    return allowSlot
end

--- @param allow boolean
function movement.setAllowCommands(allow)
    allowCommands = allow
end

--- @return boolean
function movement.isAllowCommands()
    return allowCommands
end

--- @return boolean
function movement.isPlaying()
    return isPlaying
end

--- @return boolean
function movement.isPaused()
    return isPaused
end

--- @return number
function movement.getCurrentTick()
    return tick
end

--- @param skip number
function movement.skipTicks(skip)
    tick = tick + skip
end

--- @return number
function movement.getMaxTick()
    return recordData and #recordData.data or 0
end

--- @class movementTick
--- @field sprint boolean
--- @field forward boolean
--- @field back boolean
--- @field left boolean
--- @field right boolean
--- @field attack boolean
--- @field use boolean
--- @field jump boolean
--- @field sneak boolean
--- @field yaw number
--- @field pitch number
--- @field command string

--- @return movementTick?
function movement.getMovementTick(tick)
    if not recordData or not recordData.data then
        print("Error: No recording data loaded")
        return nil
    end

    -- Проверка: существует ли место для вставки
    if not recordData.data[tick] then
        print("Error: No data for 'tick' " .. tostring(tick))
        return nil
    end

    return recordData.data[tick]
end

--- @param afterTick number
--- @param sprint boolean
--- @param forward boolean
--- @param back boolean
--- @param left boolean
--- @param right boolean
--- @param attack boolean
--- @param use boolean
--- @param jump boolean
--- @param sneak boolean
--- @param yaw number
--- @param pitch number
--- @param command string
function movement.insertMovementTick(afterTick, sprint, forward, back, left, right, attack, use, jump, sneak, yaw, pitch,
                                     command)
    if not recordData or not recordData.data then
        print("Error: No recording data loaded")
        return false
    end

    -- Проверка: существует ли место для вставки
    if not recordData.data[afterTick] then
        print("Error: No data for 'afterTick' " .. tostring(afterTick))
        return false
    end

    -- Сдвиг всех тиков выше afterTick
    local maxTick = 0
    for tickStr, _ in pairs(recordData.data) do
        local tickNum = tonumber(tickStr)
        if tickNum and tickNum > afterTick and tickNum > maxTick then
            maxTick = tickNum
        end
    end

    for i = maxTick, afterTick + 1, -1 do
        recordData.data[i + 1] = recordData.data[i]
    end

    -- Вставка нового тика
    local newTick = afterTick + 1
    recordData.data[newTick] = {
        sprint = sprint,
        forward = forward,
        back = back,
        left = left,
        right = right,
        attack = attack,
        use = use,
        jump = jump,
        sneak = sneak,
        yaw = yaw,
        pitch = pitch,
        command = command
    }
    return true
end

-- Функция для удаления тиков
--- @param startTick number
--- @param endTick number
function movement.removeTicks(startTick, endTick)
    if not recordData or not recordData.data then
        print("Error: No recording data loaded")
        return false
    end

    if startTick > endTick then
        print("Error: startTick cannot be greater than endTick")
        return false
    end

    local removedCount = 0
    for i = startTick, endTick do
        if recordData.data[i] then
            recordData.data[i] = nil
            removedCount = removedCount + 1
        end
    end

    -- Обновляем maxTick
    local newMaxTick = 0
    for tickStr, _ in pairs(recordData.data) do
        local tickNum = tonumber(tickStr)
        if tickNum and tickNum > newMaxTick then
            newMaxTick = tickNum
        end
    end

    print("Removed " .. removedCount .. " ticks from " .. startTick .. " to " .. endTick)
    print("New max tick: " .. newMaxTick)
    return true
end

-- Функция для удаления одного тика
--- @param tickToRemove number
function movement.removeTick(tickToRemove)
    return movement.removeTicks(tickToRemove, tickToRemove)
end

function movement.onTick()
    if isRecording then
        local rotation = player.getRotation()
        local position = player.getPos()
        recordingDataWrite.data[currentTickWrite] = {
            sprint = player.input.isPressedSprinting(),
            forward = player.input.isPressedForward(),
            back = player.input.isPressedBack(),
            left = player.input.isPressedLeft(),
            right = player.input.isPressedRight(),

            attack = player.input.isPressedAttack(),
            use = player.input.isPressedUse(),

            jump = player.input.isPressedJump(),
            sneak = player.input.isPressedSneak(),

            pos = {
                x = position.x,
                y = position.y,
                z = position.z
            },

            yaw = rotation.yaw,
            pitch = rotation.pitch,

            slot = player.input.getSelectedSlot(),

            command = currentTickCommand
        }
        currentTickCommand = nil
        currentTickWrite = currentTickWrite + 1
    end

    if not isPlaying or not recordData or not recordData.data or isPaused then
        return
    end

    if tick <= #recordData.data then
        local data = recordData.data[tick]
        if data then
            player.input.setPressedSprinting(data.sprint)
            player.input.setPressedForward(data.forward)
            player.input.setPressedBack(data.back)
            player.input.setPressedLeft(data.left)
            player.input.setPressedRight(data.right)
            player.input.setPressedAttack(data.attack)
            player.input.setPressedUse(data.use)

            player.input.setPressedJump(data.jump)
            player.input.setPressedSneak(data.sneak)

            if allowRotate and data.yaw and data.pitch then
                player.setRotation(data.yaw, data.pitch)
            end

            if allowSlot and data.slot then
                player.input.setSelectedSlot(data.slot)
            end

            if allowCommands and data.command then
                player.sendCommand("/" .. data.command)
            end
        else
            print("No data for tick: " .. tick)
        end
        tick = tick + 1
    else
        isPlaying = false
        isPaused = false
    end
end

--- @param record boolean
function movement.setRecording(record)
    isRecording = record
    if not record then
        currentTickCommand = nil
    end
end

--- @param name string
function movement.saveRecord(name)
    local jsonData = json.stringify(recordingDataWrite)

    local file = io.open(name .. ".json", "w")
    if file then
        currentTickWrite = 1
        file:write(jsonData)
        file:close()
    else
        print("Error: Could not open file for writing")
    end
end

registerSendCommandEvent(function(text)
    if text and isRecording then
        currentTickCommand = text
    end
end)

return movement
