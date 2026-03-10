-- @version 1.2
-- @location /libs/

local iut = require("inventory_utils")

local idk = "idk"
local idkInt = -1
local idkPos = { x = -1, y = -1, z = -1 }
local regexes = {
  petNameInAutopet = "%[Lvl %d+%] §.(.*)§.!",
  petNameInManualSummon = "You summoned your (.-)!",
  petNameInTab = "%[Lvl %d+%] (.+)",
  petNameInPetsMenu = "%[Lvl %d+%] (.+)%]"
}

-- i like 3 letter words for naming schemes so cope with this bs naming scheme
-- inf stands for info
---@class inf
---@field location string
---@field pet string
---@field petName string
---@field visitors number
---@field spray string | nil
---@field pestCd number
---@field pos {x: number, y: number, z: number}
---@field velocity number
---@field blockBelowFeet string
---@field rain number
---@field comms table | nil
---@field heldItem any | nil

---@class All
---@field inf inf
local all = {
  inf = {
    location = idk,
    pet = idk,
    petName = idk,
    visitors = idkInt,
    spray = idk,
    pestCd = idkInt,
    pos = idkPos,
    velocity = idkInt,
    blockBelowFeet = idk,
    rain = idkInt,
    comms = nil,
    heldItem = nil
  },
  tgl = {
    location = false,
    pet = false,
    visitors = false,
    spray = false,
    pestCd = false,
    pos = false,
    velocity = false,
    blockBelowFeet = false,
    rain = false,
    comms = false,
    heldItem = false
  },
  clr = {
    reset = "§r",
    bold = "§l",
    strikeThrough = "§m",
    underline = "§n",
    italic = "§o",
    obfuscated = "§k",

    black = "§0",
    blueDark = "§1",
    greenDark = "§2",
    aquaDark = "§3",
    redDark = "§4",
    purpleDark = "§5",
    gold = "§6",
    gray = "§7",
    grayDark = "§8",
    blue = "§9",
    green = "§a",
    aqua = "§b",
    red = "§c",
    purpleLight = "§d",
    yellow = "§e",
    white = "§f",
  },
  dump = {},
  tmp = {},
  _cds = {},
  gdrs = {},
  _wtr = {}
}

--------------------------------------------------------------------------------

---@param string string
---@return nil
local function grint(string)
  print("[goon] " .. string)
end
--------------------------------------------------------------------------------

---@param text string
---@return string
function all.remMcColors(text)
  if not text then return "" end
  local clean, _ = string.gsub(text, "§.", "")
  return string.match(clean, "^%s*(.-)%s*$") -- strip leading/trailing spaces
end

--------------------------------------------------------------------------------

function all.getInvItem(s)
  if not player.inventory.isAnyScreenOpened() then return nil end
  local slot = player.inventory.getStackFromContainer(s)
  if not slot then return nil end

  -- altering some stuff
  if slot.display_name then
    slot.display_name = slot.display_name:lower()
  end

  return slot
end

--------------------------------------------------------------------------------

--- @return any | nil
function all.getHeldItem()
  local test = player.input.getSelectedSlot()
  if test or test > -1 and test < 9 then
    local heldItem = player.inventory.getStack(test)
    return heldItem
  end
  return nil
end

-- default uidType is display_name
--- @return boolean
function all.holdItem(itemUid, uidType)

  local heldItem = all.getHeldItem()

  -- hold item by display_name
  if not uidType then
    -- already held
    if heldItem.display_name == itemUid then return true end
    -- not already held, hold it
    local item = iut.findItemByDisplayNameInHotbar(itemUid)
    if not item then return false end
    player.input.setSelectedSlot(item)
  end

  if uidType == "skyblock_id" then
    -- already held
    if heldItem and heldItem.skyblock_id == itemUid then return true end
    -- not already held hold it
    local item = iut.getItemInHotbar(itemUid)
    if not item then return false end
    player.input.setSelectedSlot(item)
    return true
  end

  if uidType == "name" then
  end

end

--------------------------------------------------------------------------------

---@param num1 number
---@param num2 number
---@param tolerance number
---@return boolean
function all.isNumCloseTo(num1, num2, tolerance)
  return math.abs(num1 - num2) < tolerance
end

--- @param pos1 table<string, number>
--- @param pos2 table<string, number>
--- @param tolerance number
--- @return boolean
function all.isPosCloseTo(pos1, pos2, tolerance)
    local dx = pos1.x - pos2.x
    local dy = pos1.y - pos2.y
    local dz = pos1.z - pos2.z

    -- compare distance squared to tolerance squared
    return (dx^2 + dy^2 + dz^2) < (tolerance^2)
end

--------------------------------------------------------------------------------

---@param table table
---@return string
function all.tableToString(table)
    local result = "{ "
    local first = true

    for k, v in pairs(table) do
        if not first then result = result .. ", " end
        -- format as "key = value"
        result = result .. tostring(k) .. " = " .. tostring(v)
        first = false
    end

    return result .. " }"
end

--------------------------------------------------------------------------------

--- @param table table
--- @param value any
--- @param removeAll boolean | nil -- remove all matching values ?
function all.removeValueFromTable(table, value, removeAll)
  for i = #table, 1, -1 do
    if table[i] == value then
      table.remove(table, i)
      if not removeAll then break end
    end
  end
end

--------------------------------------------------------------------------------

---@param ticks number
---@return string
function all.convertTicksToTimeFormat(ticks)

  local totalSeconds = math.floor(ticks / 20)
  local hours = math.floor(totalSeconds / 3600)
  local minutes = math.floor((totalSeconds % 3600) / 60)
  local seconds = totalSeconds % 60

  -- formatting the string
  if hours > 0 then
    return string.format("%dh %dm %ds", hours, minutes, seconds)
  elseif minutes > 0 then
    return string.format("%dm %ds", minutes, seconds)
  else
    return string.format("%ds", seconds)
  end

end

--------------------------------------------------------------------------------

---@param nums number
---@return number
function all.roundUpToTwoDecimals(nums)

  -- multiply by 100 to move two decimal places to the left
  local multiplied = nums * 100

  -- round up to the nearest whoe number using math.ceil
  local roundedUp = math.ceil(multiplied)

  -- divide by 100 to move the decimal point back to its original position
  local ret = roundedUp / 100
  return ret

end

--------------------------------------------------------------------------------

---@param prefix string
---@param list table
---@return table
function all.addPrefixToATableOfStrings(prefix, list)
  local ret = {}
  for _, name in ipairs(list) do
    ret[prefix .. name] = true
  end
  return ret
end

--------------------------------------------------------------------------------

---@param label string
---@param isPressed function
---@param showValue boolean | nil
---@return string
function all.getColoredStatusInStringOfAFunction(label, isPressed, showValue)
  local color = isPressed and all.clr.green or all.clr.red
  local str = color .. label
  if not showValue then return str end
  if isPressed == nil then return str end
  str = str .. all.clr.white .. ": " .. tostring(isPressed)
  return str
end

--------------------------------------------------------------------------------

---@param hRange number
---@param vRange number
---@param excludeEntities table | nil
function all.getNearbyEntities(hRange, vRange, excludeEntities)

  local mobList = {}
  local playerPos = player.getPos()
  if not playerPos then return mobList end

  for _, entity in ipairs(world.getEntities()) do

    -- skip the local player
    if entity
    and entity.uuid ~= player.entity.uuid
    and not (excludeEntities and excludeEntities[entity.type])
    then
      local ex, ey, ez = entity.x, entity.y, entity.z

      -- calculate distances
      local horizontalDist = math.sqrt((playerPos.x - ex)^2 + (playerPos.z - ez)^2)
      local verticalDist = math.abs(playerPos.y - ey)

      -- pass if range is nil OR if entity is within range
      local hPass = (not hRange) or (horizontalDist <= hRange)
      local vPass = (not vRange) or (verticalDist <= vRange)

      -- check if within defined ranges
      if hPass and vPass then
        table.insert(mobList, {
          name = entity.name or idk,
          display_name = entity.display_name or idk,
          type = entity.type or idk,
          uuid = entity.uuid,
          hDist = math.floor(horizontalDist * 10) / 10, -- rounded to 1 decimal
          vDist = math.floor(verticalDist * 10) / 10,
          pos = {x = ex, y = ey, z = ez},
          box = entity.box or nil
        })
      end
    end
  end
  return mobList
end

--------------------------------------------------------------------------------

---@param target string
---@param table table
---@return boolean
function all.isTargetInTableOfStrings(target, table)
  for _, str in ipairs(table) do
    if string.find(str:lower(), target:lower(), 1, true) then
      return true
    end
  end
  return false
end

--------------------------------------------------------------------------------

-- this is still used by farming so im not removing it
function all.onCooldown(uid, ticks)
  if all._cds[uid] and all._cds[uid] > 0 then return true -- is on cd
  else all._cds[uid] = ticks return false end -- not on cd, allow shit to run
end
local function updateCooldown()
  for key, ticks in pairs(all._cds) do
    if ticks > 0 then all._cds[key] = ticks - 1
    else all._cds[key] = nil end
  end
end

-- newgen cooldown -------------------------------------------------------------

-- gdr stands for "gd ready" gd being cd but goonDown instead of coolDown
-- so its just "cooldown ready" but goondown ready
-- so u can do if gdr("bla") then run-this end
function all.gdr(uid, ticks)

  local current = all.gdrs[uid] or 0

  -- not on cooldown
  if current <= 0 then

    if ticks == -1 then
      all.gdrs[uid] = math.huge
    else
    all.gdrs[uid] = ticks or 20
    end

    return true

  end

  -- on cooldown
  return false

end

local function updateGdr()
  for key, ticks in pairs(all.gdrs) do
    if ticks ~= math.huge then

      if ticks > 0 then
        all.gdrs[key] = ticks - 1
      else
        all.gdrs[key] = nil
      end

    end
  end
end


--------------------------------------------------------------------------------

function all.strip(s)
  return s:gsub("^%s+", ""):gsub("%s+$", "")
end

---@param text string
---@param lore table
---@param itrInReverse boolean
---@return boolean
function all.isTextInLore(text, lore, itrInReverse)

  local start = itrInReverse and #lore or 1
  local stop = itrInReverse and 1 or #lore
  local step = itrInReverse and -1 or 1

  for x = start, stop, step do
    local line = all.remMcColors(lore[x])
    if line:find(text, 1, true)  then
      do return true end
    end
  end
  return false
end

-- getTabInfo ------------------------------------------------------------------
-- this is for getting certain info from tab and storing them directly in
-- inf/dump

---@param s string
---@return integer
local function _handleTimeNumbers(s)
  if s == "MAX PESTS" then return -1 end
  if s == "READY" then return 0 end
  if s == nil then return -1 end
  if s == "No rain!" then return 0 end
  local min = s:match("(%d*)m") or 0
  local sec = s:match("(%d+)s") or 0
  return (tonumber(min) * 60) + tonumber(sec)
end

local function _getTabInfo(key, line, regex, fallbackValue, isNumber, dump)
  local match = line:match(regex)
  if not match then return end

  local value = isNumber and (tonumber(match) or fallbackValue) or match

  if not dump then all.inf[key] = value or fallbackValue
  else all.dump[key] = value or fallbackValue end
end

local function getTabInfo()

  local tabBody = player.getTab()
  if not tabBody then return end
  if tabBody.body then tabBody = tabBody.body end
  for i, lineRaw in ipairs(tabBody) do

    local line = all.remMcColors(lineRaw)

    -- global
    if (all.tgl.pet) and (all.inf.pet == idk) then
      _getTabInfo("pet", line, regexes.petNameInTab)
    end

    -- garden
    if all.tgl.visitors then
      _getTabInfo("visitors", line, "Visitors: %((%d+)%)", idk)
    end
    if all.tgl.spray then
      _getTabInfo("spray", line, "Spray: (.+)", idk)
    end
    -- _getTabInfo("pestAlive", line, "Alive: (%d)", -1, true)
    if all.tgl.pestCd then
      _getTabInfo("pestCdRaw", line, "Cooldown: (.*)", "MAX PESTS", false, true)
      if all.dump.pestCdRaw then
        all.inf.pestCd = _handleTimeNumbers(all.dump.pestCdRaw)
      end
    end

    -- fishing
    if all.tgl.rain then
      _getTabInfo("rainRaw", line, "Rain: (.*)", nil, false, true)
      if all.dump.rainRaw then
        all.inf.rain = _handleTimeNumbers(all.dump.rainRaw)
      end
    end

    -- dwarves
    if all.tgl.comms then
      if line:find("Commissions:", 1, true) then
        all.inf.comms = {}
        for j = 1, 4 do
          local nextLineRaw = tabBody[i + j]

          if nextLineRaw then
            nextLineRaw = all.remMcColors(nextLineRaw):lower()

            if nextLineRaw:find("done") then
              table.insert(all.inf.comms, "done")
            else
              table.insert(all.inf.comms, (nextLineRaw:gsub(": %d+%%", "")))
            end

          end
        end
      end
    end

    -- test stuff
    -- any screen is open boolean
    -- local lineAnyScreen = player.inventory.isAnyScreenOpened()
    -- all.dump.anyScreen = tostring(lineAnyScreen)
    -- chestTitle, string | nil
    -- local lineChestTitle = player.inventory.getChestTitle()
    -- all.dump.chestTitle = tostring(lineChestTitle)
    -- local lineChestSlots = tostring(player.inventory.getContainerSlots())
    -- all.dump.chestSlots = tostring(lineChestSlots)
    -- local lineChestItemFromContainer = player.inventory.getStackFromContainer(7)
    -- if lineChestItemFromContainer then all.dump.chestItemFromContainer = tostring(lineChestItemFromContainer.name) end
    -- local lineChestItem = player.inventory.getStack(10)
    -- if lineChestItem then all.dump.chestItem = tostring(lineChestItem.name) end

  end
end

--------------------------------------------------------------------------------

---@return string | nil
local function _getBlockBelowFeet()
  if type(all.inf.pos) ~= "table" then return end
  local blk = world.getBlock(all.inf.pos.x-1.0,all.inf.pos.y - 0.5,all.inf.pos.z)
  if blk then blk = blk.name else return nil end
  local ret = blk:match("block%.minecraft%.(.*)")
  return ret
end

--------------------------------------------------------------------------------

---@param txt string
---@return string | nil
local function updatePetFromManualSummon(txt)
  local match = txt:match(regexes.petNameInManualSummon)
  local ret = nil
  if match then
    ret = tostring(match)
  end
  return ret or nil
end

---@param txt string
---@return string | nil
local function updatePetFromAutopet(txt)
  local match = txt:match(regexes.petNameInAutopet)
  local ret = nil
  if match then
    ret = tostring(match)
  end
  return ret
end

--------------------------------------------------------------------------------

function all.playerInputStopAll()
  player.input.setPressedForward(false)
  player.input.setPressedBack(false)
  player.input.setPressedLeft(false)
  player.input.setPressedRight(false)

  player.input.setPressedJump(false)
  player.input.setPressedSprinting(false)
  player.input.setPressedSneak(false)

  player.input.setPressedAttack(false)
  player.input.setPressedUse(false)
end

--------------------------------------------------------------------------------

local function getVelocity()

  local pos = all.inf.pos
  if not pos then return 0 end
  local lpos = all.dump.last_pos
  if not lpos then
    all.dump.last_pos = { x = pos.x, y = pos.y, z = pos.z }
    return 0
  end

  local dx = pos.x - lpos.x
  local dy = pos.y - lpos.y
  local dz = pos.z - lpos.z
  local distance = math.sqrt(dx^2 + dy^2 + dz^2)
  local bps = distance * 20

  ---@type number
  local velocity = math.floor(bps * 100 + 0.5) / 100

  all.dump.last_pos = { x = pos.x, y = pos.y, z = pos.z }
  return velocity
end

--------------------------------------------------------------------------------

---@param value number
---@param target number
---@return boolean
function all.isValueMultipleOfTarget(value, target)
  return value % target == 0
end

--------------------------------------------------------------------------------

-- not finished yet btw use onCooldown() instead
---@param ticks number | nil
---@return boolean
function all.waiting(uid, ticks)

  if ticks then
    if not all._wtr[uid] or all._wtr[uid] <= 0 then
      all._wtr[uid] = ticks
      return true
    end
  end

  all._wtr[uid] = all._wtr[uid] - 1

  if all._wtr[uid] <= 0 then
    all._wtr[uid] = 0
    return false
  end
  return true
end

-- registers -------------------------------------------------------------------

registerClientTickPost(function()

  updateCooldown()
  updateGdr()

  getTabInfo()

  if all.tgl.pos then
    all.inf.pos = player.getPos() or idkPos
  end

  if all.tgl.velocity then
    all.inf.velocity = getVelocity() or idkInt
  end

  if all.tgl.location then
    all.inf.location = player.getRawLocation() or idk
  end

  if all.tgl.blockBelowFeet then
    all.inf.blockBelowFeet = _getBlockBelowFeet() or idk
  end

  local test = player.input.getSelectedSlot()
  if test and test > -1 and test < 9 then
    local heldItem = player.inventory.getStack(test)
    all.inf.heldItem = heldItem
  end

  -- if all.dump.playerInputStopAllValue == true then
  --   _playerInputStopAll(player)
  -- end

  -- if all.dump.setPet and all.dump.setPet == true then
  --   _setPet(player)
  -- end

end)

--------------------------------------------------------------------------------

registerMessageEvent(function(text)

  if not text then return end

  if all.tgl.pet then
    local ap = updatePetFromAutopet(text)
    local ms = updatePetFromManualSummon(text)
    if ap then
      all.inf.pet = ap
      all.inf.petName = all.remMcColors(ap)
    end
    if ms then
      all.inf.pet = ms
      all.inf.petName = all.remMcColors(ms)
    end
  end

  -- if text then print("text: " .. tostring(text)) end
  -- if overlay then print("overlay: " .. tostring(overlay)) end

end)

--------------------------------------------------------------------------------

return all
