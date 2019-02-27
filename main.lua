--[[------------------------------------------------------------------------------------

  Airmann's FaderPort Renoise Driver
  
  A Renoise tool for integration of PreSonus FaderPort DAW Controller


  Copyright 2010-2019 4irmann, 
  
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License. 
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0 
  
  Unless required by applicable law or agreed to in writing, software distributed 
  under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR 
  CONDITIONS OF ANY KIND, either express or implied. See the License for the specific 
  language governing permissions and limitations under the License. 
  
-------------------------------------------------------------------------------------]]--

require "FaderPort"
require "Emulator"

--[[ locals ]] ---------------------------------------------------------------

--[[ globals ]] --------------------------------------------------------------

-- faderport driver
driver = nil 

-- faderport emulator
emulator = nil

-- preferences
prefs = renoise.Document.create("FaderPortPreferences") {  
    
    dump_midi = false, -- dump midi messages    

    emulation_mode = true, -- true: use emulator device instead of real faderport hardware  
    emulation_alternate_button_text = true, -- true: use alternate button texts instead of original
                                            -- button texts
  
    auto_connect = true, -- true: Renoise connects to FaderPort automatically during start up
    
    default_is_post_fx_mixer = true, -- true: FaderPort driver starts in post fx mixer mode, false: in pre fx mixer mode
    
    latch_is_default_write_mode = true, -- true: default fader write mode is "latch", 
                                        -- false: default fader write mode is "write"
    
    sticky_mode_support = false, -- sticky mode available (trns button)
    
    undo_workaround = false, -- use dirty undo workaround to avoid massive creation of undo data
                             -- IMPORTANT: doesn't work WITHOUT FaderPort additional power supply !
                            
    switch_off_when_app_resigned = false, -- reset FadePort state whenever Renoise is not the active Window
                                          -- and re-initialize state whenever Renoise get the active Window
                                          -- This is important if you want to use FaderPort for more than
                                          -- one Renoise instance simultaneously          
                          
    virtual_pan_resolution = 128, -- resolution of virtual pan control (0..127)    
    anti_suck_min_turns = 3, -- the minimum number of hardware pan encoder turns for a virtual pan value change
    
    footswitch_pressed_signal = 1, -- either 0 or 1: means: signals for footswitch pressed / released can be swapped. 
                                   -- This is helpfull for compensation of varying footswitch wiring   
     
    midi_in_name = "FaderPort", -- name of MIDI in device
    midi_out_name = "FaderPort", -- name of MIDI out device
    
    -- list of device specific fader/pan binding pairs
    dsp_binding_list = {
    
    
      -- IMPORTANT HINT
      -- the order/focus of the bindings was laid on (final) mixing and not creative sound design
      -- means: level and stereo parameters like wet/gain/pan/width are usually the first binding pairs.
      -- E.g. compressors first binding pair is makeup and not threshold and so on
    
      
      --------------------- NATIVE DEVICES --------------------------------    
       
      -- Delay
      -- hint: if line sync is active 1/2 can be modfified, but you will see nothing in Renoise.
      -- Moreover 7/8 are not accessible, instead 12/13 are accessible if line sync is active
      "Delay","5","5","9","10","1","2","3","4","-1", 
      "Multitap Delay","6","5","28","27","50","49","72","71","-1",  -- T1-T4 amount/in
      "Repeater","2","1","-1", -- divisor / mode
      "Reverb","2","3","2","4","-1", -- room size, width, damp, we assume it's used in a sendtrack with 100% wet
      "mpReverb","1","6","2","7","-1", -- duration, width, predelay, pan, we assume it's used in a sendtrack with 100% wet
       
      -- Dynamics
      "Compressor","5","5","1","2","3","4","-1", -- makeup, makeup, threshold, ratio, attack, release
      "Bus Compressor","5","6","1","2","3","4","-1", -- makeup, knee, threshold, ratio, attack, release
      "Maximizer","1","5","3","4","-1", -- boost, ceiling, peak rel, slow rel 
      "Gate","1","5","2","3","4","3","-1", -- threshold, floor, attack, hold, release, hold
       
      -- Filter
      "EQ 5","1","1","2","2","3","3","4","4","5","5","-1", -- iterate over bands
      "EQ 10","1","1","2","2","3","3","4","4","5","5", -- iterate over bands
              "6","6","7","7","8","8","9","9","10","10","-1",
      "Mixer EQ","1","5","3","2","2","4","-1", -- Lo. Hi, Freq, Mid, Mid, Q
      "Filter","2","3","2","1","4","5","-1", -- cutoff, resonance, cutoff, type, gain, inertia
                                               -- hint: 4 is opt. Gain value (not always shown)
      "Comb Filter","1","2","3","4","5","5","-1", -- freq, feedback, inertia, wet mix, dry mix, dry mix
      
      -- Modulation
      "Chorus","5","2","3","1","4","6","-1", -- wet, depth, feedback, rate, delay, phase
      "Flanger","1","5","3","2","4","6","-1", -- amount, delay, amplitude, rate, feedback, phase
      "Phaser","4","5","1","2","3","7","-1", -- depth , feedback, floor, ceiling, lfo rate, stages
      "RingMod","3","3","2","1","4","5","-1",  -- amount, amount, freq, osc, phase, inertia
      
      -- Shape / distortion
      "Cabinet Simulator","4","5","3","3","-1", -- wet, dry , gain, gain
      "Convolver","8","7","1","1","-1", -- wet, dry , gain, gain
      "Exciter","4","5","11","12","18","19","-1", -- ST L Sharp, ST L Amount, ST M Sharp, ST M Amount,  ST H Sharp, ST H Amount
      "Distortion","4","5","3","2","1","1","-1", -- wet, dry, tone, drive, mode, mode 
      "LofiMat","4","5","2","1","3","6","-1", -- wet, dry, rate, bit crunch, noise, smooth
      "Scream Filter","3","4","2","1","3","5","-1", -- cutoff, resonance, distortion, cutoff, inertia
       
       -- Tools
      "Gainer","1","2","-1", -- Gain, Pan
      "DC Offset","1","2","-1", -- offset, auto dc on/off
      "Stereo Expander","1","2","-1", -- expand, surround
       
      -- #Routing
      "#Line Input","2","1","-1", -- volume, panning
      "#ReWire Input","2","1","-1", -- volume, panning
      "#Send","1","2","-1", -- amount, receiver
      "#Multiband Send","1","7","3","8","5","8","2","2","4","4","6","6","-1", -- Amount1, Low, Amount2, High, Amount3, High, Receiver 1,2,3   
       
      -- *Meta Automation
      "*Instr. Automation","1","2","3","4","5","6","7", 
                           "8","9","10","11","12","13","14","-1", -- iterate over parameters
      "*Instr. MIDI Control","1","2","3","4","5","6","7", 
                           "8","9","10","11","12","13","14","-1", -- iterate over channels
      "*Instr. Macros","1","2","3","4","5","6","7","8","-1", -- iterate over parameters
                           
      -- *Mapping
      "*Hydra","1","1","5","6","10","11","15","16",
                                "20","21","25","26","30","31","35","36",
                                "40","41","45","46","-1", -- input, input, iterate over parameters
      "*XY Pad","2","1","6","7","11","12","-1",  -- x,y, x-min, x-max, y-min, y-max 
                                                    -- Hint: auto reset not supported                     
      -- *Modulation 
      "*Key Tracker","4","5","-1", -- min, max
      "*LFO","4","5","6","7","-1", -- amplitude, offset, freq, type
      "*Signal Follower","9","6","7","8","10","11","-1", -- sensitivity, dest off, attack, release, lp, hp
      "*Velocity Tracker","4","5","-1", -- min, max 
      "*Meta Mixer","6","9","7","10","8","11","-1", -- input A,B,C weight A,B,C
     
      -- Doofer
      "Doofer","1","2","3","4","5","6","7","8","-1", -- iterate over parameters
       
      --------------------------- VST's --------------------------------------
       
      --Voxengo
      "VST: Voxengo: Elephant","3","4","-1", -- in, out
      "VST: Voxengo: Polysquasher", "5","1","3","4","2","2","-1" -- output,bypass, threshold, ratio, oversample, oversample      
       
    }
  }  
 
prefs:load_from("config.xml")
--prefs:save_as("config.xml")


--[[ initialize ]] --------------------------------------------------------------

-- instantiate driver
if (not driver) then
  driver = FaderPort()
end

if (driver) then
  
  -- add menu entries, keybindings 

  -- reset
  renoise.tool():add_menu_entry {
    name = "Main Menu:Tools:FaderPort:Reset / Show",
    active = function() return driver.connected end,
    invoke = function() driver:reset() end
  }
  renoise.tool():add_keybinding {
    name = "Global:Tools:Reset / Show FaderPort",    
    invoke = function() driver:reset() end
  }
  
  -- connect
  renoise.tool():add_menu_entry {
    name = "--- Main Menu:Tools:FaderPort:Connect",
    active = function() return not driver.connected end,
    invoke = function() driver:connect() end
  }
  renoise.tool():add_keybinding {
    name = "Global:Tools:Connect to FaderPort",
    invoke = function() driver:connect() end
  }   

  -- disconnect  
  renoise.tool():add_menu_entry {
    name = "Main Menu:Tools:FaderPort:Disconnect",
    active = function() return driver.connected end,
    invoke = function() driver:disconnect() end
  }
  renoise.tool():add_keybinding {
    name = "Global:Tools:Disconnect from FaderPort",
    invoke = function() driver:disconnect() end
  }  

  -- auto connect
  renoise.tool():add_menu_entry {
    name = "--- Main Menu:Tools:FaderPort:Auto Connect",
    invoke = function() driver:toggle_auto_connect() end,
    selected = function() return prefs.auto_connect.value end
  }
  
  -- emulation mode 
  renoise.tool():add_menu_entry {
    name = "Main Menu:Tools:FaderPort:Emulation Mode",
    invoke = function() driver:toggle_emulation_mode() end,
    selected = function() return prefs.emulation_mode.value end
  }
  
  -- undo workaround  
  renoise.tool():add_menu_entry {
    name = "--- Main Menu:Tools:FaderPort:Undo Workaround",
    invoke = function() driver:toggle_undo_workaround() end,
    selected = function() return prefs.undo_workaround.value end
  }
  renoise.tool():add_keybinding {
    name = "Global:Tools:Toggle FaderPort Undo Workaround",
    invoke = function() driver:toggle_undo_workaround() end,
    selected = function() return prefs.undo_workaround.value end
  }  
  
  -- device info dialog  
  renoise.tool():add_menu_entry {
    name = "--- Main Menu:Tools:FaderPort:Show Device Infos",
    invoke = function() driver:toggle_device_info_dialog() end,
    selected = function() return driver:device_info_dialog_visible() end
  }
  renoise.tool():add_keybinding {
    name = "Global:Tools:Show FaderPort Device Infos",
    invoke = function() driver:toggle_device_info_dialog() end,
    selected = function() return driver:device_info_dialog_visible() end
  } 

  -- help
  renoise.tool():add_menu_entry {
    name = "Main Menu:Tools:FaderPort:Show Help",
    invoke = function() driver:toggle_help_dialog() end,    
    selected = function() return driver:help_dialog_visible() end
  }
  renoise.tool():add_keybinding {
    name = "Global:Tools:Show FaderPort Help",
    invoke = function() driver:toggle_help_dialog() end,
    selected = function() return driver:help_dialog_visible() end
  } 
end  

-- always instantiate emulator
if (not emulator) then
  emulator = Emulator()
end

--[[ debug ]]--------------------------------------------------------------]]--

_AUTO_RELOAD_DEBUG = true
