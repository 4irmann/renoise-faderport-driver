--[[---------------------------------------------------------------------------------------

  FaderPort drvier Debug functions
  
  This was "outsourced" 
  
  Copyright 2010 4irmann,
  
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License. 
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 

  Unless required by applicable law or agreed to in writing, software distributed 
  under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
  CONDITIONS OF ANY KIND, either express or implied. See the License for the specific 
  language governing permissions and limitations under the License.
  
-----------------------------------------------------------------------------------------]]

-- debug function: switches all FaderPort button lights on
function FaderPort:all_lights_on()

 ------------ Channel lights
  self:midi_send({0xa0,0x15,1}) -- Mute
  self:midi_send({0xa0,0x16,1}) -- Solo
  self:midi_send({0xa0,0x17,1}) -- Rec arm

  ---------  Play State lights
  self:midi_send({0xa0,0x00,1}) -- Record
  self:midi_send({0xa0,0x01,1}) -- Play
  self:midi_send({0xa0,0x02,1}) -- Stop
  self:midi_send({0xa0,0x03,1}) -- Fast Forward
  self:midi_send({0xa0,0x04,1}) -- Rewind

  ----------- Extra lights
  self:midi_send({0xa0,0x05,1}) -- Shift 
  self:midi_send({0xa0,0x06,1}) -- Punch 
  self:midi_send({0xa0,0x07,1}) -- User 
  self:midi_send({0xa0,0x08,1}) -- Loop 

  ----------- Window View Lights
  self:midi_send({0xa0,0x09,1}) -- Undo/Redo
  self:midi_send({0xa0,0x0a,1}) -- Trns View
  self:midi_send({0xa0,0x0b,1}) -- Proj View
  self:midi_send({0xa0,0x0c,1}) -- Mix

  ----------  Fader Mode Lights
  self:midi_send({0xa0,0x0d,1}) -- Read
  self:midi_send({0xa0,0x0e,1}) -- Write
  self:midi_send({0xa0,0x0f,1}) -- Touch
  self:midi_send({0xa0,0x10,1}) -- Off

  ----------  Channel Select Lights
  self:midi_send({0xa0,0x11,1}) -- Output
  self:midi_send({0xa0,0x12,1}) -- Arrow right
  self:midi_send({0xa0,0x13,1}) -- Bank
  self:midi_send({0xa0,0x14,1}) -- Arrow left
end

-- debug function: funky lights and fader movement
-- Hint: doesn't function in emulator, because of 
-- GUI update threading ?
function FaderPort:funky_lights()

  for x = 0,0x30 do
    self:midi_send({0xa0,x,1})    
    
    local time = os.clock()+0.05
    while os.clock()< time do
    -- nothing
    end
    self:midi_send({0xa0,x,0})    

    -- funky fader movement
    self:midi_send({0xb0,0x00,x/8}) -- bank select MSB
    self:midi_send({0xb0,0x20,0}) -- bank select LSB
  end
end

--------------------------------------------------------------------------------
-- debug tracing - taken from Duplex, author: danoise
-- HINT: this code IS NOT LICENSED UNDER THE ABOVE MENTIONED APACHE LICENSE
--------------------------------------------------------------------------------

-- set one or more expressions to either show all or only a few messages 
-- from TRACE calls.

-- Some examples: 
-- {".*"} -> show all traces
-- {"^Display:"} " -> show traces, starting with "Display:" only
-- {"^ControlMap:", "^Display:"} -> show "Display:" and "ControlMap:"

-- local __trace_filters = { "on_app","on_song","reset",".*open.*",".*close*",".*connect.*"}

local __trace_filters = { }

--------------------------------------------------------------------------------
-- TRACE impl

if (__trace_filters ~= nil) then
  
  function TRACE(...)
    local result = ""
  
    -- try serializing a value or return "???"
    local function serialize(obj)
      local succeeded, result = pcall(tostring, obj)
      if succeeded then
        return result 
      else
       return "???"
      end
    end
    
    -- table dump helper
    local function rdump(t, indent, done)
      local result = "\n"
      done = done or {}
      indent = indent or string.rep(' ', 2)
      
      local next_indent
      for key, value in pairs(t) do
        if (type(value) == 'table' and not done[value]) then
          done[value] = true
          next_indent = next_indent or (indent .. string.rep(' ', 2))
          result = result .. indent .. '[' .. serialize(key) .. '] => table\n'
          rdump(value, next_indent .. string.rep(' ', 2), done)
        else
          result = result .. indent .. '[' .. serialize(key) .. '] => ' .. 
            serialize(value) .. '\n'
        end
      end
      
      return result
    end
   
    -- concat args to a string
    local n = select('#', ...)
    for i = 1, n do
      local obj = select(i, ...)
      if( type(obj) == 'table') then
        result = result .. rdump(obj)
      else
        result = result .. serialize(select(i, ...))
        if (i ~= n) then 
          result = result .. "\t"
        end
      end
    end
  
    -- apply filter
    for _,filter in pairs(__trace_filters) do
      if result:find(filter) then
        print(result)
        break
      end
    end
  end
  
else

  function TRACE()
    -- do nothing
  end
    
end



