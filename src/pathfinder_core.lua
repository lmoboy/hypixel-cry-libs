-- @version beta-0.7
-- @location /libs/


---@class Core
---@field maxNodes number Maximum nodes to explore before returning partial path
---@field jumpHeight number Maximum jump height
---@field smoothPath boolean Whether to smooth the generated path
---@field fallDepth number Maximum fall distance to consider
---@field queuedPaths table Queued paths waiting to be processed
---@field debugCapture boolean Whether to capture debug info
---@field _debugExpanded table Debug: expanded nodes
---@field _debugOpen table Debug: open set nodes
local Core = {}
local player = require("player")
local world = require("world")
local threads = require("threads")
local Core = {}

Core.maxNodes = 50000 -- haha memory leak go KABOOM<KABLOW<R.I.P MY GRANNY SHE GOT HIT BY A BAZOOKA<YEAH I THINK ABOUT HER EVERY TIME I HIT THE HOOKAH<KABLOW<KABOOM<KABLOW

Core.jumpHeight = 1
Core.smoothPath = false
Core.fallDepth = 10

Core.queuedPaths = {}


Core.debugCapture = true
Core._debugExpanded = {}
Core._debugOpen = {}
local _lock = false


local function key(x, y, z)
    return x .. "," .. y .. "," .. z
end
local function isSolid(bx, by, bz)
    local block = world.getBlock(bx, by, bz)
    if not block then return false end
    return block.is_solid or false
end

local function isLadder(x,y,z)
    local block = world.getBlock(x, y, z).name
    if not block then return false end
    if string.match(block, "ladder") then
        return true
    end
    return false
end

local function heuristic(ax, ay, az, bx, by, bz)
    local dx = math.abs(ax - bx)
    local dy = math.abs(ay - by)
    local dz = math.abs(az - bz)
    local hi = math.max(dx, dz)
    local lo = math.min(dx, dz)
    return ((hi - lo) + lo * 1.4142 + dy) * 0.8
end

---Gets the maximum Y collision height at given coordinates
---@param x number
---@param y number
---@param z number
---@return number
function Core.getMaxYCollision(x,y,z)
    local blockState = world.getBlock(x,y,z)
    local maxY = 0
    local collisions = world.getCollisionBoxes(x, y, z, blockState)
    if collisions then
        for i = 1, #collisions do
            if maxY < collisions[i].maxY then
                maxY = collisions[i].maxY
            end
        end
    end
    return maxY
end


local function isWalkable(bx, by, bz)
    local gnd  = world.getBlock(bx, by - 1, bz)
    local foot = world.getBlock(bx, by,     bz)
    local head = world.getBlock(bx, by + 1, bz)

    if gnd and gnd.is_solid then
        if Core.getMaxYCollision(bx, by - 1, bz) > 1.0 then
            return false
        end
    end

    if isLadder(bx,by,bz) then
        return true
    end

    local footCollision = Core.getMaxYCollision(bx, by, bz)
    if footCollision > 0.6 then
        return false
    end
    if head and head.is_solid then return false end
    if Core.getMaxYCollision(bx,by-1,bz) + footCollision > 1 then return false end
    if Core.getMaxYCollision(bx, by + 1, bz) >= 0.5 then return false end
    if Core.getMaxYCollision(bx, by + 2, bz) > 0.5 then return false end
    if not gnd or not gnd.is_solid or gnd.is_liquid then return false end
    if foot.name:find("lava") then return false end
    return true
end



Core.debugResolveY={}

local function resolveY(cx, cy, cz, nx, nz)
    if isWalkable(nx, cy, nz) then return cy end

    if isLadder(nx, cy, nz) or isLadder(nx, cy + 1, nz) or isLadder(nx, cy + 2, nz) then
        local upY = cy
        while isLadder(nx, upY + 1, nz) do
            upY = upY + 1
        end

        if isWalkable(nx, upY + 1, nz) then
            return upY + 1
        elseif isWalkable(nx, upY, nz) then
            return upY + 1
        end
    end

    for j = 1, Core.jumpHeight do
        if Core.getMaxYCollision(cx, cy + j + 1, cz) > 0.5 then break end
        if isWalkable(nx, cy + j, nz) then
            return cy + j
        end
        if isSolid(nx, cy + j, nz) and not isWalkable(nx, cy + j + 1, nz) then break end
    end

    for d = 0, Core.fallDepth do
        local targetY = cy - d

        if isWalkable(nx, targetY, nz) then
            return targetY
        end

        if isLadder(nx, targetY, nz) then
            local slideY = targetY
            while isLadder(nx, slideY - 1, nz) do
                slideY = slideY
            end
            if isWalkable(nx, slideY - 1, nz) then
                return slideY - 1
            end
            return slideY
        end

        if isSolid(nx, targetY, nz) then 
            break 
        end
    end

    return nil
end


local function hasGroundLOS(ax, ay, az, bx, by, bz)
    local dx = bx - ax
    local dz = bz - az
    local distance = math.sqrt(dx * dx + dz * dz)
    
    if distance < 0.1 then return true end
    local steps = math.ceil(distance / 0.3)

    for i = 0, steps do
        local t = i / steps
        local curX = math.floor(ax + (dx * t) + 0.5)
        local curZ = math.floor(az + (dz * t) + 0.5)

        local ground = world.getBlock(curX, ay - 1, curZ)
        local groundCol = Core.getMaxYCollision(curX, ay - 1, curZ)

        if not ground or not ground.is_solid or groundCol < 0.1 then
            return false
        end

        local footBlock = world.getBlock(curX, ay, curZ)
        local headBlock = world.getBlock(curX, ay + 1, curZ)

        if (footBlock and footBlock.is_solid and Core.getMaxYCollision(curX, ay, curZ) > 0.5) 
            -- or (headBlock and headBlock.is_solid and Core.getMaxYCollision(curX, ay + 1, curZ) > 0.5)
        then
            return false
        end
    end

    return true
end

local Heap = {}
Heap.__index = Heap

function Heap.new()
    return setmetatable({_d = {}, _n = 0}, Heap)
end

function Heap:push(item)
    self._n = self._n + 1
    self._d[self._n] = item
    local i, d = self._n, self._d
    while i > 1 do
        local p = math.floor(i / 2)
        if d[p].f > d[i].f then d[p], d[i] = d[i], d[p]; i = p else break end
    end
end

function Heap:pop()
    if self._n == 0 then return nil end
    local top = self._d[1]
    self._d[1] = self._d[self._n]
    self._d[self._n] = nil
    self._n = self._n - 1
    local i, d, n = 1, self._d, self._n
    while true do
        local s, l, r = i, 2 * i, 2 * i + 1
        if l <= n and d[l].f < d[s].f then s = l end
        if r <= n and d[r].f < d[s].f then s = r end
        if s == i then break end
        d[i], d[s] = d[s], d[i]; i = s
    end
    return top
end

function Heap:size() return self._n end

local function smoothPath(rawPath)
    if #rawPath <= 2 then return rawPath end

    local smooth = {rawPath[1]}
    local anchor = 1
    local i      = 2
    local valid = true
    
    while i <= #rawPath do
        local a = rawPath[anchor]
        local b = rawPath[i]

        if b.y ~= a.y then
            if i - 1 > anchor then
                if b.y-a.y > Core.jumpHeight then valid = false break end
                -- print(string.format("y diff: %d", b.y-a.y))
                table.insert(smooth, rawPath[i - 1])
                anchor = i - 1
            else
                table.insert(smooth, b)
                anchor = i
                i = i + 1
            end
        else
            if not hasGroundLOS(a.x, a.y, a.z, b.x, b.y, b.z) then
                if i - 1 > anchor then
                    table.insert(smooth, rawPath[i - 1])
                    anchor = i - 1
                else
                    table.insert(smooth, b)
                    anchor = i
                    i = i + 1
                end
            else
                i = i + 1   -- LOS clear — skip the intermediate node
            end
        end
    end

    local last  = rawPath[#rawPath]
    local slast = valid and smooth[#smooth] or rawPath[#rawPath]
    if not (slast.x == last.x and slast.y == last.y and slast.z == last.z) then
        table.insert(smooth, last)
    end
    return smooth
end


local function reconstructPath(came, node)
    local raw = {}
    local cur = node
    while cur do
        table.insert(raw, 1, {x = cur.x, y = cur.y, z = cur.z})
        cur = came[key(cur.x, cur.y, cur.z)]
    end
    return raw
end


-- with this function, it's synchronous so you must run it on another thread or your mc will freeze for god know how long
-- also the commented out return raw or return partial are for unsmoothened node only path, should make it into a feature but naah
local function astarSearch(start, goal)
    local open          = Heap.new()
    local gScore        = {}
    local came          = {}
    local closed        = {}

    Core._debugExpanded = {}
    Core._debugOpen     = {}

    local sk            = key(start.x, start.y, start.z)
    gScore[sk]          = 0

    local startH        = heuristic(start.x, start.y, start.z, goal.x, goal.y, goal.z)
    open:push({
        x = start.x,
        y = start.y,
        z = start.z,
        f = startH,
        h = startH,
    })

    local bestNode   = { x = start.x, y = start.y, z = start.z }
    local bestH      = startH

    local DIRS       = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },   -- cardinal
        { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 }, -- diagonal
    }

    local expansions = 0

    while open:size() > 0 do
        expansions = expansions + 1
        if expansions > Core.maxNodes then
            local partial = reconstructPath(came, bestNode)
            if Core.smoothPath then
                return smoothPath(partial), "node limit (" .. Core.maxNodes .. ") — partial path returned"
            else
                return partial, "node limit (" .. Core.maxNodes .. ") — partial path returned"
            end
        end


        local cur = open:pop()
        local ck  = key(cur.x, cur.y, cur.z)
        if closed[ck] then goto continue end
        closed[ck] = true

        if Core.debugCapture then
            Core._debugExpanded[#Core._debugExpanded + 1] = { x = cur.x, y = cur.y, z = cur.z }
        end

        -- Update best-node tracker
        if cur.h < bestH then
            bestH    = cur.h
            bestNode = cur
        end

        if math.abs(cur.x - goal.x) <= 1
            and math.abs(cur.y - goal.y) <= 1
            and math.abs(cur.z - goal.z) <= 1 then
            local raw = reconstructPath(came, cur)
            local last = raw[#raw]
            if not (last.x == goal.x and last.y == goal.y and last.z == goal.z) then
                raw[#raw + 1] = { x = goal.x, y = goal.y, z = goal.z }
            end
            if Core.smoothPath then
                return smoothPath(raw), nil
            else
                return raw, nil
            end
        end

        local verticalDirs = { { 0, 0, 1 }, { 0, 0, -1 } } -- dx, dz, dy
        for _, vd in ipairs(verticalDirs) do
            local nx, ny, nz = cur.x, cur.y + vd[3], cur.z
            if isLadder(cur.x, cur.y, cur.z) or isLadder(nx, ny, nz) then
                local nk = key(nx, ny, nz)
                if not closed[nk] then
                    local mc = 0.5
                    local tg = (gScore[ck] or math.huge) + mc
                    if tg < (gScore[nk] or math.huge) then
                        gScore[nk] = tg
                        came[nk] = cur
                        local h = heuristic(nx, ny, nz, goal.x, goal.y, goal.z)
                        open:push({ x = nx, y = ny, z = nz, f = tg + h, h = h })
                    end
                end
            end
        end

        for _, d in ipairs(DIRS) do
            local dx, dz = d[1], d[2]
            local nx, nz = cur.x + dx, cur.z + dz
            
            local isDiagonal = (math.abs(dx) + math.abs(dz) == 2)
        
            if isDiagonal then
                if isSolid(cur.x + dx, cur.y, cur.z) or isSolid(cur.x, cur.y, cur.z + dz) then
                    goto next_dir
                end
                if isSolid(cur.x + dx, cur.y + 1, cur.z) or isSolid(cur.x, cur.y + 1, cur.z + dz) then
                    goto next_dir
                end
            end
            local ny = resolveY(cur.x, cur.y, cur.z, nx, nz)
            if ny then
                local nk = key(nx, ny, nz)
                if not closed[nk] then
                    local diagonal = (math.abs(dx) + math.abs(dz) == 2)
                    local verticalDiff = ny - cur.y

                    local onLadder = isLadder(nx, ny, nz) or isLadder(cur.x, cur.y, cur.z)

                    local fallPenalty = 0
                    local verticalSurcharge = math.abs(verticalDiff) * 0.5

                    if onLadder then
                        verticalSurcharge = math.abs(verticalDiff) * 0.1
                    elseif verticalDiff < 0 then
                        fallPenalty = math.abs(verticalDiff) * 2.0
                    end

                    local mc = (diagonal and 1.4142 or 1.0)
                        + verticalSurcharge
                        + fallPenalty

                    local tg = (gScore[ck] or math.huge) + mc

                    if tg < (gScore[nk] or math.huge) then
                        gScore[nk] = tg
                        came[nk]   = cur
                        local h    = heuristic(nx, ny, nz, goal.x, goal.y, goal.z)
                        open:push({ x = nx, y = ny, z = nz, f = tg + h, h = h })
                        if Core.debugCapture then
                            Core._debugOpen[#Core._debugOpen + 1] = { x = nx, y = ny, z = nz }
                        end
                    end
                end
            end
            ::next_dir::
        end

        ::continue::
    end

    if bestNode.x == start.x and bestNode.y == start.y and bestNode.z == start.z then
        return nil, "no path found"
    end
    local partial = reconstructPath(came, bestNode)
    if Core.smoothPath then
        return smoothPath(partial), "no path found — partial path returned"
    else
        return partial, "no path found — partial path returned"
    end
end


---Snaps a position to integer block coordinates
---@param pos {x:number, y:number, z:number}
---@return {x:number, y:number, z:number}
function Core.snapPos(pos)
    return {
        x = math.floor(pos.x),
        y = math.floor(pos.y),
        z = math.floor(pos.z),
    }
end

---Synchronously searches for a path (blocks main thread)
---@param start {x:number, y:number, z:number}
---@param goal {x:number, y:number, z:number}
---@return table|nil, string|nil
function Core.search(start, goal)
    return astarSearch(Core.snapPos(start), Core.snapPos(goal))
end

---Asynchronously searches for a path on a separate thread
---@param goal {x:number, y:number, z:number}
---@param callback fun(path:table|nil, err:string|nil)
function Core.findPath(goal, callback)
    if _lock then
        if callback then callback(nil, "search already running") end
        return
    end
    _lock = true
    threads.startThread(function()
        local s = Core.snapPos(player.getPos())
        local g = Core.snapPos(goal)
        local path, err = astarSearch(s, g)
        _lock = false
        if callback then
            callback(path, err)
            if #Core.queuedPaths >= 1 then
                Core.findPath(Core.queuedPaths[1].goal, Core.queuedPaths[1].callback)
                table.remove(Core.queuedPaths, 1)
            end
        end
    end)
end
---Queues a path search to run when current search finishes
---@param goal {x:number, y:number, z:number}
---@param callback fun(path:table|nil, err:string|nil)
function Core.queuePath(goal, callback)
    if not _lock then
        Core.findPath(goal, callback)
    else
        table.insert(Core.queuedPaths, { goal = goal, callback = callback })
    end
end

---Clears all queued path searches
function Core.clearQueue()
    Core.queuedPaths = {}
end

---Checks if a search is currently running
---@return boolean
function Core.isSearching()
    return _lock
end



return Core