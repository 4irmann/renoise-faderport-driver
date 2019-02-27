--[[-----------------------------------------------------------------------------------
  
  FaderPort: MIDI Message Handler
  
  This was "outsourced" but actually needs refactoring
  
  Copyright 2010-2019 4irmann, 
  
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License. 
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 

  Unless required by applicable law or agreed to in writing, software distributed 
  under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
  CONDITIONS OF ANY KIND, either express or implied. See the License for the specific 
  language governing permissions and limitations under the License.
  
-------------------------------------------------------------------------------------]]

require "Globals"
require "Helpers"
require "Debug"

-- MIDI message handler
-- receives midi messages from FaderPort
function FaderPort:midi_callback(message)

  if (self.shift_pressed) then
    TRACE("midi_callback()")
  end

  -- check if midi events shall be handled at all
  if (self.lock_midi_in) then
    return
  end

  local msg = message
  if (prefs.dump_midi.value) then
    print(("FaderPort: %s received MIDI %X %X %X"):format(
      prefs.midi_in_name.value, message[1], message[2], message[3]))
  end
  
  -- we are not interested in messages if there's no valid song instance
  -- This is the case if song is in a transition state (new song/load song)
  if (not song()) then
    return
  end

  -- fader value
  if (msg[1] == 0xb0) then  
    
    -- ugly undo workaround
    -- mutex: if pan/trim control is moved ignore fader values
    if (prefs.undo_workaround.value and not self.sticky_mode) then
      if (self.pan_moved or self.trim_moved) then
        return
      end
    end       
    
    if (msg[2] == 0x00) then
      self.last_msb = msg[3] -- store msb, wait for lsb
    elseif (msg[2] == 0x20) then --lsb        
      local intval = bit.lshift(self.last_msb,3)
      intval = intval + bit.rshift(msg[3],4) 
      self:on_receive_fader_value(intval)
    end

  -- pan and trim value
  elseif (msg[1] == 0xe0 and msg[2] == 0x00) then     
    
    -- ugly undo workaround
    -- mutex: if fader is moved ignore pan control values
    if (prefs.undo_workaround.value and not self.sticky_mode) then
      if (self.fader_moved) then
        return
      end
    end 
      
    if (self.shift_pressed) then 
      -- trim device parameter value bound to fader
      self:on_receive_trim_value(msg[3])
    else  
      -- actual pan 
      self:on_receive_pan_value(msg[3])
    end

  -- button handling
  elseif (msg[1] == 0xa0) then

    -- fader touch state
    if (msg[2] == 0x7f) then
      self.fader_touched = (msg[3] == 1)
      if (self.fader_touched) then
      
        TRACE("FADER TOUCHED")
      
        -- latch mode handling
        if (self.fader_mode == FADER_MODE_LATCH and
          song().transport.playing) then
          self.latch_write = true
        end
      else -- fader release handling
        
        -- ugly undo workaround
        if (prefs.undo_workaround.value and not self.sticky_mode) then
          
          TRACE("FADER RELEASED")
          
          self.fader_moved = false 
          self.fader_undo_count = 0    
        end
        
        -- force update to be in sync with Renoise
        -- fader could've been moved and the device parameter wasn't changed
        if (self.fader_mode == FADER_MODE_READ) then
          self:on_fader_devpara_value_change()
        end
        
        -- further release handling on demand,
        -- e.g. later on force storage of undo data here if possible
      end
      
    -- pan move/touch state (faked)
    elseif (msg[2] == 0x7d) then
      local pan_touched = (msg[3] == 1)
      if (pan_touched) then
        -- n/a
      else -- pan release handling
        
        TRACE("PAN RELEASED")
        
        -- ugly undo workaround
        if (prefs.undo_workaround.value and not self.sticky_mode) then
          self.pan_moved = false 
          self.pan_undo_count = 0
        end
      end
      
    -- trim move/touch state (faked)
    elseif (msg[2] == 0x7c) then
      local trim_touched = (msg[3] == 1)
      if (trim_touched) then
        -- n/a
      else -- trim release handling
      
        TRACE("TRIM RELEASED")
        
        -- ugly undo workaround
        if (prefs.undo_workaround.value and not self.sticky_mode) then
          self.trim_moved = false 
          self.trim_undo_count = 0
        end
      end
   
    -- transport shift
    elseif (msg[2] == 0x02) then
      self.shift_pressed = (msg[3] == 1)
      self:set_light_state(0x05,self.shift_pressed)

    -- transport play or footswitch
    elseif ((msg[2] == 0x06 and msg[3] == 1) or 
            (msg[2] == 0x7e and msg[3] == prefs.footswitch_pressed_signal.value)) then      
      if (song().transport.playing) then
        song().transport:stop()
      else
        local start_mode = renoise.Transport.PLAYMODE_RESTART_PATTERN
        if (self.shift_pressed) then
          start_mode = renoise.Transport.PLAYMODE_CONTINUE_PATTERN
        end
        song().transport:start(start_mode)
      end

    -- transport stop
    elseif (msg[2] == 0x05 and msg[3] == 1) then
      if (song().transport.playing) then
        song().transport:stop()
      else
        song().transport:panic()
      end

    -- transport loop
    elseif (msg[2] == 0x0f and msg[3] == 1) then
      if (self.shift_pressed) then
        self:status_bar_display_binding()
        self:set_light_state(0x08,true)
      else
        song().transport.loop_pattern =
          not song().transport.loop_pattern
      end
    elseif (msg[2] == 0x0f and msg[3] == 0) then
      if (not song().transport.loop_pattern) then
        self:set_light_state(0x08,false)
      end

    -- transport punch
    elseif (msg[2] == 0x01 and msg[3] == 1) then
      if (self.shift_pressed) then
        song().transport:loop_block_move_backwards()
      else
        song().transport.loop_block_enabled =
          not song().transport.loop_block_enabled
      end

    -- transport user
    elseif (msg[2] == 0x00 and msg[3] == 1) then
      if (self.shift_pressed) then
        song().transport:loop_block_move_forwards()
        self:set_light_state(0x07,true)
      else
        if (renoise.app().window.sample_record_dialog_is_visible) then
          self:set_light_state(0x07,true)
          song().transport:start_stop_sample_recording()
        else
          self.fader_pan_swapped = not self.fader_pan_swapped
          self:bind_devparas_to_fader_pan(self.fader_devpara,self.pan_devpara,true) -- swap fader and pan
          self:set_light_state(0x07,self.fader_pan_swapped)
        end
      end
    elseif (msg[2] == 0x00 and msg[3] == 0) then
      if (not self.fader_pan_swapped) then
        self:set_light_state(0x07,false)
      end

    -- transport edit/record
    elseif (msg[2] == 0x07 and msg[3] == 1) then
      song().transport.edit_mode =
        not song().transport.edit_mode

    -- transport rewind
    elseif (msg[2] == 0x03 and msg[3] == 1) then
      self:set_light_state(0x04,true)
      self.rewind_pressed = true
      if (self.forward_pressed) then
        self:on_reset_fader_devpara_to_default()
      end
    elseif (msg[2] == 0x03 and msg[3] == 0) then
      if (not self.forward_pressed) then
        if (self.shift_pressed) then -- Start Pos
          local new_edit_pos = song().transport.edit_pos
          new_edit_pos.sequence = 1
          song().transport.edit_pos = new_edit_pos
        else
          self:transport_delta(-1) -- one step backwards
        end
        self.rewind_pressed = false
      else
        self.forward_pressed = false
      end
      self:set_light_state(0x04,false)

    -- transport fast forward
    elseif (msg[2] == 0x04 and msg[3] == 1) then
      self:set_light_state(0x03,true)
      self.forward_pressed = true
      if (self.rewind_pressed) then
        self:on_reset_fader_devpara_to_default()
      end
    elseif (msg[2] == 0x04 and msg[3] == 0) then
      if (not self.rewind_pressed) then

        if (self.shift_pressed) then -- End Pos
          local new_edit_pos = song().transport.edit_pos
          new_edit_pos.sequence = song().transport.song_length.sequence
          song().transport.edit_pos = new_edit_pos
        else
          self:transport_delta(1) -- one step forward
        end
        self.forward_pressed = false
      else
        self.rewind_pressed = false
      end
      self:set_light_state(0x03,false)

    -- channel mute 
    elseif (msg[2] == 0x12 and msg[3] == 1) then
      if (self.last_track.type ~= renoise.Track.TRACK_TYPE_MASTER) then
        if (self.last_track.mute_state ==
          renoise.Track.MUTE_STATE_ACTIVE) then
          self.last_track:mute()
        else
          self.last_track:unmute()
        end
      else         
        -- Since the master track can't be muted via Lua API
        -- do the same as Renoise 3: 
        -- if no track is muted -> mute all tracks but master
        -- if any track is muted -> unmute all tracks 
        local unmute = false
        for i = 1,#renoise.song().tracks do
          if (renoise.song().tracks[i].type ~= renoise.Track.TRACK_TYPE_MASTER) then
            if (renoise.song().tracks[i].mute_state ~= renoise.Track.MUTE_STATE_ACTIVE) then
              unmute = true
            end
          end
        end  
        for i = 1,#renoise.song().tracks do
          if (renoise.song().tracks[i].type ~= renoise.Track.TRACK_TYPE_MASTER) then
            if (unmute) then
              renoise.song().tracks[i]:unmute()
            else
              renoise.song().tracks[i]:mute()
            end
          end
        end                
      end

    -- channel solo
    elseif (msg[2] == 0x11 and msg[3] == 1) then
      self.last_track.solo_state =
        not self.last_track.solo_state

     -- channel rec / toggle record dialog visible
    elseif (msg[2] == 0x10 and msg[3] == 1) then
      renoise.app().window.sample_record_dialog_is_visible =
        not renoise.app().window.sample_record_dialog_is_visible

    -- fader mode read
    elseif (msg[2] == 0x0a and msg[3] == 1) then
      self:toggle_fader_mode(FADER_MODE_READ)

    -- fader mode touch
    elseif (msg[2] == 0x08 and msg[3] == 1) then
      self:toggle_fader_mode(FADER_MODE_TOUCH)

    -- fader mode write / latch
    elseif (msg[2] == 0x09 and msg[3] == 1) then
      local mode = FADER_MODE_WRITE
      if (self.shift_pressed) then
        mode = FADER_MODE_LATCH
      end
      if (prefs.latch_is_default_write_mode.value) then
        if (mode == FADER_MODE_WRITE) then
          mode = FADER_MODE_LATCH
        else
          mode = FADER_MODE_WRITE
        end
      end
      self:toggle_fader_mode(mode)

    -- fader mode: fader off
    -- HINT: as long as the button is pressed the light is switched on.
    -- Whenever the light is switched on, no fader values are sent
    -- from FaderPort while fader is beeing moved !
    -- This maybe helpfull for doing fader readjustments in write modes
    -- without actually writing values.
    -- Anyway: after releasing the button the light is set to off.
    -- The fader mode itself is not affected. To switch off fader mode the
    -- currently activated fader mode button must be pressed again
    elseif (msg[2] == 0x17 and msg[3] == 1) then
      self:set_light_state(0x10,true)
    elseif (msg[2] == 0x17 and msg[3] == 0) then
      self:set_light_state(0x10,false)

    -- channel select left
    elseif (msg[2] == 0x13 and msg[3] == 1) then
      self:set_light_state(0x14,true)
      if (self.device_type == DEVICE_PRE_MIXER or
          self.device_type == DEVICE_POST_MIXER) then
        song().selected_track_index =
          wrap_value(song().selected_track_index - 1,1, #song().tracks)
      elseif (self.device_type == DEVICE_DSP) then
        if (self.shift_pressed) then  -- select dsp
          song().selected_track_device_index =
            wrap_value(song().selected_track_device_index - 1,1, #self.last_track.devices)
        else -- select dsp binding
          self:select_prev_dsp_binding()
        end
      end
    elseif (msg[2] == 0x13 and msg[3] == 0) then
      self:set_light_state(0x14,false)

    -- channel select right
    elseif (msg[2] == 0x15 and msg[3] == 1) then
      self:set_light_state(0x12,true)
      if (self.device_type == DEVICE_PRE_MIXER or
          self.device_type == DEVICE_POST_MIXER) then
        song().selected_track_index =
          wrap_value(song().selected_track_index + 1,1, #song().tracks)
      elseif (self.device_type == DEVICE_DSP) then
        if (self.shift_pressed) then -- select dsp
          song().selected_track_device_index =
            wrap_value(song().selected_track_device_index + 1,1, #self.last_track.devices)
        else -- select dsp binding
          self:select_next_dsp_binding()
        end
      end
    elseif (msg[2] == 0x15 and msg[3] == 0) then
      self:set_light_state(0x12,false)

    -- channel select bank
    elseif (msg[2] == 0x14 and msg[3] == 1) then
      if (not self.sticky_mode) then       
          self.dsp_mode = not self.dsp_mode
      else
        -- already in sticky mode, need a valid device here
        -- Problem: if no device is selected we don't know
        -- which device shall be made sticky !
        if (self.last_device ~= nil) then
          self.dsp_mode = not self.dsp_mode
        end
      end
      self:set_light_state(0x13,self.dsp_mode)

      if (self.dsp_mode)
      then
        self.device_type = DEVICE_DSP
        self:on_device_type_change()
      else
        if (renoise.app().window.mixer_view_post_fx) then
          self.device_type = DEVICE_POST_MIXER -- post mixer has higher prio
        else
          self.device_type = DEVICE_PRE_MIXER
        end
        self:on_device_type_change()
      end

    -- channel select output
    elseif (msg[2] == 0x16 and msg[3] == 1) then
      if (self.shift_pressed) then
        self:select_master_track()
        self:set_light_state(0x11,true)
      else 
        renoise.app().window.mixer_view_post_fx = not renoise.app().window.mixer_view_post_fx
      end
    elseif(msg[2] == 0x16 and msg[3] == 0) then
      if (not renoise.app().window.mixer_view_post_fx) then
        self:set_light_state(0x11,false)
      end

    -- window view mix
    elseif (msg[2] == 0x0b and msg[3] == 1) then
      renoise.app().window.active_middle_frame =
        renoise.ApplicationWindow.MIDDLE_FRAME_MIXER

    -- window view proj
    elseif (msg[2] == 0x0c and msg[3] == 1) then
      renoise.app().window.active_middle_frame =
        renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR

    -- window view trns
    elseif (msg[2] == 0x0d and msg[3] == 1) then
      if (prefs.sticky_mode_support.value) then
        if (self.shift_pressed) then -- change middle frame
          renoise.app().window.active_middle_frame =
            renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR
        else
          self:toggle_sticky_mode() -- sticky mode
        end
      else
        renoise.app().window.active_middle_frame =
          renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR
      end

    -- window view undo / redo
    elseif (msg[2] == 0x0e and msg[3] == 1) then
      self:set_light_state(0x09,true)
      if (self.shift_pressed) then
        if (song():can_redo()) then
          song():redo()
        end
      else
        if (song():can_undo()) then
          song():undo()
        end
      end
    elseif (msg[2] == 0x0e and msg[3] == 0) then
      self:set_light_state(0x09,false)

    end
  end
end

-- MIDI message handler for sysex messages
function FaderPort:sysex_callback(message)
  -- n/a
end

