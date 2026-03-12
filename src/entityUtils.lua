-- @version 0.1.4
-- @location /libs/
-- author: smarrtie

local entityUtils = {}
entityUtils.reach = 3.5 -- this one for later useage when i update the lib
entityUtils.closest = nil -- you can set this closest global instead of declaring a new variable
entityUtils.steps = 5 -- increasing this WILL make it look for more points BUT it comes at a price of performance, 3 is enough 4 is good 5 is preferred
entityUtils.filter = { [player.entity] = false } -- keyed map to filder entities out (for example bots or npcs)

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

function entityUtils.getEntitiesByName(name)
    local entities = world.getEntities()
    local scanResult = {}
    for _, entity in pairs(entities) do
        local eName = string.lower(entity.display_name)
        local cName = string.lower(name)
        if eName:find(cName) then table.insert(scanResult, entity) end
    end
    return scanResult
end

function entityUtils.getClosestEntity()
    local closest = nil
    local entities = world.getEntities()
    for _, entity in pairs(entities) do
        if not entityUtils.filterEntity(entity) then

            local hasValidBox = entity.box
                and entity.box.maxX and entity.box.minX
                and entity.box.maxY and entity.box.minY
                and entity.box.maxZ and entity.box.minZ
                and entity.box.maxX > entity.box.minX
                and entity.box.maxY > entity.box.minY
                and entity.box.maxZ > entity.box.minZ

            if entity.distance_to_player ~= 0
                and entity.health and entity.health > 0
                and hasValidBox then
                if closest == nil or entity.distance_to_player < closest.distance_to_player then
                    closest = entity
                end
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
            local hasValidBox = entity.box
                and entity.box.maxX and entity.box.minX
                and entity.box.maxY and entity.box.minY
                and entity.box.maxZ and entity.box.minZ
                and entity.box.maxX > entity.box.minX
                and entity.box.maxY > entity.box.minY
                and entity.box.maxZ > entity.box.minZ

            if entity.distance_to_player ~= 0
                and entity.health and entity.health > 0
                and hasValidBox then
                if closest == nil or entity.distance_to_player < closest.distance_to_player then
                    closest = entity
                end
            end
        end
    end
    return closest
end

local function getBoxRays(box)
    -- local box = boxP.deflate(0.1,0.1,0.1)
    local eyePos = player.getEyePosition()
    local steps = entityUtils.steps
    if not eyePos then return nil end
    local stepX = (box.maxX - box.minX) / (steps - 1)
    local stepY = (box.maxY - box.minY) / (steps - 1)
    local stepZ = (box.maxZ - box.minZ) / (steps - 1)

    local closestPoint = nil
    local minDistance = math.huge

    for ix = 1, steps - 2 do
        for iy = 1, steps - 2 do
            for iz = 1, steps - 2 do
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
                    include_entity = true, -- for some fucking reason if you include entities it forgets to return the first ray result
                })
                local isVisible = true
                if ray ~= nil then
                    -- if ray.type == "miss" then return end
                    -- local dump = ""
                    -- for k, value in pairs(ray) do
                        -- dump = dump .. tostring(k) .. " : " .. tostring(value) .. "\n"
                    -- end
                    -- print(dump)
                    if ray.type == "entity" then
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
    local hasValidBox = 
        box.maxX and box.minX
        and box.maxY and box.minY
        and box.maxZ and box.minZ
        and box.maxX > box.minX
        and box.maxY > box.minY
        and box.maxZ > box.minZ
    if not hasValidBox then return nil end

    return getBoxRays(box)
end

return entityUtils