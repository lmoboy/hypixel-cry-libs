-- @version 1.0.2
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
    if not pos1 then return nil end
    if not pos2 then return nil end
    return math.sqrt((pos1.x - pos2.x)^2 + (pos1.y - pos2.y)^2 + (pos1.z - pos2.z)^2)
end

function utils.dump(o)
   if type(o) == 'table' then
      local s = '{ '
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. '['..k..'] = ' .. utils.dump(v) .. ','
      end
      return s .. '} '
   else
      return tostring(o)
   end
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