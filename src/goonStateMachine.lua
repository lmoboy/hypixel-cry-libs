-- @version 1.0
-- @location /libs/

local all = {}

-- state -----------------------------------------------------------------------

--- @class State
--- @field name string
--- @field tick number -- local tick (resets onEnter)
-- wait tick, this counts down from higher number to 0
-- onUpdate doesn't run while this is above 0
--- @field wait number
--- @field step number
--- @field logPrefix string
--- @field machine StateMachine | nil
--- @field [string] any -- allows extra variables to be used in state
local State = {}
State.__index = State

-- creates a new independent state instance, unlinked to any stateMachine
--- @param name string
--- @return State
function State.new(name)
  return setmetatable({
    name = name,
    tick = 0,
    wait = 0,
    step = 1,
    logPrefix = "state " .. name .. ": ",
    machine = nil
  }, State)
end

-- increments steps and returns the new step
-- crashes for some reason
function State:stepProc()
  self.step = self.step + 1
  return self.step
end

-- default callbacks, so they don't NEED to be defined
function State:onEnter() end -- called when entering the state
function State:onUpdate() end -- called every tick while the state is active
function State:onExit() end -- called when exiting the state

--- @param fields table<string>
--- @return nil
function State:ensureFields(fields)
  for _, field in ipairs(fields) do
    if self[field] == nil then

      local msg = string.format(
        "missing required field '%s' in state '%s'", field, self.name
      )
      if self.machine then self.machine:switch(nil) end
      player.addMessage("error, report this in discord")
      error(msg)

    end
  end
end

-- state machine ---------------------------------------------------------------

--- @class StateMachine
--- @field currentState State | nil
--- @field pendingState State | nil
--- @field tick number -- global tick, starts when script starts
local StateMachine = {}
StateMachine.__index = StateMachine

-- creates a new stateMachine instance
--- @return StateMachine
function StateMachine.new()
  return setmetatable({
    currentState = nil,
    pendingState = nil,
    tick = 0
  }, StateMachine)
end

-- registers a state into this statemachine
--- @param stateObj State
--- @return State
function StateMachine:addState(stateObj)
  stateObj.machine = self -- link state to this machine
  return stateObj -- return so its store-able in a variable
end

-- changes the currentState
--- @param stateObj State | nil
function StateMachine:switch(stateObj)

  self.pendingState = stateObj

end

function StateMachine:performSwitch()

  -- trigger exit logic for state being switched from
  if self.currentState  then
    self.currentState:onExit()
  end

  -- switch the state
  self.currentState = self.pendingState
  self.pendingState = nil -- clearing the queue

  if self.currentState then

    -- reset state tick
    self.currentState.tick = 0
    -- reset state step
    self.currentState.step = 1

    -- trigger enter logic for state being switched to
    self.currentState:onEnter()

  end

end

-- idk, call this at the top of the tick register
function StateMachine:update()

  -- proceed global tick
  self.tick = self.tick + 1

  if self.pendingState ~= nil then
    self:performSwitch()
  end

  -- run current state
  if self.currentState then

    -- proceed state tick
    self.currentState.tick = self.currentState.tick + 1

    -- proceed state wait
    if self.currentState.wait > 0 then
      self.currentState.wait = self.currentState.wait - 1
    end

    if self.currentState.onUpdate and self.currentState.wait < 1 then
      self.currentState:onUpdate()
    end

  end
end

-- example usage ---------------------------------------------------------------

-- local stm = StateMachine.new()
-- local states = {}
--
-- -- create the state objects
-- states.idle = stm:addState(State.new("idle"))
-- states.fishing = stm:addState(State.new("fishing"))

-- state fishing ---------------------------------------------------------------
--
-- function states.fishing:onUpdate()
--
--   -- this is state tick
--   if self.tick > 70 then
--     stm:switch(states.idle)
--   end
--
--   -- this is global tick
--   if self.machine.tick % 1200 == 0 then
--     print("stop gooning")
--   end
-- end

-- state idle ------------------------------------------------------------------

-- function states.idle:onUpdate()
--   if player.fishHook then
--     stm:switch(states.fishing)
--   end
-- end

-- state end -------------------------------------------------------------------

-- define initial state (starts the functioning)
-- stm:switch(states.idle)

-- registers -------------------------------------------------------------------

-- registerClientTickPre(function()
--   stm:update()
-- end)

all.State = State
all.StateMachine = StateMachine

return all
