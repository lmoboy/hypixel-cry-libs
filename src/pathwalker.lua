-- @version beta-0.4
-- @location /libs/

local aim = require("rotations_v3")
local pathfinder_core = require("pathfinder_core")
local smarrtieUtils   = require("smarrtieUtils")

local Walker = {}

Walker.active = false
Walker.complete = false
Walker.lookAhead = 1
Walker.lookAtPath = true
local waypoints = {}
local currentIndex = 1

Walker.stopDist = 0.5
Walker.sprintEnabled = true
Walker.sprintStartForward = 0.55
Walker.sprintKeepForward = 0.35
Walker.sprintStartDistance = 1.2
Walker.sprintKeepDistance = 1.7

Walker.forwardThreshold = 0.1
Walker.lateralThreshold = 0.1

Walker.jumpRayDistance = 1

Walker.lineFollowLookahead = 0.8

local sprintHolding = false
local sprintPressedState = false

local function setSprintPressed(state)
    if sprintPressedState ~= state then
        player.input.setPressedSprinting(state)
        sprintPressedState = state
    end
end

local function clearInputs()
    player.input.setPressedForward(false)
    player.input.setPressedBack(false)
    player.input.setPressedLeft(false)
    player.input.setPressedRight(false)
    player.input.setPressedJump(false)
    setSprintPressed(false)
    sprintHolding = false
end

local function isOnLadder()
    local pos = player.getPos()
    local bx = math.floor(pos.x)
    local by = math.floor(pos.y)
    local bz = math.floor(pos.z)

    local block = world.getBlock(bx, by, bz)
    if not block or not block.name then
        return false
    end

    return string.find(block.name, "ladder") ~= nil
end

local function needsJump(dirX, dirZ)
    local pos = player.getPos()
    local checkY = pos.y + 0.7
    local dist = 0.8

    local result = world.raycast{
        startX = pos.x, startY = checkY, startZ = pos.z,
        endX = pos.x + dirX * dist, endY = checkY, endZ = pos.z + dirZ * dist
    }

    if result and result.type == "block" then
        local bx, by, bz = result.blockPos.x, result.blockPos.y, result.blockPos.z
        local maxY = pathfinder_core.getMaxYCollision(bx, by, bz)
        if (by + maxY) > (pos.y + 0.6) then
            return true
        end
    end
    return false
end

local function insertNewPoint(ms, waypoint)
    local isNew = true
    for _, wp in pairs(waypoints) do
        if wp.x == waypoint.x and wp.y == waypoint.y and wp.z == waypoint.z then
            isNew = false
            break
        end
    end
    if isNew then table.insert(ms, {x = waypoint.x, y = waypoint.y, z = waypoint.z}) end
end

local function getClosestIndex()
    local closest = 1
    for index, wp in ipairs(waypoints) do
        if smarrtieUtils.getDistance(wp, player.getPos()) <
            smarrtieUtils.getDistance(waypoints[closest], player.getPos()) then
            closest = index
        end
    end
    return math.min(closest + 1, #waypoints)
end

-- Projects point P onto line segment AB, returns the closest point on AB
-- and the t parameter [0,1] along the segment.
local function projectOntoSegment(px, pz, ax, az, bx, bz)
    local abx = bx - ax
    local abz = bz - az
    local apx = px - ax
    local apz = pz - az
    local ab2 = abx * abx + abz * abz
    if ab2 < 0.0001 then
        return ax, az, 0
    end
    local t = (apx * abx + apz * abz) / ab2
    t = math.max(0, math.min(1, t))
    return ax + abx * t, az + abz * t, t
end

-- Returns the steering target: a point Walker.lineFollowLookahead blocks
-- ahead of the player's projection onto the current segment, clamped to the
-- segment end so we never overshoot the waypoint.
local function getLineFollowTarget(pos)
    if currentIndex <= 1 or currentIndex > #waypoints then
        -- No previous node yet; just aim at the current waypoint centre
        local wp = waypoints[currentIndex]
        if not wp then return nil end
        return wp.x + 0.5, wp.y, wp.z + 0.5
    end

    local prev = waypoints[currentIndex - 1]
    local curr = waypoints[currentIndex]

    local ax, az = prev.x + 0.5, prev.z + 0.5
    local bx, bz = curr.x + 0.5, curr.z + 0.5

    -- Project player onto the segment
    local projX, projZ, t = projectOntoSegment(pos.x, pos.z, ax, az, bx, bz)

    -- Step lookahead distance ahead along the segment
    local segLen = math.sqrt((bx - ax)^2 + (bz - az)^2)
    if segLen < 0.001 then
        return bx, curr.y, bz
    end

    local tStep = Walker.lineFollowLookahead / segLen
    local tTarget = math.min(t + tStep, 1.0)

    local targetX = ax + (bx - ax) * tTarget
    local targetZ = az + (bz - az) * tTarget

    -- Interpolate Y between the two waypoints
    local targetY = prev.y + (curr.y - prev.y) * tTarget

    return targetX, targetY, targetZ
end

function Walker.followPath(path, opts)
    if not path or #path == 0 then
        return
    end
    opts = opts or {}

    waypoints = {}
    for _, wp in ipairs(path) do
        insertNewPoint(waypoints, wp)
    end

    currentIndex = getClosestIndex()

    Walker.stopDist = opts.stopDist or 0.4
    Walker.sprintEnabled = (opts.sprint == nil) and true or opts.sprint
    Walker.jumpRayDistance = opts.jumpRayDistance or 1.5
    sprintHolding = false
    Walker.complete = false
    Walker.active = true
end

function Walker.cancel()
    Walker.active = false
    Walker.complete = false
    clearInputs()
    waypoints = {}
    currentIndex = 1
end

function Walker.walkToBlock(x, y, z, opts)
    Walker.followPath({ {x = x, y = y, z = z} }, opts)
end

registerClientTick(function()
    if not Walker.active then return end

    if #waypoints == 0 or currentIndex > #waypoints then
        Walker.active = false
        Walker.complete = true
        clearInputs()
        return
    end

    local pos = player.getPos()
    local vel = {
        x = player.velocity_x or 0,
        y = player.velocity_y or 0,
        z = player.velocity_z or 0
    }

    -- Velocity-based look-ahead to skip waypoints we're already passing
    local predictionTicks = 5
    local predictedPos = {
        x = pos.x + (vel.x * predictionTicks),
        y = pos.y + (vel.y * predictionTicks),
        z = pos.z + (vel.z * predictionTicks)
    }

    local lookAheadLimit = math.min(currentIndex + 8, #waypoints)
    for i = lookAheadLimit, currentIndex + 1, -1 do
        local wp = waypoints[i]
        local pdx = (wp.x + 0.5) - predictedPos.x
        local pdz = (wp.z + 0.5) - predictedPos.z
        local pdy = (wp.y + 0.5) - predictedPos.y
        local predDistH = math.sqrt(pdx * pdx + pdz * pdz)
        local yBuffer = (vel.y < 0) and 2.0 or 1.2
        if predDistH < (Walker.stopDist * 2.0) and math.abs(pdy) < yBuffer then
            currentIndex = i
            break
        end
    end

    -- Advance past waypoints we've reached
    local currentTarget = waypoints[currentIndex]
    local dx = (currentTarget.x + 0.5) - pos.x
    local dz = (currentTarget.z + 0.5) - pos.z
    local dy = (currentTarget.y + 0.5) - pos.y
    local horizontalDist = math.sqrt(dx * dx + dz * dz)

    if horizontalDist <= Walker.stopDist and math.abs(dy) < 1.2 then
        currentIndex = currentIndex + 1
        if currentIndex > #waypoints then
            Walker.active = false
            Walker.complete = true
            clearInputs()
            return
        end
        currentTarget = waypoints[currentIndex]
        dx = (currentTarget.x + 0.5) - pos.x
        dz = (currentTarget.z + 0.5) - pos.z
        dy = (currentTarget.y + 0.5) - pos.y
        horizontalDist = math.sqrt(dx * dx + dz * dz)
    end

    -- Ladder climb
    if isOnLadder() and dy > 0.2 then
        clearInputs()
        player.input.setPressedJump(true)
        return
    end

    -- ---------------------------------------------------------------
    -- Line-following: compute steering direction from virtual line
    -- ---------------------------------------------------------------
    local steerX, steerY, steerZ = getLineFollowTarget(pos)

    local sdx, sdz
    if steerX then
        sdx = steerX - pos.x
        sdz = steerZ - pos.z
    else
        sdx = dx
        sdz = dz
    end

    local steerDist = math.sqrt(sdx * sdx + sdz * sdz)
    local invLen = 1 / math.max(steerDist, 0.001)
    local dirX = sdx * invLen
    local dirZ = sdz * invLen
    -- ---------------------------------------------------------------

    local rot = player.getRotation()
    local yawRad = math.rad(rot.yaw or 0)
    local forwardX = -math.sin(yawRad)
    local forwardZ =  math.cos(yawRad)
    local rightX   =  math.cos(yawRad)
    local rightZ   =  math.sin(yawRad)

    local forwardComp = dirX * forwardX + dirZ * forwardZ
    local rightComp   = dirX * rightX   + dirZ * rightZ

    local speedH = math.sqrt(vel.x * vel.x + vel.z * vel.z)
    local lateralCorrectionMult = (speedH > 0.2) and 0.5 or 1.0

    player.input.setPressedForward(forwardComp > 0.2)
    player.input.setPressedBack(forwardComp < -0.3)
    player.input.setPressedLeft(rightComp > (0.3 * lateralCorrectionMult))
    player.input.setPressedRight(rightComp < (-0.3 * lateralCorrectionMult))

    if Walker.sprintEnabled then
        local shouldSprint = false
        if sprintHolding then
            shouldSprint = (forwardComp > Walker.sprintKeepForward and horizontalDist > Walker.sprintKeepDistance)
        else
            shouldSprint = (forwardComp > Walker.sprintStartForward and horizontalDist > Walker.sprintStartDistance)
        end
        if isOnLadder() then shouldSprint = false end
        setSprintPressed(shouldSprint)
        sprintHolding = shouldSprint
    else
        setSprintPressed(false)
        sprintHolding = false
    end

    if needsJump(dirX, dirZ) then
        player.input.setPressedJump(true)
    else
        player.input.setPressedJump(false)
    end
end)

aim.setModifier(7)

function Walker.isComplete()
    return Walker.complete
end


register2DRenderer(function()
    if Walker.active and Walker.lookAtPath then
        aim.update()

        local lookIndex = math.min(currentIndex + Walker.lookAhead, #waypoints)
        local lookat = waypoints[lookIndex]

        if lookat then
            aim.rotateToCoordinates(lookat.x + 0.5, lookat.y + 1.6, lookat.z + 0.5)
        end
    end
end)

return Walker