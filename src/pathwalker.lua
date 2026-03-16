-- @version beta-0.4
-- @location /libs/

local aim             = require("rotations_v3")
local pathfinder_core = require("pathfinder_core")
local util            = require("smarrtieUtils")

local Walker = {}

-- ============================================================
-- Public config
-- ============================================================
Walker.active          = false
Walker.complete        = false
Walker.lookAhead       = 1
Walker.lookAtPath      = true
Walker.recheckNode     = true

Walker.stopDist        = 0.7
Walker.sprintEnabled   = true
Walker.jumpRayDistance = 0.9
Walker.fallRecoverDist = 6

Walker.sprintForwardMin  = 0.8
Walker.sprintDistMin     = 2.0

-- Stuck detection (exposed so external scripts can read)
Walker.stuckTicks    = 0
Walker.STUCK_THRESH  = 8
Walker.STUCK_DIST    = 0.05

-- ============================================================
-- Private state
-- ============================================================
local waypoints   = {}
local currentIndex = 1
local lastPos      = nil

-- ============================================================
-- Input helpers
-- ============================================================
local function clearInputs()
    player.input.setPressedForward(false)
    player.input.setPressedBack(false)
    player.input.setPressedLeft(false)
    player.input.setPressedRight(false)
    player.input.setPressedJump(false)
    player.input.setPressedSprinting(false)
end

-- ============================================================
-- World queries
-- ============================================================
local function getBlockAt(pos)
    return world.getBlock(math.floor(pos.x), math.floor(pos.y), math.floor(pos.z))
end

local function isOnLadder()
    local pos = player.getPos()
    if not pos then return false end
    local b = getBlockAt(pos)
    return b and b.name and b.name:find("ladder") ~= nil
end

local function isInWater()
    local pos = player.getPos()
    if not pos then return false end
    local b = getBlockAt(pos)
    return b and b.name and b.name:find("water") ~= nil
end

local function hasChainLoS(fromIdx, toIdx)
    for i = fromIdx, toIdx - 1 do
        local a, b = waypoints[i], waypoints[i + 1]
        if not a or not b then return false end
        local r = world.raycast{
            startX = a.x+0.5, startY = a.y+0.5, startZ = a.z+0.5,
            endX   = b.x+0.5, endY   = b.y+0.5, endZ   = b.z+0.5,
        }
        if r and r.type == "block" then return false end
    end
    return true
end

local function needsJump(dirX, dirZ, horizontalDist)
    local pos = player.getPos()
    if not pos then return false end
    if not player.isOnGround() and not isInWater() then return false end

    local nearNode = horizontalDist <= 2.0
    local isStuck  = Walker.stuckTicks >= Walker.STUCK_THRESH
    if not nearNode and not isStuck then return false end

    local r = world.raycast{
        startX = pos.x, startY = pos.y + 0.7, startZ = pos.z,
        endX   = pos.x + dirX * Walker.jumpRayDistance,
        endY   = pos.y + 0.7,
        endZ   = pos.z + dirZ * Walker.jumpRayDistance,
    }
    if r and r.type == "block" then
        local bp   = r.blockPos
        local maxY = pathfinder_core.getMaxYCollision(bp.x, bp.y, bp.z)
        local hdiff = (bp.y + maxY) - pos.y
        if hdiff > 0.1 and hdiff <= 1.5 then
            if isStuck then Walker.stuckTicks = 0 end
            return true
        end
    end
    return false
end

-- ============================================================
-- Public API
-- ============================================================
function Walker.getClosestNode(fromPos)
    if #waypoints == 0 then return 1 end
    fromPos = fromPos or player.getPos()
    local best, bestDist = 1, math.huge
    for i, wp in ipairs(waypoints) do
        local d = util.getDistance(wp, fromPos)
        if d < bestDist then bestDist, best = d, i end
    end
    return math.min(best + 1, #waypoints)
end

function Walker.followPath(path, opts)
    if not path or #path == 0 then Walker.cancel(); return end
    opts = opts or {}
    waypoints = {}
    for _, wp in ipairs(path) do
        waypoints[#waypoints+1] = { x=wp.x, y=wp.y, z=wp.z }
    end
    currentIndex           = Walker.getClosestNode()
    Walker.stopDist        = opts.stopDist      or 0.4
    Walker.sprintEnabled   = opts.sprint == nil and true or opts.sprint
    Walker.jumpRayDistance = opts.jumpRayDistance or 1.5
    Walker.stuckTicks      = 0
    lastPos                = nil
    Walker.complete        = false
    Walker.active          = true
end

function Walker.cancel()
    Walker.active   = false
    Walker.complete = false
    Walker.stuckTicks = 0
    lastPos = nil
    clearInputs()
    waypoints     = {}
    currentIndex  = 1
end

function Walker.walkToBlock(x, y, z, opts)
    Walker.followPath({{ x=x, y=y, z=z }}, opts)
end

function Walker.isComplete() return Walker.complete end

-- ============================================================
-- Tick
-- ============================================================
registerClientTick(function()
    if not Walker.active then return end

    if #waypoints == 0 or currentIndex > #waypoints then
        Walker.active   = false
        Walker.complete = true
        clearInputs()
        return
    end

    local pos = player.getPos()
    if not pos then return end

    local vel = {
        x = player.velocity_x or 0,
        y = player.velocity_y or 0,
        z = player.velocity_z or 0,
    }

    -- ── Stuck detection ───────────────────────────────────────
    if lastPos then
        local moved = math.sqrt((pos.x-lastPos.x)^2 + (pos.z-lastPos.z)^2)
        Walker.stuckTicks = moved < Walker.STUCK_DIST and Walker.stuckTicks + 1 or 0
    end
    lastPos = { x=pos.x, y=pos.y, z=pos.z }

    -- ── Fall recovery ─────────────────────────────────────────
    local cwp = waypoints[currentIndex]
    if cwp then
        local fd = math.sqrt(
            ((cwp.x+0.5)-pos.x)^2 +
            ((cwp.z+0.5)-pos.z)^2 +
            ((cwp.y+0.5)-pos.y)^2
        )
        if fd > Walker.fallRecoverDist then
            currentIndex      = Walker.getClosestNode(pos)
            Walker.stuckTicks = 0
        end
    end

    -- ── Velocity-predicted lookahead with chain LOS ───────────
    -- local predPos = {
    --     x = pos.x + vel.x * 3,
    --     y = pos.y + vel.y * 3,
    --     z = pos.z + vel.z * 3,
    -- }
    -- local yBuffer    = vel.y < 0 and 2.0 or 1.5
    -- local skipLimit  = math.min(currentIndex + 6, #waypoints)
    -- for i = skipLimit, currentIndex + 1, -1 do
    --     local wp  = waypoints[i]
    --     local pdx = (wp.x+0.5) - predPos.x
    --     local pdz = (wp.z+0.5) - predPos.z
    --     local pdy = (wp.y+0.5) - predPos.y
    --     if math.sqrt(pdx*pdx + pdz*pdz) < Walker.stopDist * 2.0
    --        and math.abs(pdy) < yBuffer
    --        and hasChainLoS(currentIndex, i)
    --     then
    --         currentIndex = i
    --         break
    --     end
    -- end

    -- ── Advance past reached node ─────────────────────────────
    local function refreshTarget()
        local wp = waypoints[currentIndex]
        if not wp then return nil, 0, 0, 0, 0 end
        local ddx = (wp.x+0.5) - pos.x
        local ddz = (wp.z+0.5) - pos.z
        local ddy = wp.y       - pos.y
        return wp, ddx, ddz, ddy, math.sqrt(ddx*ddx + ddz*ddz)
    end

    local target, dx, dz, dy, hDist = refreshTarget()
    if not target then
        Walker.active = false; Walker.complete = true; clearInputs(); return
    end

    if hDist <= Walker.stopDist and math.abs(dy) < 1.5 then
        currentIndex = currentIndex + 1
        if currentIndex > #waypoints then
            Walker.active = false; Walker.complete = true; clearInputs(); return
        end
        target, dx, dz, dy, hDist = refreshTarget()
        if not target then
            Walker.active = false; Walker.complete = true; clearInputs(); return
        end
    end

    Walker.currentIndex = currentIndex  -- keep public field in sync

    -- ── Ladder ────────────────────────────────────────────────
    if isOnLadder() and dy > 0.2 then
        clearInputs()
        player.input.setPressedJump(true)
        local cx   = math.floor(pos.x) + 0.5
        local cz   = math.floor(pos.z) + 0.5
        local offX = cx - pos.x
        local offZ = cz - pos.z
        local yaw  = math.rad((player.getRotation() or {}).yaw or 0)
        local fC   = offX * (-math.sin(yaw)) + offZ * math.cos(yaw)
        local rC   = offX *   math.cos(yaw)  + offZ * math.sin(yaw)
        local thr  = 0.1
        player.input.setPressedForward(fC >  thr)
        player.input.setPressedBack   (fC < -thr)
        player.input.setPressedLeft   (rC >  thr)
        player.input.setPressedRight  (rC < -thr)
        return
    end

    -- ── Water ─────────────────────────────────────────────────
    if isInWater() then
        player.input.setPressedJump(dy > 0.0)
        -- fall through so horizontal steering still applies
    end

    -- ── Direction decomposition ───────────────────────────────
    local inv  = 1 / math.max(hDist, 0.001)
    local dirX = dx * inv
    local dirZ = dz * inv

    local yaw      = math.rad((player.getRotation() or {}).yaw or 0)
    local fwdX     = -math.sin(yaw)
    local fwdZ     =  math.cos(yaw)
    local fwdComp  = dirX * fwdX           + dirZ * fwdZ
    local rgtComp  = dirX * math.cos(yaw)  + dirZ * math.sin(yaw)

    local speedH   = math.sqrt(vel.x*vel.x + vel.z*vel.z)
    local latMult  = speedH > 0.2 and 0.5 or 1.0

    player.input.setPressedForward(fwdComp >  0.2)
    player.input.setPressedBack   (fwdComp < -0.3)
    player.input.setPressedLeft   (rgtComp >  0.3 * latMult)
    player.input.setPressedRight  (rgtComp < -0.3 * latMult)

    -- ── Sprint ────────────────────────────────────────────────
    player.input.setPressedSprinting(
        Walker.sprintEnabled
        and not isOnLadder()
        and fwdComp > Walker.sprintForwardMin
        and hDist   > Walker.sprintDistMin
    )

    -- ── Jump ─────────────────────────────────────────────────
    if not isInWater() then
        player.input.setPressedJump(needsJump(dirX, dirZ, hDist))
    end
end)

aim.setModifier(2)

register2DRenderer(function()
    if not Walker.active or not Walker.lookAtPath then return end
    aim.update()
    local li = math.min(currentIndex + Walker.lookAhead, #waypoints)
    local wp = waypoints[li]
    if wp then
        aim.rotateToCoordinates(wp.x+0.5, wp.y+1.6, wp.z+0.5)
    end
end)

return Walker