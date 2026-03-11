-- @version 1.0
-- @location /libs/

local gut = require("goonUtils")

gut.tgl.comms = true

local all = {}

-- location class --------------------------------------------------------------

-- TODO: create a class for pos { x = num ... }

local Location = {}
Location.__index = Location

--- @param name string
--- @param path table<Pos>
function Location.new(name, path)
  return setmetatable({
    name = name,
    path = path
  }, Location)
end

--- @return Pos | nil
function Location:getGoal()
  if not self.path or #self.path == 0 then return nil end
  return self.path[#self.path]
end

--- @return boolean
function Location:isPlayerAtGoal()
  local pos = player.getPos()
  local goal = self:getGoal()
  if not pos or not goal then return false end
  if pos.x == goal.x
  and (pos.y - 0.5) == goal.y
  and pos.z == goal.z
  then return true end
  return false
end

all.Location = Location

-- helpers ---------------------------------------------------------------------

local coords = {
  forge_top = { x = 0.5, y = 165.5, z = -11.5 },
  forge_top_left = { x = 3.5, y = 165.5, z = -11.5 },
}

all.locations = {
  warpForge = Location.new("warpforge", {
    { x = 0.5, y = 148.5, z = -68.5 }
  }),
  forge_emissary = Location.new("forge emissary", {
    { x = 10.5, y = 152.5, z = -8.5 },
    { x = 36.5, y = 146.5, z = 2.5 },
    { x = 42.5, y = 134.5, z = 22.5 }
  }),
  lava_springs = Location.new("lava springs", {
    coords.forge_top,
    { x = 0.5, y = 181.5, z = -28.5 },
    { x = 33.5, y = 197.5, z = -5.5 },
    { x = 33.5, y = 220.5, z = -9.5 }
  }),
  cliffside_veins = Location.new("cliffside veins", {
    coords.forge_top_left,
    { x = 33.5, y = 144.5, z = -1.5 }
  }),
  rampart_quarry = Location.new("rampart quarry", {
    coords.forge_top,
    { x = -32.5, y = 168.5, z = -30.5 },
    { x = -53.5, y = 182.5, z = -60.5 }
  }),
  upper_mines = Location.new("upper mines", {
    coords.forge_top,
    { x = -32.5, y = 168.5, z = -30.5 },
    { x = -53.5, y = 182.5, z = -60.5 },
    { x = -64.5, y = 161.5, z = -36.5 },
    { x = -110.5, y = 167.5, z = -71.5 },
    { x = -130.5, y = 174.5, z = -73.5 },
  }),
  royal_mines = Location.new("royal mines", {
    coords.forge_top_left,
    { x = 38.5, y = 149.5, z = 6.5 },
    { x = 76.5, y = 145.5, z = 30.5 },
    { x = 104.5, y = 156.5, z = 45.5 },
    { x = 149.5, y = 167.5, z = 23.5 }
  })
}

-- get location ----------------------------------------------------------------

--- @return string | nil
function all.getLocation()
  local str = nil
  for _, n in pairs(all.locations) do
    local goal = n.path[#n.path] -- location's goal
    local pos = player.getPos()
    if not pos or not pos.x or not pos.y or not pos.z then return nil end
    if pos.x == goal.x
    and (((pos.y - 0.5) == goal.y) or (pos.y == goal.y))
    and pos.z == goal.z
    then
      str = n.name or nil
      break
    else
      str = nil
      -- str = gut.tableToString(pos) .. " = " .. gut.tableToString(goal)
    end
  end
  return str
end

-- comms ready to claim --------------------------------------------------------

-- returns if whether or not to return (so state is switch'ed)
--- @return boolean
function all.commsClaimable()

  if not gut.isTargetInTableOfStrings("done", gut.inf.comms) then return false end
  return true

  -- register what to claim
  -- local toClaim = {}
  -- for i, n in ipairs(gut.inf.comms) do
  --   if n:find("done") then
  --     table.insert(toClaim, i)
  --   end
  -- end

  -- claim
  -- sts.aotv.target = gcu.locations.forge_emissary.path
  -- sts.aotv.callback = sts.claiming
  -- this is for debugging
  -- sts.claiming.toClaim = { 2, 3, 4 }
  -- self.machine:switch(sts.aotv)

  -- return true
end

-- get active comm -------------------------------------------------------------

--- @return nil | table
function all.getActiveCommission()

  if not gut.inf.comms then return end

  for i, n in pairs(gut.inf.comms) do
    for i2, n2 in pairs(all.locations) do

      if n:find(n2.name) then

        local type = nil
        if n:find("mithril") then
          type = all.mineables.mithril
        elseif n:find("titanium") then
          type = all.mineables.titanium
        end

        return {
          comm_index = i,
          comm_location_index = i2,
          comm_mineable_type = type
        }
      end

    end
  end

  return nil
end

--------------------------------------------------------------------------------

all.mineables = {}

all.mineables.mithril = {
  "wool",
  "prismarine",
  "cyan_terracotta"
}

all.mineables.titanium = {
  "polished_diorite",
  table.unpack(all.mineables.mithril)
}

--------------------------------------------------------------------------------

return all
