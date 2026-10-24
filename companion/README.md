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

## Run

Double-click **`tw-companion.ahk`**. It relaunches itself as admin (WC3 Reforged
usually runs elevated, and key sends need matching elevation).

- Settings persist to `tw-companion.ini` (next to the script).
- Hidden files persist to `HiddenFiles.txt`.

## Control hotkeys (fixed)

| Key | Action | Where |
|-----|--------|-------|
| `F10` | toggle the tool on/off | in WC3 |
| `F8`  | show/hide the window | anywhere |
| `Pause` | pause the game | in WC3 |
| `Esc` | hide the window | window focused |
| `Alt+Esc` | exit | anywhere |
| `Shift+Space` | show/hide the TWRPG overlay | in WC3 / overlay |
| `Ctrl+Shift+Space` | pin the overlay (see-through, click-through) | in WC3 / overlay |

A tiny always-on-top overlay (top-left) shows the tool state. When the tool is
OFF, remap/macro hotkeys are suspended. With *Auto-disable while chatting* on
(default), pressing `Enter` in WC3 temporarily suspends the tool so macro keys
don't fire mid-message.

## Sections (nav in the window)

- **Loader** (default) — your saves as a list like the site's item rows:
  click ☆ to make a save a favourite (★ saves stay on top, the rest are newest
  first), click the eye to hide one (**Show hidden** brings them back, dimmed).
  Select a save to edit its **load message**: a chat line sent when it loads;
  separate options with `|` and one is picked at random each time. Double-click,
  Enter or **LOAD** loads the selected save (arrows / PgUp / PgDn / wheel to move).
  `-convert <name>` is sent automatically (turn it off under Settings).
  **In-game commands** (also under the **?** next to search): type in WC3 chat
  - `-l sniper` / `-load sniper`: the closest match (exact name, then starts
    with, then contains; favourites, then newest, win ties)
  - `-l 2`: your 2nd ★ favourite
  - `-l`, `-ll`, `-loadlast`: the save you loaded last

  These never reach chat: while chat is open the companion records the line, and
  on Enter a loader command is closed with Esc and run instead. Anything else is
  sent normally.
  The save folder is found automatically: `Documents\Warcraft III\CustomMapData\TWRPG`
  (also when Documents is redirected to OneDrive, and the Public Test realm), or
  `<install folder>\CustomMapData\TWRPG` for classic 1.26/1.27 (from the registry
  or a running game). The first one holding TWRPG saves wins. A folder you pick
  under Settings overrides it until you press **Auto-detect**.
- **Macros** — hotkey → chat-line macros (seeded with `-recall`, `-a`,
  `-chest im lagging`, GET GOOD). Message is multi-line: one chat line per row.
- **Remap** — remap 12 spells / 6 inventory / 2 mouse inputs with per-spell
  quickcast; select a row and use *Set Your Key* / *Set Game Key* / *Toggle QC*,
  plus per-group enable checkboxes.
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
  Loader Macros Remap Host Settings Updater
ui/OverlayPanel.ahk the WebView2 overlay window (hotkeys, docking, pin, messages)
web/TWC/            offline copy of the TWRPG site (managed by the updater)
assets/bg.png       pre-rendered page + card panel + TWRPG wordmark
assets/Cinzel.ttf   the site's display font (OFL, see Cinzel-OFL.txt), loaded
                    privately at startup for section titles
```

The window is one borderless Gui laid out like the site: a sidebar with the
TWCompanion wordmark, icon + label nav (the active link tinted, with an orange
icon and an accent bar on the sidebar edge) and a footer with the tool ON/OFF
switch; then the page background with a page header (Cinzel title, subtitle,
divider). A full-size `Picture` shows `assets/bg.png`, and native controls sit
on top. Native borders are dropped: `Box` draws a filled, bordered, rounded
rectangle *behind* a control (Text controls slotted after the picture in the
z-order, rounded with a window region), so inputs get the site's `--bg2` field
with a `--border2` edge, lists sit in a `--card`, and buttons look like `.btn`.
Pages are built at (40, 160) and shifted into the content area, and shown by
toggling control visibility. The engine classes are plain AHK objects the
window calls directly — no IPC, no bridge.

### Regenerating the background

`assets/bg.png` is 920×510 and matches the window layout (`W`, `H`, `SIDE_W`,
`CX` in `tw-companion.ahk`). To tweak it, edit and
run `assets/generate_bg.py` (Pillow) from the `assets/` folder. Its colours are the
site's tokens from `src/styles/base.css`, the same ones as the `C` palette in
`tw-companion.ahk`; keep the two in step if the site's theme changes.
