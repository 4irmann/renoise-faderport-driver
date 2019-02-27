# 4irmann's Renoise Faderport driver
4irmann's Renoise Faderport driver is a sophisticated LUA tool, which integrates the PreSonus Faderport DAW Controller 
seamlessly into Renoise. Focus is laid on mixing, automation envelope creation, and general DAW control. 
This tool can seriously improve your workflow and mixing process.

## Installation of latest released version (from xrnx file)
- download latest xrns archive
- start Renoise and drag and drop xrnx archive unto Renoise

## Installation of latest version (from source)
- Locate your personal Renoise tools folder (e.g. for Windows `C:\Users\Mike\AppData\Roaming\Renoise\V3.1.1\Scripts\Tools`, different for MacOS/Linux !!)
- if not exist already create a new subfolder **de.4irmann.FaderPort.xrnx**
- if subfolder already exist, remove subfolder and recreate (make backup before and/or save your config.xml)
- download source tarball as a zip file and unzip into  subfolder **de.4irmann.FaderPort.xrnx**

## License

Apache License 2.0 (http://www.apache.org/licenses/LICENSE-2.0)

## Features:
- support of all FaderPort buttons, touch-sensitive motor fader, 
  endless pan control and lights (full bidirectional communication)
- Footswitch support for hands-free operation. You can connect an usual on/off footswitch to the FaderPort. 
  Footswitch has the same function as transport play. It's especially useful for hands-free 
  recording of audio and midi data.
- transport: play, play from position, stop, panic stop, forward, rewind, record / edit, loop, 
  block loop, block loop forward/backward
- track: mute, solo, select next track, select previous track, select master track, jump to song start / end, record sample
- pre-fx / post-fx volume / pan, and any DSP device parameter can be controlled
- currently selected track is automatically bound to FaderPort. Binding is displayed in status bar
- currently selected device/plug-in etc. can automatically be bound to FaderPort
- customizable navigation through device / plug-in parameters. 
  Relevant device parameter lists can be defined via preferences. Presets for all native devices are included.
- full automation envelope support: read, write, touch, latch mode
- 10 bit high resolution (1024 steps) for fader values (allows for precise mixing)
- endless pan control support with speed feature, adjustable virtual resolution (default 7 bit, 128 steps), 
  auto down scaling and adjustable "anti-suck" protection
- fader and pan controller can be swapped (e.g. fader controls stereo panning)
- fader value can be reset to Renoise default value (e.g. volume to 0 dB)
- fine trim mode: fader values can be fine trimmed via shift+pan control
- switch between views: mixer, pattern editor, sample editor
- sticky mode support: FaderPort controls can be sticked / bound to a specific track or device
- undo / redo support (experimental)
- Renoise status bar support (displays parameter bindings and value changes) 

## Links 
- https://soundcloud.com/4irmann
- https://www.youtube.com/user/4irmann