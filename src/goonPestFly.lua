-- @version 1.0
-- @location /libs/

local rotations = require("rotations_v2")
math.randomseed(os.time())
local scripts = {}
rotations.setRotationSpeed(16)

scripts.slotVacuum = 1
scripts.flyY = 73
local aimFov = 70          -- Угол FOV, в котором наводка отключается
local aimOffsetSpread = 20  -- Максимальное смещение в градусах (например, +/- 2 градуса)
local currentState = "Stop"
local lockFailsafe = false
local pestOffsets = {}

local math_random = math.random

function scripts.setState(newState)
  if currentState ~= newState then
    currentState = newState
  end
end

function scripts.getState()
  return currentState
end

function scripts.setLockFailsafe(newState)
  if lockFailsafe ~= newState then
    lockFailsafe = newState
  end
end

function scripts.getLockFailsafe()
  return lockFailsafe
end

function scripts.getPestPlots()
  local tabBody = (player.getTab()).body
  if not tabBody then return end
  local alive = 0
  for _, line in ipairs(tabBody) do
    line = line:gsub("§4", "")
    line = line:gsub("§b", "")
    line = line:gsub("§f", "")
    line = line:gsub("§r", "")
    local plotsStr = string.match(line, "Alive: (.*)")
    if plotsStr then
      plotsStr = plotsStr:gsub(" ", "")
      alive = tonumber(plotsStr)
    end
  end
  return alive
end

local pestTexture = {
  ["ewogICJ0aW1lc3RhbXAiIDogMTY5Njk0NTAyOTQ2MSwKICAicHJvZmlsZUlkIiA6ICI3NTE0NDQ4MTkxZTY0NTQ2OGM5NzM5YTZlMzk1N2JlYiIsCiAgInByb2ZpbGVOYW1lIiA6ICJUaGFua3NNb2phbmciLAogICJzaWduYXR1cmVSZXF1aXJlZCIgOiB0cnVlLAogICJ0ZXh0dXJlcyIgOiB7CiAgICAiU0tJTiIgOiB7CiAgICAgICJ1cmwiIDogImh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNTJhOWZlMDViYzY2M2VmY2QxMmU1NmEzY2NjNWVjMDM1YmY1NzdiNzg3MDg1NDhiNmY0ZmZjZjFkMzBlY2NmZSIKICAgIH0KICB9Cn0="] = true,
  ["ewogICJ0aW1lc3RhbXAiIDogMTYxODQxOTcwMTc1MywKICAicHJvZmlsZUlkIiA6ICI3MzgyZGRmYmU0ODU0NTVjODI1ZjkwMGY4OGZkMzJmOCIsCiAgInByb2ZpbGVOYW1lIiA6ICJCdUlJZXQiLAogICJzaWduYXR1cmVSZXF1aXJlZCIgOiB0cnVlLAogICJ0ZXh0dXJlcyIgOiB7CiAgICAiU0tJTiIgOiB7CiAgICAgICJ1cmwiIDogImh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvYThhYmI0NzFkYjBhYjc4NzAzMDExOTc5ZGM4YjQwNzk4YTk0MWYzYTRkZWMzZWM2MWNiZWVjMmFmOGNmZmU4IiwKICAgICAgIm1ldGFkYXRhIiA6IHsKICAgICAgICAibW9kZWwiIDogInNsaW0iCiAgICAgIH0KICAgIH0KICB9Cn0="] = true,
  ["ewogICJ0aW1lc3RhbXAiIDogMTY5NzU1NzA3NzAzNywKICAicHJvZmlsZUlkIiA6ICI0YjJlMGM1ODliZjU0ZTk1OWM1ZmJlMzg5MjQ1MzQzZSIsCiAgInByb2ZpbGVOYW1lIiA6ICJfTmVvdHJvbl8iLAogICJzaWduYXR1cmVSZXF1aXJlZCIgOiB0cnVlLAogICJ0ZXh0dXJlcyIgOiB7CiAgICAiU0tJTiIgOiB7CiAgICAgICJ1cmwiIDogImh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNGIyNGE0ODJhMzJkYjFlYTc4ZmI5ODA2MGIwYzJmYTRhMzczY2JkMThhNjhlZGRkZWI3NDE5NDU1YTU5Y2RhOSIKICAgIH0KICB9Cn0="] = true,
  ["ewogICJ0aW1lc3RhbXAiIDogMTcyMzE3OTgxMTI2NCwKICAicHJvZmlsZUlkIiA6ICJjZjc4YzFkZjE3ZTI0Y2Q5YTIxYmU4NWQ0NDk5ZWE4ZiIsCiAgInByb2ZpbGVOYW1lIiA6ICJNYXR0c0FybW9yU3RhbmRzIiwKICAic2lnbmF0dXJlUmVxdWlyZWQiIDogdHJ1ZSwKICAidGV4dHVyZXMiIDogewogICAgIlNLSU4iIDogewogICAgICAidXJsIiA6ICJodHRwOi8vdGV4dHVyZXMubWluZWNyYWZ0Lm5ldC90ZXh0dXJlL2EyNGM2OWY5NmNlNTU2MjIxZTE5NWM4ZWYyYmZhZDcxZWJmN2Y5NWY1YWU5MTRhNDg0YThkMGVjMjE2NzI2NzQiCiAgICB9CiAgfQp9"] = true,
  ["ewogICJ0aW1lc3RhbXAiIDogMTY5Njk0NTA2MzI4MSwKICAicHJvZmlsZUlkIiA6ICJjN2FmMWNkNjNiNTE0Y2YzOGY4NWQ2ZDUxNzhjYThlNCIsCiAgInByb2ZpbGVOYW1lIiA6ICJtb25zdGVyZ2FtZXIzMTUiLAogICJzaWduYXR1cmVSZXF1aXJlZCIgOiB0cnVlLAogICJ0ZXh0dXJlcyIgOiB7CiAgICAiU0tJTiIgOiB7CiAgICAgICJ1cmwiIDogImh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvOWQ5MGU3Nzc4MjZhNTI0NjEzNjhlMjZkMWIyZTE5YmZhMWJhNTgyZDYwMjQ4M2U1NDVmNDEyNGQwZjczMTg0MiIKICAgIH0KICB9Cn0="] = true,
  ["ewogICJ0aW1lc3RhbXAiIDogMTcyMzE3OTc4OTkzNCwKICAicHJvZmlsZUlkIiA6ICJlMjc5NjliODYyNWY0NDg1YjkyNmM5NTBhMDljMWMwMSIsCiAgInByb2ZpbGVOYW1lIiA6ICJLRVZJTktFTE9LRSIsCiAgInNpZ25hdHVyZVJlcXVpcmVkIiA6IHRydWUsCiAgInRleHR1cmVzIiA6IHsKICAgICJTS0lOIiA6IHsKICAgICAgInVybCIgOiAiaHR0cDovL3RleHR1cmVzLm1pbmVjcmFmdC5uZXQvdGV4dHVyZS83MGExZTgzNmJmMTk2OGIyZWFhNDgzNzIyN2ExOTIwNGYxNzI5NWQ4NzBlZTllNzU0YmQ2YjZkNjBkZGJlZDNjIgogICAgfQogIH0KfQ=="] = true,
  ["ewogICJ0aW1lc3RhbXAiIDogMTY5NzQ3MDQ0MzA4MiwKICAicHJvZmlsZUlkIiA6ICJkOGNkMTNjZGRmNGU0Y2IzODJmYWZiYWIwOGIyNzQ4OSIsCiAgInByb2ZpbGVOYW1lIiA6ICJaYWNoeVphY2giLAogICJzaWduYXR1cmVSZXF1aXJlZCIgOiB0cnVlLAogICJ0ZXh0dXJlcyIgOiB7CiAgICAiU0tJTiIgOiB7CiAgICAgICJ1cmwiIDogImh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvN2E3OWQwZmQ2NzdiNTQ1MzA5NjExMTdlZjg0YWRjMjA2ZTJjYzUwNDVjMTM0NGQ2MWQ3NzZiZjhhYzJmZTFiYSIKICAgIH0KICB9Cn0="] = true,
  ["ewogICJ0aW1lc3RhbXAiIDogMTY5Njg3MDQwNTk1NCwKICAicHJvZmlsZUlkIiA6ICJiMTUyZDlhZTE1MTM0OWNmOWM2NmI0Y2RjMTA5NTZjOCIsCiAgInByb2ZpbGVOYW1lIiA6ICJNaXNxdW90aCIsCiAgInNpZ25hdHVyZVJlcXVpcmVkIiA6IHRydWUsCiAgInRleHR1cmVzIiA6IHsKICAgICJTS0lOIiA6IHsKICAgICAgInVybCIgOiAiaHR0cDovL3RleHR1cmVzLm1pbmVjcmFmdC5uZXQvdGV4dHVyZS82NTQ4NWM0YjM0ZTViNTQ3MGJlOTRkZTEwMGU2MWY3ODE2ZjgxYmM1YTExZGZkZjBlY2NmODkwMTcyZGE1ZDBhIgogICAgfQogIH0KfQ=="] = true,
  ["ewogICJ0aW1lc3RhbXAiIDogMTY5Njg3MDQxOTcyNSwKICAicHJvZmlsZUlkIiA6ICJkYjYzNWE3MWI4N2U0MzQ5YThhYTgwOTMwOWFhODA3NyIsCiAgInByb2ZpbGVOYW1lIiA6ICJFbmdlbHMxNzQiLAogICJzaWduYXR1cmVSZXF1aXJlZCIgOiB0cnVlLAogICJ0ZXh0dXJlcyIgOiB7CiAgICAiU0tJTiIgOiB7CiAgICAgICJ1cmwiIDogImh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvYmU2YmFmNjQzMWE5ZGFhMmNhNjA0ZDVhM2MyNmU5YTc2MWQ1OTUyZjA4MTcxNzRhNGZlMGI3NjQ2MTZlMjFmZiIKICAgIH0KICB9Cn0="] = true,
  ["ewogICJ0aW1lc3RhbXAiIDogMTY5NzQ3MDQ3ODAzMCwKICAicHJvZmlsZUlkIiA6ICI0NmY3N2NjNmQ2MjU0NjEzYjc2NmYyZDRmMDM2MzZhNiIsCiAgInByb2ZpbGVOYW1lIiA6ICJNaXNzV29sZiIsCiAgInNpZ25hdHVyZVJlcXVpcmVkIiA6IHRydWUsCiAgInRleHR1cmVzIiA6IHsKICAgICJTS0lOIiA6IHsKICAgICAgInVybCIgOiAiaHR0cDovL3RleHR1cmVzLm1pbmVjcmFmdC5uZXQvdGV4dHVyZS9mZDQwYWE1MDkwNTIzNWI2MjhlNzM3OWViMzFmYTQ1Y2Q0MWI1MDNmMDk3MjFkYjNjNDM3ZmNlZTM5MjA3ZGZjIgogICAgfQogIH0KfQ=="] = true,
  ["ewogICJ0aW1lc3RhbXAiIDogMTc2MDQ1MDQxODQzNywKICAicHJvZmlsZUlkIiA6ICIwNjY5Y2E1MGYyZWU0NTQxODhlYWQ3YTM3NTkzNDRlMCIsCiAgInByb2ZpbGVOYW1lIiA6ICJDcjR6eWNsb3duVFYiLAogICJzaWduYXR1cmVSZXF1aXJlZCIgOiB0cnVlLAogICJ0ZXh0dXJlcyIgOiB7CiAgICAiU0tJTiIgOiB7CiAgICAgICJ1cmwiIDogImh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvMjU0YWZmNGMwYjJkY2UzYTY3MjM0OWNjMGVlOWU2ZjNhOWRlZWJlNGIzNTU2ZTg0NjExZWNhMjUwYTc4MjFiZiIsCiAgICAgICJtZXRhZGF0YSIgOiB7CiAgICAgICAgIm1vZGVsIiA6ICJzbGltIgogICAgICB9CiAgICB9CiAgfQp9"] = true, -- Dragon fly
  ["ewogICJ0aW1lc3RhbXAiIDogMTc2MDQ1MDQxOTYxMiwKICAicHJvZmlsZUlkIiA6ICI0OWIzODUyNDdhMWY0NTM3YjBmN2MwZTFmMTVjMTc2NCIsCiAgInByb2ZpbGVOYW1lIiA6ICJiY2QyMDMzYzYzZWM0YmY4IiwKICAic2lnbmF0dXJlUmVxdWlyZWQiIDogdHJ1ZSwKICAidGV4dHVyZXMiIDogewogICAgIlNLSU4iIDogewogICAgICAidXJsIiA6ICJodHRwOi8vdGV4dHVyZXMubWluZWNyYWZ0Lm5ldC90ZXh0dXJlLzFlMDRiYjYzNjdjYWE0ZTg4ZjVmZDBlZTgwZjA3NDVkMTM3YTYwNjAyMjNkYmJjNDJhMTY0NzFmZGY2NGJiODMiLAogICAgICAibWV0YWRhdGEiIDogewogICAgICAgICJtb2RlbCIgOiAic2xpbSIKICAgICAgfQogICAgfQogIH0KfQ=="] = true, -- Mantis
  ["ewogICJ0aW1lc3RhbXAiIDogMTc2MDQ1MDQyMjEzNiwKICAicHJvZmlsZUlkIiA6ICIzNDY4Y2VjMWFlOTY0YWRmYWQyNjEzMGEwZGQ0NjRkYyIsCiAgInByb2ZpbGVOYW1lIiA6ICJzdXJlZWxta18iLAogICJzaWduYXR1cmVSZXF1aXJlZCIgOiB0cnVlLAogICJ0ZXh0dXJlcyIgOiB7CiAgICAiU0tJTiIgOiB7CiAgICAgICJ1cmwiIDogImh0dHA6Ly90ZXh0dXJlcy5taW5lY3JhZnQubmV0L3RleHR1cmUvNGNlNzllOTBhZGYzNDcxOGYzMTNlYzI0ZDZjNjEzNWI2OWIzNzg4YzYxODQ5ODQ0NmNjYzgzY2E2NDBjMGIxNCIsCiAgICAgICJtZXRhZGF0YSIgOiB7CiAgICAgICAgIm1vZGVsIiA6ICJzbGltIgogICAgICB9CiAgICB9CiAgfQp9"] = true -- Firefly
}

local function isPestTexture(texture)
  if pestTexture[texture] then
    return true
  end
  return false
end

local function isPest(entity)
  if entity ~= nil and entity.head ~= nil and entity.head.head_texture ~= nil then
    if isPestTexture(entity.head.head_texture) then
      return true
    end
  end
  return false
end

local tick = 0
local wasOnGround = false
local tickForward = 0
local teleported = false

local pestsKilled = 0
local previousPests = {}

local previousAliveCount = 0

local world_getEntitiesInBox = world.getEntitiesInBox
local BOX_EXPAND_Y = 2

function scripts.getPestsKilled()
  return pestsKilled
end

function scripts.getAlivePests()
  local alive = scripts.getPestPlots() -- получить текущее число живых Pests
  if not alive or not previousAliveCount then return nil end
  if alive < previousAliveCount then
    pestsKilled = pestsKilled + (previousAliveCount - alive)
  end
  previousAliveCount = alive
  return alive
end

local function checkHasArmorStand(entity)
  if not entity then return false end

  -- Ищем сущности в коробке над мобом
  local box = entity.box
  if not box then return false end

  -- getEntitiesInBox возвращает список, проверяем его
  local entitiesAbove = world_getEntitiesInBox(entity, box.expand(0, BOX_EXPAND_Y, 0))

  if entitiesAbove then
    for _, ent in ipairs(entitiesAbove) do
      -- Проверяем, является ли сущность стойкой для брони
      if ent and ent.id ~= entity.id and ent.type == "entity.minecraft.armor_stand" then
        return true
      end
    end
  end

  return false
end


local function isPestFound(entities)
  local pestFound = false

  for _, entity in ipairs(entities) do
    if isPest(entity) then
      pestFound = true
      break
    end
  end
  return pestFound
end

local function horizontalDistanceSq(x1, z1, x2, z2)
  local dx = x2 - x1
  local dz = z2 - z1
  return dx * dx + dz * dz
end

local function getAngleDiff(a, b)
  return (a - b + 180) % 360 - 180
end

registerClientTickPost(function()
  rotations.update()

  local pos = player.getPos()
  local tab = player.getTab()
  local onGround = player.isOnGround()

  local entities = nil
  if currentState == "Forward" or currentState == "Moving" then
    entities = world.getEntities()
  end

  if currentState == "Up" then
    if pos and pos.y <= scripts.flyY then
      if onGround and not wasOnGround then
        tick = 1
      end

      if tick == 1 then
        player.input.setPressedJump(false)
        tick = 2
      elseif tick == 2 then
        player.input.setPressedJump(true)
        tick = 3
      elseif tick == 3 then
        player.input.setPressedJump(false)
        tick = 0
      elseif not onGround then
        player.input.setPressedJump(true)
      else
        player.input.setPressedJump(false)
      end

      wasOnGround = onGround
      tickForward = 0 

    else
      tickForward = 0
      currentState = "Forward"
      tick = 0
      player.input.setPressedJump(false)
      wasOnGround = onGround
    end
  elseif currentState == "Down" then
    tickForward = tickForward + 1
    if tickForward <= 15 then

    else
      currentState = "Up"
      tickForward = 0
    end
  elseif currentState == "Down2" then
    tickForward = tickForward + 1
    if tickForward <= 7 then

    else
      currentState = "Stop"
      tickForward = 0
    end
  elseif currentState == "Teleport" then
    local plots = {}
    if tab and tab.body then
      for index, line in ipairs(tab.body) do
        line = line:gsub("§b", "") 
        line = line:gsub("§f", "") 
        line = line:gsub("§r", "") 
        local plotsStr = string.match(line, "Plots: (.*)")
        if plotsStr then
          for numStr in string.gmatch(plotsStr, '([^,%s]+)') do
            local num = tonumber(numStr)
            if num then
              table.insert(plots, num)
            end
          end
        end
      end
    end

    if #plots > 0 then
      local randomIndex = math_random(1, #plots)
      local randomPlot = plots[randomIndex]

      lockFailsafe = true
      currentState = "Down"
      player.sendCommand("/tptoplot " .. randomPlot)
      tickForward = 0
      teleported = false
    else
      lockFailsafe = true
      currentState = "Down2"
      player.sendCommand("/warp garden")
      -- player.addMessage("farming now from pest_fly")
      teleported = true
    end
  elseif currentState == "Forward" then
    tickForward = tickForward + 1
    if tickForward <= 50 then
      player.input.setPressedForward(true)
      if entities and isPestFound(entities) then
        currentState = "Moving"
        tickForward = 0
      end
    else
      currentState = "Moving"
      tickForward = 0
    end
  elseif currentState == "TeleportDelay" then
    tickForward = tickForward + 1
    if tickForward <= 45 then

    else
      currentState = "Teleport"
      tickForward = 0
    end
  elseif currentState == "Moving" then
    player.input.setPressedForward(false)

    local closestPest = nil
    local minDistance = math.huge

    if entities then
      for _, entity in ipairs(entities) do
        if isPest(entity) then
          local dist = horizontalDistanceSq(pos.x, pos.z, entity.x, entity.z)
          if dist < minDistance then
            minDistance = dist
            closestPest = entity
          end
        end
      end
    end

    if closestPest then
      -- Вычисляем ID сущности для сохранения смещения
      -- Используем closestPest.id (стандартно) или преобразуем сам объект в строку если id нет
      local pestId = closestPest.id or tostring(closestPest)

      -- Если для этого вредителя еще нет смещения, генерируем его
      if not pestOffsets[pestId] then
        pestOffsets[pestId] = {
          yaw = (math_random() * aimOffsetSpread * 2) - aimOffsetSpread,
          pitch = (math_random() * aimOffsetSpread * 2) - aimOffsetSpread
        }
      end

      -- Получаем идеальную ротацию
      local perfectRotation = world.getRotation(closestPest.x, closestPest.y + 2, closestPest.z)

      -- Добавляем сохраненное смещение
      local targetYaw = perfectRotation.yaw + pestOffsets[pestId].yaw
      local targetPitch = perfectRotation.pitch + pestOffsets[pestId].pitch

      -- Логика FOV
      local myRotation = player.getRotation()
      -- Сравниваем текущую ротацию игрока с ЦЕЛЕВОЙ ротацией (включая смещение)
      local yawDiff = math.abs(getAngleDiff(targetYaw, myRotation.yaw))
      local pitchDiff = math.abs(getAngleDiff(targetPitch, myRotation.pitch))

      if yawDiff > aimFov or pitchDiff > aimFov then
        if checkHasArmorStand(closestPest) then
          rotations.rotateToYawPitch(targetYaw, targetPitch)
        end
      end

      if minDistance >= 7 * 7 then
        rotations.rotateToYawPitch(targetYaw, targetPitch)
        player.input.setPressedForward(true)
      else
        player.input.setPressedForward(false)
        player.input.setSelectedSlot(scripts.slotVacuum)
        player.input.setPressedUse(true)
      end
    else
      pestOffsets = {}
      player.input.setPressedForward(false)
      player.input.setPressedUse(false)
      currentState = "TeleportDelay"
      tickForward = 0
      rotations.stop()
    end
  end
end)

return scripts
