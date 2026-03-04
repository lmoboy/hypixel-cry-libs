-- @version 0.1.2
-- @location /libs/
-- author: smarrtie

local entityUtils = {}
entityUtils.reach = 0 -- this one for later useage when i update the lib
entityUtils.closest = nil -- you can set this closest global instead of declaring a new variable
entityUtils.steps = 5 -- increasing this WILL make it look for more points BUT it comes at a price of performance, 3 is enough 4 is good 5 is preferred
entityUtils.filter = { [player.entity] = true } -- keyed map to filder entities out (for example bots or npcs)

---@return boolean returns TRUE if entity is in the files
function entityUtils.filterEntity(entity)
    if entity and entityUtils.filter[entity] then
        return true
    end
    return false
end

function entityUtils.addToFilter(entity)
    if entity then
        entityUtils.filter[entity] = true
    end
end

function entityUtils.removeFromFilter(entity)
    if entity then
        entityUtils.filter[entity] = false
    end
end

function entityUtils.getClosestEntity()
    local closest = nil
    local entities = world.getEntities()
    for _, entity in pairs(entities) do
        if not entityUtils.filterEntity(entity) then
            if closest == nil then
                closest = entity
            end
            if entity.distance_to_player < closest.distance_to_player then
                closest = entity
            end
        end
    end
    return closest
end

function entityUtils.getClosestLivingEntity()
    local closest = nil
    local entities = world.getLivingEntities()
    for _, entity in pairs(entities) do
        if not entityUtils.filterEntity(entity) then
            if entity.distance_to_player == 0 then return end
            if closest == nil then
                closest = entity
            end
            if entity.distance_to_player < closest.distance_to_player then
                closest = entity
            end
        end
    end
    return closest
end

local function getBoxRays(box, type)
    -- local box = boxP.deflate(0.1,0.1,0.1)
    local eyePos = player.getEyePosition()
    local steps = entityUtils.steps
    if not eyePos then return nil end
    local stepX = (box.maxX - box.minX) / (steps - 1)
    local stepY = (box.maxY - box.minY) / (steps - 1)
    local stepZ = (box.maxZ - box.minZ) / (steps - 1)

    local closestPoint = nil
    local minDistance = math.huge

    for ix = 0, steps - 1 do
        for iy = 0, steps - 1 do
            for iz = 0, steps - 1 do
                local px = box.minX + (ix * stepX)
                local py = box.minY + (iy * stepY)
                local pz = box.minZ + (iz * stepZ)
                local ray = world.raycast({
                    startX = eyePos.x,
                    startY = eyePos.y,
                    startZ = eyePos.z,
                    endX = px,
                    endY = py,
                    endZ = pz,
                    include_entity = (type == "entity"), -- for some fucking reason if you include entities it forgets to return the first ray 
                })
                local testRay = world.raycast({ -- so we do some of double checking which effectively doubles our raycount and giving performance of a potato
                    startX = eyePos.x,
                    startY = eyePos.y,
                    startZ = eyePos.z,
                    endX = px,
                    endY = py,
                    endZ = pz
                })
                local isVisible = false
                if ray ~= nil then
                    if ray.type == type and testRay.type == "miss"  then
                        isVisible = true
                    end
                end

                if isVisible then
                    local dx, dy, dz = eyePos.x - px, eyePos.y - py, eyePos.z - pz
                    local distSq = (dx * dx) + (dy * dy) + (dz * dz)

                    if distSq < minDistance then
                        minDistance = distSq
                        closestPoint = { x = px, y = py, z = pz }
                    end
                end
            end
        end
    end
    return closestPoint
end

function entityUtils.getClosestHitbox(entity)
    if not entity or not entity.box then
        return nil
    end

    local box = entity.box
    local closestPoint = getBoxRays(box,"entity")
    return closestPoint
end

return entityUtils