-- @version 1.0.1
-- @location /libs/

local time = {}

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

function time.deltaTime()
    return deltaTime
end

function time.tickCount()
    return tickCount
end

function time.timestampToDate(stamp)
    stamp = math.floor(stamp/1000)
    return os.date("%Y-%m-%d %H:%M:%S", stamp)
end

function time.getFPS()
    if deltaTime > 0 then
        return math.ceil(1 / deltaTime)
    end
    return 0
end


return time