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
---Reurns sqrt dist between points
---@param pos1 table
---@param pos2 table
---@return number
function utils.getDistance(pos1, pos2)
    return math.sqrt((pos1.x - pos2.x)^2 + (pos1.y - pos2.y)^2 + (pos1.z - pos2.z)^2)
end
---comment
---@param o table
---@param depth number|nil
---@return unknown
function utils.dump(o, depth)
   depth = depth or 0
   local indent = string.rep('  ', depth)
   
   if type(o) == 'table' then
      local s = '{\n'
      for k,v in pairs(o) do
         if type(k) ~= 'number' then k = '"'..k..'"' end
         s = s .. indent .. '  ['..k..'] = ' .. utils.dump(v, depth + 1) .. ',\n'
      end
      return s .. indent .. '}'
   else
      return tostring(o)
   end
end
---Returns seconds between frames
---@return integer
function utils.deltaTime()
    return deltaTime
end
---Rounds a value to n after comma
---@param n number
---@param decimals number
---@return unknown
function utils.round(n, decimals)
    local factor = 10 ^ (decimals or 0)
    return math.floor(n * factor + 0.5) / factor
end
---Normalizes minecraft yaw
---@param yaw number
---@return number
function utils.normalizeYaw(yaw)
    yaw = yaw % 360
    if yaw > 180 then
        yaw = yaw - 360
    end
    return yaw
end
---Returns ticks since library load
---@return integer
function utils.tickCount()
    return tickCount
end
---Returns date from unix time
---@param stamp number
---@return string|osdate
function utils.timestampToDate(stamp)
    stamp = math.floor(stamp/1000)
    return os.date("%Y-%m-%d %H:%M:%S", stamp)
end
---Returns fps of the game
---@return integer
function utils.getFPS()
    if deltaTime > 0 then
        return math.ceil(1 / deltaTime)
    end
    return 0
end


return utils