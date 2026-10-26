# Companion checks

No Warcraft III needed. The game module has its own tests: `native\tests\run-tests.bat`.

```
powershell -ExecutionPolicy Bypass -File companion\tests\run-checks.ps1          all of them
powershell -ExecutionPolicy Bypass -File companion\tests\run-checks.ps1 pages    one
```

- **/validate**: `tw-companion.ahk` loads (load-time errors only).
- **checks\\*.ahk**: each runs inside the companion through `mkprev.py --check <name>`: a temp ini
  (`%TEMP%\twc-preview.ini`, never the real one), no elevation, and `TwcCheck(ok, msg)` /
  `TwcCheckDone()` writing `%TEMP%\twc-check-<name>.txt`; any error fails the check.
  - `startup`: runs 8 s without an error (a local shadowing a global, case-insensitively).
  - `pages`: every page, every WC3 version / tab / pager page, the Module check window.
  - `module`: a stand-in game module (a buffer in `engine\GameLayout.ahk`'s layout, every feature on)
    behind an off-screen "Warcraft III" window of its own: every status line and push.
  - `quickcast`: the screen quickcast's setup format and colour tuning.
- **chatpaste**: `chatpaste.py` copies the chat paste out of `lib\Common.ahk` with SendInput stubbed;
  the clipboard is saved first and put back.

Rules for new checks: never send keys or activate a game window; a check that touches the clipboard
saves it first and restores it on error too; names of functions and globals must not match each other
(AHK names ignore case: `PrevShm()` vs `prevShm` won't load).

**Previews**: `preview.ps1 <extra.ahk> <out.png>`: the extra code writes the hwnd of the window to
capture to `%TEMP%\twc-prev2.log` and ends the preview itself; `shot.ps1` takes the picture with
PrintWindow (that window only).
