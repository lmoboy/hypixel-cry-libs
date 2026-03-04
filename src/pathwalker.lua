-- @version beta-0.3
-- @location /libs/

local aim = require("rotations_v3")
local pathfinder_core = require("pathfinder_core")
local smarrtieUtils   = require("smarrtieUtils")

local Walker = {}

Walker.active = false
Walker.lookAhead = 1
Walker.lookAtPath = true
local waypoints = {}
local currentIndex = 1

Walker.stopDist = 0.5
Walker.sprintEnabled = true
Walker.jumpHeight = 6 -- Global jump height capability


Walker.forwardThreshold = 0.1 
Walker.lateralThreshold = 0.1 

Walker.jumpRayDistance = 0.9 

local function clearInputs()
    player.input.setPressedForward(false)
    player.input.setPressedBack(false)
    player.input.setPressedLeft(false)
    player.input.setPressedRight(false)
    player.input.setPressedJump(false)
    player.input.setPressedSprinting(false)
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
        -- player.addMessage("Checking waypoint: " .. wp.x .. ", " .. wp.y .. ", " .. wp.z)
        if
            wp.x == waypoint.x and
            wp.y == waypoint.y and
            wp.z == waypoint.z
            -- smarrtieUtils.getDistance({wp.x, wp.y, wp.z}, {waypoint.x, waypoint.y, waypoint.z}) < 0.1
            then
            isNew = false
            break
        end
    end
    if isNew then table.insert(ms, {x = waypoint.x, y = waypoint.y, z = waypoint.z}) end
end

local function getClosestIndex()
    local closest = 1
    for index,wp in ipairs(waypoints) do
        if smarrtieUtils.getDistance(wp, player.getPos()) <
            smarrtieUtils.getDistance(waypoints[closest], player.getPos()) then
            closest = index
        end
    end
    return closest+1 -- favour the next node instead of walking back if possible
end

function Walker.followPath(path, opts)
    if not path or #path == 0 then
        return
    end
    opts = opts or {}

    waypoints = {}
    for _, wp in ipairs(path) do
        -- table.insert(waypoints, { x = wp.x, y = wp.y, z = wp.z })
        insertNewPoint(waypoints, wp)
    end

    currentIndex = getClosestIndex()

    Walker.stopDist = opts.stopDist or 0.4
    Walker.sprintEnabled = (opts.sprint == nil) and true or opts.sprint
    Walker.jumpRayDistance = opts.jumpRayDistance or 1.5

    Walker.active = true
end

function Walker.cancel()
    Walker.active = false
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
        clearInputs()
        return
    end

    local pos = player.getPos()
    local vel = {
        x = player.velocity_x or 0,
        y = player.velocity_y or 0,
        z = player.velocity_z or 0
    }
    
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
        local predDistH = math.sqrt(pdx*pdx + pdz*pdz)

        local yBuffer = (vel.y < 0) and 2.0 or 1.2

        if predDistH < (Walker.stopDist * 2.0) and math.abs(pdy) < yBuffer then
            currentIndex = i
            break
        end
    end

    local currentTarget = waypoints[currentIndex]
    local dx = (currentTarget.x + 0.5) - pos.x
    local dz = (currentTarget.z + 0.5) - pos.z
    local dy = (currentTarget.y + 0.5) - pos.y
    local horizontalDist = math.sqrt(dx*dx + dz*dz)

    if horizontalDist <= Walker.stopDist and math.abs(dy) < 1.2 then
        currentIndex = currentIndex + 1
        if currentIndex > #waypoints then
            Walker.active = false
            clearInputs()
            return
        end
        currentTarget = waypoints[currentIndex]
        dx = (currentTarget.x + 0.5) - pos.x
        dz = (currentTarget.z + 0.5) - pos.z
        dy = (currentTarget.y + 0.5) - pos.y
        horizontalDist = math.sqrt(dx*dx + dz*dz)
    end

    if isOnLadder() and dy > 0.2 then
        clearInputs()
        player.input.setPressedJump(true)
        player.input.setPressedForward(true)
        return
    end

    local invLen = 1 / math.max(horizontalDist, 0.001)
    local dirX = dx * invLen
    local dirZ = dz * invLen

    local rot = player.getRotation()
    local yawRad = math.rad(rot.yaw or 0)
    local forwardX = -math.sin(yawRad)
    local forwardZ =  math.cos(yawRad)
    local rightX   =  math.cos(yawRad)
    local rightZ   =  math.sin(yawRad)

    local forwardComp = dirX * forwardX + dirZ * forwardZ
    local rightComp   = dirX * rightX   + dirZ * rightZ

    local speedH = math.sqrt(vel.x*vel.x + vel.z*vel.z)
    local lateralCorrectionMult = (speedH > 0.2) and 0.5 or 1.0

    player.input.setPressedForward(forwardComp > 0.2)
    player.input.setPressedBack(forwardComp < -0.3)
    player.input.setPressedLeft(rightComp > (0.3 * lateralCorrectionMult)) 
    player.input.setPressedRight(rightComp < (-0.3 * lateralCorrectionMult))    

    if Walker.sprintEnabled then
        player.input.setPressedSprinting(forwardComp > 0.8 and horizontalDist > 2.0)
    else
        player.input.setPressedSprinting(false)
    end

    if needsJump(dirX, dirZ) then
        player.input.setPressedJump(true)
    else
        player.input.setPressedJump(false)
    end
end)

aim.setModifier(3)

register2DRenderer(function ()
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