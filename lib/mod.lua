local mod = require 'core/mods'


-- -------------------------------------------------------------------------
-- STATE

local state = {
  grid_device = nil,
  script_uses_grid = false,
  midi_in_devices = {},
}


-- -------------------------------------------------------------------------
-- UTILS: CORE

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
-- UTILS: MIDI IN

local function midi_msg_to_virtual(msg)
  local data = midi.to_data(msg)
  for _, dev in pairs(midi.devices) do
    if dev.port ~= nil and dev.name == 'virtual' then
      if midi.vports[dev.port].event ~= nil then
        midi.vports[dev.port].event(data)
        return true
      end
    end
  end
  return false
end

local function note_on(note_num, vel)
  local msg = {
    type = 'note_on',
    note = note_num,
    vel = vel,
    ch = 1,
  }
  return midi_msg_to_virtual(msg)
end

local function note_off(note_num)
  local msg = {
    type = 'note_off',
    note = note_num,
    vel = 100,
    ch = 1,
  }
  return midi_msg_to_virtual(msg)
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
  if status == true then
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

mod.hook.register("script_pre_init", "gridkeys", function()
                    local script_init = init
                    init = function ()
                      script_init()
                      print("mod - gridkeys - init")
                      state.grid_device = grid.connect(1)
                      print(state.grid_device.key)
                      if state.grid_device.key ~= nil then
                        print("mod - gridkeys - grid bound by script")
                        state.grid_device.og_key = clone_function(state.grid_device.key)
                        state.script_uses_grid = true
                      else
                        toggle_grid_key(true)
                      end

                      state.grid_device.og_all = clone_function(state.grid_device.all)
                      state.grid_device.og_intensity = clone_function(state.grid_device.intensity)
                      state.grid_device.og_led = clone_function(state.grid_device.led)
                      state.grid_device.og_refresh = clone_function(state.grid_device.refresh)

                      if state.script_uses_grid then
                        params:add_separator("MOD - GRIDKEYS")
                        params:add_option("gridkeys_active", "gridkeys active", {"off", "on"}, 1)
                        params:set_action("gridkeys_active",
                                          function(x)
                                            toggle_grid_key(x ~= 2)
                        end)
                      end
                    end
end)
