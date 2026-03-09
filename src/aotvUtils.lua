-- @version 1.1
-- @location /libs/

local rotations = require("libs/rotations_v3")
local inventory = require("libs/inventory_utils")

local aotvUtils = {
    isActive = false,
    state = "IDLE",
    timer = 0,
    clickDelayRemaining = 0,
    rotateTimeRemaining = 0,
    targetPos = {x = 0, y = 0, z = 0}
}

-- WARNING: player.input.setSelectedSlot() and other movement/input functions 
-- MUST be called from a tick thread (e.g., registerClientTick) to function correctly.
-- Calling them directly from a command callback will return false and fail.

--- Initiates the AOTV process to a specific block
-- @param x Target X coordinate
-- @param y Target Y coordinate
-- @param z Target Z coordinate
-- @param rotateTime Time in ticks to wait/allow for the rotation to complete
-- @param clickDelay Time in ticks to delay between crouching and clicking
-- @param yaw Optional custom yaw
-- @param pitch Optional custom pitch
function aotvUtils.aotv(x, y, z, rotateTime, clickDelay, yaw, pitch)
    if aotvUtils.isActive then 
        return false 
    end
    
    aotvUtils.targetPos = {x = x, y = y, z = z}
    aotvUtils.targetYaw = yaw
    aotvUtils.targetPitch = pitch
    aotvUtils.rotateTimeRemaining = rotateTime or 15
    aotvUtils.clickDelayRemaining = clickDelay or 5
    
    aotvUtils.isActive = true
    aotvUtils.state = "PREPARING"
    aotvUtils.timer = 1 -- Trigger next tick
    
    return true
end

-- Tick hook to process the aotv sequence states
registerClientTick(function()
    if not aotvUtils.isActive then return end
    
    if aotvUtils.state == "PREPARING" then
        -- Perform slot swap on the main thread
        local aotvSlot = inventory.findItemByDisplayNameInHotbar("Aspect of the Void")
        if aotvSlot == -1 then
            aotvSlot = inventory.findItemByDisplayNameInHotbar("Aspect of the End")
        end

        if aotvSlot == -1 then
            player.addMessage("§c[AOTV] Error: Aspect of the Void/End not found in hotbar!")
            aotvUtils.isActive = false
            aotvUtils.state = "IDLE"
            return
        end

        -- Start sneaking
        player.input.setPressedSneak(true)
        -- Swap item
        player.input.setSelectedSlot(math.floor(aotvSlot))
        
        -- Start rotation
        local pos = aotvUtils.targetPos
        rotations.setModifier(5) -- Set a reasonable speed for AOTV
        if aotvUtils.targetYaw and aotvUtils.targetPitch then
            rotations.setTargetRotation(aotvUtils.targetYaw, aotvUtils.targetPitch)
        else
            rotations.rotateToCoordinates(pos.x, pos.y, pos.z)
        end
        
        aotvUtils.state = "ROTATING"
        aotvUtils.timer = 2 -- Small buffer for the swap to register server-side

    elseif aotvUtils.state == "ROTATING" then
        aotvUtils.rotateTimeRemaining = aotvUtils.rotateTimeRemaining - 1
        
        -- Transition if rotation is done OR timeout reached
        if (not rotations.isRotating() and aotvUtils.rotateTimeRemaining <= 0) or aotvUtils.rotateTimeRemaining < -40 then
            aotvUtils.state = "WAITING_CLICK"
            -- player.input.setPressedSneak(true)
            aotvUtils.timer = 3
        end
    -- elseif aotvUtils.state == "SNEAKING" then
    --     aotvUtils.timer = aotvUtils.timer - 1
    --     if aotvUtils.timer <= 0 then
    --         aotvUtils.state = "WAITING_CLICK"
    --         aotvUtils.timer = aotvUtils.clickDelayRemaining
    --     end
    elseif aotvUtils.state == "WAITING_CLICK" then
        aotvUtils.timer = aotvUtils.timer - 1
        if aotvUtils.timer <= 0 then
            player.input.rightClick()
            aotvUtils.state = "CLEANUP"
            aotvUtils.timer = 5
        end
    elseif aotvUtils.state == "CLEANUP" then
        aotvUtils.timer = aotvUtils.timer - 1
        if aotvUtils.timer <= 0 then
            player.input.setPressedSneak(false)
            aotvUtils.isActive = false
            aotvUtils.state = "IDLE"
        end
    end
end)

register2DRenderer(function()
    if aotvUtils.isActive then
        rotations.update()
    end
end)

return aotvUtils
