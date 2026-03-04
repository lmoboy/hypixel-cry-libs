-- @version 1.0.1
-- @location /libs/

local utils = {}

local lastTick = os.clock()
local deltaTime = 0
local tickCount = 0

registerClientTick(function ()
    tickCount = tickCount + 1
end)

registerWorldRenderer(function()
    local currentTick = os.clock()
    deltaTime = currentTick - lastTick
    lastTick = currentTick
end)

function utils.getDistance(pos1, pos2)
    print(string.format("Distance between (%d, %d, %d) and (%d, %d, %d)", pos1.x, pos1.y, pos1.z, pos2.x, pos2.y, pos2.z))
    return math.sqrt((pos1.x - pos2.x)^2 + (pos1.y - pos2.y)^2 + (pos1.z - pos2.z)^2)
end

function utils.deltaTime()
    return deltaTime
end

function utils.tickCount()
    return tickCount
end

function utils.timestampToDate(stamp)
    stamp = math.floor(stamp/1000)
    return os.date("%Y-%m-%d %H:%M:%S", stamp)
end

function utils.getFPS()
    if deltaTime > 0 then
        return math.ceil(1 / deltaTime)
    end
    return 0
end


return utils