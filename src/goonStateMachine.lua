-- @version 1.0
-- @location /libs/

local gut = require("goonUtils")

local all = {}

-- state -----------------------------------------------------------------------

--- @class State
--- @field name string
--- @field tick number -- increments every tick, resets onEnter
--- @field wait number -- decrements every tick, halts onUpdate while > 0
--- @field step number -- manually inc/dec this, resets onEnter
--- @field machine StateMachine | nil
local State = {}
State.__index = State

-- creates a unlinked state instance
--- @param name string
--- @return State
function State:new(name)
  return setmetatable({
    name = name,
    tick = 0,
    wait = 0,
    step = 1, -- value 1 is usefull for using with table indexes
    machine = nil
  }, State)
end

-- increments step and returns the new step
--- @param amount number | nil
--- @return number
function State:stepProc(amount)
  self.step = self.step + (amount or 1)
  return self.step
end

--- @deprecated switches your class, overwrite this in inherited states
--- @diagnostic disable-next-line: unused-vararg
function State:init(...)
  if not self.machine then
    error("state " .. self.name .. " has no machine linked")
    return
  end
  self.machine:switch(self)
end

-- default callbacks, so they don't NEED to be defined
function State:onEnter() end -- called when entering the state
function State:onUpdate() end -- called every tick while the state is active
function State:onExit() end -- called when exiting the state

function State:info(msg)
  if self.machine and self.machine.log then
    self.machine.log.info(self.machine.logPrefix(self.name, msg))
  end
end

function State:debug(msg)
  if self.machine and self.machine.log then
    self.machine.log.debug(self.machine.logPrefix(self.name, msg))
  end
end

function State:error(msg)
  if self.machine and self.machine.log then
    self.machine.log.error(self.machine.logPrefix(self.name, msg))
  end
end

function State:critical(msg)
  if self.machine and self.machine.log then
    self.machine.log.critical(self.machine.logPrefix(self.name, msg))
  end
end

-- state machine ---------------------------------------------------------------

--- @class StateMachine
--- @field states table<string, State>
--- @field currentState State | nil
--- @field pendingState State | nil -- used for state switch
--- @field tick number -- global tick, starts when script starts
--- @field log any | nil
--- @field rot any | nil
--- @field blockUtils any | nil
--- @field logPrefix fun( stateName: string, msg: string ): string
local StateMachine = {}
StateMachine.__index = StateMachine

-- creates a new stateMachine instance
--- @return StateMachine
function StateMachine:new()
  return setmetatable({
    states = {},
    currentState = nil,
    pendingState = nil,
    tick = 0,
    log = nil,
    rot = nil,
    blockUtils = nil,
    logPrefix = function(name, msg)
      return
        gut.clr.grayDark .. "[" ..
        gut.clr.blue .. name ..
        gut.clr.grayDark .. "] " ..
        gut.clr.gray .. msg
    end
  }, StateMachine)
end

-- registers a state into this statemachine
--- @generic T : State
--- @param stateObj T
--- @return T
function StateMachine:addState(stateObj)
  local s = stateObj --[[@as State]]
  s.machine = self -- link state to this machine
  self.states[s.name] = stateObj
  return stateObj -- return so its store-able in a variable
end

-- changes the currentState
--- @param stateObj State | nil
function StateMachine:switch(stateObj)
  self.pendingState = stateObj
end

function StateMachine:performSwitch()

  -- trigger exit logic for state being switched from
  if self.currentState then
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
    else
      self.currentState:onUpdate()
    end

  end
end

all.State = State
all.StateMachine = StateMachine

return all
