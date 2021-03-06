# spacepan
spatial audio tool using supercollider 

Note: I will convert the spacepan code to classes and write a proper helpfile within the next months, for now it is just a single .scd file and this lousy .txt! 

*** BEFORE YOU START ***

- You will need the "SC3plugins" extensions and the "wslib" and "mathlib" quarks (type "Quarks.gui") to run the code!
- You will need at least 4 loudspeakers in a front-back configuration. For proper results use >= 8 loudspeakers
- Create a dedicated spacepan folder in your SC working folder. This folder must contain SpacePanV1.scd, SpacePanHelp.txt and a subfolder named "Snapshots"

*** RUNNING SPACEPAN ***

- Open SpacePanV1.scd
- Define your audio device, samplerate and the number of in/outs
- Set the size of the virtual room. Depends on your real space, reasonable size will be between 10..50 meters
- Set your loudspeaker positions array lspos = [x, y] meters. You can choose your reference point (from where you measure x y) but it makes sense to define the middle of your loudspeaker arrangement to be the reference (0, 0). Try to be precise.
- VERY IMPORTANT: You have to set the arrays named amps = #[...] and delays = #[...] in the synthdefs "spacepan" and "staticsrc" to the number of loudspeakers! For example for 6 speakers set arrays to #[0,0,0,0,0,0]. There will be a more convenient solution in the next version of this code...
- Select the code (cursor to first bracket to autoselect all) and evaluate (cmd+enter)
- The gui shows up. No source by default. Click the green "+" in the upper left corner of the source panel to add a source.
- If needed, change your master out index (number box bottom left)
- Turn up the volume of your source. You should hear the ping sound.
- Check your outputs by clicking "Outmeters"

*** SOURCE PANEL FUNCTIONS ***

- "Label" : label the source
- "Group" : assign source group. use shiftkey to apply actions to group (mute = shift+alt+click, solo = shift+ctrl+click, move=shift+move).
- "Input" : input bus. input metering is always pre fader.
- "Solo" : solo selected source. you can do that in spaceview using "ctrl" + click. In group mode use "shift+ctrl" to solo the group.
- "Mute" : mute selected source. you can do that in spaceview using "alt" + click. In group mode use "shift+alt" to solo the group.
- "Level" : source level -inf...0dB. Group levels are always linked
- "Focus" : spread of the source. always use 1 if you have a stereo input source routed to group to minimize spill and phasing. focus is always linked.
- "Apply delay" : if position algo uses time+amplitude or amplitude only
- "Apply room fx" : apply distance based lowpass filtering and fx sends
- "Reverb" : reverb send level.
- "Delay" : delay send level.
- "Aux" : aux send level. not active yet.
- "Rota" : autorotation. adjust speed and direction as you like. always linked in groups.
- "Rand" : randomwalk. set stepsize and speed as you like. always linked in groups.
- "Mirror": mirror current source position. not linked in groups.
- "Position" : x and y position, distance and angle of selected source.

*** OPTION PANEL ***

- "Session.." : load & save a session to .txt. if you want to overwrite a file, remove the .txt extension
- "Out Meters" : output metering
- "View.." : view options
- "Snapshots" : open snapshot window. always use same number of sources. do not make a snapshot and then add sources, this will fail in recall.
- "FX Settings" : open fx setting panel.

*** MASTER PANEL ***

- "Level" : master out volume
- "Offset": offset master out

*** Contact: dominik.wegmann@tonmeister.de ***

