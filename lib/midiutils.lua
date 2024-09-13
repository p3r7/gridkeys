
local midiutils = {}


-- -------------------------------------------------------------------------
-- devices

function midiutils.update_midi_out_device_by_index(STATE, v)
  local device = midi.connect(v)
  -- print("mod - gridkeys - init_params - midi_out_device=" .. device.name)
  if device.name == 'virtual' or device.name == "none" then
    STATE.midi_out_device = nil
  else
    STATE.midi_out_device = device
  end
end


-- -------------------------------------------------------------------------
-- messages

function midiutils.send_midi_msg(STATE, msg)
  local data = midi.to_data(msg)
  local is_note_on = (msg.type == 'note_on')

  -- midi "in" (virtual)
  local is_affecting_virtual = false
  if params:string("gridkeys_midi_virtual") == "on" then
    for _, dev in pairs(midi.devices) do
      -- is `virtual` and is bound
      if dev.name == 'virtual' and dev.port ~= nil then
        if midi.vports[dev.port].event ~= nil then
          midi.vports[dev.port].event(data)
          is_affecting_virtual = true
          break
        end
      end
    end
  end

  -- nb
  local is_affecting_nb = false
  if params:string("gridkeys_nb_voice") ~= "none" then
    local player = params:lookup_param("gridkeys_nb_voice"):get_player()
    if msg.type == "note_on" then
      player:note_on(msg.note, msg.vel/127)
    elseif msg.type == "note_off" then
      player:note_off(msg.note)
    end
    is_affecting_nb = true
  end

  return (is_affecting_virtual or is_affecting_nb)
end


-- -------------------------------------------------------------------------
-- notes on/off

function midiutils.note_on(STATE, note_num, vel, chan)
  chan = chan or 1
  local msg = {
    type = 'note_on',
    note = note_num,
    vel = vel,
    ch = chan,
  }

  if STATE.active_notes[note_num] == nil then
    STATE.active_notes[note_num] = true
  end

  return midiutils.send_midi_msg(STATE, msg)
end

function midiutils.note_off(STATE, note_num, chan)
  chan = chan or 1
  local msg = {
    type = 'note_off',
    note = note_num,
    vel = 0,
    ch = chan,
  }

  STATE.active_notes[note_num] = nil

  return midiutils.send_midi_msg(STATE, msg)
end

function midiutils.all_midi_notes_off(STATE)
  for note_num, v in pairs(STATE.active_notes) do
    if v == true then
      midiutils.note_off(STATE, note_num, chan)
    end
  end
end


-- -------------------------------------------------------------------------

return midiutils
