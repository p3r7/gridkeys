local mod = require 'core/mods'


-- -------------------------------------------------------------------------
-- STATE

local state = {
  grid_device = nil,
  midi_in_devices = {},
}


-- -------------------------------------------------------------------------
-- UTILS: MIDI IN

local function midi_msg_to_virtual(msg)
  local data = midi.to_data(msg)
  for _, dev in pairs(midi.devices) do
    if dev.port ~= nil and dev.name == 'virtual' then
      if midi.vports[dev.port].event ~= nil then -- current script listen for this device
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
      state.grid_device:led(x, y, 15)
    end
  else
    midi_d_is_active = note_off(note_num)
    if midi_d_is_active then
      state.grid_device:led(x, y, 0)
    end
  end

  if midi_d_is_active then
    state.grid_device:refresh()
  end
end


-- -------------------------------------------------------------------------
-- MAIN

mod.hook.register("script_pre_init", "gridkeys", function()
                    local script_init = init
                    init = function ()
                      script_init()
                      print("mod - gridkeys - init ")
                      state.grid_device = grid.connect(1)
                      print(state.grid_device.key)
                      if state.grid_device.key ~= nil then
                        print("mod - gridkeys - grid bound by script, do nothing")
                      else
                        print("mod - gridkeys - grid is free, use it")
                        state.grid_device.key = grid_key
                      end
                    end
end)
