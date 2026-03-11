-- @version 1.0
-- @location /libs/

local gsm = require("goonStateMachine")
local gut = require("goonUtils")

local all = {}

-- gut
gut.tgl.pos = true

-- states ----------------------------------------------------------------------

-- state aotv ------------------------------------------------------------------

--- @class StateAotv : State
--- @field callback State | function | nil
--- @field target { x: number, y: number, z: number }[] | nil
StateAotv = setmetatable({}, { __index = gsm.State })
StateAotv.__index = StateAotv

--- @param name string
function StateAotv.new(name)
  local self = setmetatable(gsm.State:new(name), StateAotv)
  self.callback = nil
  self.target = nil
  return self
end

--- @param target { x: number, y: number, z: number }[]
--- @param callback State | function
--- @return nil
function StateAotv:init(target, callback)
  self.target = target
  self.callback = callback
  self.machine:switch(self)
end

function StateAotv:onEnter()

  self.rotationStarted = false
  self.isReadyToClick = false

  -- set the callback for rot
  self.machine.rot.setOnComplete(function()
    self.isReadyToClick = true
    self:debug("rotation finished")
  end)

  -- hold aotv
  if gut.holdItem("ASPECT_OF_THE_VOID", "skyblock_id")
  then self:debug("equipped aotv")
  else self:debug("couldn't equip aotv") end
  self.wait = 2

end

function StateAotv:onUpdate()

  player.input.setPressedSneak(true)
  local pos = gut.inf.pos

  -- TODO: failsafe if target not reached (does nothing atm if not reached)
  -- reached target x
  -- begin next target or exit
  if gut.isPosCloseTo(pos, self.target[self.step], 1) then
    self:debug( "reached target " .. self.step .. "/" .. #self.target)
    if self.step == #self.target then
      if type(self.callback) == "function" then
        self.callback()
      else
        -- TODO: maybe fix this diagnostic
        ---@diagnostic disable-next-line: param-type-mismatch
        self.machine:switch(self.callback)
      end
      return
    end
    self:stepProc()
    self.wait = math.random(2, 4)
    self.rotationStarted = false
    return
  end

  -- rotate to current target
  if not self.rotationStarted then
    local t = self.target[self.step]
    self.machine.rot.rotateToCoordinates(t.x, t.y, t.z)
    self.rotationStarted = true
    return
  end

  -- click
  if self.isReadyToClick then
    player.input.rightClick()
    self:debug("clicked")
    self.isReadyToClick = false
    return
  end

end

function StateAotv:onExit()
  player.input.setPressedSneak(false)
end

all.StateAotv = StateAotv

-- state mining ----------------------------------------------------------------

--- @class StateMining : State
--- @field callback State | nil
--- @field callbackCondition function | nil
--- @field blocks table
--- @field range number
--- @field blacklist table
--- @field target any | nil
--- @field targetAquiredTick number | nil
StateMining = setmetatable({}, { __index = gsm.State })
StateMining.__index = StateMining

--- @param name string
function StateMining.new(name)
  local self = setmetatable(gsm.State:new(name), StateMining)
  self.callback = nil
  self.callbackCondition = nil
  self.blocks = {}
  self.range = 3 -- default
  self.blacklist = {}
  self.target = nil
  self.targetAquiredTick = nil
  return self
end

--- @param callback State
--- @param blocks table
--- @param range number | nil
--- @return nil
function StateMining:init(callback, callbackCondition, blocks, range)
  self.callback = callback
  self.callbackCondition = callbackCondition
  self.blocks = blocks
  self.range = range or 3
  self.machine:switch(self)
end

function StateMining:onEnter()

  self.blacklist = {}
  self.target = nil
  self.targetAquiredTick = nil

  -- hold aotv
  if gut.holdItem("drill")
  then self:debug("equipped drill")
  else self:debug("didn't find any drills in hotbar") end
  player.input.setPressedAttack(true)
  self.wait = 2

end

function StateMining:onUpdate()

  -- callback condition check
  if self.callbackCondition() then
    self.machine:switch(self.callback)
    return
  end

  -- check if current target is broken
  if self.target then

    -- timeout check
    if self.targetAquiredTick and self.tick - self.targetAquiredTick >= 60 then
      local ray = player.raycast(4.5)
      local isLookingAtTarget = false
      if ray and ray.type == "block" then
        local rp = ray.blockPos
        if gut.isPosCloseTo(
          rp,
          { x = self.target.x, y = self.target.y, z = self.target.z },
          0
        ) then isLookingAtTarget = true end
      end

      if not isLookingAtTarget then
        self:error("target unreachable, blacklisting forever " .. self.target.key)
        self:blacklistBlockForever(self.target.key)
        self.target = nil
        self.targetAquiredTick = nil
        return
      else
        self.targetAquiredTick = self.tick
      end
    end

    local t = self.target
    local cur = world.getBlock(t.x, t.y, t.z)
    if cur and cur.name == self.target.name then goto curTargetNotBroken end
    self:debug("block broken, blacklisting " .. self.target.key)
    self:blacklistBlock(self.target.key)
    self.target = nil
    ::curTargetNotBroken::
    return
  end

  -- find new target
  if not self.target then
    self.target = self:findBlock()
    -- not found
    if not self.target then
      self:debug("no blocks found, switching to callback")
      self.machine:switch(self.callback)
      return
    end
    -- found, rotate
    self.targetAquiredTick = self.tick
    local t = self.target
    -- get the visible surface points using blockUtils
    local blockObj = {
      pos = { x = t.x, y = t.y, z = t.z },
      data = world.getBlock(t.x, t.y, t.z)
    }
    -- hp stands for hitpoint
    local hp = self.machine.blockUtils.getClosestHitbox(blockObj)
    if hp then
      self.machine.rot.rotateToCoordinates(hp.x, hp.y, hp.z)
      self:debug("rotating to precisely " .. t.key)
    else
      self:blacklistBlock(self.target.key)
      self:error("blacklisting forever")
      self.target = nil
    end
    self.machine.rot.setOnComplete(function()
      self:debug("breaking " .. t.key)
    end)
  end

end

function StateMining:onExit()
  player.input.setPressedAttack(false)
end

function StateMining:blacklistBlock(key)
  self.blacklist[key] = self.tick + 80
end

function StateMining:blacklistBlockForever(key)
  self.blacklist[key] = self.tick + math.huge
end

function StateMining:isBlacklisted(key)
  local expiry = self.blacklist[key]
  if not expiry then return false end
  if self.tick >= expiry then
    self.blacklist[key] = nil
  end
  return true
end

function StateMining:findBlock()
  local pos = player.getPos() if not pos then return nil end
  local curRot = player.getRotation() if not curRot then return nil end
  local range = self.range
  local fx, fy, fz = math.floor(pos.x), math.floor(pos.y), math.floor(pos.z)

  local best = nil
  local bestAngle = math.huge

  for dx = -range, range do
    for dy = -range, range do
      for dz = -range, range do
        local x, y, z = fx + dx, fy + dy, fz + dz
        local key = x .. "_" .. y .. "_" .. z
        if not self:isBlacklisted(key) then
          local block = world.getBlock(x, y, z)
          if not block or not block.name then goto thisContinue end
          for _, pattern in pairs(self.blocks) do
            if block.name:match(pattern) then
              -- score angle to block center
              local blockRot = world.getRotation(x + 0.5, y + 0.5, z + 0.5)
              if blockRot then
                local yawDiff = math.abs((blockRot.yaw - curRot.yaw + 180) % 360 - 180)
                local pitchDiff = math.abs(blockRot.pitch - curRot.pitch)
                local totalAngle = yawDiff + pitchDiff
                if totalAngle < bestAngle then
                  bestAngle = totalAngle
                  best = {
                    x = x, y = y, z = z,
                    name = block.name,
                    key = key }
                end
              end
              break
            end
          end
          ::thisContinue::
        end
      end
    end
  end
  return best
end

all.StateMining = StateMining

-- end -------------------------------------------------------------------------

return all
