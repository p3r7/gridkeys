local mod = require 'core/mods'
local script = require 'core/script'
local tabutil = require 'tabutil'


-- -------------------------------------------------------------------------
-- UTILS: CORE

function table.copy(t)
  local u = { }
  for k, v in pairs(t) do u[k] = v end
  return setmetatable(u, getmetatable(t))
end

local function clone_function(fn)
  local dumped=string.dump(fn)
  local cloned=load(dumped)
  local i=1
  while true do
    local name=debug.getupvalue(fn,i)
    if not name then
      break
    end
    debug.upvaluejoin(cloned,i,fn,i)
    i=i+1
  end
  return cloned
end


-- -------------------------------------------------------------------------
-- STATE

local init_state = {
  grid_device = nil,
  script_uses_grid = false,
  midi_in_devices = {},
  midi_out_device = nil,
}

local state = table.copy(init_state)


-- -------------------------------------------------------------------------
-- UTILS: MIDI IN

local function send_midi_msg(msg)
  local data = midi.to_data(msg)
  local is_affecting = false

  -- midi in
  if params:get("gridkeys_midi_mode") ~= 3 then
    for _, dev in pairs(midi.devices) do
      if dev.port ~= nil and dev.name == 'virtual' then
        if midi.vports[dev.port].event ~= nil then
          midi.vports[dev.port].event(data)
          is_affecting = true
          break
        end
      end
    end
  end

  -- midi out
  if params:get("gridkeys_midi_mode") ~= 1 and state.midi_out_device ~= nil then
    state.midi_out_device:send(data)
    is_affecting = true
  end

  return is_affecting
end

local function note_on(note_num, vel)
  local msg = {
    type = 'note_on',
    note = note_num,
    vel = vel,
    ch = 1,
  }
  return send_midi_msg(msg)
end

local function note_off(note_num)
  local msg = {
    type = 'note_off',
    note = note_num,
    vel = 100,
    ch = 1,
  }
  return send_midi_msg(msg)
end


-- -------------------------------------------------------------------------
-- GRID EVENT

local function grid_key(x, y, z)
  local note_num = util.clamp(((7 - y) * 5) + x + 33, 0, 127)
  local midi_d_is_active = false
  if z == 1 then
    midi_d_is_active = note_on(note_num, 100)
    if midi_d_is_active then
      state.grid_device.og_led(state.grid_device, x, y, 15)
    end
  else
    midi_d_is_active = note_off(note_num)
    if midi_d_is_active then
      state.grid_device.og_led(state.grid_device, x, y, 0)
    end
  end

  if midi_d_is_active then
    state.grid_device.og_refresh(state.grid_device)
  end
end

local function toggle_grid_key(status)
  state.grid_device.og_all(state.grid_device, 0)
  state.grid_device.og_refresh(state.grid_device)
  if status == false then
    -- print("RESTORE OG GRID KEY HANDLER")

    -- restore grid API
    state.grid_device.all = state.grid_device.og_all
    state.grid_device.intensity = state.grid_device.og_intensity
    state.grid_device.led = state.grid_device.og_led
    state.grid_device.refresh = state.grid_device.og_refresh
    -- restore og callback
    state.grid_device.key = state.grid_device.og_key
  else
    -- print("ACTIVATE GRIDKEYS")

    state.grid_device.all = function(...) end
    state.grid_device.intensity = function(...) end
    state.grid_device.led = function(...) end
    state.grid_device.refresh = function(...) end
    state.grid_device.key = grid_key
  end
end


-- -------------------------------------------------------------------------
-- MAIN

local function init_params()
  params:add_separator("MOD - GRIDKEYS")

  params:add_option("gridkeys_active", "gridkeys active", {"off", "on"},
                    state.script_uses_grid and 1 or 2)
  params:set_action("gridkeys_active",
                    function(v)
                      toggle_grid_key(v == 2)
  end)

  params:add_option("gridkeys_midi_mode", "MIDI", {"in", "in+out", "out"})
  params:add{type = "number", id = "gridkeys_midi_out_device", name = "MIDI OUT Device", min = 1, max = 4, default = 1, action = function(v)
               local device = midi.connect(v)
               if device.name == 'virtual' or device.name == "none" then
                 state.midi_out_device = nil
               else
                 state.midi_out_device = device
               end
  end}

  params:add_separator()
end

local function startup_init_grid()
  state.grid_device = grid.connect(1)

  state.grid_device.og_all = clone_function(state.grid_device.all)
  state.grid_device.og_intensity = clone_function(state.grid_device.intensity)
  state.grid_device.og_led = clone_function(state.grid_device.led)
  state.grid_device.og_refresh = clone_function(state.grid_device.refresh)

  toggle_grid_key(true)
end


local function script_init_grid()
  state.grid_device = grid.connect(1)

  if state.grid_device.key ~= nil then
    print("mod - gridkeys - OFF as grid bound by script")
    state.grid_device.og_key = clone_function(state.grid_device.key)
    state.script_uses_grid = true
  else
    print("mod - gridkeys - ON as grid is free")
    toggle_grid_key(true)
  end
end


mod.hook.register("system_post_startup", "gridkeys-sys-startup", function ()
                    local script_clear = script.clear
                    script.clear = function()
                      local is_restart = (tabutil.count(params.lookup) == 0)
                      script_clear()
                      if is_restart then
                        print("mod - gridkeys - startup clear")
                        startup_init_grid()
                        init_params()
                        params:set("gridkeys_midi_mode", 3)
                      else
                        print("mod - gridkeys - script clear")
                        state.grid_device = grid.connect(1)
                        toggle_grid_key(false)
                        state.grid_device.key = nil
                        state = table.copy(init_state)
                      end
                    end
end)


mod.hook.register("script_pre_init", "gridkeys", function()
                    local script_init = init
                    init = function ()
                      script_init()
                      print("mod - gridkeys - init")
                      script_init_grid()
                      init_params()
                      params:set("gridkeys_midi_mode", 1)
                    end
  end)

-- mod.hook.register("script_post_cleanup", "gridkeys-cleanup", function()
--                     print("mod - gridkeys - cleanup")
--                     state.grid_device = grid.connect(1)
--                     state.grid_device.key = nil
--                     state = table.copy(init_state)
-- end)
