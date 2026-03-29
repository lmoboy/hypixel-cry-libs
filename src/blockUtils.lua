-- @version 0.1.1
-- @location /libs/
-- @author smarrtie
-- @description Block utility library for finding, filtering, and interacting with Minecraft blocks

local player = require("player")
local world = require("world")
local smarrtieUtils = require("smarrtieUtils")

---@class BlockUtils
---@field reach number The reach distance for block interactions
---@field closest table|nil The closest block found
---@field steps number Number of raycast steps for hitbox checking (higher = more accurate but slower)
---@field filter table Keyed map of block names to filter (true = include, false = exclude)
---@field filterBlock function(blockName: string): boolean Check if block should be included
---@field addToFilter function(blockName: string) Add a block to the include filter
---@field disableFromFilter function(blockName: string) Remove a block from the include filter
---@field getDistanceTo function(tx: number, ty: number, tz: number): number Get distance to coordinates
---@field pseudoChunkScan function(): table Scan nearby blocks within reach
---@field getClosestBlock function(): table|nil Get closest block within reach
---@field getClosestRotationBlock function(): table|nil Get closest block that requires minimal rotation
---@field getClosestBlockSide function(pos: table, block: table): table|nil Get closest point on block hitbox
---@field getClosestHitbox function(block: table): table|nil Get closest visible hitbox point

---@type BlockUtils
local blockUtils = {}
blockUtils.reach = 3
blockUtils.closest = nil
blockUtils.steps = 4
blockUtils.filter = {
    ["block.minecraft.air"] = false,
    ["block.minecraft.void_air"] = false,
    ["block.minecraft.bedrock"] = false,
    ["block.minecraft.oak_fence"] = false,
    ["block.minecraft.glass_pane"] = false,
    ["block.minecraft.cyan_terracotta"] = true,
    ["block.minecraft.gray_wool"] = true,
    ["block.minecraft.dark_prismarine"] = true,
    ["block.minecraft.polished_diorite"] = true,
    ["block.minecraft.prismarine_bricks"] = true,
    ["block.minecraft.prismarine"] = true,
    ["block.minecraft.light_blue_wool"] = true,
}

---Check if a block should be included in scan results
---@param blockName string The block name to check
---@return boolean True if block should be included
function blockUtils.filterBlock(blockName)
    if blockName and blockUtils.filter[blockName] then
        return true
    end
    return false
end

---Add a block to the include filter
---@param blockName string The block name to add
function blockUtils.addToFilter(blockName)
    if blockName then blockUtils.filter[blockName] = true end
end

---Remove a block from the include filter
---@param blockName string The block name to remove
function blockUtils.disableFromFilter(blockName)
    if blockName then blockUtils.filter[blockName] = false end
end

---Calculate distance from player eye position to target coordinates
---@param tx number Target X coordinate
---@param ty number Target Y coordinate
---@param tz number Target Z coordinate
---@return number The distance, or math.huge if player position unavailable
function blockUtils.getDistanceTo(tx, ty, tz)
    local eyePos = player.getEyePosition()
    if not eyePos then return math.huge end
    local dx, dy, dz = tx - eyePos.x, ty - eyePos.y, tz - eyePos.z
    return math.sqrt(dx^2 + dy^2 + dz^2)
end

---Scan blocks within reach distance and return filtered blocks
---@return table Array of block data tables with {data, pos}
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

---Get the closest block that is within reach and visible
---@return table|nil The closest block data {data, pos}
function blockUtils.getClosestBlock()
    local closest = nil
    local minPadding = math.huge
    local blocks = blockUtils.pseudoChunkScan()
    local eyePos = player.getEyePosition()
    for _, block in pairs(blocks) do
        -- if blockUtils.filterBlock(block.name) then
            -- player.addMessage(block.name)
            local cast = world.raycast(
                {
                    startX = eyePos.x,
                    startY = eyePos.y,
                    startZ = eyePos.z,
                endX=block.pos.x + 0.5,
                endY=block.pos.y + 0.5,
                endZ=block.pos.z + 0.5
            })
            local dist = blockUtils.getDistanceTo(block.pos.x + 0.5, block.pos.y + 0.5,
                block.pos.z + 0.5)
            if dist < minPadding and cast.type == "block" and 
                cast.blockPos.x == block.pos.x and
                cast.blockPos.y == block.pos.y and
                cast.blockPos.z == block.pos.z
            then
                minPadding = dist
                -- print(dist .. " : " .. adjacentBlock.name)
                closest = block
            end
        -- end
    end
    return closest
end




---Get the closest block that requires minimal rotation to look at
---@return table|nil Block data {data, pos} closest to current view angle
function blockUtils.getClosestRotationBlock()
    local pPos = player.getEyePosition()
    if not pPos then return nil end

    local curRot = player.getRotation()
    if not curRot then return nil end

    local reach = blockUtils.reach
    local px, py, pz = math.floor(pPos.x), math.floor(pPos.y), math.floor(pPos.z)
    local eyePos = player.getEyePosition()

    local best = nil
    local bestAngle = math.huge

    for dx = -reach, reach do
        for dy = -reach, reach do
            for dz = -reach, reach do
                local tx, ty, tz = px + dx, py + dy, pz + dz
                local blockData = world.getBlock(tx, ty, tz)

                if blockData and blockUtils.filterBlock(blockData.name) then
                    -- Aim at center X/Z; clamp Y so pitch stays within ±reach of eye
                    local aimX = tx + 0.5
                    local aimY = ty + 0.5
                    local aimZ = tz + 0.5

                    -- Only consider blocks the player can actually hit with a raycast
                    local cast = world.raycast({
                        startX = eyePos.x,
                        startY = eyePos.y,
                        startZ = eyePos.z,
                        endX = aimX,
                        endY = aimY,
                        endZ = aimZ,
                    })

                    if cast and cast.type == "block"
                        and cast.blockPos.x == tx
                        and cast.blockPos.y == ty
                        and cast.blockPos.z == tz
                    then
                        local blockRot = world.getRotation(aimX, aimY, aimZ)
                        if blockRot then
                            -- Shortest angular distance on the yaw circle (result: 0–180)
                            local yawDiff    = math.abs((blockRot.yaw - curRot.yaw + 180) % 360 - 180)
                            local pitchDiff  = math.abs(blockRot.pitch - curRot.pitch)
                            local totalAngle = yawDiff + pitchDiff

                            if totalAngle < bestAngle then
                                bestAngle = totalAngle
                                best = {
                                    data = blockData,
                                    pos  = { x = tx, y = ty, z = tz },
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return best
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

        for ix = 1, steps - 2 do
            for iy = 1, steps - 2 do
                for iz = 1, steps - 2 do
                    local px = box.minX + (ix * stepX) + targetPos.x
                    local py = box.minY + (iy * stepY) + targetPos.y
                    local pz = box.minZ + (iz * stepZ) + targetPos.z
                    -- player.addMessage(string.format("x: %d, y: %d, z: %d",px,py,pz))
                    local ray = world.raycast({
                        startX = eyePos.x,
                        startY = eyePos.y,
                        startZ = eyePos.z,
                        endX = px,
                        endY = py,
                        endZ = pz
                    })

                    -- Check if the ray actually hit our target block coordinates
                    if ray and ray.type == "block"
                        and
                        ray.blockPos.x == targetPos.x and
                        ray.blockPos.y == targetPos.y and
                        ray.blockPos.z == targetPos.z
                    then
                        local distSq = (eyePos.x - px) ^ 2 + (eyePos.y - py) ^ 2 + (eyePos.z - pz) ^ 2
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

function blockUtils.getClosestBlockSide(pos, block)
    if not pos or not block.pos then return nil end
    local blockPos = block.pos
    
    local blockState = world.getBlock(blockPos.x, blockPos.y, blockPos.z)
    local boxes = world.getOutlineBoxes(blockPos.x, blockPos.y, blockPos.z, blockState)
    if not boxes or #boxes == 0 then return nil end
 
    local bestPoint = nil
    local bestDistSq = math.huge
 
    for i = 1, #boxes do
        local box = boxes[i]
 
        -- World-space AABB min/max
        local minX = box.minX + blockPos.x
        local minY = box.minY + blockPos.y
        local minZ = box.minZ + blockPos.z
        local maxX = box.maxX + blockPos.x
        local maxY = box.maxY + blockPos.y
        local maxZ = box.maxZ + blockPos.z
 
        -- Clamp pos into the AABB — this is the nearest interior-or-surface point
        local cx = math.max(minX, math.min(pos.x, maxX))
        local cy = math.max(minY, math.min(pos.y, maxY))
        local cz = math.max(minZ, math.min(pos.z, maxZ))
 
        -- If pos is strictly inside the box, project it onto the nearest face instead
        local inside = (pos.x > minX and pos.x < maxX)
                    and (pos.y > minY and pos.y < maxY)
                    and (pos.z > minZ and pos.z < maxZ)
 
        if inside then
            -- Distance from pos to each of the 6 faces
            local dists = {
                { axis = "x", val = minX, dist = pos.x - minX },
                { axis = "x", val = maxX, dist = maxX - pos.x },
                { axis = "y", val = minY, dist = pos.y - minY },
                { axis = "y", val = maxY, dist = maxY - pos.y },
                { axis = "z", val = minZ, dist = pos.z - minZ },
                { axis = "z", val = maxZ, dist = maxZ - pos.z },
            }
            local nearest = dists[1]
            for j = 2, #dists do
                if dists[j].dist < nearest.dist then nearest = dists[j] end
            end
            -- Project onto that face
            if nearest.axis == "x" then cx = nearest.val
            elseif nearest.axis == "y" then cy = nearest.val
            else cz = nearest.val end
        end
 
        local distSq = (pos.x - cx)^2 + (pos.y - cy)^2 + (pos.z - cz)^2
        if distSq < bestDistSq then
            bestDistSq = distSq
            bestPoint = { x = cx, y = cy, z = cz }
        end
    end
 
    return bestPoint
end

---Get the closest point on a block's hitbox from a position
---@param block table Block data with position {pos: {x, y, z}}
---@return table|nil Closest point {x, y, z} on the hitbox
function blockUtils.getClosestHitbox(block)
    if not block or not block.pos then return nil end
    local blockState = world.getBlock(block.pos.x, block.pos.y, block.pos.z)
    local boxes = world.getOutlineBoxes(block.pos.x, block.pos.y, block.pos.z, blockState)
    if not boxes or #boxes == 0 then return nil end

    -- print(dump(getBoxRays(boxes, block.pos)))
    return getBoxRays(boxes, block.pos)
end

return blockUtils