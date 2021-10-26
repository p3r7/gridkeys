local mod = require 'core/mods'
local script = require 'core/script'
local tabutil = require 'tabutil'
local music = require 'musicutil'

local grid = util.file_exists(_path.code.."midigrid") and include "midigrid/lib/midigrid" or grid
local grid_utils = require 'gridkeys/lib/grid_utils'
local Q7GridKeys = require 'gridkeys/lib/Q7GridKeys'


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

local gridkeys_modes = {'basic', 'q7'}
local default_mode = 1
local active_mode = gridkeys_modes[default_mode]

local active_scale = 1
local active_root_note = 1

local active_midi_notes = {}


-- -------------------------------------------------------------------------
-- UTILS: CROW CV OUT

local function crow_cv_note(note_num)
  crow.output[1].volts = (note_num - 60) / 12
  crow.output[2].execute()
end


-- -------------------------------------------------------------------------
-- UTILS: CROW ii JF OUT

local function crow_jf_note(note_num)
  crow.ii.jf.play_note((note_num-60)/12,5)
end


-- -------------------------------------------------------------------------
-- UTILS: MIDI IN / OUT

local function send_midi_msg(msg)
  local data = midi.to_data(msg)
  local is_note_on = (msg.type == 'note_on')
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
    msg.ch = params:get("gridkeys_midi_out_channel")
    data = midi.to_data(msg)
    state.midi_out_device:send(data)
    is_affecting = true
  end

  -- crow CV out
  if is_note_on and params:string('gridkeys_crow_out') == 'on' then
    crow_cv_note(msg.note)
    is_affecting = true
  end

  -- crow ii JF out
  if is_note_on and params:string('gridkeys_jf_out') == 'on' then
    crow_jf_note(msg.note)
    is_affecting = true
  end

  return is_affecting
end

local function note_on(note_num, vel, chan)
  chan = chan or 1
  local msg = {
    type = 'note_on',
    note = note_num,
    vel = vel,
    ch = chan,
  }

  if active_midi_notes[note_num] == nil then
    active_midi_notes[note_num] = true
  end

  return send_midi_msg(msg)
end

local function note_off(note_num, chan)
  chan = chan or 1
  local msg = {
    type = 'note_off',
    note = note_num,
    vel = 100,
    ch = chan,
  }

  active_midi_notes[note_num] = nil

  return send_midi_msg(msg)
end

function all_midi_notes_off()
  for note_num, v in pairs(active_midi_notes) do
    if v == true then
      note_off(note_num, chan)
    end
  end
end


local function update_midi_out_device_by_index(v)
  local device = midi.connect(v)
  -- print("mod - gridkeys - init_params - midi_out_device=" .. device.name)
  if device.name == 'virtual' or device.name == "none" then
    state.midi_out_device = nil
  else
    state.midi_out_device = device
  end
end


-- -------------------------------------------------------------------------
-- GRID KEY CB - BASIC

local function basic_grid_key(x, y, z)
  local note_num = util.clamp(((7 - y) * 5) + x + 33, 0, 127)
  local midi_d_is_active = false
  if z == 1 then
    midi_d_is_active = note_on(note_num, params:get("gridkeys_velocity"))
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


-- -------------------------------------------------------------------------
-- GRID KEY CB - Q7

local q7gridkeys

local q7gridkeys_default_layout_mode = 2

local gridType_none = 0
local gridType_128 = 1
local gridType_64 = 2
local gridType = 1
local gridNbLevels = 15

local q7_is_is_affecting = false

local function init_q7gridkeys()

  if state.grid_device.cols == 16 and state.grid_device.rows == 8 then
    print("grid 128 detected")
    gridType = gridType_128
  elseif state.grid_device.cols == 8 and state.grid_device.rows == 8 then
    print("grid 64 detected")
    gridType = gridType_64
  else
    gridType = gridType_none
  end
  state.grid_device.nb_levels = grid_utils.nb_levels(state.grid_device)

  q7gridkeys = Q7GridKeys.new(16,8)
  q7gridkeys.id = 1
  q7gridkeys.midi_device = 1
  q7gridkeys.midi_channel = 1 -- unused
  q7gridkeys.sound_mode = 2 -- MIDI
  q7gridkeys.note_on = q7grid_note_on
  q7gridkeys.note_off = q7grid_note_off
  q7gridkeys.key_pushed = q7grid_key_pushed
  q7gridkeys.layout_mode = q7gridkeys_default_layout_mode
  -- all_gridSeqs[i] = Q7GridSeq.new(q7gridkeys)
  -- q7gridkeys.gridSeq = all_gridSeqs[i]
  -- all_gridSeqs[i].on_pat_changed = gridSeq_pat_changed
end

local function q7grid_redraw()
  -- NB: see `GridPlay.grid_redraw`

  state.grid_device.og_all(state.grid_device, 0)

  state.grid_device.nb_levels = grid_utils.nb_levels(state.grid_device)

  local toolbar_btn_brightness = 6
  if state.grid_device.nb_levels == 1 then
    toolbar_btn_brightness = 15
  end

  q7gridkeys:draw_grid(state.grid_device, q7_is_is_affecting)

  -- toolbar
  state.grid_device.og_led(state.grid_device, state.grid_device.cols - 1, state.grid_device.rows, toolbar_btn_brightness) -- down
  state.grid_device.og_led(state.grid_device, state.grid_device.cols, state.grid_device.rows, toolbar_btn_brightness) -- up

  state.grid_device.og_refresh(state.grid_device)
end

local function q7grid_key(x, y, z)
  -- NB: see `GridPlay.grid_key`

  if y == 8 and ((gridType == gridType_128 and x == 15) or (gridType == gridType_64 and x == 7)) then
    all_midi_notes_off()
    q7gridkeys:scroll_down()
  elseif y == 8 and ((gridType == gridType_128 and x == 16) or (gridType == gridType_64 and x == 8)) then
    all_midi_notes_off()
    q7gridkeys:scroll_up()
  else
    q7gridkeys:grid_key(x,y,z)
  end

  q7grid_redraw()
  state.grid_device.og_refresh(state.grid_device)
end

function q7grid_note_on(gKeys, noteNum, vel)
  -- print("Note On: " .. noteNum.. " " .. vel .. " " .. music.note_num_to_name(noteNum))

  if gKeys.sound_mode == 2 then -- midi out
    q7_is_is_affecting = note_on(noteNum, params:get("gridkeys_velocity"))
  end
end

function q7grid_note_off(gKeys, noteNum)
  -- print("Note Off: " .. noteNum .. " " .. music.note_num_to_name(noteNum))

  if gKeys.sound_mode == 2 then
    note_off(noteNum)
  end
end

function q7grid_key_pushed(gKeys, noteNum, vel)
  return
end

function change_q7gridkeys_layout(new_layout_mode)
  -- NB: see `change_gridKey_layout`
  -- gridKeys.layout_mode = (gridKeys.layout_mode == 1) and 2 or 1

  -- new_layout_mode = new_layout_mode or ((q7gridkeys.layout_mode % 3) + 1)
  new_layout_mode = new_layout_mode or q7gridkeys.layout_mode

  q7gridkeys.layout_mode = new_layout_mode

  if q7gridkeys.layout_mode == 3 then
    q7gridkeys:zero_vertical_offset()
  end

  -- if q7gridkeys.sound_mode == 2 then
  --   all_midi_notes_off(q7gridkeys.midi_device)
  -- end
end


-- -------------------------------------------------------------------------
-- GRID KEY CB

local function grid_key(x, y, z)
  if active_mode == 'basic' then
    basic_grid_key(x, y, z)
  else
    q7grid_key(x, y, z)
  end
end


-- -------------------------------------------------------------------------
-- STATE MANAGEMENT

local function toggle_grid_key(status)

  local status_str = status and "true" or "false"
  print("mod - gridkeys - TOGGLE_GRID_KEY = "..status_str)

  if state.grid_device == nil then
    print("mod - gridkeys - TOGGLE_GRID_KEY -> ABORT")
    return
  end

  state.grid_device.og_all(state.grid_device, 0)
  state.grid_device.og_refresh(state.grid_device)

  if status == false then
    if state.grid_device.gridkeys_on == true then
      -- print("RESTORE OG GRID KEY HANDLER")

      -- restore grid API
      state.grid_device.all = state.grid_device.og_all
      state.grid_device.intensity = state.grid_device.og_intensity
      state.grid_device.led = state.grid_device.og_led
      state.grid_device.refresh = state.grid_device.og_refresh
      -- restore og callback
      state.grid_device.key = state.grid_device.og_key
      state.grid_device.gridkeys_on = nil
    else
      print("mod - gridkeys - TOGGLE_GRID_KEY -> NO CHANGE")
    end
  else
    if state.grid_device.gridkeys_on == nil then

      -- print("ACTIVATE GRIDKEYS")

      state.grid_device.all = function(...) end
      state.grid_device.intensity = function(...) end
      state.grid_device.led = function(...) end
      state.grid_device.refresh = function(...) end
      state.grid_device.key = grid_key
      -- state.grid_device.key = basic_grid_key
      state.grid_device.gridkeys_on = true

      if active_mode == 'q7' then
        q7grid_redraw()
      end
    else
        print("mod - gridkeys - TOGGLE_GRID_KEY -> NO CHANGE")
    end
  end
end

--- restore grid API fns
local function restore_grid_initial_state()
  state.grid_device = grid.connect(1)
  toggle_grid_key(false)
  state.grid_device.key = nil
  state = table.copy(init_state)
  -- print("mod - gridkeys - UNSET KEY() !!!!!")
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
  params:add{type = "number", id = "gridkeys_midi_out_device", name = "MIDI Out Device", min = 1, max = 4, default = 1, action = function(v)
               all_midi_notes_off()
               update_midi_out_device_by_index(v)
  end}

  params:add{type = "number", id = "gridkeys_midi_out_channel", name = "MIDI Out Channel", min = 1, max = 16, default = 1}
  params:set_action("gridkeys_midi_out_channel",
                    function(v)
                      all_midi_notes_off()
  end)


  params:add_option("gridkeys_crow_out", "crow 1+2 out", {"off", "on"})
  params:set_action("gridkeys_crow_out",
                    function(v)
                      if v == 2 then
                        crow.output[2].action = "{to(5,0),to(0,0.25)}"
                      end
  end)

  params:add_option("gridkeys_jf_out", "crow ii jf out", {"off", "on"})
  params:set_action("gridkeys_jf_out",
                    function(v)
                      if v == 2 then
                        crow.ii.pullup(true)
                        crow.ii.jf.mode(1)
                      else
                        crow.ii.jf.mode(0)
                      end
  end)

  params:add{type = "number", id = "gridkeys_velocity", name = "Velocity", min = 1, max = 127, default = 100}

  params:add_option("gridkeys_mode", "Mode", gridkeys_modes, default_mode)
  params:set_action("gridkeys_mode",
                    function(v)
                      active_mode = gridkeys_modes[v]
                      all_midi_notes_off()
                      if active_mode == 'basic' then
                        state.grid_device.og_all(state.grid_device, 0)
                        state.grid_device.og_refresh(state.grid_device)
                        params:hide("gridkeys_q7_layout")
                        params:hide("gridkeys_q7_scale")
                        params:hide("gridkeys_q7_root_note")
                      else
                        q7grid_redraw()
                        params:show("gridkeys_q7_layout")
                        params:show("gridkeys_q7_scale")
                        params:show("gridkeys_q7_root_note")
                      end
                      _menu.rebuild_params()
  end)

  params:add_option("gridkeys_q7_layout", "Q7 layout", Q7GridKeys.layout_names, q7gridkeys_default_layout_mode)
  params:set_action("gridkeys_q7_layout",
                    function(v)
                      q7gridkeys.layout_mode = v
                      change_q7gridkeys_layout()
                      if active_mode == "q7" then
                        all_midi_notes_off()
                        q7grid_redraw()
                      end
  end)

  local scale_names = {}
  for  _, scale in pairs(music.SCALES) do
    table.insert(scale_names, scale.name)
  end

  params:add_option("gridkeys_q7_scale", "Q7 scale", scale_names)
  params:set_action("gridkeys_q7_scale",
                    function(v)
                      active_scale = v
                      q7gridkeys:change_scale(active_root_note, active_scale)
                      if active_mode == "q7" then
                        all_midi_notes_off()
                        q7grid_redraw()
                      end
  end)

  params:add_option("gridkeys_q7_root_note", "Q7 root note", music.NOTE_NAMES)
  params:set_action("gridkeys_q7_root_note",
                    function(v)
                      active_root_note = v
                      q7gridkeys:change_scale(active_root_note, active_scale)
                      if active_mode == "q7" then
                        all_midi_notes_off()
                        q7grid_redraw()
                      end
  end)

  params:add_separator()

  if gridkeys_modes[default_mode] ~= 'q7' then
    params:hide("gridkeys_q7_layout")
    params:hide("gridkeys_q7_scale")
    params:hide("gridkeys_q7_root_note")
    -- _menu.rebuild_params()
  end
end

local function startup_init_grid()
  state.grid_device = grid.connect(1)

  state.grid_device.og_all = clone_function(state.grid_device.all)
  state.grid_device.og_intensity = clone_function(state.grid_device.intensity)
  state.grid_device.og_led = clone_function(state.grid_device.led)
  state.grid_device.og_refresh = clone_function(state.grid_device.refresh)

  init_q7gridkeys()

  toggle_grid_key(true)
end


local function script_init_grid()
  state.grid_device = grid.connect(1)

  -- print("mod - gridkeys - TESTING KEY() !!!!!")

  if state.grid_device.key ~= nil then
    print("mod - gridkeys - OFF as grid bound by script")
    state.grid_device.og_key = clone_function(state.grid_device.key)
    state.script_uses_grid = true
  else
    print("mod - gridkeys - ON as grid is free")
    toggle_grid_key(true)
  end
end

--- when no script gets loaded, activate gridkeys
--- this happens on system (re)start and script stop
mod.hook.register("system_post_startup", "gridkeys-sys-post-startup", function ()
                    local script_clear = script.clear
                    script.clear = function()

                      local is_restart = (tabutil.count(params.lookup) == 0)

                      -- if state.grid_device ~= nil then
                      --   restore_grid_initial_state()
                      -- end

                      script_clear()

                      if is_restart then
                        print("mod - gridkeys - clear at (re)start")
                        startup_init_grid()
                        init_params()
                        update_midi_out_device_by_index(1)
                        params:set("gridkeys_midi_mode", 3)
                      else
                        print("mod - gridkeys - clear at script stop / pre-start")
                        -- script_init_grid()
                        state.grid_device = grid.connect(1)
                        init_params()
                        update_midi_out_device_by_index(1)
                        params:set("gridkeys_midi_mode", 3)
                        params:set('gridkeys_active', 2)
                        -- params:bang()
                      end
                    end
end)

--- on script load, conditionally activate gridkeys
mod.hook.register("script_pre_init", "gridkeys-script-pre-init", function()
                    local script_init = init
                    init = function ()

                      if state.grid_device ~= nil then
                        params:set('gridkeys_active', 1)
                      end

                      print("mod - gridkeys - script init")
                      script_init()

                      print("mod - gridkeys - mod init")
                      script_init_grid()
                      params:set('gridkeys_active', (state.script_uses_grid and 1 or 2))
                      params:set("gridkeys_midi_mode", 1)
                    end
end)

--- before any script load, restore grid API &
--- NB: appears to get triggered BEFORE loading any script, even if no script previously loaded + when stopping a script (before a `script.clear`)
mod.hook.register("script_post_cleanup", "gridkeys-script-post-cleanup", function()
                    print("mod - gridkeys - script post cleanup")
                    if state.grid_device ~= nil then
                      restore_grid_initial_state()
                      -- params:set("gridkeys_midi_mode", 3)

                      if params:string("gridkeys_jf_out") == "on" then
                        crow.ii.jf.mode(0)
                      end
                    end
end)
