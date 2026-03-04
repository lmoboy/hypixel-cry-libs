-- @version 0.1.0
-- @location /libs/
-- author: smarrtie

local blockUtils = {}
blockUtils.reach = 3
blockUtils.closest = nil
blockUtils.steps = 10
blockUtils.filter = {
    ["block.minecraft.air"] = false,
    ["block.minecraft.void_air"] = false,
    ["block.minecraft.bedrock"] = false,
    ["block.minecraft.oak_fence"] = true,
    ["block.minecraft.glass_pane"]=true
}

---@return boolean
function blockUtils.filterBlock(blockName)
    if blockName and blockUtils.filter[blockName] then
        return true
    end
    return false
end

function blockUtils.addToFilter(blockName)
    if blockName then blockUtils.filter[blockName] = true end
end

function blockUtils.disableFromFilter(blockName)
    if blockName then blockUtils.filter[blockName] = false end
end

function blockUtils.getDistanceTo(tx, ty, tz)
    local eyePos = player.getEyePosition()
    if not eyePos then return math.huge end
    local dx, dy, dz = tx - eyePos.x, ty - eyePos.y, tz - eyePos.z
    return math.sqrt(dx^2 + dy^2 + dz^2)
end

function blockUtils.pseudoChunkScan()
    local pPos = player.getPos()
    if pPos == nil then return {} end
    local reach = blockUtils.reach
    local scanResult = {}
    local px, py, pz = math.floor(pPos.x), math.floor(pPos.y), math.floor(pPos.z)

    for x = -reach, reach do
        for y = -reach, reach do
            for z = -reach, reach do
                local tx, ty, tz = px + x, py + y, pz + z
                local blockData = world.getBlock(tx, ty, tz)
                if blockData then
                    if blockUtils.filterBlock(blockData.name) then
                        table.insert(scanResult, {data=blockData, pos={x=tx,y=ty,z=tz}})
                    end
                end
            end
        end
    end
    return scanResult
end

function blockUtils.getClosestBlock()
    local closest = nil
    local minPadding = math.huge
    local blocks = blockUtils.pseudoChunkScan()

    for _, block in pairs(blocks) do
        -- if blockUtils.filterBlock(block.name) then
            player.addMessage(block.name)
            local dist = blockUtils.getDistanceTo(block.pos.x + 0.5, block.pos.y + 0.5, block.pos.z + 0.5)
            if dist < minPadding then
                minPadding = dist
                closest = block
            end
        -- end
    end
    return closest
end

local function getBoxRays(boxes, targetPos)
    local eyePos = player.getEyePosition()
    if not eyePos or not boxes then return nil end

    local closestPoint = nil
    local minDistanceSq = math.huge
    local steps = blockUtils.steps

    for i = 1, #boxes do
        local box = boxes[i]
        
        -- Calculate step sizes
        local stepX = (box.maxX - box.minX) / math.max(1, steps - 1)
        local stepY = (box.maxY - box.minY) / math.max(1, steps - 1)
        local stepZ = (box.maxZ - box.minZ) / math.max(1, steps - 1)

        for ix = 0, steps - 1 do
            for iy = 0, steps - 1 do
                for iz = 0, steps - 1 do
                    local px = box.minX + (ix * stepX) + targetPos.x
                    local py = box.minY + (iy * stepY) + targetPos.y
                    local pz = box.minZ + (iz * stepZ) + targetPos.z
                    -- player.addMessage(string.format("x: %d, y: %d, z: %d",px,py,pz))
                    local ray = world.raycast({
                        startX = eyePos.x, startY = eyePos.y, startZ = eyePos.z,
                        endX = px, endY = py, endZ = pz
                    })

                    -- Check if the ray actually hit our target block coordinates
                    if ray and ray.type == "block"
                        and
                       ray.blockPos.x == targetPos.x and
                       ray.blockPos.y == targetPos.y and
                        ray.blockPos.z == targetPos.z
                       then

                        local distSq = (eyePos.x - px)^2 + (eyePos.y - py)^2 + (eyePos.z - pz)^2
                        if distSq < minDistanceSq then
                            minDistanceSq = distSq
                            closestPoint = { x = px, y = py, z = pz }
                        end
                    end
                end
            end
        end
    end
    return closestPoint
end

function blockUtils.getClosestHitbox(block)
    if not block or not block.pos then return nil end
    local boxes = world.getOutlineBoxes(block.pos.x, block.pos.y, block.pos.z, block.data)
    if not boxes or #boxes == 0 then return nil end
    return getBoxRays(boxes, block.pos)
end

return blockUtils