 --[[------------------------------------------------------------------------------------
  
  FaderPort driver main

  this is a big class that actually needs some refactoring.
  
  Copyright 2010-2019 4irmann, 
  
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License. 
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 

  Unless required by applicable law or agreed to in writing, software distributed 
  under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
  CONDITIONS OF ANY KIND, either express or implied. See the License for the specific 
  language governing permissions and limitations under the License.
  
--------------------------------------------------------------------------------------]]--

class "FaderPort"

-- includes and outsourced stuff
require "Debug"
require "Helpers"
require "Globals"
require "MidiHandler"

-- constructor for initializations on application level 
-- nothing song specific is initialized in here
function FaderPort:__init()

  TRACE("__init()")

  self:init_members()

  self.midi_in = nil
  self.midi_out = nil
  
  self.lock_midi_in = true -- signals that no midi events shall be received 
  self.lock_midi_out = true -- signals that no midi events shall be sent
  
  self.connected = false -- connected state. Indicates if FaderPort is connected/bound to Renoise
  
  -- workaround "emulator dialog invisible bug"
  self.application_loaded = false -- status flag. 
                                  -- Indicates if Renoise main window was loaded/initialized
     
  -- app became active 
  if (not renoise.tool().app_became_active_observable:has_notifier(
    self,self.on_app_became_active)) then
    renoise.tool().app_became_active_observable:add_notifier(
      self,self.on_app_became_active)
  end
  
  -- app resigned active 
  if (not renoise.tool().app_resigned_active_observable:has_notifier(
    self,self.on_app_resigned_active)) then
    renoise.tool().app_resigned_active_observable:add_notifier(
      self,self.on_app_resigned_active)
  end
  
  -- add new song observer
  if (not renoise.tool().app_new_document_observable:has_notifier(
    self,self.on_song_created)) then
    renoise.tool().app_new_document_observable:add_notifier(
      self,self.on_song_created)
  end
  
  -- add song pre-release observer  
  if (not renoise.tool().app_release_document_observable:has_notifier(
    self,self.on_song_pre_release)) then
    renoise.tool().app_release_document_observable:add_notifier(
      self,self.on_song_pre_release)
  end
       
  -- device info dialog 'n view
  local vb = renoise.ViewBuilder()
  self.device_info_dialog = nil
  local device_info_dialog_width = 250
  self.device_info_bindings = 
    vb:textfield { 
      text = "n/a", 
      width = device_info_dialog_width,
    }
  self.device_info_name =
    vb:textfield {
      text = "select a device",
      width = device_info_dialog_width,
    }
  self.device_info_parameters = 
    vb:multiline_textfield {
      text = "select a device",
      width = device_info_dialog_width,
      height = 300,        
    }
  self.device_info_view = 
    vb:column {
      margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
      spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,
      self.device_info_name,
      self.device_info_bindings,
      self.device_info_parameters     
    }     
    
   -- help dialog 'n view
   io.input("doc/help.txt")
   local help_file = io.read("*all")
   self.help_dialog = nil
   local help_dialog_width = 700
   self.manual_button =
     vb:button {       
       height = 30,
       text = "Open PDF manual in browser",
       released = function() renoise.app():open_url("doc/faderport_manual.pdf") end
     }   
   self.latest_release_button =
     vb:button {       
       height = 30,
       text = "Latest release",
       released = function()    renoise.app():open_url("https://github.com/4irmann/renoise-faderport-driver.git") end
     }        
   
   self.help_text =
     vb:multiline_textfield {
       text = help_file,
       width = help_dialog_width,
       height = 800,
       font = "mono",
       edit_mode = false      
     }
   self.help_view =
     vb:column {
       margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
       spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,       
       vb:row {
         margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
         spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,              
         self.donate_button,
         self.manual_button,          
         self.latest_release_button,
         self.airmann_blog_button
       },
       self.help_text
     }          
end

-- member variable initialization
function FaderPort:init_members()

  TRACE("init_members()")

  -- idle workarounds for missing observable support
  -- will be changed as soon as observable support is available
  self.last_record_dialog_is_visible = nil
  self.last_loop_block_enabled = nil
  self.last_edit_pos_line = nil  

  -- track 'n device
  self.last_track = nil -- last selected track
  self.last_track_index = nil -- last selected track index
  self.last_device = nil -- last selected device in device chain
  self.last_device_index = nil -- last selected device index

  -- currently selected device type
  if (prefs.default_is_post_fx_mixer.value) then
    self.device_type = DEVICE_POST_MIXER
  else
    self.device_type = DEVICE_PRE_MIXER 
  end
  
  self.dsp_mode = false -- fader and pan are bound to dsp devices
  self.sticky_mode = false -- indicates if sticky mode is active
  renoise.app().window.mixer_view_post_fx = 
    prefs.default_is_post_fx_mixer.value -- fader and pan are bound to post mixer volume / panning
  self.fader_pan_swapped = false -- fader and pan swapped

  self.dsp_binding_start_index = nil -- start index of current dsp binding list
  self.dsp_binding_end_index = nil -- end index of current dsp binding list
  self.dsp_binding_sel_index = nil -- index of currently selected dsp binding pair

  -- fader
  self.fader_devpara = nil -- device parameter bound to fader
  self.last_msb = nil -- last received MSB of MIDI bank select
  self.fader_value = nil -- cached current fader value - received or send/set
  self.fader_mode = FADER_MODE_OFF -- fader mode (affects also light states)
  self.latch_write = false -- indicates for latch mode that values are written
  self.fader_touched = false  -- indicates if fader is currently beeing touched (reflects hardware event !)
  self.fader_moved = false -- indicates if fader was moved while beeing touched. Means also: we have received a value
  self.fader_undo_count = 0 -- number of created Renoise undo points during movement 

  -- pan
  self.pan_devpara = nil -- device parameter bound to pan control
  self.last_pan_time = nil --  virtual pan control modification time - for relative speed measurement
  self.last_pan_value_received_time = nil -- midi receive time - for release detection
  self.pan_left_count = 0 -- for relative speed measurement
  self.pan_right_count = 0 -- for relative speed measurement
  self.virtual_pan_value = 0 -- absolute value of virtual pan control
  self.pan_moved = false -- true after first value is received, indicates implicitly if pan has been touched
  self.pan_undo_count = 0 -- number of created Renoise undo points during movement 

  -- fader trim
  self.last_trim_time = nil -- virtual trim control modification time - for relative speed measurement
  self.last_trim_value_received_time = nil -- midi receive time - for release detection
  self.trim_left_count = 0 -- for relative speed measurement
  self.trim_right_count = 0 -- for relative speed measurement
  self.trim_moved = false -- true after first value is received, indicates implicitly if trim has been touched
  self.trim_undo_count = 0 -- number of created Renoise undo points during movement

  -- button states. Indicate if buttons are currently pressed
  self.shift_pressed = false
  self.write_pressed = false
  self.touch_pressed = false
  self.rewind_pressed = false
  self.forward_pressed = false

end

-- switch off all FaderPort lights
function FaderPort:switch_off_lights()

  TRACE("switch_off_lights()")
  
  local message = {nil, nil, nil}
  for x = 0, 0x30 do
      message = {0xa0,x,0}
      self:midi_send(message)
  end
end

-- switch off lights and send a specific MIDI reset message to reset FaderPort
function FaderPort:send_midi_reset()

  TRACE("send_midi_reset()")

  -- this is a kind of init/reset message
  -- TODO: but what is it exactly ? Note On command, channel 0 ?
  local message = {0x91,0x00,0x64}
  self:midi_send(message)
  
  self:switch_off_lights()  
  
  -- wait some milliseconds to be sure
  local time = os.clock()+0.1
  while os.clock()< time do
    -- nothing
  end
end

-- reset midi ports, FaderPort controller and light states
-- without re-initializing member variables
function FaderPort:reset()

  TRACE("reset()")

  if (not self.connected) then
    return
  end

  self.lock_midi_in = true
  self.lock_midi_out = true

  -- emulator handling
  -- HINT: it is possible to close (=destroy!) the emulator dialog
  -- while the emulator still stays in connected state.
  -- This is not possible with real hardware. So if the
  -- dialog is in closed state while being reset, we need a 
  -- disconnect+connect call which has to be explicitly done here.
  -- Otherwise the emulators dialog state (especially fader state) 
  -- would not be updated correctly.
  if (prefs.emulation_mode.value) then
    if (not emulator:dialog_visible()) then
      self:connect()
    end  
  else
    -- close and re-create MIDI I/O devices
    self:midi_close()
    self:midi_open()  
  end

  -- switch off lights and send reset message to FaderPort
  if (self.midi_in) then
    self.lock_midi_out = false
    self:send_midi_reset()  
    self:update_light_states()
 end
  
  if (self.midi_out) then
    self.lock_midi_in = false
  end
end

-- connect FaderPort to Renoise
function FaderPort:connect()

  TRACE("connect()")  

  -- emulator handling
  -- HINT: it is possible to close (=destroy!) the emulator dialog
  -- while the emulator still stays in connected state. This
  -- is not possible with real hardware. So if the
  -- dialog is in closed state while being connected, we need a 
  -- a disconnect+connect call which has to be explicitly done here.
  -- Otherwise the emulators dialog state (especially fader state) 
  -- would not be updated correctly.
  if (prefs.emulation_mode.value) then
    if (self.connected) then
      if (not emulator:dialog_visible()) then            
        self:disconnect() -- close everything, so that it is re-openend and
                          -- properly initialized later on. We take into
                          -- account that some functions like midi_close or
                          -- send_midi_reset are called multiple times
      end          
    end
  end  

  if (not (self.midi_in and self.midi_out)) then
    self:midi_close()
    self:midi_open()
  end 
  
  -- error
  if (not (self.midi_in and self.midi_out)) then
    return
  end
    
  if (self.connected) then
    return
  end
  
  if (song()) then
   
    self:init_members()  
   
    self.lock_midi_in = false
    self.lock_midi_out = false
  
    self:send_midi_reset() 
   
    self:add_notifiers()    
    self:update_light_states()
        
    self.connected = true  
  end
end

-- disconnect FaderPort from Renoise
-- removes all notifiers, reset members, 
-- clear lights and close MIDI I/O devices
function FaderPort:disconnect()

  TRACE("disconnect()")
  
  self.lock_midi_in = true
  
  if (self.connected) then
    self:remove_notifiers()
    self:init_members()
  end
  
  self.lock_midi_out = false
  
  self:switch_off_lights()
  self:midi_close()
  
  self.lock_midi_out = true
 
  self.connected = false
end

-- song created handler
-- reset member variables and register notifiers
function FaderPort:on_song_created()
  
  TRACE("on_song_created()")
  
  if (prefs.auto_connect.value) then    
    self:connect()    
  end      
end

-- song pre release handler
-- this is called right before the song is being released
function FaderPort:on_song_pre_release()

  TRACE("on_song_pre_release()")    
    
  -- we don't close midi, but instead lock it
  -- if we would close it, there could arise problems
  -- while re-opening it later on. It's not efficient, either.
  -- If Renoise is quit, then MIDI is closed implicitly by Renoise
  self.lock_midi_in = true
  self.lock_midi_out = false
  
  self:remove_notifiers()
  self:init_members() 
  self:switch_off_lights()
  
  -- emulator handling (needs that midi is closed)
  if (prefs.emulation_mode.value) then
  self:midi_close()
  end
  
  self.lock_midi_out = true
  self.connected = false  
end

-- app resigned handler
-- this is important if FaderPort shall be used for more
-- than one Renoise instance simultaneously
-- TODO: still experimental code !
function FaderPort:on_app_resigned_active()
  
  TRACE("on_app_resigned_active()")
  
  if (prefs.switch_off_when_app_resigned.value) then
    self:send_midi_reset()
    self:midi_close()
  end
end

-- app became active handler
-- this is important if FaderPort shall be used for more
-- than one Renoise instance simultaneously
-- TODO: still experimental code !
function FaderPort:on_app_became_active()

  TRACE("on_app_became_active()")

  if (prefs.switch_off_when_app_resigned.value) then    
    
    local time = os.clock()+3
    while (os.clock() < time) and not
          ((self.midi_in and self.midi_in.is_open) or
          (self.midi_out and self.midi_out.is_open)) do
      self:midi_open()
    end
    
    self:send_midi_reset()
    self:update_light_states()
    if (self.fader_devpara) then
      self:on_fader_devpara_value_change()
    end
  end
end

-- update all light states
function FaderPort:update_light_states()

  TRACE("update_light_state()")    

  self:set_light_state(0x15,
    self.last_track.mute_state ~= renoise.Track.MUTE_STATE_ACTIVE) --mute
  self:set_light_state(0x16,
    self.last_track.solo_state) -- solo
  self:set_light_state(0x17,
    self.last_record_dialog_is_visible) -- rec

  self:set_light_state(0x13,self.dsp_mode) -- bank
  self:set_light_state(0x11,renoise.app().window.mixer_view_post_fx) -- output

  self:set_light_state(0x0d,self.fader_mode == FADER_MODE_READ) -- read
  self:set_light_state(0x0f,self.fader_mode == FADER_MODE_TOUCH) -- touch
  self:set_light_state(0x0e,self.fader_mode == FADER_MODE_WRITE or -- write
    self.fader_mode == FADER_MODE_LATCH)

  local middle_frame = renoise.app().window.active_middle_frame
  self:set_light_state(0x0c,middle_frame ==
    renoise.ApplicationWindow.MIDDLE_FRAME_MIXER) -- mix
  self:set_light_state(0x0b,middle_frame ==
    renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR) -- proj
  if (prefs.sticky_mode_support.value) then
    self:set_light_state(0x0a,self.sticky_mode) -- trns
  else
    self:set_light_state(0x0a,middle_frame ==
      renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR)
  end

  self:set_light_state(0x06, song().transport.loop_block_enabled) -- punch
  self:set_light_state(0x07,self.fader_pan_swapped) -- user
  self:set_light_state(0x08, song().transport.loop_pattern) -- loop

  self:set_light_state(0x01, song().transport.playing) -- play
  self:set_light_state(0x02, not song().transport.playing) -- stop
  self:set_light_state(0x00, song().transport.edit_mode) -- record
  
  -- for debugging, only
  -- self:all_lights_on() 
  -- self:funky_lights()
end

-- add various notifiers to song. Important: song must be available !
function FaderPort:add_notifiers()

  TRACE("add_notifiers()")

  -- transport
  
  if (not song().transport.playing_observable:has_notifier(
    self,self.on_playing_change)) then
    song().transport.playing_observable:add_notifier(
      self,self.on_playing_change) -- playing state
  end
  self:on_playing_change() -- init

  if (not song().transport.edit_mode_observable:has_notifier(
    self,self.on_edit_mode_change)) then
    song().transport.edit_mode_observable:add_notifier(
      self,self.on_edit_mode_change) -- edit mode / record
  end
  self:on_edit_mode_change() -- init
  
  if (not song().transport.loop_pattern_observable:has_notifier(
    self,self.on_loop_pattern_change)) then
    song().transport.loop_pattern_observable:add_notifier(
      self,self.on_loop_pattern_change) -- loop pattern state
  end
  self:on_loop_pattern_change() -- init

  -- track / channel
  
  if (not song().selected_track_observable:has_notifier(
    self,self.on_selected_track_change)) then
    song().selected_track_observable:add_notifier(
      self,self.on_selected_track_change) -- track/channel changed
  end
  self:on_selected_track_change() -- init

  if (not song().tracks_observable:has_notifier(
    self,self.on_tracks_change)) then
    song().tracks_observable:add_notifier(
      self,self.on_tracks_change) --tracks list changed
  end

  -- device chain
  
  if (not song().selected_track_device_observable:has_notifier(
    self,self.on_selected_device_change)) then
    song().selected_track_device_observable:add_notifier(
      self,self.on_selected_device_change) -- device changed
  end
  self:on_selected_device_change() -- init

  -- application
  
  if (not renoise.app().window.active_middle_frame_observable:has_notifier(
    self,self.on_middle_frame_change)) then
    renoise.app().window.active_middle_frame_observable:add_notifier(
      self,self.on_middle_frame_change) -- middle frame state change
  end
  self:on_middle_frame_change() -- init
  
  if (not renoise.app().window.mixer_view_post_fx_observable:has_notifier(
    self,self.on_mixer_view_post_fx_change)) then
    renoise.app().window.mixer_view_post_fx_observable:add_notifier(
      self,self.on_mixer_view_post_fx_change) -- view post fx state change
  end
  self:on_mixer_view_post_fx_change() -- init

  -- temporary workaround for missing observable support
  -- (will be altered later on)
  -- HINT: though observer is not "song"-specific it's only used
  -- for song-related stuff, so we install it together with
  -- the song specific observers. It's the right place, here.
  if (not renoise.tool().app_idle_observable:has_notifier(
    self,self.on_idle)) then
    renoise.tool().app_idle_observable:add_notifier(
      self,self.on_idle)
  end
  self:on_idle() -- init
  
  -- workaround "emulator dialog invisible bug"
  -- add another idle notifier
  if (not renoise.tool().app_idle_observable:has_notifier(
    self,self.on_idle2)) then    
    renoise.tool().app_idle_observable:add_notifier(
      self,self.on_idle2)
  end  
end

-- workaround "emulator dialog invisible bug"
-- This handler is called the first time after the Renoise
-- application window was loaded. Since the Renoise application
-- overlays our emulator dialog we "re-open" the dialog and
-- reinitialize the state of the dialog controls. 
function FaderPort:on_idle2()
  -- remove handler TODO: is this allowed inside handler ?
  renoise.tool().app_idle_observable:remove_notifier(self,self.on_idle2)  
  if (not self.application_loaded) then  
    
    self.application_loaded = true    
    
    -- update state of dialog controls
    if (emulator:dialog_visible()) then
      emulator:open()
      self:update_light_states()
      
      -- Lazy workaround for updating fader position:
      -- 1. remember currently selected track
      -- 1. select master track
      -- 1. reselect currently selected track
      local track_index = renoise.song().selected_track_index
      self:select_master_track()  
      song().selected_track_index = track_index
    end
  end    
end
  
-- remove all notifiers from the song
function FaderPort:remove_notifiers()
  
  TRACE("remove_notifiers()")

  -- transport
  
  if ( song().transport.playing_observable:has_notifier(
    self,self.on_playing_change)) then
    song().transport.playing_observable:remove_notifier(
      self,self.on_playing_change) -- playing state
  end

  if (song().transport.edit_mode_observable:has_notifier(
    self,self.on_edit_mode_change)) then
    song().transport.edit_mode_observable:remove_notifier(
      self,self.on_edit_mode_change) -- edit mode / record
  end
  
  if (song().transport.loop_pattern_observable:has_notifier(
    self,self.on_loop_pattern_change)) then
    song().transport.loop_pattern_observable:remove_notifier(
      self,self.on_loop_pattern_change) -- loop pattern state
  end
  
  -- track / channel
  
  self:remove_selected_track_notifiers() -- last selected track
  
  if (song().selected_track_observable:has_notifier(
    self,self.on_selected_track_change)) then
    song().selected_track_observable:remove_notifier(
      self,self.on_selected_track_change) -- track/channel changed
  end
  
  if (song().tracks_observable:has_notifier(
    self,self.on_tracks_change)) then
    song().tracks_observable:remove_notifier(
      self,self.on_tracks_change) --tracks list changed
  end

  -- device parameter 
  
  if (self.fader_devpara) then
    if (self.fader_devpara.value_observable:has_notifier(
      self,self.on_fader_devpara_value_change)) then
        self.fader_devpara.value_observable:remove_notifier(
          self,self.on_fader_devpara_value_change) -- fader device parameter
    end
  end
  
  if (self.pan_devpara) then
    if (self.pan_devpara.value_observable:has_notifier(
      self,self.on_pan_devpara_value_change)) then
        self.pan_devpara.value_observable:remove_notifier(
          self,self.on_pan_devpara_value_change) -- pan device parameter
    end
  end
  
   -- device chain
  
  if (song().selected_track_device_observable:has_notifier(
    self,self.on_selected_device_change)) then
    song().selected_track_device_observable:remove_notifier(
      self,self.on_selected_device_change) -- device changed
  end

  -- application
  
  if (renoise.app().window.active_middle_frame_observable:has_notifier(
    self,self.on_middle_frame_change)) then
    renoise.app().window.active_middle_frame_observable:remove_notifier(
      self,self.on_middle_frame_change) -- middle frame state change
  end
  
  if (renoise.app().window.mixer_view_post_fx_observable:has_notifier(
    self,self.on_mixer_view_post_fx_change)) then
    renoise.app().window.mixer_view_post_fx_observable:remove_notifier(
      self,self.on_mixer_view_post_fx_change) -- view post fx state change
  end

  -- temporary workaround for missing observable support
  -- (will be altered later on)
  if (renoise.tool().app_idle_observable:has_notifier(
    self,self.on_idle)) then
    renoise.tool().app_idle_observable:remove_notifier(
      self,self.on_idle)
  end
end  

-- tracks[] list change handler. Computes self.last_track_index in sticky mode
-- A valid index is needed if sticky mode is active and the track is deleted.
-- If the track is deleted, sticky mode is switched off automatically.
-- it's a PITA to do, but I didn't find an appropriate API function
function FaderPort:on_tracks_change(notification)

  TRACE("on_tracks_change()")

  assert(self.last_track_index ~= nil, "self.last_track_index is nil")

  local type = notification.type
  local index = notification.index
  local index1 = notification.index1
  local index2 = notification.index2
  
  -- pure debug code
  --[[ print("TYPE:",type)
  print("INDEX:",index)
  print("INDEX1:",index1)
  print("INDEX2:",index2)
  print("LAST:",self.last_track_index) 
  --]]

  if (type == "insert") then
    if (index <= self.last_track_index) then
      self.last_track_index = self.last_track_index + 1
    end

  elseif (type == "swap") then
    local index1 = notification.index1
    local index2 = notification.index2
    if (index1 == self.last_track_index) then
      self.last_track_index = index2      
    elseif (index2 == self.last_track_index) then
      self.last_track_index = index1
    end

  elseif (type == "remove") then
    if (index < self.last_track_index) then
      self.last_track_index = self.last_track_index - 1
    elseif (index == self.last_track_index) then

      if (self.sticky_mode) then
     
        -- track 'n device is no more
        self.last_track = nil -- last selected track is no more
        self.last_track_index = nil -- last selected track index is no more 
        self.last_device = nil -- last selected device is no more (no track no device !)
        self.last_device_index = nil -- last selected device index is no more (no track no device !)
        
        self:toggle_sticky_mode() -- switch off sticky mode, update states       
      end
    end
  end
  
  -- pure debug code
  -- print("LAST NEW:",self.last_track_index)
end

-- devices[] list change handler. Computes self.last_device_index in sticky mode
-- A valid index is needed if sticky mode is active and the track is deleted
-- If the device is deleted or moved to another track, sticky mode is switched off
-- automatically. It's a PITA to do, but I didn't find an appropriate API function
function FaderPort:on_devices_change(notification)

  TRACE("on_devices_change()")
  
  if (not self.last_device_index) then
    return -- that's the case if device mode wasn't selected at least one time
  end

  local type = notification.type
  local index = notification.index

  if (type == "insert") then
    if (index <= self.last_device_index) then
      self.last_device_index = self.last_device_index + 1
    end

  elseif (type == "swap") then
    local index1 = notification.index1
    local index2 = notification.index2
    if (index1 == self.last_device_index) then
      self.last_device_index = index2
    elseif (index2 == self.last_device_index) then
      self.last_device_index = index1
    end      

  elseif (type == "remove") then
    if (index < self.last_device_index) then
      self.last_device_index = self.last_device_index - 1
    elseif (index == self.last_device_index) then

      self.last_device = nil -- last selected device is no more
      self.last_device_index = nil -- last selected device index is no more
      
      if (self.sticky_mode) then        
        self:toggle_sticky_mode() -- switch off sticky mode, update states
      end
    end
  end
end

-- remove all notifiers from last selected track
function FaderPort:remove_selected_track_notifiers()
    
  if (self.last_track) then

    -- mute state 
    if (self.last_track.mute_state_observable:has_notifier(
      self,self.on_mute_state_change)) then
      self.last_track.mute_state_observable:remove_notifier(
        self,self.on_mute_state_change)
    end

    -- solo state
    if (self.last_track.solo_state_observable:has_notifier(
      self,self.on_solo_state_change)) then
      self.last_track.solo_state_observable:remove_notifier(
        self,self.on_solo_state_change)
    end

     -- devices list changed
    if (self.last_track.devices_observable:has_notifier(
      self,self.on_devices_change)) then
      self.last_track.devices_observable:remove_notifier(
        self,self.on_devices_change)
    end
  end
end

-- selected track change handler
function FaderPort:on_selected_track_change()

  TRACE("on_selected_track_change()")
  
  if (self.last_track) then

    -- ignore currently selected track in sticky mode
    if (self.sticky_mode) then
      return
    end

    -- remove all notifiers from last selected track
    self:remove_selected_track_notifiers()  
  end

  -- add notifiers to currently selected track

  self.last_track = song().selected_track
  self.last_track_index = song().selected_track_index

  -- mute
  self.last_track.mute_state_observable:add_notifier(
    self,self.on_mute_state_change)
  self:on_mute_state_change() -- init

  -- solo 
  self.last_track.solo_state_observable:add_notifier(
    self,self.on_solo_state_change)
  self:on_solo_state_change() -- init

  -- devices list changed
  self.last_track.devices_observable:add_notifier(
    self,self.on_devices_change)

  -- force device parameter type change in order
  -- to rebind either prefx_volume, postfx_volume or 
  -- dsp device parameter of currently selected 
  -- track to fader/pan
  self:on_device_type_change()
end

-- device type change handler
-- for device type see DEVICE enum of this class
function FaderPort:on_device_type_change()

  TRACE("on_device_type_change()")

  local fader_devpara = nil
  local pan_devpara = nil

  -- bind new device parameter to fader and pan control
  if (self.device_type == DEVICE_PRE_MIXER) then
    fader_devpara = self.last_track.prefx_volume
    pan_devpara = self.last_track.prefx_panning

  elseif (self.device_type == DEVICE_POST_MIXER) then
    fader_devpara = self.last_track.postfx_volume
    pan_devpara = self.last_track.postfx_panning

  elseif (self.device_type == DEVICE_DSP) then
    if (not self.sticky_mode) then
      self:on_selected_device_change() -- force update
    else -- rebind in sticky mode
      if (self.dsp_binding_sel_index ~= nil) then
        self:select_dsp_binding(self.dsp_binding_sel_index)
      end
    end
    return
  end

  -- bind device parameter to fader and pan control
  -- optionally swap fader and pan control
  self:bind_devparas_to_fader_pan(fader_devpara,pan_devpara,self.fader_pan_swapped)  
end

-- select next dsp binding for fader/pan
function FaderPort:select_next_dsp_binding()

  TRACE("select_next_dsp_binding()")

  -- check if there are bindings at all
  if (self.dsp_binding_sel_index == nil) then
    return
  end

  -- check if only one dsp binding pair available
  if (self.dsp_binding_start_index == self.dsp_binding_end_index) then
    return
  end

  local dsp_index = self.dsp_binding_sel_index
  if (dsp_index == self.dsp_binding_end_index) then
    dsp_index = self.dsp_binding_start_index
  else
    dsp_index = dsp_index + 2
  end
  self:select_dsp_binding(dsp_index)
end

-- select previous dsp binding for fader/pan
function FaderPort:select_prev_dsp_binding()

  TRACE("select_prev_dsp_binding()")

  -- check if there are bindings at all
  if (self.dsp_binding_sel_index == nil) then
    return
  end

  -- check if only one dsp binding pair available
  if (self.dsp_binding_start_index == self.dsp_binding_end_index) then
    return
  end

  local dsp_index = self.dsp_binding_sel_index
  if (self.dsp_binding_sel_index == self.dsp_binding_start_index) then
    dsp_index = self.dsp_binding_end_index
  else
    dsp_index = dsp_index - 2
  end
  self:select_dsp_binding(dsp_index)
end

-- bind new device parameters to fader/pan according to dsp binding list
function FaderPort:select_dsp_binding(dsp_index)

  TRACE("select_dsp_binding()")

  local fader_devpara = nil
  local pan_devpara = nil
  local fader_index = tonumber(prefs.dsp_binding_list[dsp_index].value)
  local pan_index = tonumber(prefs.dsp_binding_list[dsp_index+1].value)

  -- TODO: more user feedback ?
  assert(fader_index ~= nil, "fader index is no number ("..self.last_device.name..")")
  assert(pan_index ~= nil, "pan index is no number ("..self.last_device.name..")")
  assert(fader_index > -1, "index out of bounds ("..self.last_device.name..")")
  assert(pan_index > -1, "index out of bounds ("..self.last_device.name..")")
  assert(fader_index <= #self.last_device.parameters, 
    "index out of bounds ("..self.last_device.name..")")
  assert(pan_index <= #self.last_device.parameters, 
    "index out of bounds ("..self.last_device.name..")")

  self.dsp_binding_sel_index = dsp_index

  if (fader_index > 0) then
    -- hint: if range is invalid, then nothing is bound to fader
    fader_devpara = self.last_device.parameters[fader_index]
  end
  if (pan_index > 0) then
    -- hint: if range is invalid, then nothing is bound to pan control
    pan_devpara = self.last_device.parameters[pan_index]
  end

  -- bind device parameters to fader and pan
  -- optionally swap fader and pan control
  self:bind_devparas_to_fader_pan(fader_devpara,pan_devpara,self.fader_pan_swapped)
end

-- selected dsp device change handler
-- if dsp bindings for the device are defined
-- new device parameters are bound to fader/pan.
-- Otherwise nothing is bound to fader / pan
function FaderPort:on_selected_device_change()

  TRACE("on_selected_device_change()")

  if (self.device_info_dialog and self.device_info_dialog.visible) then
    self:update_device_info_view()
  end

  if (self.device_type == DEVICE_DSP) then

    -- ignore currently selected device in sticky mode
    if (self.sticky_mode and self.last_device ~= nil) then
      return
    end

    self.last_device = song().selected_track_device
    self.last_device_index = song().selected_track_device_index

    -- bind new device parameters to fader/pan
    if (self.last_device) then

      local dsp_index =
        tonumber(prefs.dsp_binding_list:find(1,self.last_device.name))

      -- dsp binding entry found for the device
      if (dsp_index) then

        -- are there any dsp bindings defined ?
        if (tonumber(prefs.dsp_binding_list[dsp_index+1].value) > -1) then

          self.dsp_binding_start_index = dsp_index+1
          self:select_dsp_binding(dsp_index+1)

          -- find last index and validate binding list
          local index = nil
          local size = 0
          for i = dsp_index+1,#prefs.dsp_binding_list do
            index = tonumber(prefs.dsp_binding_list[i].value)
            assert(index ~= nil, 
              "index is no number ("..self.last_device.name..")") -- e.g. forgotten -1
            if (index == -1) then
              break
            end
            i = i + 1
            size = size + 1
          end
          assert(index == -1, 
            "-1 missing in dsp binding list ("..self.last_device.name..")")
          assert(size % 2 == 0, 
            "odd number of dsp bindings ("..self.last_device.name..")")
          self.dsp_binding_end_index = dsp_index + 1 + size - 2

        else -- no dsp binding definitions: clear bindings
          self:clear_bindings()
        end
      else -- no dsp binding entry: clear bindings
        self:clear_bindings()
      end
    else -- no device selected: clear bindings
      self:clear_bindings()
    end
  end
end

-- clear dsp binding variables and
-- unbind device parameters currently bound to fader/pan
function FaderPort:clear_bindings()

    TRACE("clear_bindings()")

    -- reset binding variables
    self.dsp_binding_start_index = nil
    self.dsp_binding_end_index = nil
    self.dsp_binding_sel_index = nil

    -- remove bound device parameters
    self:unbind_devpara_from_fader()
    self:unbind_devpara_from_pan()
end

-- bind device parameters to fader and pan (maybe nil)
-- swap true: parameters are swapped before being bound
function FaderPort:bind_devparas_to_fader_pan(fader_devpara,pan_devpara,swap)

  TRACE("bind_devparas_to_fader_pan()")

  if (swap) then
    local help = fader_devpara
    fader_devpara = pan_devpara
    pan_devpara = help    
  end
  
  -- first, unbind everything
  local fader_touched = self.fader_touched -- store current state 
  self:unbind_devpara_from_fader()
  self:unbind_devpara_from_pan()
  
  self.fader_touched = fader_touched -- restore state  
  self:bind_devpara_to_fader(fader_devpara)
  self:bind_devpara_to_pan(pan_devpara)
   
  -- update Renoise status bar
  self:status_bar_display_binding()
end

-- unbind currently bound device parameter from fader
function FaderPort:unbind_devpara_from_fader()

  TRACE("unbind_devpara_from_fader()")

  -- if fader is currently touched, send a faked "fader release" message 
  if (self.fader_touched) then
    self:midi_callback({0xa0,0x7f,0}) 
  end
  
  -- if trim is being moved (implicitly the same as being touched)
  -- send a faked "trim release" message 
  if (self.trim_moved) then
    self:midi_callback({0xa0,0x7d,0})
  end

  -- remove all notifiers from last device parameter bound to fader
  if (self.fader_devpara) then
    if (self.fader_devpara.value_observable:has_notifier(
      self,self.on_fader_devpara_value_change)) then
      self.fader_devpara.value_observable:remove_notifier(
        self,self.on_fader_devpara_value_change)
    end
  end
   
  self.fader_devpara = nil

  -- re-initialize states fader
  self.last_msb = nil 
  self.fader_value = nil 
  self:toggle_fader_mode(FADER_MODE_OFF)
  self.latch_write = false 
  self.fader_moved = false
  self.fader_undo_count = 0
    
  -- re-initialize states trim 
  self.last_trim_time = nil 
  self.last_trim_value_received_time = nil 
  self.trim_left_count = 0 
  self.trim_right_count = 0 
  self.trim_moved = false
  self.trim_undo_count = 0
end

-- bind a device parameter to fader 
-- device paramter maybe nil
function FaderPort:bind_devpara_to_fader(devpara)
  
  TRACE("bind_devpara_to_fader()")
  
  assert(self.fader_devpara == nil, 
    "device parameter already bound to fader")
  
  self.fader_devpara = devpara
  if (not self.fader_devpara) then
    return
  end
  
  -- observe fader device parameter value
  self.fader_devpara.value_observable:add_notifier(
    self,self.on_fader_devpara_value_change)
  
  -- if fader is currently touched send a faked "fader touched" message
  if (self.fader_touched) then
     self:midi_callback({0xa0,0x7f,1}) 
  end    
    
  self:on_fader_devpara_value_change() -- init
end

-- unbind currently bound device parameter from pan control
function FaderPort:unbind_devpara_from_pan()

  TRACE("unbind_devpara_from_pan()")

  -- if pan is being moved (implicitly the same as being touched)
  -- send a faked "pan release" message 
  if (self.pan_moved) then
    self:midi_callback({0xa0,0x7d,0}) 
  end

  -- remove all notifiers from last device parameter bound to pan control
  if (self.pan_devpara) then
    if (self.pan_devpara.value_observable:has_notifier(
      self,self.on_pan_devpara_value_change)) then
      self.pan_devpara.value_observable:remove_notifier(
        self,self.on_pan_devpara_value_change)
    end
  end

  self.pan_devpara = nil
  
  -- re-initialize states for pan
  self.last_pan_time = nil 
  self.last_pan_value_received_time = nil 
  self.pan_left_count = 0 
  self.pan_right_count = 0 
  self.virtual_pan_value = 0 
  self.pan_moved = false 
  self.pan_undo_count = 0 
end

-- bind a device parameter to pan control
function FaderPort:bind_devpara_to_pan(devpara)

  TRACE("bind_devpara_to_pan()")

  assert(self.pan_devpara == nil, 
    "device parameter already bound to pan control")

  self.pan_devpara = devpara
  if (not self.pan_devpara) then
    return
  end

  self.virtual_pan_resolution =
    prefs.virtual_pan_resolution.value

  -- for e.g. Renoise "send device" receiver parameter
  local range = devpara.value_max - devpara.value_min
  if (devpara.value_quantum > 0) then
    self.virtual_pan_resolution = range + devpara.value_quantum
  end

  -- observe pan control device parameter value
  self.pan_devpara.value_observable:add_notifier(
    self,self.on_pan_devpara_value_change)
  self:on_pan_devpara_value_change() -- init
end

-- selected automation envelope changed
function FaderPort:on_selected_parameter_change()

  TRACE("on_selected_parameter_change()")
  -- TODO: not supported, yet
end

-- reset value of device parameter bound to fader to default value
function FaderPort:on_reset_fader_devpara_to_default()

  TRACE("on_reset_fader_devpara_to_default()")

  if (self.fader_devpara) then
    if (not self.fader_devpara.is_automated) then
      self.fader_devpara.value = self.fader_devpara.value_default
      
      self:status_bar_display_fader_value()
    end
  end
end

-- device parameter value change handler
-- for device parameter which was last bound to fader
function FaderPort:on_fader_devpara_value_change()

  TRACE("on_fader_devpara_value_change()")

  -- check if a device parameter is bound to fader
  if (not self.fader_devpara) then
    return
  end

  -- if fader is currently touched, we don't send updates to FaderPort
  if (self.fader_touched) then
    return
  end

  -- check fader mode - some modes don't need updates
  if (self.fader_devpara.is_automated and
      self.device_type ~= DEVICE_POST_MIXER) then
    if (self.fader_mode == FADER_MODE_OFF or
        self.fader_mode == FADER_MODE_WRITE or
       (self.fader_mode == FADER_MODE_LATCH and self.latch_write)) then
      return
    end
  end

  local value = self.fader_devpara.value
  local value_min = self.fader_devpara.value_min
  local value_max = self.fader_devpara.value_max

  -- if value exceeds range clamp to min/max
  -- that may be the case if device parameter is in a none, n/a state (hydra)
  value = clamp_value(value,value_min,value_max)

  local range = value_max - value_min
  local intval = math.floor((((value-value_min) * 1023) / range)+0.5) 

  self.fader_value = intval -- TODO: necessary ?

  -- TODO: add some smoothing to prevent hard fader movement, here ?
  local msb = bit.rshift(intval,7) -- high 7 bits
  local lsb = bit.band(intval,127) -- low 7 bits
  self:midi_send({0xb0,0x00,msb}) -- bank select MSB
  self:midi_send({0xb0,0x20,lsb}) -- bank select LSB
end

-- handler for received FaderPort fader values
function FaderPort:on_receive_fader_value(intvalue)

  TRACE("on_receive_fader_value()")

  -- store new fader value as current fader value
  self.fader_value = intvalue

  -- check if a device parameter is bound to fader
  if (not self.fader_devpara) then
    return
  end

  -- already automated (either per envelope or per pattern fx)
  if (self.fader_devpara.is_automated) then

    if (self.fader_mode == FADER_MODE_READ or
        self.fader_mode == FADER_MODE_OFF) then
      return

    elseif (self.fader_mode == FADER_MODE_WRITE and
        not song().transport.playing) then
      return
    end

    -- add point to existing or newly created envelope
    self:add_automation_point(intvalue)

  else  -- not automated

    if ((((self.fader_mode == FADER_MODE_TOUCH or
          self.fader_mode == FADER_MODE_LATCH) and self.fader_touched) or
          (self.fader_mode == FADER_MODE_WRITE and song().transport.playing)) and
          self.device_type ~= DEVICE_POST_MIXER) then

       -- add point to newly created envelope
       -- TODO a bit untidy since find_automation is called and
       -- that makes actually no sense
       self:add_automation_point(intvalue)
    else

      -- map fader value directly to device parameter value
      local value_min = self.fader_devpara.value_min
      local value_max = self.fader_devpara.value_max
      local range = value_max - value_min
      local value = value_min + (intvalue * range) / 1023.0

      -- round to exact center value (snap to center)
      if (self.fader_devpara.polarity == renoise.DeviceParameter.POLARITY_BIPOLAR) then
        local mid_value =  (value_max - value_min) / 2 + value_min
        if (value ~= mid_value and -- 1024 to avoid rounding fuzz
            math.abs(mid_value - value) < range / 1024.0) then
          value = mid_value
        end
      end

      -- quantize / round if necessary
      -- TODO: vs. global midi
      local quantum = self.fader_devpara.value_quantum
      if (quantum > 0) then
        value = quantize_value(value, quantum)
      end     
      
      if (self.fader_devpara.value ~= value) then
    
        -- undo last value change if fader is "on the move"
        -- TODO: this is actually a dirty workaround for the
        -- missing proper Renoise undo/redo support for realtime data.
        -- It's dirty because actions that happen in parallel are undone, too !!
        -- BUT: at least it makes the FaderPort useable as long as there is no further support.
        if (prefs.undo_workaround.value and not self.sticky_mode) then 
          if (self.fader_undo_count > 0) then         
            for c = 1,self.fader_undo_count do
              TRACE("FADER UNDO")
              song():undo()
            end 
            self.fader_undo_count = 0
          end
        end
      
        -- hint about storing last value here:
        -- Renoise seems to internally round the values to three decimal places or so before setting the value
        -- This means: sometimes the value isn't set, if the difference is too small. In this case no undo point
        -- is created. So we store the old value here and compare the later new value with the old value.
        -- If they're different then an undo point has been created.
        local last_value = nil 
        if (self.fader_devpara) then
        
          last_value = self.fader_devpara.value
          self.fader_devpara.value = value 
          
          self:status_bar_display_fader_value()         
        else
          -- this can be the case in certain "undo workaround" situations:
          -- The device can be removed by the undo() call.
          -- This is the ugliness of the "ugly undo workaround" :/.
          -- But at least no data is lost: you can redo() all actions.
          return
        end
      
        -- ugly undo workaround
        -- set moved flag after first value was received
        if (prefs.undo_workaround.value and not self.sticky_mode) then
          
          if (self.fader_devpara.value ~= last_value) then
            self.fader_undo_count = 1
            if (not self.fader_moved) then
              TRACE("FADER MOVED")
              self.fader_moved = true
            end
          end
        end            
      end
    end
  end
end

-- add automation envelope point for device parameter bound to fader
-- write into an existing or newly created automation envelope
function FaderPort:add_automation_point(intvalue)

  TRACE("add_automation_point()")

  -- TODO: finding automation everytime is slow ?
  local pattern_index = song().selected_pattern_index
  local pattern_track = song().patterns[pattern_index].tracks[self.last_track_index]
  local automation =
    pattern_track:find_automation(self.fader_devpara)
    
  if (not automation) then
    automation =
      pattern_track:create_automation(self.fader_devpara)
  end

  assert(automation,"automation envelope could not have been created")

  local value = intvalue / 1023 -- envelope values are always 0.0 - 1.0

  local time = song().transport.edit_pos.line
  automation:add_point_at(time, value)
end

-- display fader value in status bar
function FaderPort:status_bar_display_fader_value()

  local message = ""
  if (self.last_track) then
    message = message..self.last_track.name
  end
  
  if (self.last_device) then
    message = message.."  "..self.last_device.name
  end
  
  if (self.fader_devpara) then
    message = message.."   ^"..self.fader_devpara.name
                .." -> "..self.fader_devpara.value_string 
  else
    message = message.."n/a"
  end
          
  renoise.app():show_status(message)
end

-- display pan value in status bar
function FaderPort:status_bar_display_pan_value()

  local message = ""
  if (self.last_track) then
    message = message..self.last_track.name
  end
  
  if (self.last_device) then
    message = message.."  "..self.last_device.name
  end
  
  if (self.pan_devpara) then
    message = message.."   >"..self.pan_devpara.name
                .." -> "..self.pan_devpara.value_string 
  else
    message = message.."n/a"
  end
          
  renoise.app():show_status(message)
end

-- display current fader/pan binding in status bar 
function FaderPort:status_bar_display_binding()

  local message = ""
  if (self.last_track) then
    message = message..self.last_track.name
  end
  
  if (self.last_device) then
    message = message.."  "..self.last_device.name
  end
  
  if (self.fader_devpara) then
    message = message.."   ^"..self.fader_devpara.name               
  end
    
  if (self.pan_devpara) then
    message = message.."   >"..self.pan_devpara.name                
  end
          
  renoise.app():show_status(message)
end

-- calculate pan control speed based on os.clock time stamp value
-- min speed = 1, max speed = 20
function FaderPort:compute_pan_speed()

  TRACE("compute_pan_speed()")

  local speed = 1

  -- if resolution is low, don't use speed feature at all
  if (self.virtual_pan_resolution <= 20) then -- TODO: ballistics prefs ?
    return speed
  end

  if (self.last_pan_time) then
    local time = os.clock()
    speed = time-self.last_pan_time
    speed = 1 + math.floor(0.20 / speed + 0.5) -- TODO: ballistics prefs ?
  end
  self.last_pan_time = os.clock()
  speed = clamp_value(speed,1, 20) -- TODO: ballistics prefs ?

  return speed
end

-- turn virtual pan control to absolute value
-- returns true if value was changed, false otherwise
function FaderPort:turn_virtual_pan(value)

  TRACE("turn_virtual_pan()")

  local min_turns = prefs.anti_suck_min_turns.value
  local value_min = 0
  local value_max = self.virtual_pan_resolution-1
  local delta = 0

  -- turn right (usually 1..3)
  if (value < 63) then

    if (value ~= 1) then
      return false
    end

    self.pan_right_count = self.pan_right_count + 1
    if (self.pan_right_count < min_turns) then
      return false
    end
    delta = self:compute_pan_speed()

  -- turn left (usually 0x7e..0x7c)
  else
    if (value ~= 0x7e) then
      return false
    end
    self.pan_left_count = self.pan_left_count + 1
    if (self.pan_left_count < min_turns) then
      return false
    end
    delta = -self:compute_pan_speed()
  end

  self.pan_left_count = 0
  self.pan_right_count = 0

  value = self.virtual_pan_value + delta
  value = clamp_value(value, value_min, value_max)
  self.virtual_pan_value = value
  
  return true
end

-- calculate trim control speed based on os.clock time stamp value
-- min speed = 1, max speed = 20
function FaderPort:compute_trim_speed()

  TRACE("compute_trim_speed()")

  local speed = 1

  if (self.last_trim_time ~= nil) then
    local time = os.clock()
    speed = time-self.last_trim_time
    speed = 1 + math.floor(0.20 / speed + 0.5) -- TODO: ballistics prefs?
  end
  self.last_trim_time = os.clock()
  speed = clamp_value(speed,1, 20) -- TODO: ballistics prefs ?

  return speed
end

-- turn virtual trim control to relative value
function FaderPort:turn_virtual_trim(value)

  TRACE("turn_virtual_trim()")

  local min_turns = prefs.anti_suck_min_turns.value
  local delta = 0

  -- turn right (usually 1..3)
  if (value < 63) then

    if (value ~= 1) then
      return delta
    end

    self.trim_right_count = self.trim_right_count + 1
    if (self.trim_right_count < min_turns) then
      return delta
    end
    delta = self:compute_trim_speed()

  -- turn left (usually 0x7e..0x7c)
  else
    if (value ~= 0x7e) then
      return delta
    end
    self.trim_left_count = self.trim_left_count + 1
    if (self.trim_left_count < min_turns) then
      return delta
    end
    delta = -self:compute_trim_speed()
  end

  self.trim_left_count = 0
  self.trim_right_count = 0

  return delta
end

-- handler for received trim control values
-- TODO: if device parameter is automated, trim is not supported right now
function FaderPort:on_receive_trim_value(value)

  TRACE("on_receive_trim_value()")

  if (not self.fader_devpara or self.fader_devpara.is_automated) then
    return
  end

  self.last_trim_value_received_time = os.clock()

  local value_min = self.fader_devpara.value_min
  local value_max = self.fader_devpara.value_max
  local range = value_max - value_min

  local delta = self:turn_virtual_trim(value)
  if (delta ~= 0) then
    value = self.fader_devpara.value + (range * 0.0005) * delta -- TODO ballistics / precision prefs
    value = clamp_value(value, value_min, value_max)
      
    if (self.fader_devpara.value ~= value) then
     
      -- ugly undo workaround
      if (prefs.undo_workaround.value and not self.sticky_mode) then
        if (self.trim_undo_count > 0) then
          for c = 1,self.trim_undo_count do         
            TRACE("TRIM UNDO")     
            song():undo()
          end          
          self.trim_undo_count = 0
        end
      end
      
      -- trim the current fader value
      
      -- hint about storing last value here:
      -- Renoise seems to internally round the values to three decimal places or so before setting the value
      -- This means: sometimes the value isn't set, if the difference is too small. In this case no undo point
      -- is created. So we store the old value here and compare the later new value with the old value.
      -- If they're different then an undo point has been created.      
      local last_value = nil
      if (self.fader_devpara) then
        last_value = self.fader_devpara.value
        self.fader_devpara.value = value
      
        self:status_bar_display_fader_value()
      else
        -- this can be the case in certain "undo workaround" situations:
        -- The device can be removed by the undo() call.
        -- This is the ugliness of the "ugly undo workaround" :/.
        -- But at least no data is lost: you can redo() all actions.
        return
      end
        
      -- ugly undo workaround
      if (prefs.undo_workaround.value and not self.sticky_mode) then                   
        if (self.fader_devpara.value ~= last_value) then
          if (not self.trim_moved) then        
            TRACE("TRIM MOVED")       
            self.trim_moved = true
          end
          self.trim_undo_count = 1
        end
      end   
    end
  end
end

-- handler for received FaderPort pan control values
function FaderPort:on_receive_pan_value(value)

  TRACE("on_receive_pan_value()")

  -- check if a device parameter is bound to pan control
  if (not self.pan_devpara or self.pan_devpara.is_automated) then
    return
  end
  
  self.last_pan_value_received_time = os.clock()

  if (self:turn_virtual_pan(value)) then
  
    local value = self.virtual_pan_value
    local value_min = self.pan_devpara.value_min
    local value_max = self.pan_devpara.value_max
    local range = value_max - value_min
    local pan_max_value = self.virtual_pan_resolution-1

    value = (value * range) / pan_max_value + value_min

    -- round to exact center value (snap to center)
    if (self.pan_devpara.polarity == renoise.DeviceParameter.POLARITY_BIPOLAR) then
      local mid_value =  (value_max - value_min) / 2 + value_min
      if (value ~= mid_value and -- pan_max_value+1 to avoid rounding fuzz
          math.abs(mid_value - value) < range / (pan_max_value+1)) then
        value = mid_value
      end
    end

    -- quantize / round if necessary
    -- TODO: vs. global midi
    local quantum = self.pan_devpara.value_quantum
    if (quantum > 0) then
      value = quantize_value(value, quantum)
    end

    if (self.pan_devpara.value ~= value) then
    
      -- ugly undo workaround
      if (prefs.undo_workaround.value and not self.sticky_mode) then          
        if (self.pan_undo_count > 0) then        
          for c = 1,self.pan_undo_count do
            TRACE("PAN UNDO")
            song():undo()
          end  
          self.pan_undo_count = 0
        end        
      end
      
      -- hint about storing last value here:
      -- Renoise seems to internally round the values to three decimal places or so before setting the value
      -- This means: sometimes the value isn't set, if the difference is too small. In this case no undo point
      -- is created. So we store the old value here and compare the later new value with the old value.
      -- If they're different then an undo point has been created.
      local last_value = nil
      if (self.pan_devpara) then
      
        last_value = self.pan_devpara.value
        self.pan_devpara.value = value
        
        self:status_bar_display_pan_value()
      else
        -- this can be the case in certain "undo workaround" situations:
        -- The device can be removed by the undo() call.
        -- This is the ugliness of the "ugly undo workaround" :/.
        -- But at least no data is lost: you can redo() all actions.
        return 
      end
  
      -- ugly undo workaround
      -- set moved flag after first value was received
      if (prefs.undo_workaround.value and not self.sticky_mode) then
        if (self.pan_devpara.value ~= last_value) then
          if (not self.pan_moved) then           
            TRACE("PAN MOVED")
            self.pan_moved = true                  
          end        
          self.pan_undo_count = 1
        end
      end   
    end
  end     
end

-- device parameter value change handler
-- for device parameter which was last bound to fader
function FaderPort:on_pan_devpara_value_change()

  TRACE("on_pan_devpara_value_change()")

  -- check if a device parameter is bound to pan control
  if (not self.pan_devpara) then
    return
  end

  local value = self.pan_devpara.value
  local value_min = self.pan_devpara.value_min
  local value_max = self.pan_devpara.value_max

  -- if value exceeds range clamp to min/max
  -- that may be the case if device parameter is in a none, n/a state (hydra)
  value = clamp_value(value,value_min,value_max)

  local range = value_max - value_min
  local pan_max_value = self.virtual_pan_resolution-1
  local intval = math.floor((((value-value_min) * pan_max_value) / range)+0.5)

  self.virtual_pan_value = intval
end

-- mute state change handler
function FaderPort:on_mute_state_change()

  TRACE("on_mute_state_change()")

  local mute_state = self.last_track.mute_state
  if (mute_state ~= renoise.Track.MUTE_STATE_ACTIVE) then
    self:midi_send({0xa0,0x15,1}) -- mute light on
  else
    self:midi_send({0xa0,0x15,0}) -- mute light off
  end
end

-- solo state change handler
function FaderPort:on_solo_state_change()

  TRACE("on_solo_state_change()")

  local solo_state = self.last_track.solo_state
  if (solo_state) then
    self:midi_send({0xa0,0x16,1}) -- solo light on
  else
    self:midi_send({0xa0,0x16,0}) -- solo light off
  end
end

-- playing state change handler
function FaderPort:on_playing_change()

  TRACE("on_playing_change()")

  local playing = song().transport.playing

  -- latch mode handling
  if (playing) then

    -- if latch mode and fader already touched, start writing immediatley.
    if(self.fader_mode == FADER_MODE_LATCH) then
      self.latch_write = self.fader_touched
    end

    -- force update to be in sync with Renoise
    -- during stop fader could've been moved
    -- and the device parameter value wasn't changed
    self:on_fader_devpara_value_change()

  else
    -- if stopped always clear latch write flag
    self.latch_write = false
  end

  if (playing) then
    self:midi_send({0xa0,0x01,1}) -- Play light on
    self:midi_send({0xa0,0x02,0}) -- Stop light off
  else
    self:midi_send({0xa0,0x01,0}) -- Play light off
    self:midi_send({0xa0,0x02,1}) -- Stop light on
  end
end

-- edit/record mode state change handler
function FaderPort:on_edit_mode_change()

  TRACE("on_edit_mode_change()")

  local edit_mode = song().transport.edit_mode
  if (edit_mode) then
    self:midi_send({0xa0,0x00,1}) -- Record/Edit light on
  else
    self:midi_send({0xa0,0x00,0}) -- Record/Edit light off
  end
end

-- loop pattern state change handler
function FaderPort:on_loop_pattern_change()

  TRACE("on_loop_pattern_change()")

  local loop_pattern = song().transport.loop_pattern
  if (loop_pattern) then
    self:midi_send({0xa0,0x08,1}) -- loop light on
  else
    self:midi_send({0xa0,0x08,0}) -- loop light off
  end  
end

-- middle frame state change handler
function FaderPort:on_middle_frame_change()

  TRACE("on_middle_frame_change()")

  local frametype = renoise.app().window.active_middle_frame

  if (frametype == renoise.ApplicationWindow.MIDDLE_FRAME_MIXER)
  then
    self:midi_send({0xa0,0x0c,1}) -- Mix light on
  else
    self:midi_send({0xa0,0x0c,0}) -- Mix light off
  end

  if (frametype == renoise.ApplicationWindow.MIDDLE_FRAME_PATTERN_EDITOR)
  then
    self:midi_send({0xa0,0x0b,1}) -- Proj light on
  else
    self:midi_send({0xa0,0x0b,0}) -- Proj light off
  end

  if (not prefs.sticky_mode_support.value) then
    if (frametype == renoise.ApplicationWindow.MIDDLE_FRAME_INSTRUMENT_SAMPLE_EDITOR)
    then
      self:midi_send({0xa0,0x0a,1}) -- Trns light on
    else
      self:midi_send({0xa0,0x0a,0}) -- Trns light off
    end
  end
end

-- view post fx state change handler
function FaderPort:on_mixer_view_post_fx_change()

  TRACE("on_mixer_view_post_fx_change()")
  
  if (renoise.app().window.mixer_view_post_fx) then
    self:set_light_state(0x11,true)
    self.device_type = DEVICE_POST_MIXER
    self:on_device_type_change()
  else
    self:set_light_state(0x11, false)
    if (self.dsp_mode) then
      self.device_type = DEVICE_DSP
    else
      self.device_type = DEVICE_PRE_MIXER
    end
    self:on_device_type_change()
  end
 
end

-- select master track
function FaderPort:select_master_track()

  TRACE("select_master_track()")

  local tracks = song().tracks
  for t = 1,#tracks do
    if (tracks[t].type == renoise.Track.TRACK_TYPE_MASTER) then
      song().selected_track_index = t
    end
  end
end

-- idle handler. We're called whenever the workload is low
-- average: 10 times per second:
-- TODO: high load and fader writes: Renoise restriction
function FaderPort:on_idle()
  
  if (self.shift_pressed) then
    TRACE("on_idle()")
  end

  -- TODO: later on: don't forget that a lot of functions need self.fader_touched !
  -- fader control fake release detection
  -- this is important if the additional power supply ist not
  -- connected to FaderPort: in this case no fader touch state is 
  -- transmitted from FaderPort, so we have to fake it
  --[[
  if (self.fader_moved and self.last_fader_value_received_time) then  
    if (os.clock() - self.last_fader_value_received_time > 0.5) then -- TODO: ballistics prefs
      self.last_fader_value_received_time = nil
      self:midi_callback({0xa0,0x7f,0}) -- send fader released faked midi event      
    end
  end--]]

  -- pan control fake release detection
  if (self.pan_moved and self.last_pan_value_received_time) then  
    if (os.clock() - self.last_pan_value_received_time > 0.5) then -- TODO: ballistics prefs
      self.last_pan_value_received_time = nil
      self:midi_callback({0xa0,0x7d,0}) -- send pan released faked midi event      
    end
  end
  
  -- trim control fake release detection
  if (self.trim_moved and self.last_trim_value_received_time) then  
    if (os.clock() - self.last_trim_value_received_time > 0.5) then -- TODO: ballistics prefs
      self.last_trim_value_received_time = nil
      self:midi_callback({0xa0,0x7c,0}) -- send trim released faked midi event      
    end
  end

  -- update last edit_pos line (no observable support, so far)
  local old_edit_pos_line = self.last_edit_pos_line
  self.last_edit_pos_line = song().transport.edit_pos.line

  -- fader write
  -- TODO: problem with high speed/LPB settings, high load and omitted positions: Renoise restriction !
  -- actually we need an observable editor position
  -- TODO: bouncing fader problem: Renoise restriction ?
  if (song().transport.playing) then
    if (self.fader_mode == FADER_MODE_WRITE or
       (self.fader_mode == FADER_MODE_TOUCH and self.fader_touched) or
       (self.fader_mode == FADER_MODE_LATCH and self.latch_write)) then
      self:on_receive_fader_value(self.fader_value)
    end
  else -- step mode handling

    if (self.last_edit_pos_line ~= old_edit_pos_line) then
      if (self.fader_devpara and self.fader_devpara.is_automated and
          ((self.fader_mode == FADER_MODE_TOUCH or
          self.fader_mode == FADER_MODE_LATCH) and self.fader_touched)) then
        self:on_receive_fader_value(self.fader_value)
      end
    end
  end

  -- midi updates

  -- loop block state
  local loop_block_enabled = song().transport.loop_block_enabled
  if (self.last_loop_block_enabled ~= loop_block_enabled) then
    self.last_loop_block_enabled = loop_block_enabled
    if (self.last_loop_block_enabled) then
      self:midi_send({0xa0,0x06,1}) -- punch light on
    else
      self:midi_send({0xa0,0x06,0}) -- punch light off
    end
  end

  -- rec / record dialog visible
  local record_dialog_is_visible =
    renoise.app().window.sample_record_dialog_is_visible
  if (self.last_record_dialog_is_visible ~= record_dialog_is_visible) then
    self.last_record_dialog_is_visible = record_dialog_is_visible
    if (self.last_record_dialog_is_visible) then
      self:midi_send({0xa0,0x17,1}) -- rec light on
    else
      self:midi_send({0xa0,0x17,0}) -- rec light off
    end
  end
end

-- moves delta steps forward/backward in sequencer editor. works in playing and non-playing mode
-- If possible the current edit line number remains the same (shorter pattern !)
-- delta may be positive or negative
function FaderPort:transport_delta(delta)

  TRACE("transport_delta()")

  local new_edit_pos = song().transport.edit_pos

  -- clamp sequence number
  new_edit_pos.sequence =
    clamp_value(new_edit_pos.sequence + delta,1, song().transport.song_length.sequence)

  -- clamp pattern index
  local pattern_index = renoise.song().sequencer.pattern_sequence[new_edit_pos.sequence]
  local max_lines = song().patterns[pattern_index].number_of_lines
  new_edit_pos.line = clamp_value(new_edit_pos.line,1, max_lines)

  song().transport.edit_pos = new_edit_pos
end

-- switch sticky mode on/off
function FaderPort:toggle_sticky_mode()

  TRACE("toggle_sticky_mode()")

  self.sticky_mode = not self.sticky_mode
  self:set_light_state(0x0a,self.sticky_mode)

  -- if has been switched off, force updates
  if (not self.sticky_mode) then
    if (self.dsp_mode) then
      self:on_selected_device_change()
    else
      self:on_selected_track_change()
    end
  end
end

-- toggle fader mode and update lights
function FaderPort:toggle_fader_mode(fader_mode)

  TRACE("toggle_fader_mode()")
  
  -- check if an automatable parameter is bound to fader 
  if (not (self.fader_devpara and self.fader_devpara.is_automatable)) then 
    fader_mode = FADER_MODE_OFF
  end
  
  -- if the mode was already set, toggle to OFF
  if (self.fader_mode == fader_mode) or
     (self.fader_mode == FADER_MODE_LATCH and fader_mode == FADER_MODE_WRITE) or
     (self.fader_mode == FADER_MODE_WRITE and fader_mode == FADER_MODE_LATCH) then
      self.fader_mode = FADER_MODE_OFF
  else
    self.fader_mode = fader_mode

    -- init latch mode
    if (self.fader_mode == FADER_MODE_LATCH) then
      self.latch_write = false
    end

    -- force update in order to be in sync with Renoise
    -- E.g. think about a mode change from write mode to any reading mode
    self:on_fader_devpara_value_change()
  end

  self:set_light_state(0x0d,self.fader_mode == FADER_MODE_READ)
  self:set_light_state(0x0f,self.fader_mode == FADER_MODE_TOUCH)
  self:set_light_state(0x0e,self.fader_mode == FADER_MODE_WRITE or
    self.fader_mode == FADER_MODE_LATCH)

  -- OFF light isn't explicitly set when fader mode is off. It's disturbing
  -- This is also more Reaper compatible.
  -- ALSO VERY IMPORTANT: if off light is set, no fader values are sent from
  -- FaderPort. Means: it's despite the most other lights
  -- an internal state, not just a light.
end

-- switch fader port button light on/off
function FaderPort:set_light_state(nr,state)

  if (state == true) then
    self:midi_send({0xa0,nr,1}) -- light on
  else
    self:midi_send({0xa0,nr,0}) -- light off
  end
end

require "Emulator" -- TODO refactoring, better place

-- open FaderPort midi I/O devices. Means: register midi callbacks
function FaderPort:midi_open()

  TRACE("midi_open()")

  -- normal midi handling
  if (not prefs.emulation_mode.value) then  
    local input_devices = renoise.Midi.available_input_devices()
    if table.find(input_devices, prefs.midi_in_name.value) then
    self.midi_in = renoise.Midi.create_input_device(prefs.midi_in_name.value,
      {self, self.midi_callback},
      {self, self.sysex_callback})
    else
    print("Notice: Could not create MIDI input device ", prefs.midi_in_name.value)
    -- TODO better user feedback ?
    end  

    local output_devices = renoise.Midi.available_output_devices()
    if table.find(output_devices, prefs.midi_out_name.value) then
    self.midi_out = renoise.Midi.create_output_device(prefs.midi_out_name.value)
    else
    print("Notice: Could not create MIDI output device ", prefs.midi_out_name.value)
    -- TODO better user feedback ?
    end 
    
  -- emulator handling   
  else
    self.midi_in = 1
    self.midi_out = 1
    emulator:open()
  end
  
end

-- close FaderPort midi I/O devices
function FaderPort:midi_close()

  TRACE("midi_close()")
  
  -- emulator handling
  if (self.midi_in == 1 and self.midi_out == 1) then
    emulator:close()
    self.midi_in = nil
    self.midi_out = nil    
  
  -- normal midi handling
  else
    if (self.midi_in and self.midi_in.is_open) then
      self.midi_in:close()  
    end
    self.midi_in = nil
    
    if (self.midi_out and self.midi_out.is_open) then      
      self.midi_out:close()
    end
    self.midi_out = nil 
  end
end
  
-- Send midi message to FaderPort
function FaderPort:midi_send(message)
  
  -- check if midi events shall be sent at all
  if (self.lock_midi_out) then
    return
  end
  
  if (not prefs.emulation_mode.value) then
  
    if (not self.midi_out or not self.midi_out.is_open) then
    return
    end
        
    self.midi_out:send(message)
  else
    emulator:on_midi_receive(message)  
  end  
end

-- toggle ugly undo workaround and store
-- the state persistently in preferences
function FaderPort:toggle_undo_workaround()

  TRACE("toggle_undo_workaround()")

  prefs.undo_workaround.value = not prefs.undo_workaround.value
  prefs:save_as("config.xml")
end

-- toggle auto connect and store
-- the state persistently in preferences
function FaderPort:toggle_auto_connect()

  TRACE("toggle_auto_connect()")

  prefs.auto_connect.value = not prefs.auto_connect.value
  prefs:save_as("config.xml")
end

-- toggle emulation mode and store
-- the state persistently in preferences
function FaderPort:toggle_emulation_mode()

  TRACE("toggle_emulation_mode()")

  local connected = self.connected

  if (connected) then
    self:disconnect()
  end

  prefs.emulation_mode.value = not prefs.emulation_mode.value
  prefs:save_as("config.xml")
  
  if (connected) then
    self:connect()
  end    
end

-- device info dialog handler
function FaderPort:toggle_device_info_dialog()
  if (self:device_info_dialog_visible()) then
    self.device_info_dialog:close()
  else
    if (self.device_info_view) then
      self:update_device_info_view()
      self.device_info_dialog = 
        renoise.app():show_custom_dialog("FaderPort Device Infos", self.device_info_view)  
    end
  end
end

-- indicates if device info dialog is visible/valid
function FaderPort:device_info_dialog_visible()

  TRACE("device_info_dialog_visible()")

  return self.device_info_dialog and self.device_info_dialog.visible
end

-- updates data/text of device info view (child views)
function FaderPort:update_device_info_view()
  
  TRACE("update_device_info_view()")
  
  local text = "select a device"
  local device = song().selected_track_device
  if (device) then
    self.device_info_name.text = device.name
    self:update_device_info_bindings(device.name)
    self.device_info_parameters:clear()
    local parameters =  device.parameters
    for i = 1,#parameters do
      self.device_info_parameters:add_line(i.." ]  "..parameters[i].name)
    end  
  else
    self.device_info_parameters.text = text
  end
end  

-- updates dsp bindings textfield
function FaderPort:update_device_info_bindings(device_name)

  TRACE("update_device_info_bindings()") 

  local text = ""
  local dsp_index =
    tonumber(prefs.dsp_binding_list:find(1,device_name))
    
  -- dsp binding entry found for the device
  if (dsp_index) then

    -- are there any dsp bindings defined ?
    if (tonumber(prefs.dsp_binding_list[dsp_index+1].value) > -1) then

      local dsp_binding_start_index = dsp_index+1
      
      -- find last index and validate binding list
      local index = nil
      local size = 0
      for i = dsp_index+1,#prefs.dsp_binding_list do
        index = tonumber(prefs.dsp_binding_list[i].value)
        assert(index ~= nil, "index is no number ("..device_name..")") -- e.g. forgotten -1
        if (index == -1) then
          break
        end
        if ((i-dsp_index) % 2 == 1) then
          text = text.."["..index..","
        else
          text = text..index.."] "
        end
        i = i + 1
        size = size + 1
      end
      assert(index == -1, "-1 missing in dsp binding list ("..device_name..")")
      assert(size % 2 == 0, "odd number of dsp bindings ("..device_name..")")
      local dsp_binding_end_index = dsp_index + 1 + size - 2
    end      
  end
  
  self.device_info_bindings.text = text
end

-- help dialog handler
function FaderPort:toggle_help_dialog()
  if (self:help_dialog_visible()) then
    self.help_dialog:close()
  else
    if (self.help_view) then      
      self.help_dialog = 
        renoise.app():show_custom_dialog("FaderPort Help & About", self.help_view)  
    end
  end
end

-- indicates if help dialog is visible/valid
function FaderPort:help_dialog_visible()

  TRACE("help_dialog_visible()")

  return self.help_dialog and self.help_dialog.visible
end
