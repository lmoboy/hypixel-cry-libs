-- @version 1.0
-- @location /libs/

local SmoothRotation = {}
local rotationSpeed = 18
local targetYaw, targetPitch = 0, 0
local currentYaw, currentPitch = 0, 0
local isRotating = false
local completionCallback = nil
local initialYawDiff, initialPitchDiff = nil, nil
local gravity = 6.0       -- Сила "гравитации" для замедления в конце
local windX, windY = 0, 0 -- Случайные помехи для естественности
local player = require("player")

-- WindMouse алгоритм для плавного человеческого движения
local function windMouse(startX, startY, destX, destY, G_0, W_0, M_0, D_0)
    local current_x, current_y = startX, startY
    local v_x, v_y = 0, 0
    local w_x, w_y = 0, 0
    local sqrt2 = math.sqrt(2)
    local sqrt3 = math.sqrt(3)
    local sqrt5 = math.sqrt(5)

    local dist = math.sqrt((destX - startX) ^ 2 + (destY - startY) ^ 2)
    if dist < 0.1 then return destX, destY end

    while true do
        local random_chance = math.random()
        if random_chance < 0.05 then
            w_x = w_x / sqrt3 + (math.random() * 2 - 1) * sqrt3
            w_y = w_y / sqrt3 + (math.random() * 2 - 1) * sqrt3
        else
            w_x = w_x / sqrt2
            w_y = w_y / sqrt2
            if math.abs(w_x) + math.abs(w_y) < 3 then
                w_x = (math.random() * 2 - 1) * sqrt3
                w_y = (math.random() * 2 - 1) * sqrt3
            end
        end

        local veloX = (destX - current_x) / G_0
        local veloY = (destY - current_y) / G_0

        v_x = v_x + veloX + w_x
        v_y = v_y + veloY + w_y

        local v_mag = math.sqrt(v_x ^ 2 + v_y ^ 2)
        if v_mag > M_0 then
            v_x = (v_x / v_mag) * M_0
            v_y = (v_y / v_mag) * M_0
        end

        current_x = current_x + v_x
        current_y = current_y + v_y

        local d = math.sqrt((destX - current_x) ^ 2 + (destY - current_y) ^ 2)
        if d < 1 then
            return destX, destY
        end

        if d <= D_0 then
            break
        end
    end

    return current_x, current_y
end

--- @param yaw number
--- @param pitch number
function SmoothRotation.setTargetRotation(yaw, pitch)
    targetYaw = yaw
    targetPitch = pitch
    local currentRot = player.getRotation()
    currentYaw = currentRot.yaw or currentRot
    currentPitch = currentRot.pitch or 0
    isRotating = true
    initialYawDiff, initialPitchDiff = nil, nil

    -- Инициализируем случайные помехи
    windX = (math.random() * 2 - 1) * 0.2
    windY = (math.random() * 2 - 1) * 0.2

    return true
end

-- Плавный поворот к координатам
--- @param x number
--- @param y number
--- @param z number
function SmoothRotation.rotateToCoordinates(x, y, z)
    local rotation = world.getRotation(x, y, z)
    return SmoothRotation.setTargetRotation(rotation.yaw, rotation.pitch)
end

-- Плавный поворот к конкретным значениям yaw и pitch
--- @param yaw number
--- @param pitch number
function SmoothRotation.rotateToYawPitch(yaw, pitch)
    return SmoothRotation.setTargetRotation(yaw, pitch)
end

-- Установка скорости вращения
--- @param speed number
function SmoothRotation.setRotationSpeed(speed)
    rotationSpeed = math.max(1, math.min(speed, 180))
    return rotationSpeed
end

-- Установка callback функции при завершении
--- @param callback fun()
function SmoothRotation.setOnComplete(callback)
    completionCallback = callback
    return true
end

-- Плавное вращение к цели с человеческим поведением
--- Execute this in tickEvent
function SmoothRotation.update()
    if not isRotating then return false end

    -- Получаем текущее вращение игрока
    local currentRot = player.getRotation()
    local currentYawRot = currentRot.yaw or currentRot
    local currentPitchRot = currentRot.pitch or 0

    -- Вычисляем разницу углов
    local yawDiff = (targetYaw - currentYawRot + 180) % 360 - 180
    local pitchDiff = targetPitch - currentPitchRot

    -- Проверяем, достигли ли цели
    if math.abs(yawDiff) < 0.1 and math.abs(pitchDiff) < 0.1 then
        player.setRotation(targetYaw, targetPitch)
        isRotating = false

        if completionCallback then
            completionCallback()
        end

        return true
    end

    -- Применяем WindMouse-подобное поведение
    local totalDist = math.sqrt(yawDiff ^ 2 + pitchDiff ^ 2)
    local maxStep = rotationSpeed * (1 + math.random() * 0.2) -- Небольшая случайность в скорости

    -- Замедляемся при приближении к цели (гравитационный эффект)
    local slowdown = math.min(1, totalDist / 30.0)
    local effectiveSpeed = maxStep * slowdown

    -- Добавляем небольшие случайные колебания для естественности
    if math.random() < 0.1 then
        windX = windX * 0.017 + (math.random() * 2 - 1.98)
        windY = windY * 0.017 + (math.random() * 2 - 1.98)
    else
        windX = windX * 0.15
        windY = windY * 0.15
    end

    -- Вычисляем шаги с учетом WindMouse алгоритма
    local yawStep, pitchStep = windMouse(
        0, 0,
        yawDiff, pitchDiff,
        gravity,
        0.8,                  -- Wind factor
        effectiveSpeed * 1.2, -- Max step
        effectiveSpeed * 0.6  -- Target radius
    )

    -- Ограничиваем максимальный шаг
    local stepMagnitude = math.sqrt(yawStep ^ 2 + pitchStep ^ 2)
    if stepMagnitude > effectiveSpeed then
        yawStep = (yawStep / stepMagnitude) * effectiveSpeed
        pitchStep = (pitchStep / stepMagnitude) * effectiveSpeed
    end

    -- Добавляем случайные помехи
    yawStep = yawStep + windX * slowdown
    pitchStep = pitchStep + windY * slowdown

    -- Применяем поворот
    currentYawRot = (currentYawRot + yawStep) % 360
    currentPitchRot = math.max(-90, math.min(90, currentPitchRot + pitchStep))

    player.setRotation(currentYawRot, currentPitchRot)
    return false
end

-- Проверка, выполняется ли поворот
--- @return boolean
function SmoothRotation.isRotating()
    return isRotating
end

-- Принудительная остановка поворота
--- @return boolean
function SmoothRotation.stop()
    if isRotating then
        isRotating = false
        return true
    end
    return false
end

-- Получение прогресса поворота (0-1)
--- @return number progress
function SmoothRotation.getProgress()
    if not isRotating then return 1 end

    local currentRot = player.getRotation()
    local currentYawRot = currentRot.yaw or currentRot
    local currentPitchRot = currentRot.pitch or 0

    local yawDiff = (targetYaw - currentYawRot + 180) % 360 - 180
    local pitchDiff = targetPitch - currentPitchRot

    if not initialYawDiff or not initialPitchDiff then
        local startRot = player.getRotation()
        local startYaw = startRot.yaw or startRot
        local startPitch = startRot.pitch or 0

        initialYawDiff = math.abs((targetYaw - startYaw + 180) % 360 - 180)
        initialPitchDiff = math.abs(targetPitch - startPitch)
    end

    local totalDiff = math.sqrt(yawDiff ^ 2 + pitchDiff ^ 2)
    local initialTotalDiff = math.sqrt(initialYawDiff ^ 2 + initialPitchDiff ^ 2)

    return math.max(0, math.min(1, 1 - (totalDiff / math.max(initialTotalDiff, 0.1))))
end

-- Функция для получения знака числа
function math.sign(x)
    return x > 0 and 1 or x < 0 and -1 or 0
end

return SmoothRotation
