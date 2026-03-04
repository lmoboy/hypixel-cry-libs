-- @version beta-0.3
-- @location /libs/

local Core = {}

Core.maxNodes = 8000 -- haha memory leak go KABOOM<KABLOW<R.I.P MY GRANNY SHE GOT HIT BY A BAZOOKA<YEAH I THINK ABOUT HER EVERY TIME I HIT THE HOOKAH<KABLOW<KABOOM<KABLOW

Core.jumpHeight = 6
Core.smoothPath = false
Core.fallDepth = 10
Core.debugCapture = false
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
    local hair = world.getBlock(bx, by + 2, bz)

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

    if Core.getMaxYCollision(bx,by-1,bz) + footCollision > 1 then return false end
    if Core.getMaxYCollision(bx, by + 1, bz) > 0.5 then return false end
    if Core.getMaxYCollision(bx, by + 2, bz) > 0.5 then return false end
    if not gnd or not gnd.is_solid or gnd.is_liquid then return false end
    return true
end



local debugResolveY={}

local function resolveY(cx, cy, cz, nx, nz)
    if isWalkable(nx, cy, nz) then return cy end

    if isLadder(nx, cy, nz) or isLadder(nx, cy + 1, nz) then
        local upY = cy
        while isLadder(nx, upY + 1, nz) do
            upY = upY + 1
        end

        if isWalkable(nx, upY + 1, nz) then
            return upY + 1
        elseif isWalkable(nx, upY, nz) then
            return upY
        end
    end

    if Core.jumpHeight >= 1 and isWalkable(nx, cy + 1, nz) then
        return cy + 1
    end

    for d = 1, Core.fallDepth do
        local targetY = cy - d
        if debugResolveY then
            debugResolveY[#debugResolveY + 1] = {x = nx, y = targetY, z = nz}
        end

        if isWalkable(nx, targetY, nz) then
            return targetY
        end

        if isLadder(nx, targetY, nz) then
            local slideY = targetY
            while isLadder(nx, slideY - 1, nz) do
                slideY = slideY - 1
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
function Core.debugViewYResolve(ctx)
    for i, block in ipairs(debugResolveY) do
        local filled = {
            x = block.x, y = block.y, z = block.z,
            red = 255, green = 0, blue = 0, alpha = 140,
            through_walls = true
        }
        ctx.renderFilled(filled)
    end
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

    while i <= #rawPath do
        local a = rawPath[anchor]
        local b = rawPath[i]

        if b.y ~= a.y then
            if i - 1 > anchor then
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
    local slast = smooth[#smooth]
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

-- Attempts to stitch a forward partial path and a reverse partial path together.
-- Finds the closest pair of endpoints between the two paths and splices them.
-- Returns the merged path, or whichever single path was longer if no reasonable meet point exists.
local function stitchPaths(fwdPath, revPath)
    if not fwdPath or #fwdPath == 0 then
        if revPath and #revPath > 0 then
            -- reverse the reverse path so it runs start→goal direction
            local out = {}
            for i = #revPath, 1, -1 do out[#out + 1] = revPath[i] end
            return out
        end
        return nil
    end
    if not revPath or #revPath == 0 then return fwdPath end

    -- The reverse search ran from goal→start, so revPath[1] is near the goal.
    -- Flip it so it runs from its best node toward the goal.
    local revFlipped = {}
    for i = #revPath, 1, -1 do revFlipped[#revFlipped + 1] = revPath[i] end

    -- Find the closest pair of nodes between the tip of fwdPath and the tip of revFlipped.
    -- "Tip" = the end of fwdPath and the start of revFlipped (they should be closest).
    -- We do a small window search rather than O(n²) across full paths.
    local WINDOW = 10
    local fStart = math.max(1, #fwdPath - WINDOW)
    local rEnd   = math.min(#revFlipped, WINDOW)

    local bestDist = math.huge
    local bestFi, bestRi = #fwdPath, 1

    for fi = fStart, #fwdPath do
        local fp = fwdPath[fi]
        for ri = 1, rEnd do
            local rp = revFlipped[ri]
            local dx = fp.x - rp.x
            local dy = fp.y - rp.y
            local dz = fp.z - rp.z
            local d  = dx*dx + dy*dy + dz*dz
            if d < bestDist then
                bestDist = d
                bestFi   = fi
                bestRi   = ri
            end
        end
    end

    -- Only stitch if the gap is reasonable (≤ ~8 blocks manhattan-ish).
    -- If the gap is huge the paths didn't get close enough to be useful joined.
    if bestDist > 64 then
        -- Return whichever partial got closer to the other's origin.
        if #fwdPath >= #revFlipped then return fwdPath else return revFlipped end
    end

    local merged = {}
    for i = 1, bestFi do
        merged[#merged + 1] = fwdPath[i]
    end
    for i = bestRi, #revFlipped do
        merged[#merged + 1] = revFlipped[i]
    end
    return merged
end

-- with this function, it's synchronous so you must run it on another thread or your mc will freeze for god know how long
-- also the commented out return raw or return partial are for unsmoothened node only path, should make it into a feature but naah
local function astarSearch(start, goal, _isReverse)
    local open = Heap.new()
    local gScore = {}
    local came = {}
    local closed = {}

    local gx, gy, gz = goal.x, goal.y, goal.z
    local sk = key(start.x, start.y, start.z)
    gScore[sk] = 0

    local startH = heuristic(start.x, start.y, start.z, gx, gy, gz)
    open:push({ x = start.x, y = start.y, z = start.z, f = startH, h = startH })

    local bestNode = { x = start.x, y = start.y, z = start.z, h = startH }
    local expansions = 0

    local DIRS = {
        { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
        { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
    }

    while open:size() > 0 do
        expansions = expansions + 1
        if expansions > Core.maxNodes then
            local partial = reconstructPath(came, bestNode)
            if not _isReverse then
                -- Run a reverse search from goal toward start and try to stitch.
                local revPartial, revErr = astarSearch(goal, start, true)
                local merged = stitchPaths(partial, revPartial)
                local final = (Core.smoothPath and merged) and smoothPath(merged) or merged
                return final, "limit"
            end
            return Core.smoothPath and smoothPath(partial) or partial, "limit"
        end

        local cur = open:pop()
        local ck = key(cur.x, cur.y, cur.z)
        if closed[ck] then goto continue end
        closed[ck] = true

        if cur.h < bestNode.h then
            bestNode = cur
        end

        if math.abs(cur.x - gx) <= 1 and math.abs(cur.y - gy) <= 1 and math.abs(cur.z - gz) <= 1 then
            local raw = reconstructPath(came, cur)
            if not (raw[#raw].x == gx and raw[#raw].y == gy and raw[#raw].z == gz) then
                raw[#raw + 1] = { x = gx, y = gy, z = gz }
            end
            return Core.smoothPath and smoothPath(raw) or raw, nil
        end

        local verticalDirs = { { 0, 0, 1 }, { 0, 0, -1 } }
        for _, vd in ipairs(verticalDirs) do
            local nx, ny, nz = cur.x, cur.y + vd[3], cur.z
            if isLadder(cur.x, cur.y, cur.z) or isLadder(nx, ny, nz) then
                local nk = key(nx, ny, nz)
                if not closed[nk] then
                    local mc = 0.5
                    local tg = gScore[ck] + mc
                    if tg < (gScore[nk] or math.huge) then
                        gScore[nk] = tg
                        came[nk] = cur
                        local h = heuristic(nx, ny, nz, gx, gy, gz)
                        open:push({ x = nx, y = ny, z = nz, f = tg + h, h = h })
                    end
                end
            end
        end

        for _, d in ipairs(DIRS) do
            local dx, dz = d[1], d[2]
            local nx, nz = cur.x + dx, cur.z + dz

            if math.abs(dx) + math.abs(dz) == 2 then
                if not isLadder(cur.x, cur.y, cur.z) then
                    if isSolid(cur.x + dx, cur.y, cur.z) or isSolid(cur.x, cur.y, cur.z + dz) then
                        goto next_dir
                    end
                end
            end

            local ny = resolveY(cur.x, cur.y, cur.z, nx, nz)
            if ny then
                local nk = key(nx, ny, nz)
                if not closed[nk] then
                    local diagonal = (math.abs(dx) + math.abs(dz) == 2)
                    local verticalDiff = ny - cur.y
                    local groundBlock = world.getBlock(nx, ny - 1, nz)
                    
                    local preferenceBonus = 0
                    if groundBlock then
                        local name = groundBlock.name:lower()
                        if string.match(name, "slab") or string.match(name, "stairs") then
                            preferenceBonus = -0.4
                        end
                    end

                    local verticalSurcharge = 0
                    local fallPenalty = 0
                    if verticalDiff > 0 then
                        verticalSurcharge = verticalDiff * 2.0
                    elseif verticalDiff < 0 then
                        fallPenalty = math.abs(verticalDiff) * 1.5
                    end

                    local mc = (diagonal and 1.4142 or 1.0) + verticalSurcharge + fallPenalty + preferenceBonus
                    mc = math.max(mc, 0.1)
                    
                    local tg = gScore[ck] + mc
                    if tg < (gScore[nk] or math.huge) then
                        gScore[nk] = tg
                        came[nk] = cur
                        local h = heuristic(nx, ny, nz, gx, gy, gz)
                        local f = tg + h
                        open:push({ x = nx, y = ny, z = nz, f = f - (tg * 0.0001), h = h })
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

    if not _isReverse then
        -- Run a reverse search from goal toward start and try to stitch.
        local revPartial, revErr = astarSearch(goal, start, true)
        local merged = stitchPaths(partial, revPartial)
        local final = (Core.smoothPath and merged) and smoothPath(merged) or merged
        return final, "no path found - partial"
    end

    return Core.smoothPath and smoothPath(partial) or partial, "no path found - partial"
end

function Core.snapPos(pos)
    return {
        x = math.floor(pos.x),
        y = math.floor(pos.y),
        z = math.floor(pos.z),
    }
end

function Core.search(start, goal)
    return astarSearch(Core.snapPos(start), Core.snapPos(goal))
end
-- for path searching use this instead, it runs on a diff thread and has all the necessary checks in place
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
        if callback then callback(path, err) end
    end)
end

function Core.isSearching()
    return _lock
end



return Core