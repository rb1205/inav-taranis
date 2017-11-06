# Readme

A LUA telemetry script derived from the very fine [LuaPilot](https://github.com/ilihack/LuaPilot_Taranis_Telemetry) to work with SmartPort telemetry data from [inav](https://github.com/iNavFlight/inav) on Taranis.

![Screenshot](ss_inav-taranis.png)

The script displays the current flight mode, the battery level, the RSSI signal feedback and some additional telemetry data (see screenshot).

It provides some audible feedbacks: armed/disarmed, entered/exited failsafe, GPS lock acquired/lost, started/ended autonomus flight, ready to arm, home reset, low/critical battery. You can customize the alarms by editing the WAV files in the SCRIPT/SOUNDS directory, make sure you're using WAV files with a format [compatible to OpenTX](https://opentx.gitbooks.io/manual-for-opentx-2-2/content/advanced/audio.html) or they won't play. The audible alarm will work regardless if the GUI is displayed or not.

Furthermore, it displays the last GPS value from the craft to aid in case of lost models.

Theis script works with OpenTX 2.2 and has been updated with the recent changes to SPort telemetry in inav 1.8.
