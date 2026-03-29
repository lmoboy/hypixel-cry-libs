-- @version 1.0.0
-- @location /libs

---@class ActiveBlock
---@field x number
---@field y number
---@field z number
---@field power number
---@field type string

---@class MovedBlock
---@field id number
---@field x number
---@field y number
---@field z number

---@class RedstoneFast
---@field new fun(self: RedstoneFast, world: world): RedstoneFast
---@field addSource fun(self: RedstoneFast, x: number, y: number, z: number, active: boolean?)
---@field clear fun(self: RedstoneFast)
---@field scan fun(self: RedstoneFast, sx: number, sy: number, sz: number)
---@field predict fun(self: RedstoneFast)
---@field getActiveBlocks fun(self: RedstoneFast): ActiveBlock[]
---@field getMovedBlocks fun(self: RedstoneFast): MovedBlock[]
---@field step fun(self: RedstoneFast): boolean

local RedstoneFast = {}
RedstoneFast.__index = RedstoneFast

local function isSlime(b) return b and b.info and b.info.name:find("slime") end
local function isHoney(b) return b and b.info and b.info.name:find("honey") end

local function isMovable(b)
    if not b or (b.info and b.info.is_air) then return true end
    local name = b.info.name:lower()
    -- Список неподвижных блоков
    if name:find("obsidian") or name:find("bedrock") or name:find("chest") or
        name:find("interface") or name:find("piston_head") or name:find("extended") or
        name:find("furnace") or name:find("chest") or name:find("dispenser") or
        name:find("dropper") or name:find("barrel") or name:find("oak_shelf") or
        name:find("jukebox") then
        return false
    end
    -- Нельзя двигать расширенный поршень
    if b.type == "piston" and b.isExtended then return false end
    return true
end

local function canStick(b1, b2)
    if not b1 or not b2 or not b1.info or not b2.info then return false end

    -- НОВОЕ: Если один из блоков неподвижен (печка, обсидиан),
    -- они не могут слипнуться в одну группу движения.
    if not isMovable(b1) or not isMovable(b2) then return false end

    local n1, n2 = b1.info.name:lower(), b2.info.name:lower()
    local s1, h1 = n1:find("slime"), n1:find("honey")
    local s2, h2 = n2:find("slime"), n2:find("honey")

    -- Слизь и Мед НЕ прилипают друг к другу
    if (s1 and h2) or (h1 and s2) then return false end
    -- Если хотя бы один из них слизь или мед — они слипаются
    return (s1 or h1 or s2 or h2)
end

---------------------------------------------------------
-- 1. НАСТРОЙКА ОСЕЙ (С учетом East = -X)
---------------------------------------------------------
-- fx/fz - смещение выхода (FRONT)
-- bx/bz - смещение входа (BACK)
local function getDirections(facing)
    local f = tostring(facing or "north"):lower()
    local dirs = {
        -- fx/fz - ВЫХОД, bx/bz - ВХОД, lx/lz - ЛЕВО, rx/rz - ПРАВО
        north = { fx = 0, fz = 1, bx = 0, bz = -1, lx = 1, lz = 0, rx = -1, rz = 0 },
        south = { fx = 0, fz = -1, bx = 0, bz = 1, lx = -1, lz = 0, rx = 1, rz = 0 },
        east  = { fx = -1, fz = 0, bx = 1, bz = 0, lx = 0, lz = -1, rx = 0, rz = 1 },
        west  = { fx = 1, fz = 0, bx = -1, bz = 0, lx = 0, lz = 1, rx = 0, rz = -1 },
        up    = { fx = 0, fz = 0, fy = 1, bx = 0, bz = 0, by = -1, lx = 1, lz = 0, rx = -1, rz = 0 },
        down  = { fx = 0, fz = 0, fy = -1, bx = 0, bz = 0, by = 1, lx = 1, lz = 0, rx = -1, rz = 0 }
    }
    return dirs[f] or dirs.north
end

local function getDirectionsPiston(facing)
    local f = tostring(facing or "north"):lower()
    local dirs = {
        -- fx/fy/fz - ВПЕРЕД (Лицо), bx/by/bz - НАЗАД (Спина)
        -- lx/lz - ЛЕВО, rx/rz - ПРАВО (относительно лица)
        north = { fx = 0, fy = 0, fz = -1, bx = 0, by = 0, bz = 1, lx = -1, lz = 0, rx = 1, rz = 0 },
        south = { fx = 0, fy = 0, fz = 1, bx = 0, by = 0, bz = -1, lx = 1, lz = 0, rx = -1, rz = 0 },
        west  = { fx = -1, fy = 0, fz = 0, bx = 1, by = 0, bz = 0, lx = 0, lz = 1, rx = 0, rz = -1 },
        east  = { fx = 1, fy = 0, fz = 0, bx = -1, by = 0, bz = 0, lx = 0, lz = -1, rx = 0, rz = 1 },
        up    = { fx = 0, fy = 1, fz = 0, bx = 0, by = -1, bz = 0, lx = 1, lz = 0, rx = -1, rz = 0 },
        down  = { fx = 0, fy = -1, fz = 0, bx = 0, by = 1, bz = 0, lx = 1, lz = 0, rx = -1, rz = 0 }
    }
    return dirs[f] or dirs.north
end

local function posKey(x, y, z) return x .. "," .. y .. "," .. z end

---------------------------------------------------------
-- 2. КЛАССЫ КОМПОНЕНТОВ
---------------------------------------------------------
local Component = {}
Component.__index = Component
function Component.new(x, y, z, info, typeName)
    return setmetatable({
        x = x,
        y = y,
        z = z,
        info = info,
        type = typeName,
        power = 0,
        nextPower = 0,
        inputs = {} -- Ссылки на объекты
    }, Component)
end

-- КОНСЮМЕРЫ с квазис связью
local SuperConsumer = setmetatable({}, Component)
SuperConsumer.__index = SuperConsumer
function SuperConsumer:calculate()
    local p = 0
    for i = 1, #self.inputs do
        if self.inputs[i].power > 0 then
            p = 999; break
        end
    end
    self.nextPower = p
end

-- НАБЛЮДАТЕЛЬ
local Observer = setmetatable({}, Component)
Observer.__index = Observer
function Observer:calculate()
    -- 1. Считываем текущее состояние входа
    local currentPower = (self.inputTarget and self.inputTarget.power) or 0
    local currentId = (self.inputTarget and self.inputTarget.info and self.inputTarget.info.name) or "air"

    -- НОВОЕ: Проверка состояния головки поршня
    local currentExt = false
    if self.inputTarget and self.inputTarget.type == "piston" then
        -- Если мы смотрим прямо на поршень ИЛИ на пространство, куда он выдвигается
        currentExt = self.inputTarget.isExtended
    end

    -- 2. Выход сигнала (из очереди)
    self.nextPower = self.queue[1] or 0
    table.remove(self.queue, 1)
    if #self.queue == 0 then table.insert(self.queue, 0) end

    -- 3. Детекция изменений (Добавлена проверка lastExt)
    local changed = (currentPower ~= self.lastPower) or
        (currentId ~= self.lastId) or
        (currentExt ~= self.lastExt)

    if changed then
        self.queue[1] = 15
        self.lastPower = currentPower
        self.lastId = currentId
        self.lastExt = currentExt -- Запоминаем состояние выдвижения
        self.isPending = true
    else
        self.isPending = (self.nextPower > 0 or self.queue[1] > 0)
    end
end

-- ПЫЛЬ
local Wire = setmetatable({}, Component)
Wire.__index = Wire
function Wire:calculate()
    local max = 0
    for i = 1, #self.inputs do
        local inp = self.inputs[i]
        if inp then
            local p = 0
            if inp.type == "wire" then
                -- От пыли к пыли: затухание
                p = (inp.power or 0) - 1
            elseif inp.type == "solid" then
                -- От блока: только если блок "сильно" запитан
                local stronglyPowered = false
                for _, bInp in ipairs(inp.inputs) do
                    -- Наблюдатель, Факел, Повторитель или Рычаг запитывают блок насквозь
                    if bInp.power > 0 and bInp.type ~= "wire" and bInp.type ~= "solid" then
                        stronglyPowered = true
                        break
                    end
                end
                p = stronglyPowered and 15 or 0
            else
                -- Наблюдатель, Повторитель, Источник: прямая передача 15
                p = inp.power or 0
            end
            if p > max then max = p end
        end
    end
    self.nextPower = math.max(0, max)
end

-- ПОВТОРИТЕЛЬ
local Repeater = setmetatable({}, Component)
Repeater.__index = Repeater
function Repeater:calculate()
    local isLocked = false
    for i = 1, #self.inputsSide do
        local side_component = self.inputsSide[i]
        local scheduled_output = side_component.queue and side_component.queue[side_component.delay] or 0
        if side_component.power > 0 or scheduled_output > 0 then
            isLocked = true
            break
        end
    end

    if isLocked then
        self.nextPower = self.power
    else
        self.nextPower = self.queue[self.delay] or 0
        local inputPowered = false
        for j = 1, #self.inputs do
            if self.inputs[j].power > 0 then
                inputPowered = true; break
            end
        end
        local currentInput = inputPowered and 15 or 0
        table.insert(self.queue, 1, currentInput)
        table.remove(self.queue)
    end

    -- НОВОЕ: Проверяем, есть ли сигнал в очереди, чтобы симуляция не останавливалась
    local active = false
    for _, v in ipairs(self.queue) do
        if v > 0 then
            active = true; break
        end
    end
    self.isPending = active or (self.nextPower > 0)
end

-- ФАКЕЛ / ИСТОЧНИК / БЛОК
local Torch = setmetatable({}, Component)
Torch.__index = Torch
function Torch:calculate()
    local p = false
    for i = 1, #self.inputs do
        if self.inputs[i].power > 0 then
            p = true; break
        end
    end
    self.nextPower = p and 0 or 15
end

-- Полный блок
local Solid = setmetatable({}, Component)
Solid.__index = Solid
function Solid:calculate()
    local max = 0
    for i = 1, #self.inputs do
        -- Блок принимает любой сигнал, но важна только его сила
        if self.inputs[i].power > max then
            max = self.inputs[i].power
        end
    end
    self.nextPower = max
end

-- Поршни и остальные полные блоки которые потребляют редстоун
local Consumer = setmetatable({}, Component)
Consumer.__index = Consumer
function Consumer:calculate()
    local p = 0
    for i = 1, #self.inputs do
        if self.inputs[i].power > 0 then
            p = 999; break
        end
    end
    self.nextPower = p
end

-- Источник редстоун сигнала
local Source = setmetatable({}, Component)
Source.__index = Source
function Source:calculate(p)
    -- Если уже включен и нет pending, сохраняем состояние
    if self.power > 0 and not self.isPending then
        self.nextPower = self.power
        return
    end

    if self.isPending then
        self.nextPower = 15
        self.isPending = false
        return
    end

    if p ~= nil then
        self.nextPower = p
    elseif self.info and self.info.properties then
        local powered = (self.info.properties.powered == "true" or self.info.properties.powered == true)
        self.nextPower = powered and 15 or 0
    else
        self.nextPower = 0
    end
end

-- РАЗДАТЧИК / ВЫБРАСЫВАТЕЛЬ (THROWER)
local Thrower = setmetatable({}, Component)
Thrower.__index = Thrower
function Thrower:calculate()
    local p = 0
    for i = 1, #self.inputs do
        if self.inputs[i].power > 0 then
            p = 15; break
        end
    end
    self.nextPower = p
end

function Thrower:tryThrow(world_blocks)
    if self.nextPower == 0 then return false end

    local dx, dy, dz = self.facing.fx or 0, self.facing.fy or 0, self.facing.fz or 0
    local sx, sy, sz = self.x, self.y, self.z

    local landX, landY, landZ

    for i = 1, 3 do
        local tx, ty, tz = sx + dx * i, sy + dy * i, sz + dz * i
        local key = posKey(tx, ty, tz)
        local b = world_blocks[key]

        if b and b.info then
            local name = b.info.name:lower()
            local isWoodPlate = name:find("pressure_plate") and not name:find("stone") and not name:find("heavy") and
                not name:find("light")
            local isSolid = b.info.is_solid

            if isWoodPlate then
                if i < 3 then
                    local afterKey = posKey(tx + dx, ty + dy, tz + dz)
                    local afterBlock = world_blocks[afterKey]
                    local afterIsSolid = afterBlock and afterBlock.info and afterBlock.info.is_solid

                    if afterIsSolid then
                        landX, landY, landZ = tx, ty, tz
                        break
                    end
                else
                    landX, landY, landZ = tx, ty, tz
                    break
                end
            elseif isSolid then
                if i == 1 then
                    return false
                end

                landX, landY, landZ = tx - dx, ty - dy, tz - dz
                break
            end
        end

        if i == 3 then
            landX, landY, landZ = tx, ty, tz
        end
    end

    if not landX then return false end

    local checkKey = posKey(landX, landY, landZ)
    local checkBlock = world_blocks[checkKey]

    if checkBlock and checkBlock.info then
        local checkName = checkBlock.info.name:lower()
        if checkName:find("pressure_plate") and not checkName:find("stone") and not checkName:find("heavy") and not checkName:find("light") then
            if not checkBlock.power or checkBlock.power == 0 then
                checkBlock.nextPower = 15
                checkBlock.isPending = true
                return true
            end
        end
    end

    local underKey = posKey(landX, landY - 1, landZ)
    local underBlock = world_blocks[underKey]

    if underBlock and underBlock.info then
        local underName = underBlock.info.name:lower()
        if underName:find("pressure_plate") and not underName:find("stone") and not underName:find("heavy") and not underName:find("light") then
            if not underBlock.power or underBlock.power == 0 then
                underBlock.nextPower = 15
                underBlock.isPending = true
                return true
            end
        end
    end

    return false
end

-- КОМПАРАТОР
local Comparator = setmetatable({}, Component)
Comparator.__index = Comparator
function Comparator:calculate()
    local mainPower = 0
    -- Основной вход (сзади)
    for i = 1, #self.inputsMain do
        if self.inputsMain[i].power > mainPower then mainPower = self.inputsMain[i].power end
    end

    -- Боковые входы (максимальный из них)
    local sidePower = 0
    for i = 1, #self.inputsSide do
        if self.inputsSide[i].power > sidePower then sidePower = self.inputsSide[i].power end
    end

    local finalPower = 0
    if self.mode == "subtract" then
        finalPower = math.max(0, mainPower - sidePower)
    else -- mode "compare"
        finalPower = (mainPower >= sidePower) and mainPower or 0
    end

    self.nextPower = finalPower
end

-- ПОРШЕНЬ
local Piston = setmetatable({}, Component)
Piston.__index = Piston
function Piston:calculate()
    local p = 0
    for i = 1, #self.inputs do
        if self.inputs[i].power > 0 then
            p = 15; break
        end
    end

    -- Логика счетчика: если сигнал есть, увеличиваем. Если пропал — сбросим позже в tryMove.
    if p > 0 then
        self.activeTicks = (self.activeTicks or 0) + 1
    end

    self.nextPower = p
    self.nextState = (p > 0)
end

function Piston:tryMove(world_blocks, history)
    -- Если состояние не меняется, ничего не делаем
    if self.nextState == self.isExtended then return false end

    local dx, dy, dz = self.facing.fx or 0, self.facing.fy or 0, self.facing.fz or 0
    local moveList = {}
    local seen = {}

    -- Рекурсивный сбор группы блоков (Slime/Honey)
    local function collect(x, y, z)
        local key = posKey(x, y, z)
        if seen[key] then return true end

        local b = world_blocks[key]
        if not b or (b.info and b.info.is_air) then return true end
        if not isMovable(b) then return false end
        if b.x == self.x and b.y == self.y and b.z == self.z then return true end

        seen[key] = true
        table.insert(moveList, b)
        if #moveList > 12 then return false end

        -- Толкание вперед
        if not collect(x + dx, y + dy, z + dz) then return false end

        -- Слипание слизи/меда
        if isSlime(b) or isHoney(b) then
            local sides = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
            for _, s in ipairs(sides) do
                local nx, ny, nz = x + s[1], y + s[2], z + s[3]
                local neighbor = world_blocks[posKey(nx, ny, nz)]
                if neighbor and canStick(b, neighbor) then
                    if not collect(nx, ny, nz) then return false end
                end
            end
        end
        return true
    end

    if self.nextState then -- ВЫДВИЖЕНИЕ (Push)
        if not collect(self.x + dx, self.y + dy, self.z + dz) then return false end

        -- Сдвигаем группу вперед
        for i = #moveList, 1, -1 do
            local b = moveList[i]
            world_blocks[posKey(b.x, b.y, b.z)] = nil
            b.x, b.y, b.z = b.x + dx, b.y + dy, b.z + dz
        end
        for _, b in ipairs(moveList) do world_blocks[posKey(b.x, b.y, b.z)] = b end

        self.isExtended = true
        return true
    else -- ЗАДВИЖЕНИЕ (Retract)
        -- ЛОГИКА 1-ТИКОВОГО ИМПУЛЬСА (Dropping blocks)
        -- Если поршень был включен (power > 0) и в этом же шаге выключается (nextPower == 0)
        -- это считается коротким импульсом, и липкий поршень НЕ тянет блок.
        local isShortPulse = (self.power > 0 and self.nextPower == 0)

        self.isExtended = false

        -- Если поршень липкий и это НЕ короткий импульс — тянем блок
        if self.info.name:find("sticky") and not isShortPulse then
            if collect(self.x + dx * 2, self.y + dy * 2, self.z + dz * 2) then
                -- Сдвигаем группу назад
                for i = 1, #moveList do
                    local b = moveList[i]
                    world_blocks[posKey(b.x, b.y, b.z)] = nil
                    b.x, b.y, b.z = b.x - dx, b.y - dy, b.z - dz
                end
                for _, b in ipairs(moveList) do world_blocks[posKey(b.x, b.y, b.z)] = b end
                return true
            end
        end
    end
    return false
end

---------------------------------------------------------
-- 3. ОСНОВНОЙ КЛАСС RedstoneFast
---------------------------------------------------------

local function isRedstoneComponent(info, x, y, z, sources)
    if not info or info.is_air then return false end
    local name = info.name:lower()

    -- 1. Явные редстоун компоненты
    if name:find("redstone") or name:find("wire") or name:find("repeater") or
        name:find("torch") or name:find("comparator") or name:find("lever") or
        name:find("dropper") or name:find("despenser") or name:find("slime") or name:find("honey") or
        name:find("button") or name:find("pressure_plate") or name:find("observer") or
        name:find("piston") or name:find("lamp") then
        return true
    end

    -- 2. Пользовательские источники (из таблицы sources)
    if sources[posKey(x, y, z)] then
        return true
    end

    return false
end

---@return RedstoneFast
function RedstoneFast.new(world)
    return setmetatable({ world = world, blocks = {}, blockList = {}, sources = {}, movedBlocks = {} }, RedstoneFast)
end

function RedstoneFast:addSource(x, y, z, active)
    self.sources[posKey(x, y, z)] = active and 15 or 0
    print(string.format("§a[DEBUG] Источник на %d, %d установлен в %s", x, z, tostring(active)))
end

function RedstoneFast:clear()
    self.blocks = {}
    self.blockList = {}
    self.movedBlocks = {}
end

function RedstoneFast:scan(sx, sy, sz)
    local queue = { { x = sx, y = sy, z = sz, d = 0 } }
    local visited = {}

    -- Направления для обхода
    local ds = {
        { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 },
        { 1, 1, 0 }, { -1, 1, 0 }, { 0, 1, 1 }, { 0, 1, -1 }, { 1, -1, 0 }, { -1, -1, 0 }, { 0, -1, 1 }, { 0, -1, -1 },
        { 2, 0, 0 }, { -2, 0, 0 }, { 0, 2, 0 }, { 0, -2, 0 }, { 0, 0, 2 }, { 0, 0, -2 },
        { 2, 2, 0 }, { -2, 2, 0 }, { 0, 2, 2 }, { 0, 2, -2 }, { 2, -2, 0 }, { -2, -2, 0 }, { 0, -2, 2 }, { 0, -2, -2 }
    }

    while #queue > 0 do
        local curr = table.remove(queue, 1)
        local key = posKey(curr.x, curr.y, curr.z)

        -- Посещаем координату только один раз за этот скан
        if not visited[key] then
            visited[key] = true

            local info = self.world.getBlock(curr.x, curr.y, curr.z)
            if info then
                local isRS = isRedstoneComponent(info, curr.x, curr.y, curr.z, self.sources)
                local isSolid = info.is_solid

                if isRS or isSolid then
                    -- ПРОВЕРКА НА ДУБЛИКАТ:
                    -- Если блок по этим координатам уже существует в self.blocks,
                    -- мы используем его и НЕ добавляем в self.blockList снова.
                    local b = self.blocks[key]

                    if not b then
                        -- Блока еще нет, создаем и добавляем в список отрисовки
                        b = self:initBlock(curr.x, curr.y, curr.z, info)
                        if b then
                            self.blocks[key] = b
                            table.insert(self.blockList, b)
                        end
                    end

                    -- Если блок найден или создан, продолжаем сканировать соседей
                    if b then
                        for i = 1, #ds do
                            local nx, ny, nz = curr.x + ds[i][1], curr.y + ds[i][2], curr.z + ds[i][3]
                            local nKey = posKey(nx, ny, nz)

                            -- Добавляем соседа в очередь, если мы его еще не посетили в ЭТОМ скане
                            if not visited[nKey] and curr.d < 256 then
                                if isRS then
                                    table.insert(queue, { x = nx, y = ny, z = nz, d = curr.d + 1 })
                                elseif isSolid then
                                    local nInfo = self.world.getBlock(nx, ny, nz)
                                    if nInfo and isRedstoneComponent(nInfo, nx, ny, nz, self.sources) then
                                        table.insert(queue, { x = nx, y = ny, z = nz, d = curr.d + 1 })
                                    end
                                end
                            end
                        end

                        -- Форсированный скан перед поршнем
                        if b.type == "piston" then
                            local dx, dy, dz = b.facing.fx, b.facing.fy, b.facing.fz
                            for i = 1, 12 do
                                local tx, ty, tz = b.x + dx * i, b.y + dy * i, b.z + dz * i
                                local tKey = posKey(tx, ty, tz)
                                if not visited[tKey] then
                                    table.insert(queue, { x = tx, y = ty, z = tz, d = curr.d + 1 })
                                end
                            end
                        end

                        -- Форсированный скан перед выбрасывателем
                        if b.type == "thrower" then
                            local dx, dy, dz = b.facing.fx, b.facing.fy, b.facing.fz
                            for i = 1, 3 do
                                local tx, ty, tz = b.x + dx * i, b.y + dy * i, b.z + dz * i
                                local tKey = posKey(tx, ty, tz)
                                if not visited[tKey] then
                                    table.insert(queue, { x = tx, y = ty, z = tz, d = curr.d + 1 })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- Пересчитываем связи между всеми найденными блоками
    self:link()
end

function RedstoneFast:initBlock(x, y, z, info)
    local name = info.name:lower()
    local key = posKey(x, y, z)

    -- Более строгий список прозрачных блоков (не проводящих сигнал)
    local isTransparent = name:find("slab") or
        name:find("glass") or
        name:find("stairs") or
        name:find("leaves") or
        name:find("hopper") or
        name:find("glowstone") or
        name:find("observer")

    local canConduct = info.is_solid and not isTransparent
    local b = nil
    if (name:find("wire") or (name:find("redstone"))) and not name:find("torch") and not name:find("trip") and not name:find("lamp") then
        b = Component.new(x, y, z, info, "wire")
        setmetatable(b, Wire)
    elseif name:find("repeater") then
        b = Component.new(x, y, z, info, "repeater")
        b.facing = getDirections(info.facing)
        b.inputsSide = {}
        b.delay = (info.delay and tonumber(info.delay)) or 1
        -- Очередь задержки (пустая при старте предсказания)
        b.queue = { 0, 0, 0, 0 }
        b.power = 0 -- Начинаем с выключенного состояния
        setmetatable(b, Repeater)
    elseif name:find("torch") then
        b = setmetatable(Component.new(x, y, z, info, "torch"), Torch)
    elseif name:find("observer") then
        b = Component.new(x, y, z, info, "observer")
        -- Получаем стандартные векторы
        local d = getDirectionsPiston(info.facing)

        -- ИНВЕРСИЯ:
        -- Лицо (bx) теперь там, куда указывает facing (d.fx)
        -- Выход (fx) теперь сзади (d.bx)
        b.facing = {
            bx = d.fx,
            by = d.fy,
            bz = d.fz, -- Глаза (Вход)
            fx = d.bx,
            fy = d.by,
            fz = d.bz, -- Точка (Выход)
        }

        b.lastPower = 0
        b.lastId = "air"
        b.lastExt = false
        b.queue = { 0, 0, 0 }
        b.power = 0
        setmetatable(b, Observer)
    elseif name:find("piston") then
        b = Component.new(x, y, z, info, "piston")
        b.facing = getDirectionsPiston(info.facing)
        b.activeTicks = 0
        b.isExtended = info.extended
        --b.isExtended = false
        setmetatable(b, Piston)
    elseif name:find("dispenser") or name:find("dropper") then
        b = Component.new(x, y, z, info, "thrower")
        b.facing = getDirectionsPiston(info.facing)
        setmetatable(b, Thrower)
    elseif name:find("crafter") or name:find("lamp") or name:find("bulb") then
        b = setmetatable(Component.new(x, y, z, info, "super_consumer"), SuperConsumer)
    elseif name:find("lever") or name:find("button") or name:find("pressure_plate") then
        b = setmetatable(Component.new(x, y, z, info, "source"), Source)
    elseif self.sources[key] then
        b = setmetatable(Component.new(x, y, z, info, "source"), Source)
    elseif name:find("comparator") then
        b = Component.new(x, y, z, info, "comparator")
        b.facing = getDirections(info.facing)
        b.mode = tostring(info.mode) or "compare"
        b.inputsMain = {}
        b.inputsSide = {}
        setmetatable(b, Comparator)
    elseif info.is_solid then
        b = setmetatable(Component.new(x, y, z, info, "solid"), Solid)
    end

    if b then
        b.startX, b.startY, b.startZ = x, y, z -- Сохраняем "точку старта"
        b.canConduct = canConduct
        return b
    end
end

function RedstoneFast:link()
    -- Очистка старых связей
    for _, b in ipairs(self.blockList) do b.inputs = {} end

    for _, b in ipairs(self.blockList) do
        local function get(dx, dy, dz) return self.blocks[posKey(b.x + dx, b.y + dy, b.z + dz)] end

        ---------------------------------------------------------
        -- 1. ПЫЛЬ (WIRE) - Логика 1.16+
        ---------------------------------------------------------
        if b.type == "wire" then
            local function connects(nb)
                if not nb then return false end
                -- Пыль тянется ТОЛЬКО к редстоун-компонентам
                return nb.type == "wire" or nb.type == "repeater" or
                    nb.type == "torch" or nb.type == "source" or nb.type == "comparator"
            end

            local n_nb, s_nb = get(0, 0, -1), get(0, 0, 1)
            local e_nb, w_nb = get(1, 0, 0), get(-1, 0, 0)
            local n, s, e, w = connects(n_nb), connects(s_nb), connects(e_nb), connects(w_nb)

            local isDot = not (n or s or e or w)

            -- Определяем форму (куда смотрят "усики")
            local pN, pS, pE, pW = false, false, false, false

            if not (n or s or e or w) then
                -- Если нет соединений, это "крест" (точка), светит во все стороны
                pN, pS, pE, pW = true, true, true, true
            else
                -- Если есть хоть одно соединение, пыль светит туда, куда соединена
                pN = n; pS = s; pE = e; pW = w
                -- Добавляем логику прямой линии: если есть Север, но нет остального - светит и на Юг
                if n and not (s or e or w) then pS = true end
                if s and not (n or e or w) then pN = true end
                if e and not (w or n or s) then pW = true end
                if w and not (e or n or s) then pE = true end
            end

            -- Пыль ПЕРЕДАЕТ сигнал только туда, куда она направлена
            local function push(target)
                if target and target.type ~= "torch" and target.type ~= "repeater" then
                    table.insert(target.inputs, b)
                end
            end

            if pN then push(n_nb) end
            if pS then push(s_nb) end
            if pE then push(e_nb) end
            if pW then push(w_nb) end

            -- Вертикальные ступеньки (только для другой пыли)
            local steps = { { 1, 1, 0 }, { -1, 1, 0 }, { 0, 1, 1 }, { 0, 1, -1 }, { 1, -1, 0 }, { -1, -1, 0 }, { 0, -1, 1 }, { 0, -1, -1 } }
            for i = 1, #steps do
                local nb = get(steps[i][1], steps[i][2], steps[i][3])
                if nb and nb.type == "wire" then table.insert(b.inputs, nb) end
            end

            -- БЛОК ПОД ПЫЛЬЮ (Пыль всегда его запитывает)
            local bottom = get(0, -1, 0)
            if bottom then
                table.insert(bottom.inputs, b) -- Пыль -> Блок под ней
                table.insert(b.inputs, bottom) -- Пыль <- Блок под ней (может быть запитан факелом)

                local bottom2 = get(0, -2, 0)
                if bottom2 and (bottom2.type == "piston") then
                    table.insert(bottom2.inputs, bottom)
                    --table.insert(bottom.inputs, bottom2)

                    local bottom3 = get(0, -3, 0)
                    if bottom3 and (bottom2.type == "piston") then
                        table.insert(bottom3.inputs, bottom2) -- Пыль -> Блок под ней
                        --table.insert(bottom2.inputs, bottom3) -- Пыль <- Блок под ней (может быть запитан факелом)
                    end
                end
            end


            ---------------------------------------------------------
            -- 2. ПОВТОРИТЕЛЬ (REPEATER)
            ---------------------------------------------------------
        elseif b.type == "repeater" then
            b.inputs = {}
            b.inputsSide = {}

            -- 1. Вход сзади
            local back = get(b.facing.bx, 0, b.facing.bz)
            if back then table.insert(b.inputs, back) end

            -- 2. Боковые входы (СТРОГАЯ ПРОВЕРКА НАПРАВЛЕНИЯ)

            local function checkSide(dx, dz)
                local side = get(dx, 0, dz)
                if side and (side.type == "repeater" or side.type == "comparator" or side.type == "wire") then
                    -- Если это повторитель/компаратор, проверяем, что он смотрит в нас
                    if side.type ~= "wire" then
                        local pointsAtMe = (side.x + side.facing.fx == b.x) and (side.z + side.facing.fz == b.z)
                        if pointsAtMe then table.insert(b.inputsSide, side) end
                    end
                end
            end

            -- Проверяем блоки слева и справа относительно направления повторителя
            checkSide(b.facing.lx, b.facing.lz)
            checkSide(b.facing.rx, b.facing.rz)

            -- 3. Выход вперед
            local front = get(b.facing.fx, 0, b.facing.fz)
            if front then table.insert(front.inputs, b) end

            ---------------------------------------------------------
            -- 3. ПОРШЕНЬ / ЛАМПА / ВЫБРАСЫВАТЕЛЬ (CONSUMER)
            ---------------------------------------------------------
        elseif b.type == "consumer" or b.type == "piston" or b.type == "thrower" then
            -- Список всех 6 соседних координат (dx, dy, dz)
            local ds = {
                { x = 1, y = 0, z = 0, from = "e" },  -- Сосед на Востоке (+X)
                { x = -1, y = 0, z = 0, from = "w" }, -- Сосед на Западе (-X)
                { x = 0, y = -1, z = 0, from = "d" }, -- Сосед снизу (-Y)
                { x = 0, y = 0, z = 1, from = "s" },  -- Сосед на Юге (+Z)
                { x = 0, y = 0, z = -1, from = "n" }  -- Сосед на Севере (-Z)
            }

            for i = 1, #ds do
                local off = ds[i]
                local nb = get(off.x, off.y, off.z)

                if nb then
                    if nb.type == "wire" then
                        -- СПЕЦИАЛЬНАЯ ЛОГИКА ДЛЯ ПЫЛИ (1.16+)
                        -- Пыль запитывает механизм, если она СВЕРХУ или НАПРАВЛЕНА в него
                        local isDirected = false
                        if off.from == "u" then
                            isDirected = true -- Пыль сверху всегда запитывает
                        elseif off.from == "e" and nb.dirs and nb.dirs.w then
                            isDirected = true -- Пыль на Востоке смотрит на Запад
                        elseif off.from == "w" and nb.dirs and nb.dirs.e then
                            isDirected = true -- Пыль на Западе смотрит на Восток
                        elseif off.from == "s" and nb.dirs and nb.dirs.n then
                            isDirected = true -- Пыль на Юге смотрит на Север
                        elseif off.from == "n" and nb.dirs and nb.dirs.s then
                            isDirected = true -- Пыль на Севере смотрит на Юг
                        end

                        if isDirected then
                            table.insert(b.inputs, nb)
                        end
                    else
                        -- СТАРОЕ ПОВЕДЕНИЕ (для всех остальных типов)
                        -- Просто добавляем соседа как вход, если это редстоун-компонент или твердый блок
                        if nb.type == "torch" or nb.type == "repeater" or nb.type == "solid" or
                            nb.type == "source" or nb.type == "observer" or nb.type == "comparator" then
                            table.insert(b.inputs, nb)
                        end
                    end
                end
            end

            ---------------------------------------------------------
            -- 4. ТВЕРДЫЙ БЛОК (SOLID)
            ---------------------------------------------------------
        elseif b.type == "solid" then
            local ds = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }
            for i = 1, #ds do
                local target = get(ds[i][1], ds[i][2], ds[i][3])
                if target and (target.type == "piston" or target.type == "super_consumer" or target.type == "wire") then
                    table.insert(target.inputs, b)
                end
            end

            ---------------------------------------------------------
            -- 5. ФАКЕЛ И ОСТАЛЬНОЕ
            ---------------------------------------------------------
        elseif b.type == "torch" or b.type == "source" then
            -- 1. Определяем, на каком блоке висит компонент (Parent)
            local f = "up" -- По умолчанию (на полу)
            if b.info and b.info.facing then
                f = tostring(b.info.facing):lower()
            end

            local px, py, pz = 0, 0, 0
            if f == "north" then
                pz = 1
            elseif f == "south" then
                pz = -1
            elseif f == "east" then
                px = -1
            elseif f == "west" then
                px = 1
            else
                py = -1
            end -- Для напольных факелов и кнопок на верхней грани

            -- Блок-основание выключает факел
            if b.type == "torch" then
                local parent = get(px, py, pz)
                if parent then table.insert(b.inputs, parent) end
            end

            -- 2. Передача сигнала ОТ факела/источника СОСЕДЯМ
            local ds = {
                { 1,  0,  0 },
                { -1, 0,  0 },
                { 0,  1,  0 },
                { 0,  -1, 0 },
                { 0,  0,  1 },
                { 0,  0,  -1 },
                { 0,  -2, 0 }
            }

            for i = 1, #ds do
                local dx, dy, dz = ds[i][1], ds[i][2], ds[i][3]
                local target = get(dx, dy, dz)

                if target then
                    -- ВАЖНО: Факел НЕ запитывает блок, на котором висит (parent)
                    local isParent = (dx == px and dy == py and dz == pz)

                    if b.type == "source" then
                        -- Кнопка/рычаг запитывают всё вокруг
                        if target.type ~= "repeater" then table.insert(target.inputs, b) end
                    elseif b.type == "torch" and not isParent then
                        -- Квазис связь
                        if dx == 0 and dy == -2 and dz == 0 then
                            if target.type == "consumer" or target.type == "piston" then
                                table.insert(target.inputs, b)
                            end
                        else
                            -- Факел запитывает всё вокруг, кроме своего блока-основания
                            if target.type ~= "repeater" then
                                table.insert(target.inputs, b)
                            end
                        end
                    end
                end
            end
            ---------------------------------------------------------
            -- 6. КОМПАРАТОР (COMPARATOR)
            ---------------------------------------------------------
        elseif b.type == "comparator" then
            -- 1. Сбор входов
            local back = get(b.facing.bx, 0, b.facing.bz)
            if back then table.insert(b.inputsMain, back) end

            local left = get(b.facing.lx, 0, b.facing.lz)
            if left then table.insert(b.inputsSide, left) end

            local right = get(b.facing.rx, 0, b.facing.rz)
            if right then table.insert(b.inputsSide, right) end

            -- 2. Передача сигнала вперед
            local front = get(b.facing.fx, 0, b.facing.fz)
            if front then
                table.insert(front.inputs, b)
            end
            ---------------------------------------------------------
            -- 7. НАБЛЮДАТЕЛЬ (OBSERVER)
            ---------------------------------------------------------
        elseif b.type == "observer" then
            -- Точка, куда смотрит лицо наблюдателя
            local tx, ty, tz = b.x + b.facing.bx, b.y + b.facing.by, b.z + b.facing.bz
            local targetKey = posKey(tx, ty, tz)

            -- Вариант А: Перед лицом есть блок
            b.inputTarget = self.blocks[targetKey]

            -- Вариант Б: Перед лицом пусто, но туда может выдвинуться головка поршня
            if not b.inputTarget then
                -- Ищем поршень вокруг этой пустой точки, который направлен в неё
                local neighbors = {
                    { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 }
                }
                for _, offset in ipairs(neighbors) do
                    local potentialPiston = self.blocks[posKey(tx + offset[1], ty + offset[2], tz + offset[3])]
                    if potentialPiston and potentialPiston.type == "piston" then
                        -- Проверяем, смотрит ли этот поршень в точку tx, ty, tz
                        local pFace = potentialPiston.facing
                        local headX = potentialPiston.x + (pFace.fx or 0)
                        local headY = potentialPiston.y + (pFace.fy or 0)
                        local headZ = potentialPiston.z + (pFace.fz or 0)

                        if headX == tx and headY == ty and headZ == tz then
                            b.inputTarget = potentialPiston
                            break
                        end
                    end
                end
            end

            -- Выход (красная точка)
            local ox, oy, oz = b.x + b.facing.fx, b.y + b.facing.fy, b.z + b.facing.fz
            local outputTarget = self.blocks[posKey(ox, oy, oz)]
            if outputTarget then
                table.insert(outputTarget.inputs, b)
            end
        end
    end
end

---@return boolean
function RedstoneFast:step()
    local changed = false

    -- 1. ФАЗА ПРИМЕНЕНИЯ (Механизмы обновляют свою энергию)
    for _, b in ipairs(self.blockList) do
        if b.type == "repeater" or b.type == "torch" or b.type == "piston" or
            b.type == "consumer" or b.type == "super_consumer" or b.type == "comparator" or
            b.type == "observer" or b.type == "thrower" or b.type == "source" then
            if b.power ~= b.nextPower or b.isPending then
                b.power = b.nextPower
                b.isPending = false
                changed = true
            end
        end
    end

    -- 2. ФАЗА РАСПРОСТРАНЕНИЯ (Пыль и блоки)
    local instantChanged = true
    local limit = 0
    while instantChanged and limit < 100 do
        limit = limit + 1
        instantChanged = false
        for _, b in ipairs(self.blockList) do
            if b.type == "wire" or b.type == "solid" or b.type == "source" then
                local oldP = b.power
                if b.type == "source" then
                    b:calculate(self.sources[posKey(b.x, b.y, b.z)])
                else
                    b:calculate()
                end

                if b.nextPower ~= oldP then
                    b.power = b.nextPower
                    instantChanged = true
                    changed = true
                end
            end
        end
    end

    -- 3. ФАЗА РАСЧЕТА (Механизмы смотрят на пыль и планируют следующий шаг)
    for _, b in ipairs(self.blockList) do
        if b.type == "repeater" or b.type == "torch" or b.type == "piston" or
            b.type == "consumer" or b.type == "super_consumer" or b.type == "comparator" or
            b.type == "observer" or b.type == "thrower" or b.type == "source" then
            local oldNP = b.nextPower
            b:calculate()
            if b.nextPower ~= oldNP or b.isPending then
                changed = true
            end
        end
    end

    -- 4. ФАЗА ПОРШНЕЙ И ВЫБРАСЫВАТЕЛЕЙ
    local blocksMoved = false
    for _, b in ipairs(self.blockList) do
        if b.type == "piston" and b.nextState ~= b.isExtended then
            if b:tryMove(self.blocks, self.movedBlocks) then
                blocksMoved = true
            end
        elseif b.type == "thrower" and b.nextPower > 0 and b.power == 0 then
            if b:tryThrow(self.blocks) then
                blocksMoved = true
            end
        end
    end

    if blocksMoved then
        self:link()
        changed = true
    end

    return changed
end

function RedstoneFast:predict()
    local it = 0
    while self:step() and it < 100 do it = it + 1 end
end

---@return ActiveBlock[]
function RedstoneFast:getActiveBlocks()
    local res = {}
    for _, b in ipairs(self.blockList) do
        if b.power > 0 and b.type ~= "solid" then
            table.insert(res, b)
        end
    end
    return res
end

---@return MovedBlock[]
function RedstoneFast:getMovedBlocks()
    local moved = {}
    for _, b in ipairs(self.blockList) do
        if b.startX and (b.x ~= b.startX or b.y ~= b.startY or b.z ~= b.startZ) then
            table.insert(moved, {
                id = b.info.id,
                x = b.x,
                y = b.y,
                z = b.z
            })
        end
    end
    return moved
end

return RedstoneFast
