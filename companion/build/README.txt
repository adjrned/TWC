TW Companion {VERSION}
======================

Install
  Run TWC-Companion-Setup-{VERSION}.exe and press Install. No admin rights
  needed: it installs for you only, into %LOCALAPPDATA%\Programs\TW Companion,
  with a Start Menu shortcut (and a desktop one if you tick it).

  Windows SmartScreen or your antivirus may warn about an unknown app. That
  is normal for small unsigned tools built with AutoHotkey.
  SmartScreen: "More info" > "Run anyway".

  When TW Companion starts, Windows asks for admin rights: Warcraft III
  usually runs as admin, and the companion has to match to send keys to it.

  Run Warcraft III in Windowed Fullscreen (or windowed) so the companion can
  draw over it and read the screen for quickcast.

  (Or, without installing: unzip TWC-Companion-{VERSION}.zip anywhere and run
  TW Companion.exe. Keep the files together.)

Update
  Run the new Setup and press Update. Your settings (tw-companion.ini), hidden
  saves and quickcast setup are kept.

Uninstall
  Windows Settings > Apps > TW Companion > Uninstall. Your Warcraft III save
  files are not touched.

Keys
  F8           show / hide the window
  Hold Esc     pause / resume remaps and macros (1.5 s, in Warcraft III)
  Shift+Space  TWRPG overlay (in Warcraft III)
  Alt+Esc      quit

This is a beta: please report bugs to Ruzai. If something misbehaves: tray
icon > "Debug: show status in game", and send companion-debug.log from the
install folder.
