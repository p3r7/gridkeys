local mod = require 'core/mods'
local script = require 'core/script'
local tabutil = require 'tabutil'
local music = require 'musicutil'

local nb = include("gridkeys/lib/nb/lib/nb")

local grid = util.file_exists(_path.code.."midigrid") and include "midigrid/lib/midigrid" or grid

local midiutils = include("gridkeys/lib/midiutils")
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

local function bool_as_str(v)
  return v and "true" or "false"
end


-- -------------------------------------------------------------------------
-- STATE

local gridkeys_modes = {'basic', 'q7'}
  local default_mode = 2

  local init_state = {
    grid_device = nil,
    script_uses_grid = false,
    midi_in_devices = {},
    midi_out_device = nil,

    active_notes = {},
  }

  GRIDKEYS_STATE = table.copy(init_state)

  local function is_gridkeys_on()
  if not GRIDKEYS_STATE.grid_device then
    return false
  end

  return ( GRIDKEYS_STATE.grid_device.gridkeys_on == true )
end


-- -------------------------------------------------------------------------
-- GRID KEY CB - BASIC

local function basic_grid_key(x, y, z)
  local note_num = util.clamp(((7 - y) * 5) + x + 33, 0, 127)
  local midi_d_is_active = false
  if z == 1 then
    midi_d_is_active = midiutils.note_on(GRIDKEYS_STATE, note_num, params:get("gridkeys_velocity"), params:get("gridkeys_midi_virtual_channel"))
    if midi_d_is_active then
      GRIDKEYS_STATE.grid_device.og_led(GRIDKEYS_STATE.grid_device, x, y, 15)
    end
  else
    midi_d_is_active = midiutils.note_off(GRIDKEYS_STATE, note_num, params:get("gridkeys_midi_virtual_channel"))
    if midi_d_is_active then
      GRIDKEYS_STATE.grid_device.og_led(GRIDKEYS_STATE.grid_device, x, y, 0)
    end
  end

  if midi_d_is_active then
    GRIDKEYS_STATE.grid_device.og_refresh(GRIDKEYS_STATE.grid_device)
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
  if not GRIDKEYS_STATE.grid_device then
    gridType = gridType_none
  else
    if GRIDKEYS_STATE.grid_device.cols == 16 and GRIDKEYS_STATE.grid_device.rows == 8 then
      print("grid 128 detected")
      gridType = gridType_128
    elseif GRIDKEYS_STATE.grid_device.cols == 8 and GRIDKEYS_STATE.grid_device.rows == 8 then
      print("grid 64 detected")
      gridType = gridType_64
    else
      gridType = gridType_none
    end
    GRIDKEYS_STATE.grid_device.nb_levels = grid_utils.nb_levels(GRIDKEYS_STATE.grid_device)
  end

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

  GRIDKEYS_STATE.grid_device.og_all(GRIDKEYS_STATE.grid_device, 0)

  GRIDKEYS_STATE.grid_device.nb_levels = grid_utils.nb_levels(GRIDKEYS_STATE.grid_device)

  local toolbar_btn_brightness = 6
  if GRIDKEYS_STATE.grid_device.nb_levels == 1 then
    toolbar_btn_brightness = 15
  end

  q7gridkeys:draw_grid(GRIDKEYS_STATE.grid_device, q7_is_is_affecting)

  -- toolbar
  GRIDKEYS_STATE.grid_device.og_led(GRIDKEYS_STATE.grid_device, GRIDKEYS_STATE.grid_device.cols - 1, GRIDKEYS_STATE.grid_device.rows, toolbar_btn_brightness) -- down
  GRIDKEYS_STATE.grid_device.og_led(GRIDKEYS_STATE.grid_device, GRIDKEYS_STATE.grid_device.cols, GRIDKEYS_STATE.grid_device.rows, toolbar_btn_brightness) -- up

  GRIDKEYS_STATE.grid_device.og_refresh(GRIDKEYS_STATE.grid_device)
end

local function q7grid_key(x, y, z)
  -- NB: see `GridPlay.grid_key`

  if y == 8 and ((gridType == gridType_128 and x == 15) or (gridType == gridType_64 and x == 7)) then
    midiutils.all_midi_notes_off(GRIDKEYS_STATE)
    q7gridkeys:scroll_down()
  elseif y == 8 and ((gridType == gridType_128 and x == 16) or (gridType == gridType_64 and x == 8)) then
    midiutils.all_midi_notes_off(GRIDKEYS_STATE)
    q7gridkeys:scroll_up()
  else
    q7gridkeys:grid_key(x,y,z)
  end

  q7grid_redraw()
  GRIDKEYS_STATE.grid_device.og_refresh(GRIDKEYS_STATE.grid_device)
end

function q7grid_note_on(gKeys, noteNum, vel)
  -- print("Note On: " .. noteNum.. " " .. vel .. " " .. music.note_num_to_name(noteNum))

  if gKeys.sound_mode == 2 then -- midi out
    q7_is_is_affecting = midiutils.note_on(GRIDKEYS_STATE, noteNum, params:get("gridkeys_velocity"), params:get("gridkeys_midi_virtual_channel"))
  end
end

function q7grid_note_off(gKeys, noteNum)
  -- print("Note Off: " .. noteNum .. " " .. music.note_num_to_name(noteNum))

  if gKeys.sound_mode == 2 then
    midiutils.note_off(GRIDKEYS_STATE, noteNum, params:get("gridkeys_midi_virtual_channel"))
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
  if params:string("gridkeys_mode") == 'basic' then
    basic_grid_key(x, y, z)
  else
    q7grid_key(x, y, z)
  end
end


-- -------------------------------------------------------------------------
-- STATE MANAGEMENT

local function save_og_grid_fns(g)
  g.og_all = clone_function(g.all)
  if g.intensity ~= nil then
    g.og_intensity = clone_function(g.intensity)
  else
    -- NB: workaround for `midigrid`
    g.og_intensity = function(...) end
  end

  g.og_led = clone_function(g.led)
  g.og_refresh = clone_function(g.refresh)
end

local function remove_snapshoted_grid_fns(g)
  -- methods
  g.og_all = nil
  g.og_intensity = nil
  g.og_led = nil
  g.og_refresh = nil

  -- callbacks
  g.og_key = nil
end

local function restore_og_grid_fns(g)
  if not g.og_all then
    return
  end

  -- methods
  g.all = g.og_all
  g.intensity = g.og_intensity
  g.led = g.og_led
  g.refresh = g.og_refresh

  -- callbacks
  g.key = g.og_key
end


local function gridkeys_takeover(g)
  g.all = function(...) end
  g.intensity = function(...) end
  g.led = function(...) end
  g.refresh = function(...) end

  g.key = grid_key
  -- g.key = basic_grid_key

  g.gridkeys_on = true
end

local function set_gridkeys(status)
  print("mod - gridkeys - SET_GRIDKEYS = "..bool_as_str(status))

  if not GRIDKEYS_STATE.grid_device  then
    print("mod - gridkeys - SET_GRIDKEYS - no grid -> ABORT")
    return
  end

  GRIDKEYS_STATE.grid_device.og_all(GRIDKEYS_STATE.grid_device, 0)
  GRIDKEYS_STATE.grid_device.og_refresh(GRIDKEYS_STATE.grid_device)

  if status == false then
    if is_gridkeys_on() then
      restore_og_grid_fns(GRIDKEYS_STATE.grid_device)

      GRIDKEYS_STATE.grid_device.gridkeys_on = nil
    else
      print("mod - gridkeys - SET_GRIDKEYS -> NO CHANGE")
    end
  else
    if not is_gridkeys_on() then
      -- print("ACTIVATE GRIDKEYS")
      gridkeys_takeover(GRIDKEYS_STATE.grid_device)

      GRIDKEYS_STATE.grid_device.gridkeys_on = true

      if params:string("gridkeys_mode") == 'q7' then
        q7grid_redraw()
      end
    else
      print("mod - gridkeys - SET_GRIDKEYS -> NO CHANGE")
    end
  end
end

local function enable_gridkeys()
  set_gridkeys(true)
end

local function disable_gridkeys()
  set_gridkeys(false)
end

--- restore grid API fns
local function restore_grid_initial_state()
  GRIDKEYS_STATE.grid_device = grid.connect(1)
  disable_gridkeys()
  GRIDKEYS_STATE.grid_device.key = nil
  state = table.copy(init_state)
  -- print("mod - gridkeys - UNSET KEY() !!!!!")
end


-- -------------------------------------------------------------------------
-- MAIN

local function init_params()
  params:add_separator("MOD - GRIDKEYS")

  local OFF_ON = {"off", "on"}
  local ON_OFF = {"on", "off"}
  params:add_option("gridkeys_active", "gridkeys active", OFF_ON,
                    GRIDKEYS_STATE.script_uses_grid and tab.key(OFF_ON, "off") or tab.key(OFF_ON, "on"))
  params:set_action("gridkeys_active",
                    function(v)
                      set_gridkeys(OFF_ON[v] == "on")
  end)

  params:add_option("gridkeys_midi_virtual", "midi virtual", ON_OFF)
  params:set_action("gridkeys_midi_virtual",
                    function(v)
                      midiutils.all_midi_notes_off(GRIDKEYS_STATE)

                      if ON_OFF[v] == "on" then
                        params:show("gridkeys_midi_virtual_channel")
                      else
                        params:hide("gridkeys_midi_virtual_channel")
                      end
                      _menu.rebuild_params()
  end)

  params:add{type = "number", id = "gridkeys_midi_virtual_channel", name = "MIDI Out Channel", min = 1, max = 16, default = 1}
  params:set_action("gridkeys_midi_virtual_channel",
                    function(v)
                      midiutils.all_midi_notes_off(GRIDKEYS_STATE)
  end)

  nb:add_param("gridkeys_nb_voice", "nb Voice")

  params:add{type = "number", id = "gridkeys_velocity", name = "Velocity", min = 1, max = 127, default = 100}

  params:add_option("gridkeys_mode", "Mode", gridkeys_modes, default_mode)
  params:set_action("gridkeys_mode",
                    function(v)
                      local prev_mode = params:string("gridkeys_mode")

                      midiutils.all_midi_notes_off(GRIDKEYS_STATE)
                      if prev_mode == 'basic' then
                        if is_gridkeys_on() then
                          GRIDKEYS_STATE.grid_device.og_all(GRIDKEYS_STATE.grid_device, 0)
                          GRIDKEYS_STATE.grid_device.og_refresh(GRIDKEYS_STATE.grid_device)
                        end
                        params:hide("gridkeys_q7_layout")
                        params:hide("gridkeys_q7_scale")
                        params:hide("gridkeys_q7_root_note")
                      else
                        if is_gridkeys_on() then
                          q7grid_redraw()
                        end
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
                      if params:string("gridkeys_mode") == "q7" then
                        midiutils.all_midi_notes_off(GRIDKEYS_STATE)
                        q7grid_redraw()
                      end
  end)

  local scale_names = {}
  for _, scale in pairs(music.SCALES) do
    table.insert(scale_names, scale.name)
  end

  params:add_option("gridkeys_q7_scale", "Q7 scale", scale_names)
  params:set_action("gridkeys_q7_scale",
                    function(v)
                      q7gridkeys:change_scale(params:get("gridkeys_q7_root_note"), v)
                      if params:string("gridkeys_mode") == "q7" then
                        midiutils.all_midi_notes_off(GRIDKEYS_STATE)
                        q7grid_redraw()
                      end
  end)

  params:add_option("gridkeys_q7_root_note", "Q7 root note", music.NOTE_NAMES)
  params:set_action("gridkeys_q7_root_note",
                    function(v)
                      q7gridkeys:change_scale(v, params:get("gridkeys_q7_scale"))
                      if params:string("gridkeys_mode") == "q7" then
                        midiutils.all_midi_notes_off(GRIDKEYS_STATE)
                        q7grid_redraw()
                      end
  end)

  if gridkeys_modes[default_mode] ~= 'q7' then
    params:hide("gridkeys_q7_layout")
    params:hide("gridkeys_q7_scale")
    params:hide("gridkeys_q7_root_note")
    -- _menu.rebuild_params()
  end

  -- TODO: conditionally add those if script not using nb
  nb:add_player_params()
end


-- -------------------------------------------------------------------------
-- mod lifecycle - init

local function script_init_grid()
  local i = 1
  local g = grid.connect(i)

  if not g or g.name == "none" then
    print("mod - gridkeys - no grid detected at position "..i)
    return
  end

  GRIDKEYS_STATE.grid_device = g
  save_og_grid_fns(GRIDKEYS_STATE.grid_device)

  if GRIDKEYS_STATE.grid_device.key ~= nil then
    print("mod - gridkeys - OFF as grid bound by script")
    GRIDKEYS_STATE.grid_device.og_key = clone_function(GRIDKEYS_STATE.grid_device.key)
    GRIDKEYS_STATE.script_uses_grid = true
  else
    print("mod - gridkeys - ON as grid is free")
    enable_gridkeys()
  end
end


-- -------------------------------------------------------------------------
-- mod lifecycle - hooks

--- on script load, conditionally activate gridkeys
mod.hook.register("script_post_init", "gridkeys-script-post-init", function()
                    print("mod - gridkeys - mod init")

                    nb.voice_count = 1
                    nb:init()

                    init_params()
                    GRIDKEYS_STATE.grid_device = grid.connect(1)
                    init_q7gridkeys()

                    script_init_grid()

                    params:set('gridkeys_active', (GRIDKEYS_STATE.script_uses_grid and 1 or 2))
end)

--- before any script load, restore grid API &
--- NB: appears to get triggered BEFORE loading any script, even if no script previously loaded + when stopping a script (before a `script.clear`)
mod.hook.register("script_post_cleanup", "gridkeys-script-post-cleanup", function()
                    print("mod - gridkeys - script post cleanup")
                    for i=1,16 do
                      local g = grid.connect(i)
                      if g then
                        restore_og_grid_fns(g)
                        remove_snapshoted_grid_fns(g)
                      end
                    end
end)
