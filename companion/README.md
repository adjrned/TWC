# TW Companion

A light TWRPG loader / helper for Warcraft III, styled like the TWRPG site
(dark neutral surfaces, one orange accent, Cinzel headings). Pure
**AutoHotkey v2** — a borderless window on a baked background with native
controls on top. It opens instantly and uses almost no
memory, since it's meant to be flashed open, load a save, and close.

## Requirements

- [AutoHotkey v2](https://www.autohotkey.com/) (v2.0+).
- Warcraft III with TWRPG.

The companion window itself is pure AHK. The **TWRPG overlay** additionally uses
the Microsoft Edge WebView2 Runtime (built into Windows 11; on Windows 10 install
it from Microsoft if the overlay won't start). Warcraft III must run in
**Windowed Fullscreen** (or windowed) for anything to draw over it.

## Install (players)

Download `TWC-Companion-<version>.zip`, unzip it anywhere and run
**`TW Companion.exe`**: no AutoHotkey install needed. The zip's `README.txt`
covers SmartScreen, updating (unzip over the old folder; settings are kept) and
uninstalling.

## Build the zip

```
powershell -ExecutionPolicy Bypass -File companion\build\build.ps1
```

Compiles `tw-companion.ahk` with Ahk2Exe (downloaded into `build\.tools` on
the first run) and zips it with `assets\`, the WebView2 loader DLL and
`build\README.txt` into `companion\dist\`. The version comes from
`global version` in `tw-companion.ahk`.

## Run from source

Running `tw-companion.ahk` (not the exe), the companion keeps itself on the
latest commit of the `beta` branch: on start and every 5 minutes it compares
its files with GitHub's (by git blob hash), downloads only the changed ones
and restarts (in the middle of a game: once Warcraft III isn't focused). Tray
menu: *Check for companion updates*. Settings, `HiddenFiles.txt` and `web\`
are never touched. `[SelfUpdate] branch=` / `auto=0` in the ini change the
branch or turn it off; a `.no-self-update` file next to the script turns it
off too (for a dev checkout whose files are ahead of GitHub).

Double-click **`tw-companion.ahk`**. It relaunches itself as admin (WC3 Reforged
usually runs elevated, and key sends need matching elevation).

- Settings persist to `tw-companion.ini` (next to the script).
- Hidden files persist to `HiddenFiles.txt`.

## Control hotkeys (fixed)

| Key | Action | Where |
|-----|--------|-------|
| `F10` | pause / resume remaps and macros | in WC3 |
| `F8`  | show/hide the window | anywhere |
| `Pause` | pause the game | in WC3 |
| `Esc` | hide the window | window focused |
| `Alt+Esc` | exit | anywhere |
| `Shift+Space` | show/hide the TWRPG overlay | in WC3 / overlay |
| `Ctrl+Shift+Space` | pin the overlay (see-through, click-through) | in WC3 / overlay |

Remaps and macros are always on, except while the WC3 chat box is open, so
typing is never interrupted. The companion follows `Enter` / `Esc` / clicks and
also checks the chat box on screen 5 times a second (its gold border; the place
is known for 1.28 at 1920x1080 and found by itself the first time chat opens
elsewhere), which corrects the tracking when chat is opened or closed some
other way.
`F10` (or the sidebar's On | Off) pauses them by hand, with a short toast.

## Sections (nav in the window)

- **Loader** (default) — your saves as a list like the site's item rows:
  click ☆ to make a save a favourite (★ saves stay on top, the rest are newest
  first), click the eye to hide one (**Show hidden** brings them back, dimmed).
  Select a save to edit its **load message**: a chat line sent when it loads;
  separate options with `|` and one is picked at random each time. The ⓘ next
  to the field explains it, and the text beside it shows what will be sent
  (nothing / once per load / N options picked at random). Double-click,
  Enter or **LOAD** loads the selected save (arrows / PgUp / PgDn / wheel to move).
  `-convert <name>` is sent automatically (turn it off under Settings).
  **In-game commands** (also under the **?** next to search): type in WC3 chat
  - `-l sniper` / `-load sniper`: the closest match (exact name, then starts
    with, then contains; favourites, then newest, win ties)
  - `-l 2`: your 2nd ★ favourite (numbers beyond your favourites match names,
    so `-l 92` finds `knight#92`)
  - `-l`, `-ll`, `-loadlast`: the save you loaded last
  - `-sn` / `-savenext` (optionally `-sn <name>`): types `-save <next number>`
    for the save you loaded through the companion this session, e.g.
    `-save knight#93` after `knight#92` (not one remembered from an earlier day:
    you may be on another hero). TWRPG's `-save` drops spaces and saves
    lowercase (`-save Sorc 3` writes `sorc3.txt`), so `-sn` types names that
    way, and `-l` ignores spaces when matching (`-l sorc 3` finds `sorc3`)

  **Numbered saves.** Saves ending in a number (`knight#91`, `knight#92`, or
  `sniper_007`) are one *series*: a single row showing the newest number with a
  "N saves ▸" badge (click it to list the older ones), and one star, hide toggle
  and load message for the whole series. `-l knight` loads the newest number.
  `-sn` uses the highest number on disk + 1, so loading an older save and saving
  again never overwrites a newer one; your separator and zero padding are kept
  (`sniper_007` → `sniper_008`).

  These never reach chat. The companion records what you type in WC3 (only while
  WC3 is focused) since the last Enter/Esc/click; if a line is exactly a loader
  command, the chat box is emptied and closed and the command runs. Anything
  else is sent normally. This works in game and in the lobby, and doesn't depend
  on tracking whether chat is open. During a load, keyboard and mouse are held
  for the second or two it takes, so nothing you press lands inside the codes.
  Loading types your codes in chat, so only load once you're in the game.
  The save folder is found automatically: `Documents\Warcraft III\CustomMapData\TWRPG`
  (also when Documents is redirected to OneDrive, and the Public Test realm), or
  `<install folder>\CustomMapData\TWRPG` for classic 1.26/1.27 (from the registry
  or a running game). The first one holding TWRPG saves wins. A folder you pick
  under Settings overrides it until you press **Auto-detect**.
- **Remap** — your own keys for the WC3 HUD: the Command Card (TWRPG's layout:
  Move Stop Hold Attack / Patrol D T F / Q W E R), inventory slots 1–6
  (Numpad 7 8 4 5 1 2) and both mouse buttons. *HUD* shows them laid out
  like the game (click a slot, press a key); *List* is the same as a table.
  Unset slots keep the game's key; Shift + your key still queues; a key can
  only be on one slot (setting it again moves it), and keys the companion
  uses (F8, F10, macros, overlay) are refused. Esc or Backspace (or *Clear*)
  clears a slot. The QC pill on a slot (or right-click) toggles its quickcast. Remaps are live whenever the tool is On.
  **Quickcast** casts at the cursor; held, it repeats (every 40 ms by default).
  *Quickcast setup* on the toolbar runs a one-time setup in game (Insert three
  times: over Move, over the bottom-right button, then while a skill waits for
  a target), per game version and window size. After that the companion clicks
  only when the command card shows the game is waiting for a target, read from
  the screen, no injection, same on 1.28 and Reforged. Without a setup it uses
  LCH's method (selection saved to control groups 9 and 0 around each cast).
- **Macros** — hotkey → chat-line macros (seeded with `-recall`, `-a`,
  `-chest im lagging`, GET GOOD). Message is multi-line: one chat line per row.
- **Host** — whisper a host bot for private/public lobbies with a `+1` game-name
  incrementer. In-game: `-h`/`-host`, `-hp`/`-hostpub`.
- **Settings** — startup behaviour, load timing, TWRPG folder, reset.
- **Overlay** — hotkeys, dock side, opacity, unload timer, update options.

## TWRPG overlay

The TWRPG site (build planner, items, tracker, monsters, heroes, effects, patch
notes) in a panel docked over the game, like Path of Exile's Awakened Trade:

- `Shift+Space` in Warcraft III opens it focused; `Shift+Space` again, `Esc`,
  clicking back into the game, or switching apps hides it and gives the game
  focus back. `Esc` first closes whatever is open in the page (menus, pickers,
  search) and only hides the panel when there's nothing left to close.
- `Ctrl+Shift+Space` **pins** it: it stays on screen semi-transparent and
  clicks go through to the game, as a reference while you play.
  `Shift+Space` unpins it.
- The hotkeys are off while you type in WC3 chat, so `Shift+Space` stays a space.
- Docks right by default (left / full on the Overlay page); drag the inner
  edge to resize. Width, zoom (`Ctrl+wheel`) and the last page are remembered.
- Works fully **offline**: the site is bundled in `web/TWC` and served locally
  as `https://twc.local/TWC/`. Your planner/tracker data is stored in
  `%AppData%\tw-companion\webview` (separate from the website's).
- Links to other sites open in your normal browser; share links point at the
  public site.
- The WebView starts on first use and closes after being hidden for 10 minutes
  (configurable), so it uses no memory until you need it.

### Updates

**Update data now** (Overlay page), **Check for updates** (overlay sidebar) or
the tray menu downloads the latest site from GitHub Pages. Only changed files are
downloaded; each is checked against its SHA-256 from `overlay-manifest.txt`, then
the new copy replaces `web/TWC` in one move (the old one is kept if anything fails).
On start it checks quietly and tells you when there's an update (or installs it
with *Install updates automatically*). The source URL is `updateUrl` under
`[Overlay]` in `tw-companion.ini`.

To refresh the bundle from a local checkout of the site instead:
`npm run overlay` at the repo root (builds the site and copies `dist/` into `companion/web/TWC`).

## Architecture

```
tw-companion.ahk    window (baked-bg + native controls), pages, hotkeys, wiring
lib/Common.ahk      helpers, INI, InputHook, RegisterHotkey
lib/WebView2/       thqby's WebView2.ahk (MIT) + Microsoft's WebView2Loader.dll
lib/ComVar.ahk, lib/Promise.ahk   its dependencies
engine/             GUI-free logic that the window calls directly:
  Loader Remap Quickcast ChatBox Macros Host Settings Updater SelfUpdate
ui/OverlayPanel.ahk the WebView2 overlay window (hotkeys, docking, pin, messages)
web/TWC/            offline copy of the TWRPG site (managed by the updater)
assets/bg.png       pre-rendered page + card panel + TWRPG wordmark
assets/Cinzel.ttf   the site's display font (OFL, see Cinzel-OFL.txt), loaded
                    privately at startup for section titles
```

The window is one borderless Gui laid out like the site: a sidebar with the
TWCompanion wordmark, icon + label nav (the active link tinted, with an orange
icon and an accent bar on the sidebar edge) and a footer with the tool ON/OFF
switch; then the page background with a compact toolbar row (Cinzel page
title plus that page's main controls, e.g. the Loader's search) over a divider. A full-size `Picture` shows `assets/bg.png`, and native controls sit
on top. Native borders are dropped: `Box` draws a filled, bordered, rounded
rectangle *behind* a control (Text controls slotted after the picture in the
z-order, rounded with a window region), so inputs get the site's `--bg2` field
with a `--border2` edge, lists sit in a `--card`, and buttons look like `.btn`.
Pages are built at (40, 160) and shifted into the content area, and shown by
toggling control visibility. The engine classes are plain AHK objects the
window calls directly — no IPC, no bridge.

### Regenerating the background

`assets/bg.png` is 880×510 and matches the window layout (`W`, `H`, `SIDE_W`,
`CX` in `tw-companion.ahk`). To tweak it, edit and
run `assets/generate_bg.py` (Pillow) from the `assets/` folder. Its colours are the
site's tokens from `src/styles/base.css`, the same ones as the `C` palette in
`tw-companion.ahk`; keep the two in step if the site's theme changes.
