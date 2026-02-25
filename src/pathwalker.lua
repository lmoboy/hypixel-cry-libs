-- @version beta-0.1
-- @location /libs/

--#region
-- THIS IS A BETA LIB
-- the only reason this lib is out and about is because i want to see what people will come up with
-- it is bad and it is a huge subject to change especially from more experienced developers than me
-- refer to example in scripts to figure out how to properly use this
--# 

local aim = require("rotations_v3")

local Walker = {}

Walker.active = false -- global for example purposes, doesn't really do anythin
local waypoints = {}
local currentIndex = 1

local stopDist = 0.35
local sprintEnabled = true

local forwardThreshold = 0.1 -- the higher the less it will compensate, setting it too low is also bad so yk
local lateralThreshold = 0.1 -- same as ^^ 

local jumpRayDistance = 1.5 -- really should be doing more than just raycasting but it's enough it's whatever

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

    local block = world.getBlockState(bx, by, bz)
    if not block or not block.name then
        return false
    end

    return string.find(block.name, "ladder") ~= nil
end

local function needsJump(dirX, dirZ)
    local pos = player.getPos()
    local eyeY = pos.y + 0.6   -- just above step height

    local endX = pos.x + dirX * jumpRayDistance
    local endZ = pos.z + dirZ * jumpRayDistance

    local result = world.raycast{
        startX = pos.x, startY = eyeY, startZ = pos.z,
        endX   = endX,   endY   = eyeY, endZ   = endZ
    }

    if result and result.type == "block" then
        local bx = result.blockPos.x
        local by = result.blockPos.y
        local bz = result.blockPos.z
        local blockState = world.getBlock(bx, by, bz)
        if blockState then
            local boxes = world.getCollisionBoxes(bx, by, bz, blockState)
            if boxes then
                local stepHeight = pos.y + 0.5
                for _, box in ipairs(boxes) do
                    if box.maxY > stepHeight then
                        return true
                    end
                end
            end
        end
    end
    return false
end


function Walker.followPath(path, opts)
    if not path or #path == 0 then
        return
    end
    opts = opts or {}

    waypoints = {}
    for _, wp in ipairs(path) do
        table.insert(waypoints, { x = wp.x, y = wp.y, z = wp.z })
    end
    currentIndex = 1

    stopDist = opts.stopDist or 0.35
    sprintEnabled = (opts.sprint == nil) and true or opts.sprint
    jumpRayDistance = opts.jumpRayDistance or 1.5

    Walker.active = true
end

function Walker.cancel()
    Walker.active = false
    clearInputs()
    waypoints = {}
    currentIndex = 1
end

function Walker.walkToBlock(x, y, z, opts) -- probably better to use this if you are going to implement your own pathfinding algorithm
    Walker.followPath({ {x = x, y = y, z = z} }, opts)
end


local pressForward, pressBack, pressRight, pressLeft
local currentTarget
registerClientTick(function()
    if not Walker.active then return end

    if #waypoints == 0 or currentIndex > #waypoints then
        Walker.active = false
        clearInputs()
        return
    end

    currentTarget = waypoints[currentIndex]
    local targetX = currentTarget.x + 0.5
    local targetY = currentTarget.y + 0.5
    local targetZ = currentTarget.z + 0.5

    local pos = player.getPos()
    local rot = player.getRotation()

    local dx = targetX - pos.x
    local dz = targetZ - pos.z
    local dy = targetY - pos.y

    local horizontalDist = math.sqrt(dx*dx + dz*dz)

    if horizontalDist <= stopDist and math.abs(dy) < 0.6 then
        currentIndex = currentIndex + 1
        if currentIndex > #waypoints then
            Walker.active = false
            clearInputs()
        end
        return
    end

    if isOnLadder() and dy > 0.2 then
        clearInputs()
        player.input.setPressedJump(true)
        return
    end

    local invLen = 1 / math.max(horizontalDist, 0.0001)
    local dirX = dx * invLen
    local dirZ = dz * invLen

    local yawRad = math.rad(rot.yaw or 0)
    local forwardX = -math.sin(yawRad)
    local forwardZ =  math.cos(yawRad)
    local rightX   =  math.cos(yawRad)
    local rightZ   =  math.sin(yawRad)

    local forwardComp = dirX * forwardX + dirZ * forwardZ
    local rightComp   = dirX * rightX   + dirZ * rightZ

    pressForward = (forwardComp > forwardThreshold)
    pressBack    = (forwardComp < -forwardThreshold)
    pressLeft    = (rightComp > lateralThreshold)
    pressRight   = (rightComp < -lateralThreshold)

    player.input.setPressedForward(pressForward)
    player.input.setPressedBack(pressBack)
    player.input.setPressedRight(pressRight)
    player.input.setPressedLeft(pressLeft)

    if sprintEnabled then
        player.input.setPressedSprinting(forwardComp > 0.8 and horizontalDist > 1.5)
    else
        player.input.setPressedSprinting(false)
    end

    if pressForward and needsJump(dirX, dirZ) and (dy >= 1 or dy == -1) then
        player.input.setPressedJump(true)
    else
        player.input.setPressedJump(false)
    end
end)

register2DRenderer(function ()
    aim.setModifier(4)
    aim.update()
    local lookat = waypoints[currentIndex + 2]
    if not lookat and currentIndex == #waypoints then lookat = waypoints[currentIndex] end
    aim.rotateToCoordinates(lookat.x+0.5, lookat.y+1.6, lookat.z+0.5)
end)


return Walker