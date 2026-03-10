-- @version 1.0
-- @location /libs/

local gsm = require("goonStateMachine")
local gut = require("goonUtils")

local all = {}

-- gut
gut.tgl.pos = true

-- template ----------------------------------------------------------------------

--- @class StateTemplate : State
--- @field callback State | nil
--- @field target any | nil
--- @field gog any | nil
--- @field rot any | nil

local templates = {}

function all.instantiate(templateName)

  local logic = templates[templateName]
  if not logic then
    error("template " .. templateName .. " does not exist")
  end

  local instance = gsm.State.new(templateName) --[[@as StateTemplate]]

  instance.onEnter = logic.onEnter
  instance.onUpdate = logic.onUpdate
  instance.onExit = logic.onExit

  return instance

end

-- state template aotv ---------------------------------------------------------

templates.aotv = {}

function templates.aotv:onEnter()

  self:ensureFields({ "callback", "target", "gog", "rot" })

  -- requires self.postUnsneak (optional) (unsneak after done or not)
  -- default: true
  if self.unsneakOnceDone == nil then
    self.unsneakOnceDone = true
  end

  self.rotationStarted = false
  self.isReadyToClick = false
  -- set the callback for rot
  self.rot.setOnComplete(function()
    self.isReadyToClick = true
    self.gog.debug(self.logPrefix .. "rotation finished")
  end)

  -- hold aotv
  -- NOTE: handle return
  if gut.holdItem("ASPECT_OF_THE_VOID", "skyblock_id") then
    self.gog.debug(self.logPrefix .. "equipped aotv")
  else
    self.gog.debug(self.logPrefix .. "couldn't equip aotv")
  end
  self.wait = 2

end

function templates.aotv:onUpdate()

  player.input.setPressedSneak(true)
  local pos = gut.inf.pos

  -- reached target x
  -- begin next target or exit
  if gut.isPosCloseTo(pos, self.target[self.step], 1) then
    self.gog.debug(
      self.logPrefix .. "reached target " .. self.step .. "/" .. #self.target
    )
    if self.step == #self.target then
      self.machine:switch(self.callback)
      return
    end
    -- self.stepProc()
    self.step = self.step + 1
    self.wait = math.random(2, 4)
    self.rotationStarted = false
    return
  end

  if not self.rotationStarted then
    local t = self.target[self.step]
    self.rot.rotateToCoordinates(t.x, t.y, t.z)
    self.rotationStarted = true
    return
  end

  if self.isReadyToClick then
    player.input.rightClick()
    self.gog.debug(self.logPrefix .. "clicked")
    self.isReadyToClick = false
    return
  end

end

function templates.aotv:onExit()

  if self.unsneakOnceDone then
    player.input.setPressedSneak(false)
  end

end

function all.instantiateAotv() return all.instantiate("aotv") end

-- end -------------------------------------------------------------------------

return all
