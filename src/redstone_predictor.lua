local RedstoneFast = {}
RedstoneFast.__index = RedstoneFast

---------------------------------------------------------
-- 1. НАСТРОЙКА ОСЕЙ (С учетом East = -X)
---------------------------------------------------------
-- fx/fz - смещение выхода (FRONT)
-- bx/bz - смещение входа (BACK)
local function getDirections(facing)
    local f = tostring(facing or "north"):lower()
    local dirs = {
        -- fx/fz - ВЫХОД (перед), bx/bz - ВХОД (зад)
        north = {fx=0, fz=1,  bx=0, bz=-1},
        south = {fx=0, fz=-1, bx=0, bz=1},
        east  = {fx=-1, fz=0, bx=1, bz=0},
        west  = {fx=1, fz=0,  bx=-1, bz=0}
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
        x = x, y = y, z = z,
        info = info,
        type = typeName,
        power = 0,
        nextPower = 0,
        inputs = {} -- Ссылки на объекты
    }, Component)
end

-- ПЫЛЬ
local Wire = setmetatable({}, Component)
Wire.__index = Wire
function Wire:calculate()
    local max = 0
    for i = 1, #self.inputs do
        local inp = self.inputs[i]
        local p = 0
        if inp.type == "wire" then
            p = inp.power - 1
        else
            p = inp.power
        end
        if p > max then max = p end
    end
    self.nextPower = math.max(0, max)
end

-- ПОВТОРИТЕЛЬ
local Repeater = setmetatable({}, Component)
Repeater.__index = Repeater
function Repeater:calculate()
    local powered = false
    -- Проверяем только те блоки, которые попали в inputs через логику "СЗАДИ" в link
    for i = 1, #self.inputs do
        if self.inputs[i].power > 0 then
            powered = true
            break
        end
    end
    self.nextPower = powered and 15 or 0
end
-- ФАКЕЛ / ИСТОЧНИК / БЛОК
local Torch = setmetatable({}, Component)
Torch.__index = Torch
function Torch:calculate()
    local p = false
    for i=1, #self.inputs do if self.inputs[i].power > 0 then p = true; break end end
    self.nextPower = p and 0 or 15
end

local Solid = setmetatable({}, Component)
Solid.__index = Solid
function Solid:calculate()
    local max = 0
    for i=1, #self.inputs do if self.inputs[i].power > max then max = self.inputs[i].power end end
    self.nextPower = max
end

local Consumer = setmetatable({}, Component)
Consumer.__index = Consumer
function Consumer:calculate()
    local p = 0
    for i=1, #self.inputs do 
        if self.inputs[i].power > 0 then p = 999; break end 
    end
    self.nextPower = p
end


local Source = setmetatable({}, Component)
Source.__index = Source
function Source:calculate(p) 
    if p then 
        -- Если задано вручную через addSource
        self.nextPower = p 
    else
        -- Читаем состояние из свойств блока Minecraft
        -- В большинстве модов это поле properties.powered
        local powered = false
        if self.info and self.info.properties then
            powered = (self.info.properties.powered == "true" or self.info.properties.powered == true)
        end
        self.nextPower = powered and 15 or 0
    end
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
	   name:find("dropper") or name:find("despenser") or 
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

function RedstoneFast.new(world)
    return setmetatable({world=world, blocks={}, blockList={}, sources={}}, RedstoneFast)
end

function RedstoneFast:addSource(x, y, z, active)
    self.sources[posKey(x, y, z)] = active and 15 or 0
    print(string.format("§a[DEBUG] Источник на %d, %d установлен в %s", x, z, tostring(active)))
end

function RedstoneFast:scan(sx, sy, sz)
    -- Очищаем старые данные
    self.blocks = {}
    self.blockList = {}
    
    local queue = {{x=sx, y=sy, z=sz, d=0}}
    local visited = {}
    
    -- Направления для обхода (6 сторон + диагонали для пыли)
    local ds = {
        {1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1},
        {1,1,0}, {-1,1,0}, {0,1,1}, {0,1,-1}, {1,-1,0}, {-1,-1,0}, {0,-1,1}, {0,-1,-1}
    }

    while #queue > 0 do
        local curr = table.remove(queue, 1)
        local key = posKey(curr.x, curr.y, curr.z)
        
        if not visited[key] and curr.d < 128 then -- Увеличил лимит дистанции
            visited[key] = true
            
            local info = self.world.getBlock(curr.x, curr.y, curr.z)
            if info then
                local isRS = isRedstoneComponent(info, curr.x, curr.y, curr.z, self.sources)
                local isSolid = info.is_solid
                
                -- Инициализируем блок, только если он редстоун или полезный Solid
                if isRS or isSolid then
                    local b = self:initBlock(curr.x, curr.y, curr.z, info)
                    if b then
                        self.blocks[key] = b
                        table.insert(self.blockList, b)
                        
                        -- ГЛАВНАЯ ОПТИМИЗАЦИЯ:
                        -- Если это обычный блок (камень), мы НЕ идем от него к другим камням.
                        -- Мы продолжаем сканирование только если:
                        -- 1. Это редстоун-компонент (он может вести к камню или другому редстоуну)
                        -- 2. Это камень, но мы проверяем соседей только в поисках редстоуна.
                        
                        for i=1, #ds do
                            local nx, ny, nz = curr.x+ds[i][1], curr.y+ds[i][2], curr.z+ds[i][3]
                            local nKey = posKey(nx, ny, nz)
                            
                            if not visited[nKey] then
                                -- Если текущий блок - редстоун, проверяем всех соседей
                                if isRS then
                                    table.insert(queue, {x=nx, y=ny, z=nz, d=curr.d+1})
                                -- Если текущий блок - камень, добавляем соседа только если это редстоун
                                elseif isSolid then
                                    local nInfo = self.world.getBlock(nx, ny, nz)
                                    if nInfo and isRedstoneComponent(nInfo, nx, ny, nz, self.sources) then
                                        table.insert(queue, {x=nx, y=ny, z=nz, d=curr.d+1})
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    print(string.format("§7[DEBUG] Сканирование завершено. Найдено компонентов: %d", #self.blockList))
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
    if (name:find("wire") or (name:find("redstone"))) and not name:find("torch") and not name:find("trip") then 
        b = Component.new(x, y, z, info, "wire")
        setmetatable(b, Wire)
    elseif name:find("repeater") then
        b = Component.new(x, y, z, info, "repeater")
        b.facing = getDirections(info.facing, x, z)
        setmetatable(b, Repeater)
    elseif name:find("torch") then 
        b = setmetatable(Component.new(x, y, z, info, "torch"), Torch)
    elseif name:find("piston") or name:find("dispenser") or name:find("dropper") or name:find("crafter") then
        b = setmetatable(Component.new(x, y, z, info, "consumer"), Consumer)
    elseif name:find("lever") or name:find("button") or name:find("pressure_plate") then
        b = setmetatable(Component.new(x, y, z, info, "source"), Source)
    elseif self.sources[key] then 
        b = setmetatable(Component.new(x, y, z, info, "source"), Source)
    elseif info.is_solid then 
        b = setmetatable(Component.new(x, y, z, info, "solid"), Solid)
    end

    if b then
        -- Явно прописываем true/false, чтобы не было nil
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
                       nb.type == "torch" or nb.type == "source"
            end

            local n_nb, s_nb = get(0, 0, -1), get(0, 0, 1)
            local e_nb, w_nb = get(1, 0, 0), get(-1, 0, 0)
            local n, s, e, w = connects(n_nb), connects(s_nb), connects(e_nb), connects(w_nb)

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

            -- Пыль ВСЕГДА запитывает блок под собой (если он проводит ток)
            local bottom = get(0, -1, 0)
            if bottom and bottom.type ~= "repeater" then
                table.insert(bottom.inputs, b)
            end

            -- Вертикальные ступеньки (только для другой пыли)
            local steps = {{1,1,0},{-1,1,0},{0,1,1},{0,1,-1},{1,-1,0},{-1,-1,0},{0,-1,1},{0,-1,-1}}
            for i=1, #steps do
                local nb = get(steps[i][1], steps[i][2], steps[i][3])
                if nb and nb.type == "wire" then table.insert(b.inputs, nb) end
            end

        ---------------------------------------------------------
        -- 2. ПОВТОРИТЕЛЬ (REPEATER)
        ---------------------------------------------------------
        elseif b.type == "repeater" then
            local back = get(b.facing.bx, 0, b.facing.bz)
            if back then table.insert(b.inputs, back) end
            
            local front = get(b.facing.fx, 0, b.facing.fz)
            if front then table.insert(front.inputs, b) end

        ---------------------------------------------------------
        -- 3. ПОРШЕНЬ / ЛАМПА (CONSUMER)
        ---------------------------------------------------------
        elseif b.type == "consumer" then
            -- Поршень НЕ берет сигнал от пыли сбоку. 
            -- Он ждет, пока пыль сама "направится" на него (через функцию push выше)
            -- Но он всё еще берет сигнал от факелов, повторителей и запитанных блоков рядом.
            local ds = {{1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1}}
            for i=1, #ds do
                local nb = get(ds[i][1], ds[i][2], ds[i][3])
                if nb and (nb.type == "torch" or nb.type == "repeater" or nb.type == "solid" or nb.type == "source") then
                    table.insert(b.inputs, nb)
                end
            end

        ---------------------------------------------------------
        -- 4. ТВЕРДЫЙ БЛОК (SOLID)
        ---------------------------------------------------------
        elseif b.type == "solid" then
            local ds = {{1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1}}
            for i=1, #ds do
                local target = get(ds[i][1], ds[i][2], ds[i][3])
                -- Камень передает сигнал поршням, но НЕ пыли (пыль сама берет из камня)
                if target and target.type == "consumer" then 
                    table.insert(target.inputs, b) 
                end
            end

        ---------------------------------------------------------
        -- 5. ФАКЕЛ И ОСТАЛЬНОЕ
        ---------------------------------------------------------
        elseif b.type == "torch" or b.type == "source" then
            local ds = {{1,0,0}, {-1,0,0}, {0,1,0}, {0,-1,0}, {0,0,1}, {0,0,-1}}
            for i=1, #ds do
                local target = get(ds[i][1], ds[i][2], ds[i][3])
                if target and target.type ~= "repeater" then table.insert(target.inputs, b) end
            end
            -- Если это факел, добавим логику parent-блока
            if b.type == "torch" then
                local f = tostring(b.info.facing)
                local px, py, pz = 0, 0, 0
                if f == "north" then pz = 1 elseif f == "south" then pz = -1
                elseif f == "east" then px = -1 elseif f == "west" then px = 1 else py = -1 end
                local parent = get(px, py, pz)
                if parent then table.insert(b.inputs, parent) end
            end
			
			local face = b.face or "up"
			
			if face ~= "wall" then
				
			end
        end
    end
end

function RedstoneFast:step()
    local changed = false
    for _, b in ipairs(self.blockList) do
        if b.type == "source" then b:calculate(self.sources[posKey(b.x, b.y, b.z)]) else b:calculate() end
    end
    for _, b in ipairs(self.blockList) do
        if b.power ~= b.nextPower then b.power = b.nextPower; changed = true end
    end
    return changed
end

function RedstoneFast:predict()
    local it = 0
    while self:step() and it < 100 do it = it + 1 end
end

function RedstoneFast:getActiveBlocks()
    local res = {}
    for _, b in ipairs(self.blockList) do 
        -- Показываем питание только для редстоун-компонентов и поршней
        -- Исключаем обычные блоки (solid), чтобы они не подсвечивались
        if b.power > 0 and b.type ~= "solid" then 
            table.insert(res, b) 
        end 
    end
    return res
end

return RedstoneFast