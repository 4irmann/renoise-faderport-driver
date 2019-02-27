--[[-----------------------------------------------------------------------------------
  
  FaderPort Emulator 
  
  Copyright 2014 4irmann, 
  
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License. 
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 

  Unless required by applicable law or agreed to in writing, software distributed 
  under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
  CONDITIONS OF ANY KIND, either express or implied. See the License for the specific 
  language governing permissions and limitations under the License.
  
-------------------------------------------------------------------------------------]]

class "Emulator"

require "Debug"

-- Static class variables
-- See http://forum.renoise.com/index.php?/topic/
-- 33944-solved-luabind-lua-classes-staticnonstatic/

-- mutex locks
Emulator.lock_fader = false 

-- light colors
Emulator.red = {0xff,0,0}
Emulator.green = {0,0xff,0}
Emulator.blue = {0,0,0xff}
Emulator.yellow = {0xff,0xff,0}

function Emulator:__init()

  TRACE("__init()")
  self.dialog = nil
  self.last_state = {} -- for hold button emulation
  
  self:initialize_midi_mappings()
end

function Emulator:open()  
  self:close()
  self:create_dialog()    
end

function Emulator:close()  
  if (self:dialog_visible()) then
    self.dialog:close()
  end
end

function Emulator:switch_light_state(button,color,state)
  
  if (state == 1) then
    button.color = color
  else
    button.color = {0,0,0}
  end
end  

------------------------------- RECEIVE HANDLERS

-- MIDI receive handler 
-- this function receives midi messages from Faderport driver code
function Emulator:on_midi_receive(message)

  local msg = message

  if (prefs.dump_midi.value) then
    print(("FaderPort Emulator: received MIDI %X %X %X"):format(
      message[1], message[2], message[3]))
  end
  
  -- fader value
  if (msg[1] == 0xb0) then  
        
    if (msg[2] == 0x00) then
      self.last_msb = msg[3] -- store msb, wait for lsb
    elseif (msg[2] == 0x20) then --lsb        
      local intval = bit.lshift(self.last_msb,7)      
      intval = intval + msg[3]
      self:on_receive_fader_value(intval)
    end
  
  -- lights  
  elseif (msg[1] == 0xa0) then

    -- play row
    if (msg[2] == 0x00) then self:switch_light_state(self.record,self.red,msg[3]) 
    elseif (msg[2] == 0x01) then self:switch_light_state(self.play,self.green,msg[3]) 
    elseif (msg[2] == 0x02) then self:switch_light_state(self.stop,self.yellow,msg[3]) 
    elseif (msg[2] == 0x03) then self:switch_light_state(self.forward,self.yellow,msg[3]) 
    elseif (msg[2] == 0x04) then self:switch_light_state(self.rewind,self.yellow,msg[3]) 
    
    -- extra row
    elseif (msg[2] == 0x05) then self:switch_light_state(self.shift,self.red,msg[3]) 
    elseif (msg[2] == 0x06) then self:switch_light_state(self.punch,self.red,msg[3]) 
    elseif (msg[2] == 0x07) then self:switch_light_state(self.user,self.red,msg[3]) 
    elseif (msg[2] == 0x08) then self:switch_light_state(self.loop,self.blue,msg[3]) 
    
    -- window view row
    elseif (msg[2] == 0x09) then self:switch_light_state(self.undo,self.red,msg[3]) 
    elseif (msg[2] == 0x0a) then self:switch_light_state(self.trns,self.red,msg[3]) 
    elseif (msg[2] == 0x0b) then self:switch_light_state(self.proj,self.red,msg[3]) 
    elseif (msg[2] == 0x0c) then self:switch_light_state(self.mix,self.red,msg[3]) 
        
    -- fader row
    elseif (msg[2] == 0x0d) then self:switch_light_state(self.read,self.green,msg[3]) 
    elseif (msg[2] == 0x0e) then self:switch_light_state(self.write,self.red,msg[3]) 
    elseif (msg[2] == 0x0f) then self:switch_light_state(self.touch,self.red,msg[3]) 
    elseif (msg[2] == 0x10) then self:switch_light_state(self.off,self.red,msg[3]) 
    
    -- channel select row
    elseif (msg[2] == 0x11) then self:switch_light_state(self.output,self.yellow,msg[3]) 
    elseif (msg[2] == 0x12) then self:switch_light_state(self.right,self.red,msg[3]) 
    elseif (msg[2] == 0x13) then self:switch_light_state(self.bank,self.red,msg[3]) 
    elseif (msg[2] == 0x14) then self:switch_light_state(self.left,self.red,msg[3]) 
    
    -- channel mode row
    elseif (msg[2] == 0x15) then self:switch_light_state(self.mute,self.red,msg[3]) 
    elseif (msg[2] == 0x16) then self:switch_light_state(self.solo,self.yellow,msg[3]) 
    elseif (msg[2] == 0x17) then self:switch_light_state(self.rec,self.red,msg[3]) 
    
    end 
  end
end

function Emulator:on_receive_fader_value(intval)

   TRACE(("on_receive_fader_value(intval=%d)"):format(intval))   
   
   if (not Emulator.lock_fader) then -- MUTEX
     Emulator.lock_fader = true 
     self.fader.value = intval
     Emulator.lock_fader = false
   end
end

--------------------------------- SEND HANDLERS

-- FADER
function Emulator:on_fader_value_change(intval)
    
  TRACE(("on_fader_value_change(intval=%d)"):format(intval))     
  
  if (not Emulator.lock_fader) then -- MUTEX 
    Emulator.lock_fader = true        
    
    -- send fader touched event
    self:midi_send({0xa0,0x7f,0x01})
    
    -- off button has a special behaviour:
    -- if light is set, no fader values are
    -- sent to midi out. We emulate this, here.
    -- Touch state is sent, though ???
    -- TODO: check this with real hardware
    if (self.off.color[1] ~= self.red[1] or 
        self.off.color[2] ~= self.red[2] or
        self.off.color[3] ~= self.red[3]) then
    
      local msb = bit.rshift(intval,3)  -- shift higher 7 bits
      local lsb = bit.band(intval,7) -- %0111 mask lower 3 bits
      local lsb = bit.lshift(lsb,4)  -- shift 3 bits to higher nibble
      self:midi_send({0xb0,0x00,msb}) -- bank select MSB
      self:midi_send({0xb0,0x20,lsb}) -- bank select LSB        
    end
    
    -- send fader untouched event
    self:midi_send({0xa0,0x7f,0x00})
    
    Emulator.lock_fader = false
  end 
end

-- PAN
function Emulator:on_pan_value_change(floatval)
  
  TRACE(("on_pan_value(X=%.2f, Y= %.2f)"):format(floatval.x, floatval.y))   
    
  if (floatval.x < 0.5) then
    self:midi_send({0xe0,0x00,0x7e}) -- turn left               
  elseif (floatval.x > 0.5) then
    self:midi_send({0xe0,0x00,0x01}) -- turn right
  end 
end

-- MIDI send handler
-- this function sends midi message to Faderport driver code,  
-- means to midi callback handler
function Emulator:midi_send(message)  
  driver:midi_callback(message)
end

function Emulator:midi_send(message)  
  driver:midi_callback(message)
end

function Emulator:midi_send_button(midi_nr,state)
  if (not self.hold.value) then
    self:midi_send({0xa0,midi_nr,state})
    self.last_state[midi_nr] = state
  else
    if (state == 1) then      
      if (self.last_state[midi_nr] == nil or self.last_state[midi_nr] == 0) then
        self:midi_send({0xa0,midi_nr,1})
        self.last_state[midi_nr] = 1
      else
        self:midi_send({0xa0,midi_nr,0})
        self.last_state[midi_nr] = 0
      end
    end  
  end
end

------------------------------- MIDI MAPPING

function Emulator:trigger_send(msg,buttonnr)
  if (msg:is_trigger()) then
    self:midi_send({0xa0,buttonnr,0x01}) 
    self:midi_send({0xa0,buttonnr,0x00}) 
  end
end

function Emulator:switch_send(msg,buttonnr)
  if (msg:is_switch()) then
    if (msg.boolean_value) then 
      self:midi_send({0xa0,buttonnr,0x01}) 
    else
      self:midi_send({0xa0,buttonnr,0x00}) 
    end
  end
end

function Emulator:initialize_midi_mappings()
  
  -- FADER
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:fader value [Set]",
    invoke = 
      function(msg) 
        local intval 
        if (msg:is_abs_value()) then
          intval = msg.int_value/127*1023 --upscale to high resolution
        else 
          return  -- rel values not supported
        end         
        self:on_receive_fader_value(intval) -- update emulator
        self:on_fader_value_change(intval)  -- update Renoise      
      end
  }
  
  -- PAN
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:pan value [Set]",
    invoke = 
      function(msg)         
        if (msg:is_rel_value()) then                            
          if (msg.int_value < 0) then
            self:midi_send({0xe0,0x00,0x7e}) -- turn left -> update Renoise              
          elseif(msg.int_value > 0) then
            self:midi_send({0xe0,0x00,0x01}) -- turn right -> update Renoise
          end                      
        else
          return  -- abs values not supported
        end                         
      end
  }  
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:mute [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x12) end                    
  }

  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:solo [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x11) end                    
  }
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:rec [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x10) end                    
  }
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:left [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x13) end                    
  }
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:bank [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x14) end                    
  }

  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:right [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x15) end                    
  }

  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:output [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x16) end                    
  }
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:read [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x0a) end                    
  }
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:write [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x09) end                    
  }
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:touch [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x08) end                    
  }
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:off [Gate]",
    invoke = function(msg) self:switch_send(msg,0x17) end                    
  }
   
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:mix [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x0b) end                    
  }
   
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:proj [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x0c) end                    
  }
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:trns [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x0d) end                    
  }
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:undo [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x0e) end                    
  } 
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:shift [Gate]",
    invoke = function(msg) self:switch_send(msg,0x02) end                    
  } 
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:punch [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x01) end                    
  } 
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:user [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x00) end                    
  } 
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:loop [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x0f) end                    
  } 
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:rwd [Gate]",
    invoke = function(msg) self:switch_send(msg,0x03) end                    
  }
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:fwd [Gate]",
    invoke = function(msg) self:switch_send(msg,0x04) end                    
  }
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:stop [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x05) end                    
  }
  
  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:play [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x06) end                    
  }

  renoise.tool():add_midi_mapping {
    name = "Tools:FaderPort Emulator:record [Trigger]",
    invoke = function(msg) self:trigger_send(msg,0x07) end                    
  }
  
end

---------------------------------- GUI
  
function Emulator:create_view()
 
  local vb = renoise.ViewBuilder()  
  local dialog_width = 350
 
  self.list =
    vb:multiline_textfield {
        text = "",
        width = dialog_width,
        height = 500,        
    }               
    
  self.pan = 
    vb:xypad {     
      width = 50,
      height = 10, 
      min = {x=0.0,y=0.0},
      max = {x=1.0,y=1.0},
      value = {x=0.5,y=0.5},
      snapback = {x=0.5,y=0.5},
      midi_mapping = "Tools:FaderPort Emulator:pan value [Set]",
      notifier = function(floatval)
        self:on_pan_value_change(floatval)        
      end
  }    
    
  -- ATTENTION: Renoise slider has only a resolution of 100
  -- Means: min,max can be higher, but values are skipped 
  -- and thus precision is lost  
  self.fader = 
    vb:slider {     
         width = 50,
         height = 300,
         min = 0,
         max = 1023,
         midi_mapping = "Tools:FaderPort Emulator:fader value [Set]",
         notifier = function (intval)
            self:on_fader_value_change(intval)                      
         end         
    }          
  
  -- associative array for button text 
  self.btntxt = {}
  self.btntxt["mute"] = "mute"
  self.btntxt["solo"] = "solo"
  self.btntxt["rec"] = "rec"
  self.btntxt["left"] = "< left"
  self.btntxt["bank"] = "bank"
  self.btntxt["right"] = "right >"
  self.btntxt["output"] = "output"
  self.btntxt["read"] = "read"
  self.btntxt["write"] = "write"
  self.btntxt["touch"] = "touch"
  self.btntxt["off"] = "off"
  self.btntxt["mix"] = "mix"
  self.btntxt["proj"] = "proj"
  self.btntxt["trns"] = "trns"
  self.btntxt["undo"] = "undo"
  self.btntxt["shift"] = "shift"
  self.btntxt["punch"] = "punch"
  self.btntxt["user"] = "user"
  self.btntxt["loop"] = "loop"
  self.btntxt["rwd"] = "<< rwd"
  self.btntxt["fwd"] = "fwd >>"
  self.btntxt["stop"] = "stop"
  self.btntxt["play"] = "play"
  self.btntxt["record"] = "record"
  
  -- alternate button texts
  if (prefs.emulation_alternate_button_text.value) then
    self.btntxt["bank"] = "devices"
    self.btntxt["output"] = "post"
    self.btntxt["proj"] = "pattern"
    self.btntxt["trns"] = "sample"
    self.btntxt["user"] = "swap"
  end
  
  self.mute = vb:button {
      width = 50,height = 25, text = self.btntxt["mute"],
      pressed = function()  self:midi_send_button(0x12,1) end,      
      released = function() self:midi_send_button(0x12,0) end,
      midi_mapping = "Tools:FaderPort Emulator:mute [Trigger]"
    }   
  self.solo = vb:button {
      width = 50, height = 25, text = self.btntxt["solo"],
      pressed = function() self:midi_send({0xa0,0x11,0x01}) end,
      released = function() self:midi_send({0xa0,0x11,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:solo [Trigger]"
    }  
  self.rec = vb:button {
      width = 50, height = 25, text = self.btntxt["rec"],
      pressed = function() self:midi_send({0xa0,0x10,0x01}) end, 
      released = function() self:midi_send({0xa0,0x10,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:rec [Trigger]"
    } 
    
  self.left = vb:button { 
      width = 50, height = 25, text = self.btntxt["left"],
      pressed = function() self:midi_send({0xa0,0x13,0x01}) end,
      released = function() self:midi_send({0xa0,0x13,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:left [Trigger]"
    }    
  self.bank = vb:button {
      width = 50, height = 25, text = self.btntxt["bank"],
      pressed = function() self:midi_send({0xa0,0x14,0x01}) end,
      released = function() self:midi_send({0xa0,0x14,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:bank [Trigger]"
    }    
  self.right = vb:button {
      width = 50, height = 25, text = self.btntxt["right"],
      pressed = function() self:midi_send({0xa0,0x15,0x01}) end,
      released = function() self:midi_send({0xa0,0x15,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:right [Trigger]"
    }  
  self.output = vb:button {
      width = 50, height = 25, text = self.btntxt["output"],
      pressed = function() self:midi_send({0xa0,0x16,0x01}) end,
      released = function() self:midi_send({0xa0,0x16,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:output [Trigger]"
    }  
  
  self.read = vb:button {
      width = 50, height = 25, text = self.btntxt["read"],
      pressed = function() self:midi_send({0xa0,0x0a,0x01}) end,
      released = function() self:midi_send({0xa0,0x0a,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:read [Trigger]"
    }    
  self.write = vb:button {
      width = 50, height = 25, text = self.btntxt["write"],
      pressed = function() self:midi_send({0xa0,0x09,0x01}) end,
      released = function() self:midi_send({0xa0,0x09,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:write [Trigger]"
    }    
  self.touch = vb:button {
      width = 50, height = 25, text = self.btntxt["touch"],
      pressed = function() self:midi_send({0xa0,0x08,0x01}) end,
      released = function() self:midi_send({0xa0,0x08,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:touch [Trigger]"
    }  
  self.off = vb:button {
      width = 50, height = 25, text = self.btntxt["off"],
      pressed = function()  self:midi_send_button(0x17,1) end,      
      released = function() self:midi_send_button(0x17,0) end,
      midi_mapping = "Tools:FaderPort Emulator:off [Gate]"
    }
  
  self.mix = vb:button {
      width = 50, height = 25, text = self.btntxt["mix"],
      pressed = function() self:midi_send({0xa0,0x0b,0x01}) end,
      released = function() self:midi_send({0xa0,0x0b,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:mix [Trigger]"
    }    
  self.proj = vb:button {
      width = 50, height = 25, text = self.btntxt["proj"],
      pressed = function() self:midi_send({0xa0,0x0c,0x01}) end,
      released = function() self:midi_send({0xa0,0x0c,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:proj [Trigger]"
    }  
  self.trns = vb:button {
      width = 50, height = 25, text = self.btntxt["trns"],
      pressed = function() self:midi_send({0xa0,0x0d,0x01}) end,
      released = function() self:midi_send({0xa0,0x0d,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:trns [Trigger]"
    }  
  self.undo = vb:button {
      width = 50, height = 25, text = self.btntxt["undo"],
      pressed = function() self:midi_send({0xa0,0x0e,0x01}) end,
      released = function() self:midi_send({0xa0,0x0e,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:undo [Trigger]"
    }
  
  self.shift = vb:button {  
      width = 50, height = 25, text = self.btntxt["shift"],
      pressed = function()  self:midi_send_button(0x02,1) end,      
      released = function() self:midi_send_button(0x02,0) end,
      midi_mapping = "Tools:FaderPort Emulator:shift [Gate]"
    }
  self.punch = vb:button {
      width = 50, height = 25, text = self.btntxt["punch"],
      pressed = function() self:midi_send({0xa0,0x01,0x01}) end,
      released = function() self:midi_send({0xa0,0x01,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:punch [Trigger]"
    }
  self.user = vb:button {
      width = 50, height = 25, text = self.btntxt["user"],  
      pressed = function() self:midi_send({0xa0,0x00,0x01}) end,
      released = function() self:midi_send({0xa0,0x00,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:user [Trigger]"
    }
  self.loop = vb:button {
      width = 50, height = 25, text = self.btntxt["loop"],    
      pressed = function() self:midi_send({0xa0,0x0f,0x01}) end,
      released = function() self:midi_send({0xa0,0x0f,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:loop [Trigger]"
    }
  
  self.rewind = vb:button {
      width = 50, height = 25, text = self.btntxt["rwd"],      
      pressed = function()  self:midi_send_button(0x03,1) end,      
      released = function() self:midi_send_button(0x03,0) end,
      midi_mapping = "Tools:FaderPort Emulator:rwd [Gate]"
    }
  self.forward = vb:button {
      width = 50, height = 25, text = self.btntxt["fwd"],
      pressed = function()  self:midi_send_button(0x04,1) end,      
      released = function() self:midi_send_button(0x04,0) end,
      midi_mapping = "Tools:FaderPort Emulator:fwd [Gate]"
    }
  self.stop = vb:button {
      width = 50, height = 25, text = self.btntxt["stop"],
      pressed = function() self:midi_send({0xa0,0x05,0x01}) end,
      released = function() self:midi_send({0xa0,0x05,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:stop [Trigger]"
    }
  self.play = vb:button {
      width = 50, height = 25, text = self.btntxt["play"],
      pressed = function() self:midi_send({0xa0,0x06,0x01}) end,
      released = function() self:midi_send({0xa0,0x06,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:play [Trigger]"
    }    
  self.record = vb:button {
      width = 50, height = 25, text = self.btntxt["record"],
      pressed = function() self:midi_send({0xa0,0x07,0x01}) end,
      released = function() self:midi_send({0xa0,0x07,0x00}) end,
      midi_mapping = "Tools:FaderPort Emulator:record [Trigger]"
    }    
    
  self.hold = vb:checkbox {
      width = 20, height = 20, value = false
      --notifier = function() self: TODO: reset hold state ?
  }  
  self.hold_label = vb:text {
      height = 20, text = "Emulate hold key (shift,rwd,fwd, off only!)"
  }
  
  self.alternate_button_text = vb:checkbox {
      width = 20, height = 20, value = prefs.emulation_alternate_button_text.value,
      notifier = function() 
        prefs.emulation_alternate_button_text.value = self.alternate_button_text.value 
        prefs:save_as("config.xml")
        if (prefs.emulation_alternate_button_text.value) then
          self.bank.text = "devices"
          self.output.text = "post"
          self.proj.text = "pattern"
          self.trns.text = "sample"
          self.user.text = "swap"
        else
          self.bank.text = "bank"
          self.output.text = "output"
          self.proj.text = "proj"
          self.trns.text = "trns"
          self.user.text = "user"
        end        
      end
  }
  self.alternate_button_text_label = vb:text {
      height = 20, text = "Alternate button text"
  }
     
  self.view =    
    vb:row { 
      margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,     
      spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING, 
      vb:column {
        margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
        spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING, 
        self.pan,
        self.fader
      },     
      vb:column {
        margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
        spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING, 
        vb:space {
          height = 8
        },
        vb:row {
          margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
          spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,        
          self.mute,self.solo,self.rec
        },
        vb:row {
          margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
          spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,        
          self.left,self.bank,self.right,self.output
        },
        vb:row {
          margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
          spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,        
          self.read,self.write,self.touch,self.off
        },
        vb:row {
          margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
          spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,        
          self.mix,self.proj,self.trns,self.undo
        },
        vb:row {
          margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
          spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,        
          self.shift,self.punch,self.user,self.loop
        },         
        vb:row {
          margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
          spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING-7,        
          self.rewind,self.forward,self.stop,self.play,self.record
        },              
        vb:row {  
          margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
          spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,
          self.hold, self.hold_label
        },
        vb:row {
          margin = renoise.ViewBuilder.DEFAULT_DIALOG_MARGIN,
          spacing = renoise.ViewBuilder.DEFAULT_DIALOG_SPACING,
          self.alternate_button_text, self.alternate_button_text_label
        }
      }
    }
end 

function Emulator:keyhandler(dialog,key)
  TRACE("keyhandler()")
  -- not implemented
end

-- indicates if emulator dialog is visible/valid
function Emulator:dialog_visible()
  TRACE("dialog_visible()")
  return self.dialog and self.dialog.visible
end

-- device info dialog handler
function Emulator:create_dialog()  
  self:create_view()  
  self.dialog = 
    renoise.app():show_custom_dialog("FaderPort Emulator", self.view,self.keyhandler)                  
end

