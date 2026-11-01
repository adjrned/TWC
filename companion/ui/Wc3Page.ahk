#Requires AutoHotkey v2.0
; ============================================================================
;  WC3 page - features that read or change the running game, in one place.
;  At the top right, the version switch: 1.28f | Reforged. The page shows only what
;  works on that version (and "Both" features); opening the page picks the
;  running game's version. 1.28f features use the game module (injected;
;  its row is only on the 1.28f side); Reforged ones only read the screen.
;  Three tabs set where every feature goes, now and later (quickcast is on
;  the Remap page, with its keys: a switch and Options per version):
;    Timers    what's ready and what's running out: timers in the game
;              (cooldowns, buff seconds), buff alerts
;    Display   how the game looks: health & mana bars (size, colours, numbers,
;              mana bars, the portrait), game keys, hiding the UI, widescreen
;              (world and UI), the buff bar, fast menu, detailed tooltips, FPS
;    Combat    allies' and bosses' cards, pings, boss timers
;    Hosting   games you host: lobby latency, the start countdown; logging in
;              to Battle.net (eurobattle.net) by itself
;  Each feature is one entry in Wc3Features(): a compact card (two columns)
;  with its version badge, its On/Off switch, an Options button under it
;  that opens the feature's own window, and a short status line; hovering a
;  card shows what it does and its full status on the line at the bottom.
;  Built in the pages' (40, 160) layout space like the other pages. A tab
;  with more cards than fit shows them in pages (‹ n/m › in the tab row).
; ============================================================================

global wc3Tab := "display", wc3TabBtns := Map(), wc3Cards := [], wc3ModuleBtn, wc3ModuleText, wc3Planned
; the page is 1.28f's only for now (the user, 2026-11-01: the 1.28f | Reforged switch is gone; the Reforged side's
; cards and lines stay in the code, for when it comes back: Wc3Versions)
global wc3Ver := "128", wc3ModuleRow := []
global wc3PageNo := Map(), wc3PagerCtls := [], wc3PagerText       ; tab + version -> the page shown
global wc3HoverCard := 0                                           ; the card under the cursor
global WC3_COL_W := 335, WC3_CARD_H := 48, WC3_ROW := 54

Wc3Tabs() => [["display", "Display"], ["timers", "Timers"], ["combat", "Combat"], ["hosting", "Hosting"]]
; the two versions: key, switch label
Wc3Versions() => [["128", "1.28f"]]                ; (["reforged", "Reforged"] when its side comes back)
Wc3VerBadge(ver) => ver = "128" ? "1.28f" : "Reforged"
; the running game's version ("128" / "reforged"), "" if none
Wc3RunningVer() => (k := WC3WindowKey()) = "" ? "" : InStr(k, "reforged") = 1 ? "reforged" : "128"
; does a feature show on the version in view?
Wc3OnVersion(f, ver) => f.badge = "Both" || f.badge = Wc3VerBadge(ver)
; its badge on the version in view: "1.28f", or "1.28f · WIP" for one still being worked on (wip: true) and
; for everything on the Reforged side (the user, 2026-10-31, readying the public beta: Reforged is experimental)
; (with only 1.28f on the page, no "1.28f" on every card: only WIP shows)
Wc3BadgeText(f, ver) => (f.HasProp("wip") && f.wip) || ver = "reforged" ? "WIP" : ""

; what each tab will hold later on each version (on the line at the bottom)
Wc3PlannedText(tab, ver) {
    static p := Map(
        "timers128", "",
        "timersreforged", "Planned: cooldown and buff timers read from the screen. To help build them: tray menu > Debug: save HUD pictures, in a game, then send the folder.",
        "display128", "",
        "displayreforged", "Nothing planned yet.",
        "combat128", "",
        "combatreforged", "Nothing planned yet.",
        "hosting128", "",
        "hostingreforged", "Nothing planned: Battle.net hosts Reforged games.")
    return p[tab ver]
}

; parts loaded besides (none in the shipped companion): what they add when the companion starts, and their
; cards on this page (as Wc3Features' entries, after the page's own)
class Extensions {
    static onStart := []
    static wc3Features := []
}

; Every feature on the page. Keys: tab, title, badge ("1.28f" / "Reforged" /
; "Both"), wip (true: still being worked on, "· WIP" on its badge), desc (what it does: the hover line and its window's intro),
; status() -> text; optional on() / set(v) for the switch, and either
; opts(d) (rows added to the feature's standard Options window, see Opt*)
; or window() (a window of its own).
Wc3Features() {
    global gameModule, timersHud, quickcast, gameCmds, buffWatch, healthBars, gameDisplay, bnetLogin
    static list := 0
    if list
        return list
    list := [
        ; buff seconds and cooldowns, a card each, buffs first (the user, 2026-11-01); every note right under the
        ; option it explains; "Turn Red" (red near the end: the module's warning colour, was gold; ini keys keep *Gold)
        { tab: "timers", title: "Buff Timers", badge: "1.28f",
            desc: "Seconds left on your buffs, under the buff icons.",
            on: (*) => timersHud.buffs, set: (v) => timersHud.setBuffs(v), status: (*) => timersHud.buffStatus(),
            reset: (*) => timersHud.resetLook("buffs"),
            opts: (d) => (OptSlider(d, "Size", (*) => timersHud.bfSize, (v) => timersHud.setBfSize(v), 0.75, 1.5, 0.05, BarSizeText),
                OptSlider(d, "Turn Red", (*) => timersHud.bfGold, (v) => timersHud.setBfGold(v), 0, 30, 1),
                OptNote(d, "The seconds turn red when this many are left (0: never)."),
                OptToggle(d, "Show Minutes (1:35, not 95)", timersHud.buffMinutes, (v) => timersHud.setMinutes("buffMinutes", v)),
                OptToggle(d, "Aura Countdown", timersHud.bfAuras, (v) => timersHud.setBfAuras(v)),
                OptNote(d, "Auras show no timer while you're in range. When you step out of range, this shows the seconds until the aura's effect wears off.")) },
        { tab: "timers", title: "CD Timers", badge: "1.28f",
            desc: "Seconds left on your abilities and items, on their buttons.",
            on: (*) => timersHud.cooldowns, set: (v) => timersHud.setCooldowns(v), status: (*) => timersHud.cooldownStatus(),
            reset: (*) => timersHud.resetLook("cds"),
            opts: (d) => (OptSlider(d, "Size", (*) => timersHud.cdSize, (v) => timersHud.setCdSize(v), 0.75, 1.5, 0.05, BarSizeText),
                OptSlider(d, "Turn Red", (*) => timersHud.cdGold, (v) => timersHud.setCdGold(v), 0, 30, 1),
                OptNote(d, "The seconds turn red when this many are left (0: never)."),
                OptToggle(d, "Show Minutes (1:35, not 95)", timersHud.cdMinutes, (v) => timersHud.setMinutes("cdMinutes", v)),
                OptToggle(d, "Ready Flash", timersHud.cdReady, (v) => timersHud.setCdReady(v)),
                OptNote(d, "A green 'Ready' for a moment when a cooldown ends."),
                OptToggle(d, "Plain Sweep", timersHud.cdSweep, (v) => timersHud.setCdSweep(v)),
                OptNote(d, "Replaces TWRPG's clock on the button with a plain dark sweep.")) },
        { tab: "timers", title: "Buff Alerts", badge: "Both",
            desc: "A line over the game when a buff on your hero is missing or running out.",
            on: (*) => buffWatch.enabled, set: (v) => buffWatch.setEnabled(v), status: (*) => buffWatch.statusText(),
            window: (*) => BuffWatchDialog() },
        ; the bars in one card: size, colours, numbers; mana bars are always there (the user, 2026-11-01)
        { tab: "display", title: "Health and Mana Bars", badge: "1.28f",
            desc: "Size and colors of the bars, numbers over them; mana bars under them.",
            reset: (*) => healthBars.reset(),
            status: (*) => Wc3Both([[healthBars.enabled, "Size", (*) => healthBars.statusText()], [healthBars.colours, "Colours", (*) => healthBars.colourStatus()],
                [healthBars.numbers, "Numbers", (*) => healthBars.numberStatus()], [healthBars.mana, "Mana bars", (*) => healthBars.manaStatus()]]),
            ; each switch with its own window's button on its row (Size… sat under the colours' switch, the user), both
            ; named Options; titles in title case, US spelling here (the user's "Health Bar Colors")
            opts: (d) => (OptToggle(d, "Health and Mana Size", healthBars.enabled, (v) => healthBars.setEnabled(v), 0, ["Options", (*) => BarSizeDialog()]),
                OptToggle(d, "Health Bar Colors", healthBars.colours, (v) => healthBars.setColours(v), 0, ["Options", (*) => BarColoursDialog()]),
                OptDivider(d),
                OptToggle(d, "Health Bar Numbers", healthBars.numbers, (v) => healthBars.setNumbers(v)),
                OptChoice(d, "Value", [[1, "Total"], [2, "Truncated"], [3, "Percent"]], (*) => healthBars.numberMode, (v) => healthBars.setNumberMode(v)),
                OptNote(d, "Total: 13000. Truncated: 13k. Percent: 65%."),
                OptChoice(d, "Color", HealthBarsEngine.NUMBER_COLOURS, (*) => healthBars.numberColour, (v) => healthBars.setNumberColour(v)),
                OptSwatch(d, "Custom Color", (*) => healthBars.numberCustom, (g) => (rgb := ChooseColour(g.Hwnd, healthBars.numberCustom)) != "" ? (healthBars.setNumberCustom(rgb), rgb) : ""),
                OptNote(d, "Dynamic: green, to yellow at half, to red. Owner: its bar's color (Health Bar Colors above). Custom: the swatch's."),
                OptToggles(d, "Display", HealthBarsEngine.NUMBER_WHO, (key) => healthBars.numberShows(key), (key, on) => healthBars.setNumberShows(key, on))) },
        { tab: "display", title: "Game Keys", badge: "1.28f",
            desc: "Keys that wipe the trigger messages or the chat, and minimise the multiboard.",
            on: (*) => gameCmds.enabled, set: (v) => gameCmds.setEnabled(v), status: (*) => gameCmds.statusText(),
            opts: (d) => (OptKey(d, "Clear messages", "clearMessages"), OptKey(d, "Clear chat", "clearChat"), OptKey(d, "Multiboard", "multiboard"),
                OptNote(d, "Esc while setting one: no key.")) },
        { tab: "display", title: "Hide the UI", badge: "1.28f",
            ; plain words (the user, 2026-11-01: the old ones were confusing): what goes, what stays, what each option does
            desc: "Removes the black console and the top bars, so you see more of the map.",
            on: (*) => gameDisplay.hideUi, set: (v) => gameDisplay.setHideUi(v), status: (*) => gameDisplay.hideStatus(),
            opts: (d) => (OptNote(d, "Hidden: the console's black frame, the clock, the gold and lumber bar and the idle worker button. "
                    . "Kept: the minimap, portrait, command card, inventory and buffs."),
                OptDivider(d),
                ; both as what stays on screen (the user's names): On = shown, the opposite of the ini's hideMenu / coverOff
                OptToggle(d, "Show Upper Menu Bar", !gameDisplay.hideMenu, (v) => gameDisplay.setHideMenu(!v)),
                OptNote(d, "The Quests, Menu, Allies and Log buttons at the top. Off: hidden with the rest."),
                OptDivider(d),
                OptToggle(d, "Show Inventory Cover", !gameDisplay.coverOff, (v) => gameDisplay.setCoverOff(!v)),
                OptNote(d, "The art over the inventory of a unit that has none. Off: empty slots instead, even with the card switched off.")) },
        ; the world, the UI and the cursor in one card (WFE's widescreen, Upgraded UI, Slim Cursor); plain words,
        ; no WFE names (the user, 2026-11-01: the settings were confusing)
        { tab: "display", title: "Widescreen", badge: "1.28f",
            desc: "Fixes the stretched look on a wide screen: the view, the UI and the cursor.",
            status: (*) => Wc3Both([[gameDisplay.widescreen, "View", (*) => gameDisplay.wsStatus()], [gameDisplay.wideUi, "UI", (*) => gameDisplay.wideUiStatus()],
                [gameDisplay.slimCursor, "Cursor", (*) => gameDisplay.slimCursorStatus()]]),
            opts: (d) => (OptToggle(d, "Wide View", gameDisplay.widescreen, (v) => gameDisplay.setWidescreen(v)),
                OptNote(d, "See more of the map at the sides, without stretching. Left off by itself if another widescreen mod already does it."),
                OptToggle(d, "Wide UI", gameDisplay.wideUi, (v) => gameDisplay.setWideUi(v)),
                OptNote(d, "The command card, inventory, minimap and unit panel keep their normal shape."),
                OptToggle(d, "Normal Cursor", gameDisplay.slimCursor, (v) => gameDisplay.setSlimCursor(v)),
                OptNote(d, "The mouse cursor keeps its normal shape, in menus and in games.")) },
        ; the buff bar's own settings in one place (the user's ask, 2026-10-30: the raise sat in the Widescreen UI's
        ; Options): the switch is the bigger size; the raise is on its own (the module's, or the Widescreen UI's layout when that's on)
        { tab: "display", title: "Buff Bar", badge: "1.28f",
            desc: "The buff bar bigger (x1 to x2), and raised over the console.",
            on: (*) => gameDisplay.buffBar, set: (v) => gameDisplay.setBuffBar(v), status: (*) => gameDisplay.buffBarStatus(),
            opts: (d) => (OptSlider(d, "Size", (*) => gameDisplay.buffBarScale, (v) => gameDisplay.setBuffBarScale(v), 1, 2, 0.05, BarSizeText),
                OptNote(d, "Times the game's own size (the card's switch). Still 8 buffs at most: the game has 8 buff icons. With Wide UI on (Widescreen card), it grows to the right instead."),
                OptDivider(d),
                OptToggle(d, "Raise the buff bar over the console", gameDisplay.buffBarUp, (v) => gameDisplay.setBuffBarUp(v)),
                OptNote(d, "The buffs float above the command card, without their label. Works whatever this card's switch is.")) },
        { tab: "display", title: "Hide Hover Names", badge: "1.28f",
            desc: "No name pops up over the unit under the mouse.",
            on: (*) => gameDisplay.unitNames, set: (v) => gameDisplay.setUnitNames(v), status: (*) => gameDisplay.unitNamesStatus() },
        { tab: "display", title: "Fast Menu", badge: "1.28f",
            desc: "Menu screens switch instantly, with no slide-in animations.",
            on: (*) => gameDisplay.fastMenu, set: (v) => gameDisplay.setFastMenu(v), status: (*) => gameDisplay.fastMenuStatus(),
            opts: (d) => (OptToggle(d, "Bring Game to Front", gameDisplay.toFront, (v) => gameDisplay.setToFront(v)),
                OptNote(d, "When a game starts while Warcraft III is behind other windows or minimised, it comes to the front. Works even with the card switched off.")) },
        { tab: "display", title: "Detailed Tooltips", badge: "1.28f",
            desc: "The damage and armor tooltips also show cooldown, attacks a second and speed.",
            on: (*) => gameDisplay.tooltips, set: (v) => gameDisplay.setTooltips(v), status: (*) => gameDisplay.tooltipsStatus() },
        { tab: "display", title: "FPS Unlock", badge: "1.28f",
            desc: "Lifts the game's frame rate cap, up to the limit you pick. Off puts it back.",
            on: (*) => gameDisplay.fps, set: (v) => gameDisplay.setFps(v), status: (*) => gameDisplay.fpsStatus(),
            opts: (d) => (OptSlider(d, "Limit", (*) => gameDisplay.fpsLimit, (v) => gameDisplay.setFpsLimit(v), 64, 1000, 1),
                OptNote(d, "Frames a second, 64 to 1000.")) },
        ; out of the Cooldowns' Options (the user's cleanup): cards of their own, on the Combat tab
        { tab: "combat", title: "Allies' and Bosses' Cards", badge: "1.28f",
            desc: "An ally's or a boss's unit selected: its abilities and cooldowns on the card.",
            on: (*) => timersHud.allies, set: (v) => timersHud.setAllies(v), status: (*) => timersHud.alliesStatus(),
            opts: (d) => (OptToggle(d, "Enemies' too (bosses, creeps)", timersHud.alliesEnemies, (v) => timersHud.setAlliesEnemies(v)),
                OptNote(d, "Shown as an observer sees it. Clicking their buttons does nothing. A boss TWRPG holds paused until it's engaged shows an empty card till then.")) },
        { tab: "combat", title: "Pings", badge: "1.28f",
            desc: "Alt + click an ability, item, buff, stat or the portrait: your allies are told.",
            on: (*) => timersHud.pings, set: (v) => timersHud.setPings(v), status: (*) => timersHud.pingStatus(),
            opts: (d) => OptNote(d, "Sent to your allies (who gets it: the game's Chat dialog):`n'Paladin >> Holy Light | Cooldown: 7', '| Ready!' or '| Not enough mana!'`na buff: 'Paladin >> Inner Fire | 12 s left' or '| active'`nthe portrait: HP and mana (and a hero's level); the damage, armor and hero icons: their numbers.`nYour units', allies' and enemies'.") },
        { tab: "combat", title: "Boss Timers", badge: "1.28f", wip: true,
            desc: "Learns each boss's spells over your attempts and counts down to the next ones.",
            on: (*) => bossBars.enabled, set: (v) => bossBars.setEnabled(v), status: (*) => bossBars.statusText(),
            opts: (d) => (OptSlider(d, "Rows", (*) => bossBars.rowCount, (v) => bossBars.setNumber("rows", v, 3, 8, true), 3, 8, 1),
                OptSlider(d, "Warn at", (*) => bossBars.warnSecs, (v) => bossBars.setNumber("warn", v, 0, 10), 0, 10, 0.5, SecsText),
                OptNote(d, "A bar turns red this long before its spell (an HP mark: within 5%)."),
                OptSlider(d, "Bosses from", (*) => bossBars.minHp, (v) => bossBars.setNumber("minHp", v, 0, 1000000), 0, 100000, 1000),
                OptNote(d, "HP: an enemy with less isn't timed (its minions). The meter's pinned unit always is."),
                OptSlider(d, "Opacity", (*) => bossBars.opacity, (v) => (bossBars.setNumber("opacity", v, 30, 100), bossBars.rebuild(), true), 30, 100, 1),
                OptNote(d, "Each attempt teaches it: when each spell first came (from the first hit, and at what HP) and how often after. The first attempt only learns; '~' means the times spread; 'at 50%' a spell that comes at an HP mark."),
                OptDivider(d),
                OptButtons(d, [["Show the timers", (*) => (bossBars.setHidden(false), RefreshWc3())], ["Show a sample", (*) => bossBars.setSample(true)], ["Hide the sample", (*) => bossBars.setSample(false)],
                    ["Forget all", (*) => (MsgBox("Forget what the boss timers learned about every boss?", "TW Companion", "YesNo 0x40000") = "Yes" ? (bossBars.forget(), RefreshWc3()) : 0)]]),
                OptNote(d, "It comes up by itself when you hit a boss or it casts. Its ✕ hides it until the next attempt; Show the timers brings it back now. The sample is a made-up boss: drag the window where you want it.")) },
        { tab: "hosting", title: "Lobby Latency", badge: "1.28f",
            desc: "Games you host answer orders sooner: a shorter turn time.",
            on: (*) => gameDisplay.latency, set: (v) => gameDisplay.setLatency(v), status: (*) => gameDisplay.latencyStatus(),
            opts: (d) => (OptSlider(d, "Latency", (*) => gameDisplay.latencyMs, (v) => gameDisplay.setLatencyMs(v), 5, 1000, 1),
                OptNote(d, "Milliseconds, 5 to 1000. The game's own is 100.")) },
        { tab: "hosting", title: "Start Countdown", badge: "1.28f",
            desc: "Games you host start this long after Start Game, not the usual 6 s.",
            on: (*) => gameDisplay.countdown, set: (v) => gameDisplay.setCountdown(v), status: (*) => gameDisplay.countdownStatus(),
            opts: (d) => (OptSlider(d, "Seconds", (*) => gameDisplay.countdownSecs, (v) => gameDisplay.setCountdownSecs(v), 0, 6, 0.1, SecsText),
                OptNote(d, "From 0 to 6 s; the game's own is 6.")) },
        { tab: "hosting", title: "Battle.net Login", badge: "1.28f",
            desc: "Straight to Battle.net, logged in, and into your game (or the custom games).",
            on: (*) => bnetLogin.enabled, set: (v) => bnetLogin.setEnabled(v), status: (*) => bnetLogin.statusText(),
            window: (*) => BattleNetLoginDialog() },
    ]
    for f in Extensions.wc3Features
        list.Push(f)
    return list
}

; a card of several switches: "Cooldowns, Buffs" (each part's own status when only it is on), "Off" when none
; parts: [[on, name, status fn or 0]]
Wc3Both(parts) {
    on := []
    for p in parts
        if p[1]
            on.Push(p)
    if !on.Length
        return "Off"
    if on.Length = 1 && on[1][3]
        return on[1][2] ": " (on[1][3])()
    s := ""
    for p in on
        s .= (s = "" ? "" : ", ") p[2]
    return "On · " s
}

Wc3ScreenQcStatus(*) {
    global quickcast
    s := quickcast.get()
    where := WC3WindowName(s.window)
    return !s.window ? "Start Warcraft III to see whether it's set up for that window"
        : s.calibrated ? "Set up for " where : "Not set up for " where " yet"
}

BuildWc3Page() {
    global
    local x := 40, y := 160, cw := 682
    ; the game module in the title row (the user, 2026-11-01: the version switch's place): its status, then Log,
    ; Check and its On switch at the far right (page space is shifted by CX - 40, CY - 160); the tabs under it
    local mx := TB_R - (CX - 40) - 3 * 76 + 6, ty := TB_Y + 1 - CY + 160
    wc3ModuleText := mainGui.AddText("x" (x + 80) " y" (ty + 4) " w" (mx - 8 - x - 80) " h18 Right 0x200 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3ModuleText, "s8")
    local logBtn := MkButton("Log", mx, ty, 70, 26, C.chip, C.text, (*) => Wc3OpenLog())
    local chkBtn := MkButton("Check", mx + 76, ty, 70, 26, C.chip, C.text, (*) => ModuleCheckDialog())
    wc3ModuleBtn := MkButton("Off", mx + 152, ty, 70, 26, C.chip, C.muted, (*) => (gameModule.setEnabled(!gameModule.enabled), RefreshWc3()))
    AddToPage("wc3", wc3ModuleText, logBtn, chkBtn, wc3ModuleBtn)
    wc3ModuleRow := [wc3ModuleText, logBtn, chkBtn, wc3ModuleBtn]
    ; the tabs, like the Overlay page's dock switch
    for i, t in Wc3Tabs() {
        local b := MkButton(t[2], x + (i - 1) * 96, y, 90, 28, C.chip, C.muted, Wc3ShowTab.Bind(t[1]))
        wc3TabBtns[t[1]] := b
        AddToPage("wc3", b)
    }
    ; feature cards, all built at one spot: RefreshWc3 shows the tab's and
    ; version's own and lays them out in two columns
    for f in Wc3Features() {
        local top := y + 42, cwd := WC3_COL_W, right := x + cwd - 12 - 64
        local card := Box("wc3", x, top, cwd, WC3_CARD_H, C.card, C.border, 6)
        local tt := mainGui.AddText("x" (x + 12) " y" (top + 6) " w200 h20 0x200 +Background" C.card " c" C.text, f.title)
        UISetFont(tt, "s10 w600")
        local tw := Min(TextWidth(tt, f.title), cwd - 12 - 90 - 70)
        tt.Move(, , tw + 4)
        local bd := mainGui.AddText("x" (x + 20 + tw) " y" (top + 8) " w72 h16 0x200 +Background" C.card " c" C.accent, f.badge)
        UISetFont(bd, "s8 w600")
        local st := mainGui.AddText("x" (x + 12) " y" (top + 27) " w" (right - x - 20) " h16 0x200 0x4000 +Background" C.card " c" C.muted, "")
        UISetFont(st, "s8")
        local sw := 0, ob := 0
        if f.HasProp("on") {
            sw := MkButton("Off", right, top + 5, 64, 19, C.chip, C.muted, Wc3Switch.Bind(f))
            UISetFont(sw, "s8 w600")
            AddToPage("wc3", sw)
        }
        if f.HasProp("opts") || f.HasProp("window") {
            ob := MkButton("Options", right, top + (sw ? 26 : 5), 64, 18, C.chip, C.text, Wc3Options.Bind(f))
            UISetFont(ob, "s8 w600")
            AddToPage("wc3", ob)
        }
        AddToPage("wc3", tt, bd, st)
        wc3Cards.Push({ f: f, box: card, ctrls: [tt, bd, st], sw: sw, ob: ob, x: 0, y: 0, shown: false })
    }
    ; the pager, at the right end of the tab row (shown only when a tab has pages)
    local pr := MkButton("‹", x + cw - 108, y + 2, 28, 24, C.chip, C.text, Wc3Turn.Bind(-1))
    wc3PagerText := mainGui.AddText("x" (x + cw - 76) " y" (y + 2) " w44 h24 Center 0x200 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3PagerText, "s8")
    local nx := MkButton("›", x + cw - 28, y + 2, 28, 24, C.chip, C.text, Wc3Turn.Bind(1))
    AddToPage("wc3", pr, wc3PagerText, nx)
    wc3PagerCtls := [pr, wc3PagerText, nx]
    ; the line at the bottom: the hovered card's description and status, else what's planned
    wc3Planned := mainGui.AddText("x" x " y" (y + 82 + 4 * 80) " w" cw " h32 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3Planned, "s8")
    AddToPage("wc3", wc3Planned)
    OnMessage(0x200, Wc3Hover)              ; WM_MOUSEMOVE (the popovers' handler runs too)
}

; a feature's Options: its own window, or the standard one with its rows
Wc3Options(f, *) {
    static g := 0
    if f.HasProp("window")
        return (w := f.window)()
    if g
        try g.Destroy()
    d := Wc3Dialog(f.title, f.desc, 440)
    g := d.g
    (o := f.opts)(d)
    if f.HasProp("reset")
        d.reset := (*) => ((r := f.reset)(), Wc3Options(f))
    Wc3DialogShow(d)
    return g
}

; the hovered card's description and full status on the bottom line (static
; texts don't get mouse messages, so it's the cursor against the cards' boxes)
Wc3Hover(wParam, lParam, msg, hwnd) {
    global wc3HoverCard, wc3Cards, wc3Planned, currentPage, mainGui, DPI_K
    if currentPage != "wc3" || !IsSet(wc3Planned)
        return
    if DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr") != mainGui.Hwnd
        return                                  ; another window (an Options window): keep the line
    pt := Buffer(8), DllCall("GetCursorPos", "ptr", pt), DllCall("ScreenToClient", "ptr", mainGui.Hwnd, "ptr", pt)
    mx := NumGet(pt, 0, "int") / UiK(mainGui), my := NumGet(pt, 4, "int") / UiK(mainGui)
    c := 0
    for card in wc3Cards
        if card.shown && mx >= card.x && mx < card.x + WC3_COL_W && my >= card.y && my < card.y + WC3_CARD_H {
            c := card
            break
        }
    if c = wc3HoverCard
        return
    wc3HoverCard := c
    Wc3HintLine()
}
Wc3HintLine() {
    global wc3HoverCard, wc3Planned, wc3Tab, wc3Ver, C
    if hc := wc3HoverCard {
        SetIf(wc3Planned, hc.f.title ((bt := Wc3BadgeText(hc.f, wc3Ver)) != "" ? " (" bt ")" : "") ": " hc.f.desc "`n" hc.f.status())
        wc3Planned.Opt("c" C.muted)
    } else {
        SetIf(wc3Planned, (p := Wc3PlannedText(wc3Tab, wc3Ver)) != "" ? p : "Point at a feature to see what it does.")
        wc3Planned.Opt("c" C.dim)
    }
}

; Buff alerts' Options. On 1.28f (the game module): your hero's buffs now, each
; with Watch (by rawcode: no capture, no setup), and a box to type a rawcode.
; On Reforged: adding one from the screen and the buff bar setup (in game).
; Then the watched buffs (a label each, shown in the alert line; Remove) and
; the running-out warning. Labels save as you type.
BuffWatchDialog() {
    global C, buffWatch, timersHud, wc3Ver
    static g := 0
    if g
        try g.Destroy()
    list := buffWatch.buffs()
    d := Wc3Dialog("Buff Alerts", "A line over the game when a buff you watch is missing on your hero, or running out.", 480)
    g := d.g
    if wc3Ver = "128" {
        OptHeader(d, "ON YOUR HERO NOW")
        hb := 0
        if buffWatch.moduleReady() {
            if !(hb := buffWatch.heroBuffs(true)) || hb.hero = ""
                Sleep(250), hb := buffWatch.heroBuffs(true)          ; the module reads them from now on (10 a second)
            SetTimer(() => buffWatch.enabled || buffWatch.heroBuffs(false), -60000)
        }
        watched := Map()
        for b in list
            if b.HasProp("id")
                watched[b.id] := 1
        if !hb
            OptNote(d, "In a 1.28f game with the game module on, your hero's buffs show here: Watch one, no capture needed.")
        else if hb.hero = ""
            OptNote(d, "No hero of yours found in this game yet.")
        else if !hb.buffs.Length
            OptNote(d, "Your hero has no buffs right now. Cast one, then Refresh.")
        for hx in hb ? hb.buffs : [] {
            nm := g.AddText("x" d.x " y" (d.y + 3) " w" (d.tw - 100 - 64) " h22 0x200 +Background" C.card " c" (hx.positive ? C.text : C.muted),
                (hx.name != "" ? hx.name : "(no name)") (hx.aura ? "  · aura" : hx.total > 0 ? "  · " Round(hx.total) " s" : ""))
            idt := g.AddText("x" (d.x + d.tw - 100 - 60) " y" (d.y + 3) " w54 h22 0x200 +Background" C.card " c" C.dim, hx.id)
            UISetFont(idt, "s9")
            on := watched.Has(hx.id)
            wb := g.AddText("x" (d.x + d.tw - 90) " y" d.y " w90 h28 Center 0x200 +Background" C.chip " c" (on ? C.dim : C.text), on ? "Watching" : "Watch")
            UISetFont(wb, "s9 w600"), Box.Round(wb, 90, 28, 4)
            if !on
                wb.OnEvent("Click", ((bx, *) => (buffWatch.addId(bx.id, bx.name), BuffWatchDialog(), RefreshWc3())).Bind(hx))
            d.y += 32
        }
        ; a rawcode typed (a buff that isn't on the hero now)
        e := g.AddEdit("x" d.x " y" (d.y + 2) " w90 h24 Limit4 +Background" C.well " c" C.text, "")
        SendMessage(0x1501, 1, StrPtr("Binf"), e)                   ; EM_SETCUEBANNER
        add := g.AddText("x" (d.x + 98) " y" d.y " w90 h28 Center 0x200 +Background" C.chip " c" C.text, "Watch")
        UISetFont(add, "s9 w600"), Box.Round(add, 90, 28, 4)
        add.OnEvent("Click", (*) => (buffWatch.addId(e.Value) ? (BuffWatchDialog(), RefreshWc3()) : Toast("A rawcode is 4 letters, as Binf (or it's watched already)", "error")))
        rf := g.AddText("x" (d.x + d.tw - 90) " y" d.y " w90 h28 Center 0x200 +Background" C.chip " c" C.text, "Refresh")
        UISetFont(rf, "s9 w600"), Box.Round(rf, 90, 28, 4)
        rf.OnEvent("Click", (*) => BuffWatchDialog())
        d.y += 36
        OptNote(d, "Or type a buff's rawcode. Watched by rawcode on your hero whatever is selected, any window size.")
    } else {
        OptButtons(d, [["Add a buff", (*) => (g.Destroy(), WinExist(WarcraftIII) && HideMainWindow(), buffWatch.captureStart())],
            ["Set up the buff bar", (*) => (g.Destroy(), WinExist(WarcraftIII) && HideMainWindow(), timersHud.setupStart())]])
        OptNote(d, timersHud.buffBar() ? "The buff bar is set up for this window size." : "The buff bar isn't set up for this window size yet (in a game, your hero selected).")
    }
    OptDivider(d)
    OptHeader(d, "WATCHED BUFFS")
    if !list.Length
        OptNote(d, wc3Ver = "128" ? "None yet: Watch one above." : "None yet: Add a buff, in a game with the buff on your hero.")
    ; a row each, as the game keys' (its label to type, what it is, Remove at the right)
    for i, b in list {
        n := g.AddText("x" d.x " y" (d.y + 3) " w24 h22 0x200 +Background" C.card " c" C.muted, i)
        UISetFont(n, "s9 w600")
        e := g.AddEdit("x" (d.x + 28) " y" (d.y + 2) " w" (d.tw - 28 - 100 - 64) " h24 +Background" C.well " c" C.text, b.name)
        if b.HasProp("id")
            SendMessage(0x1501, 1, StrPtr(b.gname != "" ? b.gname : b.id), e)     ; EM_SETCUEBANNER: the game's name until you type one
        e.OnEvent("Change", ((i, src, *) => buffWatch.rename(i, src.Value)).Bind(i))
        k := g.AddText("x" (d.x + d.tw - 100 - 58) " y" (d.y + 3) " w56 h22 0x200 +Background" C.card " c" C.dim, b.HasProp("id") ? b.id : "screen")
        UISetFont(k, "s9")
        r := g.AddText("x" (d.x + d.tw - 90) " y" d.y " w90 h28 Center 0x200 +Background" C.chip " c" C.text, "Remove")
        UISetFont(r, "s9 w600"), Box.Round(r, 90, 28, 4)
        r.OnEvent("Click", ((i, *) => (buffWatch.remove(i), BuffWatchDialog(), RefreshWc3())).Bind(i))
        d.y += 34
    }
    if list.Length
        OptNote(d, "The label is what the alert line says (empty: the game's name). 'screen': captured from the buff bar; the rest by rawcode (1.28f).")
    OptDivider(d)
    OptSlider(d, "Warn at", (*) => buffWatch.warnAt, (v) => (IsNumber(v) && (buffWatch.setWarnAt(Round(Min(Max(v + 0, 0), 60))), true)), 0, 60, 1)
    OptNote(d, "Seconds left when a buff counts as running out (0 = never); 1.28f, with the game module.")
    Wc3DialogShow(d)
    return g
}

; Battle.net login's Options: the account name (saved as you type) and the
; password (saved in Windows' Credential Manager with Save; the box is
; emptied then and never shows a saved one).
BattleNetLoginDialog() {
    global C, bnetLogin
    static g := 0
    if g
        try g.Destroy()
    d := Wc3Dialog("Battle.net Login", "At the main menu, the game goes to Battle.net and logs in with your account: on the gateway chosen in the game (eurobattle.net).", 460)
    g := d.g
    row(label, opts, value) {
        lb := g.AddText("x" d.x " y" (d.y + 3) " w100 h22 0x200 +Background" C.card " c" C.text, label)
        e := g.AddEdit("x" (d.x + 104) " y" (d.y + 1) " w" (d.tw - 104 - 100) " h24 +Background" C.well " c" C.text " " opts, value)
        return e
    }
    acc := row("Account", "Limit31", bnetLogin.account)
    acc.OnEvent("Change", (src, *) => bnetLogin.setAccount(src.Value))
    d.y += 34
    pw := row("Password", "Password Limit63", "")
    SendMessage(0x1501, 1, StrPtr(bnetLogin.hasPassword() ? "saved (type to replace)" : "not saved yet"), pw)   ; EM_SETCUEBANNER
    save := g.AddText("x" (d.x + d.tw - 90) " y" (d.y - 1) " w90 h28 Center 0x200 +Background" C.chip " c" C.text, "Save")
    UISetFont(save, "s9 w600"), Box.Round(save, 90, 28, 4)
    save.OnEvent("Click", (*) => (pw.Value != "" && (bnetLogin.setPassword(pw.Value) ? Toast("Password saved in Windows' Credential Manager") : Toast("The password couldn't be saved", "error")),
        pw.Value := "", BattleNetLoginDialog(), RefreshWc3()))
    d.y += 36
    OptNote(d, "The password is kept in Windows' Credential Manager (encrypted for your Windows account), never in the companion's files. It goes to the game only at the login screen.")
    OptButtons(d, [["Forget the password", (*) => (bnetLogin.setPassword(""), Toast("Password removed"), BattleNetLoginDialog(), RefreshWc3())]])
    OptDivider(d)
    OptHeader(d, "THEN")
    OptToggle(d, "Open the custom games", bnetLogin.customGames, (v) => bnetLogin.setCustomGames(v))
    gm := row("Join game", "Limit31", bnetLogin.game)
    SendMessage(0x1501, 1, StrPtr("its name (empty: the list)"), gm)       ; EM_SETCUEBANNER
    gm.OnEvent("Change", (src, *) => bnetLogin.setGame(src.Value))
    d.y += 34
    OptNote(d, "Joined by its name as soon as you're in. Empty, or if it isn't there: the custom games list stays open to pick from.")
    OptDivider(d)
    OptNote(d, "Once each time the game starts. Hold Shift at the main menu to stay there. A wrong password isn't tried again: the game says so, log in yourself.")
    Wc3DialogShow(d)
    return g
}

; a dialog in the companion's style: -> { g, card, x, tw, w, y } to add rows to, then Wc3DialogShow
Wc3Dialog(title, intro, w := 380) {
    global C, mainGui, UI_FONT
    x := 26, tw := w - 52
    g := Gui("-Caption +ToolWindow +AlwaysOnTop +Owner" mainGui.Hwnd)
    MakeScalable(g, "popup")
    g.MarginX := 0, g.MarginY := 0
    card := DialogCard(g, w)
    t := g.AddText("x" x " y22 w" tw " h28 +Background" C.card " c" C.text, title)
    t.SetFont("s13 w700 q4", "Cinzel")
    it := g.AddText("x" x " y56 w" tw " h18 +Background" C.card " c" C.dim, intro)
    UISetFont(it, "s9")
    ih := Max(18, TextHeight(it, intro, tw)), it.Move(, , , ih)
    g.SetFont("s10", UI_FONT)
    return { g: g, card: card, x: x, tw: tw, w: w, y: 56 + ih + 16 }
}
Wc3DialogShow(d) {
    global C, mainGui, DPI_K
    g := d.g, w := d.w, y := d.y + 14
    close := g.AddText("x" (w - d.x - 104) " y" y " w104 h34 Center 0x200 +Background" C.chip " c" C.text, "Close")
    UISetFont(close, "s9 w600"), Box.Round(close, 104, 34, 4)
    close.OnEvent("Click", (*) => (g.Destroy(), RefreshWc3()))
    if d.HasProp("reset") {             ; this window's settings back to their defaults (it opens again with them)
        rs := g.AddText("x" d.x " y" y " w150 h34 Center 0x200 +Background" C.chip " c" C.muted, "Reset to default")
        UISetFont(rs, "s9 w600"), Box.Round(rs, 150, 34, 4)
        rs.OnEvent("Click", (*) => (r := d.reset)())
    }
    h := y + 34 + 24
    d.card.Move(, , , h - 2)
    g.OnEvent("Escape", (*) => (g.Destroy(), RefreshWc3()))
    DialogStyle(g)
    WinGetPos(&ox, &oy, &ow, &oh, mainGui)
    g.Show("x" Round(ox + (ow - w * UiK(g)) / 2) " y" Round(oy + (oh - h * UiK(g)) / 2) " w" w " h" h)
    try if InStr(ControlGetClassNN(ControlGetFocus(g)), "Edit")
        SendMessage(0xB1, -1, 0, ControlGetFocus(g))   ; EM_SETSEL: a name box that has the focus isn't all selected
    DialogRepaint(g)
}

; -- rows for the Options windows (d: a Wc3Dialog) ------------------------------
; a switch: its text, and an On/Off toggle at the row's end (MkToggle); indent moves the text right (a sub-option);
; btn: [text, click], a button of its own just before the switch (its window: Options)
OptToggle(d, text, on, set, indent := 0, btn := 0) {
    global C
    bw := 0
    if btn {
        b := d.g.AddText("x0 y" d.y " w60 h24 Center 0x200 +Background" C.chip " c" C.text, btn[1])
        UISetFont(b, "s9 w600")
        bw := Max(80, TextWidth(b, btn[1]) + 24), b.Move(d.x + d.tw - 56 - 8 - bw, , bw), Box.Round(b, bw, 24, 4)
        b.OnEvent("Click", btn[2])
        bw += 8
    }
    tw := d.tw - indent - 66 - bw
    lb := d.g.AddText("x" (d.x + indent) " y" (d.y + 2) " w" tw " h20 +Background" C.card " c" C.text, text)
    nh := Max(20, TextHeight(lb, text, tw)), lb.Move(, , , nh)
    t := MkToggle(d.g, d.x + d.tw - 56, d.y, on, (v) => set(v ? 1 : 0))
    d.y += Max(30, nh + 10)
    return t
}
; a number: a slider and a box to type in (the game changes as you go). get() -> the value,
; set(v) -> false if it isn't one; step: the slider's step (0.1 for tenths); fmt: the box's text
OptSlider(d, label, get, set, lo, hi, step, fmt := 0) {
    global C
    fmt := fmt ? fmt : (v) => step < 1 ? RTrim(RTrim(Format("{:.2f}", v), "0"), ".") : Round(v)
    g := d.g
    lb := g.AddText("x" d.x " y" (d.y + 2) " w76 h22 0x200 +Background" C.card " c" C.text, label)
    sl := g.AddSlider("x" (d.x + 80) " y" d.y " w" (d.tw - 80 - 74) " h26 NoTicks Range" Round(lo / step) "-" Round(hi / step) " +Background" C.card, Round(get() / step))
    ed := g.AddEdit("x" (d.x + d.tw - 64) " y" (d.y + 1) " w64 h24 Center +Background" C.well " c" C.text, fmt(get()))
    busy := { on: false }
    sl.OnEvent("Change", (src, *) => (set(src.Value * step), busy.on := true, ed.Value := fmt(get()), busy.on := false))
    ed.OnEvent("Change", (src, *) => (!busy.on && set(StrReplace(Trim(src.Value), ",", ".")) && (sl.Value := Round(get() / step))))
    d.y += 36
    return [sl, ed]
}
; one of a few: a row of buttons, the chosen one lit. choices: [[value, text], ...]
OptChoice(d, label, choices, get, set) {
    global C
    g := d.g, btns := []
    lb := g.AddText("x" d.x " y" (d.y + 3) " w76 h22 0x200 +Background" C.card " c" C.text, label)
    for ch in choices {
        b := OptChip(g, d.x, d.y, ch[2])
        btns.Push({ ctl: b, v: ch[1] })
    }
    OptRight(d, btns.Length, (i) => btns[i].ctl)
    paint() {
        for it in btns
            it.ctl.Opt("+Background" (it.v = get() ? C.navOn : C.chip) " +c" (it.v = get() ? C.accent : C.muted)), it.ctl.Redraw()
    }
    for it in btns
        it.ctl.OnEvent("Click", ((v, *) => (set(v), paint())).Bind(it.v))
    paint()
    d.y += 34
}
; a row of buttons: [[text, click], ...], at the row's right end
OptButtons(d, list) {
    global C
    bts := []
    for b in list {
        bt := d.g.AddText("x" d.x " y" d.y " w60 h28 Center 0x200 +Background" C.chip " c" C.text, b[1])
        UISetFont(bt, "s9 w600")
        bw := Max(90, TextWidth(bt, b[1]) + 24), bt.Move(, , bw), Box.Round(bt, bw, 28, 4)
        bt.OnEvent("Click", b[2])
        bts.Push(bt)
    }
    OptRight(d, bts.Length, (i) => bts[i], 8)
    d.y += 36
}
; a row's controls moved to end at its right edge, in order, gap apart (the user's general rule: to the right)
OptRight(d, n, ctl, gap := 6) {
    total := 0
    loop n
        ctl(A_Index).GetPos(, , &rw), total += rw + (A_Index > 1 ? gap : 0)          ; (GetPos is in base units: WindowScale)
    x := d.x + d.tw - total
    loop n {
        ct := ctl(A_Index)
        ct.GetPos(, , &rw), ct.Move(x), x += rw + gap
    }
}
; a game key (GameCommands): its key, and a button that asks for a new one
OptKey(d, label, name) {
    global C, gameCmds
    g := d.g
    lb := g.AddText("x" d.x " y" (d.y + 3) " w140 h22 0x200 +Background" C.card " c" C.text, label)
    kt := g.AddText("x" (d.x + 146) " y" (d.y + 3) " w" (d.tw - 146 - 100) " h22 0x200 +Background" C.card " c" C.accent, gameCmds.keyText(name))
    b := g.AddText("x" (d.x + d.tw - 90) " y" d.y " w90 h28 Center 0x200 +Background" C.chip " c" C.text, "Set key")
    UISetFont(b, "s9 w600"), Box.Round(b, 90, 28, 4)
    b.OnEvent("Click", (*) => (Wc3Capture(name), kt.Text := gameCmds.keyText(name)))
    d.y += 34
}
; a section's title, as the size window's HEALTH BARS
OptHeader(d, text) {
    global C
    hd := d.g.AddText("x" d.x " y" d.y " w" d.tw " h18 +Background" C.card " c" C.muted, text)
    UISetFont(hd, "s8 w600")
    d.y += 24
}
; a colour: its label, a swatch to click (Windows' colour dialog) and a check box after it.
; get() -> RRGGBB or "player"; pick() -> the new RRGGBB or ""; check(on) for the box
OptColour(d, label, get, pick, boxText, check) {
    global C
    g := d.g, col := get()
    lb := g.AddText("x" d.x " y" (d.y + 3) " w140 h22 0x200 +Background" C.card " c" C.text, label)
    sw := g.AddText("x" (d.x + 146) " y" (d.y + 3) " w60 h22 +Border +Background" (col = "player" ? C.card : col), "")
    pb := OptChip(g, d.x + 146 + 60 + 14, d.y, boxText)
    pb.GetPos(, , &pw), pb.Move(d.x + d.tw - pw), sw.Move(d.x + d.tw - pw - 12 - 60)
    paint() => (cur := get(), sw.Opt("+Background" (cur = "player" ? C.card : cur)), sw.Redraw(), Wc3SetSelected(pb, cur = "player"))
    sw.OnEvent("Click", (*) => (pick() != "" && paint()))
    pb.OnEvent("Click", (*) => (check(get() != "player" ? 1 : 0), paint()))
    paint()
    d.y += 34
}
; a colour swatch to click (Windows' colour dialog): get() -> RRGGBB; pick(g) -> the new RRGGBB or ""
OptSwatch(d, label, get, pick) {
    global C
    g := d.g
    lb := g.AddText("x" d.x " y" (d.y + 3) " w140 h22 0x200 +Background" C.card " c" C.text, label)
    sw := g.AddText("x" (d.x + d.tw - 60) " y" (d.y + 3) " w60 h22 +Border +Background" get(), "")
    sw.OnEvent("Click", (*) => ((rgb := pick(g)) != "" && (sw.Opt("+Background" rgb), sw.Redraw())))
    d.y += 34
}
; a button that's lit while it's on (OptToggles', OptColour's), as OptChoice's
OptChip(g, x, y, text) {
    global C
    b := g.AddText("x" x " y" y " w60 h26 Center 0x200 +Background" C.chip " c" C.muted, text)
    UISetFont(b, "s9 w600")
    bw := Max(70, TextWidth(b, text) + 22), b.Move(, , bw), Box.Round(b, bw, 26, 4)
    return b
}
; any of a few: a row of buttons after a label, each lit while it's on: items [[key, text], ...]; on(key) -> 0/1, set(key, on)
OptToggles(d, label, items, on, set) {
    global C
    g := d.g, bx := d.x + 80
    g.AddText("x" d.x " y" (d.y + 3) " w76 h22 0x200 +Background" C.card " c" C.text, label)
    chips := []
    for it in items {
        b := OptChip(g, bx, d.y, it[2])
        Wc3SetSelected(b, on(it[1]))
        b.OnEvent("Click", ((key, src, *) => (set(key, on(key) ? 0 : 1), Wc3SetSelected(src, on(key)))).Bind(it[1]))
        chips.Push(b)
    }
    OptRight(d, chips.Length, (i) => chips[i])
    d.y += 34
}
OptNote(d, text) {
    global C
    nt := d.g.AddText("x" d.x " y" d.y " w" d.tw " h18 +Background" C.card " c" C.dim, text)
    UISetFont(nt, "s8")
    nh := Max(16, TextHeight(nt, text, d.tw)), nt.Move(, , , nh)
    d.y += nh + 8
}
OptDivider(d) {
    global C
    d.y += 4
    d.g.AddText("x" d.x " y" d.y " w" d.tw " h1 +Background" C.border)
    d.y += 14
}

; Health bar and mana bar size, in one window: a slider and a box to type in
; for each (the game changes as you go)
BarSizeDialog(*) {
    global C, healthBars
    static g := 0
    if g
        try g.Destroy()
    d := Wc3Dialog("Health and Mana Size", "Health bars: times the game's own size (with Health and Mana Size on). Mana bars: times their health bar's.", 460)
    g := d.g
    for sec in [["HEALTH BARS", [["height", "Height"], ["width", "Width"]]], ["MANA BARS", [["manaHeight", "Height"], ["manaWidth", "Width"]]]] {
        if sec[1] = "MANA BARS"
            OptDivider(d)
        OptHeader(d, sec[1])
        for r in sec[2] {
            lim := HealthBarsEngine.SIZES[r[1]]
            OptSlider(d, r[2], ((k, *) => healthBars.size(k)).Bind(r[1]), ((k, v) => healthBars.setSize(k, v)).Bind(r[1]), lim[2], lim[3], 0.01, BarSizeText)
        }
        OptNote(d, sec[1] = "HEALTH BARS" ? "×0.25 to ×4; ×1 is the game's own. The width is experimental." : "×0.25 to ×2 of the health bar.")
    }
    d.reset := (*) => (healthBars.reset("sizes"), BarSizeDialog())
    Wc3DialogShow(d)
    return g
}

BarSizeText(v) => RTrim(RTrim(Format("{:.2f}", v), "0"), ".")
SecsText(v) => RTrim(RTrim(Format("{:.1f}", v), "0"), ".")

; Health bar colours by owner: each a colour of your own, or the owner's player colour
BarColoursDialog() {
    global healthBars
    static g := 0
    if g
        try g.Destroy()
    d := Wc3Dialog("Health Bar Colors", "By owner (your own color, or each owner's player color), or by health left.", 440)
    g := d.g
    OptChoice(d, "Color", [["owner", "By owner"], ["health", "By health"]], (*) => healthBars.colourMode, (v) => healthBars.setColourMode(v))
    OptNote(d, "By health: green, to yellow at half, to red.")
    OptDivider(d)
    OptHeader(d, "BY OWNER")
    for o in HealthBarsEngine.OWNERS
        OptColour(d, o[3], ((key, *) => healthBars.colour(key)).Bind(o[1]), BarPickColour.Bind(o[1], g), "Player Color",
            ((key, def, on) => BarPlayerColour(key, def, on)).Bind(o[1], o[2]))
    OptNote(d, "Click a color to change it. Player Color: each owner's own (the game's 12).")
    d.reset := (*) => (healthBars.reset("colours"), BarColoursDialog())
    Wc3DialogShow(d)
    return g
}
BarPlayerColour(key, def, on) {
    global healthBars
    last := Ini(healthBars.section, key "Own", def = "player" ? "FFFFFF" : def)
    healthBars.setColour(key, on ? "player" : last)
}
; -> the new colour, or "" (cancelled)
BarPickColour(key, g, *) {
    global healthBars
    col := healthBars.colour(key)
    if (rgb := ChooseColour(g.Hwnd, col = "player" ? Ini(healthBars.section, key "Own", "FFFFFF") : col)) = ""
        return ""
    SetIni(rgb, healthBars.section, key "Own")
    healthBars.setColour(key, rgb)
    return rgb
}
; Windows' colour dialog: RRGGBB in, RRGGBB out ("" = cancelled)
ChooseColour(owner, rgb) {
    static custom := Buffer(64, 0xFF)
    n := Integer("0x" rgb), ref := ((n & 0xFF) << 16) | (n & 0xFF00) | (n >> 16)      ; COLORREF is BGR
    cc := Buffer(A_PtrSize = 8 ? 72 : 36, 0), p := A_PtrSize
    NumPut("uint", cc.Size, cc, 0), NumPut("ptr", owner, cc, p), NumPut("uint", ref, cc, 3 * p)
    NumPut("ptr", custom.Ptr, cc, 4 * p), NumPut("uint", 0x3, cc, 5 * p)                 ; CC_RGBINIT | CC_FULLOPEN
    if !DllCall("comdlg32\ChooseColor", "ptr", cc)
        return ""
    ref := NumGet(cc, 3 * p, "uint")
    return Format("{:06X}", ((ref & 0xFF) << 16) | (ref & 0xFF00) | (ref >> 16))
}

Wc3Label(l) => HasMethod(l) ? l() : l
Wc3Capture(name) {
    global gameCmds
    Toast("Press the key for it (Esc = none)", "", 0)
    if gameCmds.capture(name)
        Toast("Key set: " gameCmds.keyText(name), "", 1500)
    RefreshWc3()
}

; the next / previous page of the tab's cards (wraps around)
Wc3Turn(d, *) {
    global wc3PageNo, wc3Tab, wc3Ver
    k := wc3Tab wc3Ver
    wc3PageNo[k] := wc3PageNo.Get(k, 1) + d
    RefreshWc3()
}
Wc3ShowTab(tab, *) {
    global wc3Tab := tab
    RefreshWc3()
}
Wc3ShowVersion(ver, *) {
    global wc3Ver := ver
    SetIni(ver, "Wc3", "view")
    RefreshWc3()
}
; opening the page: the running game's version, if one runs
Wc3PageOpened() {
    global wc3Ver
    ; (1.28f's side only for now: the running game no longer picks the side)
    RefreshWc3()
}
Wc3Switch(f, *) {
    set := f.set                ; called as a function: f.set(v) would pass f as a first parameter
    set(!f.on())
    RefreshWc3()
}
Wc3OpenLog() {
    log := A_ScriptDir "\native\twc-game.log"
    if FileExist(log)
        Run('notepad.exe "' log '"')
    else
        Toast("No game module log yet: it starts with the first 1.28f game the module is loaded into", "", 4000)
}

; an On/Off switch button's look
Wc3SetSwitch(b, on) {
    b.Text := on ? "On" : "Off"
    Wc3SetSelected(b, on)
}
; a segmented or switch button's look (selected: tinted, accent text)
Wc3SetSelected(b, on) {
    global C, boxes
    bg := on ? C.navOn : C.chip
    b.Opt("+Background" bg " +c" (on ? C.accent : C.muted)), b.Redraw()
    if boxes.Has(b.Hwnd)
        boxes[b.Hwnd].Fill := bg
}

; move a card (its box, texts, switch, Options and their boxes) to x, y (window units)
Wc3MoveCard(card, x, y) {
    global boxes
    if !card.x
        card.box.outer.GetPos(&l, &t), card.x := l, card.y := t
    dx := x - card.x, dy := y - card.y
    if !dx && !dy
        return
    card.x := x, card.y := y
    ctls := [card.box.outer, card.box.inner, card.ctrls*]
    for b in [card.sw, card.ob]
        if b
            ctls.Push(b)
    for c in ctls {
        c.GetPos(&cl, &cTop)
        c.Move(cl + dx, cTop + dy)
        if boxes.Has(c.Hwnd) {
            bx := boxes[c.Hwnd]
            bx.Move(bx.x + dx, bx.y + dy, bx.w, bx.h)
        }
    }
}
; the short form of a status line for a card (the full one is on the hover line)
Wc3Short(s) => (p := InStr(s, " (")) ? SubStr(s, 1, p - 1) : s

RefreshWc3() {
    global wc3Tab, wc3TabBtns, wc3Cards, wc3ModuleBtn, wc3ModuleText, wc3Planned, gameModule, currentPage
    global wc3Ver, wc3ModuleRow, wc3PageNo, wc3PagerCtls, wc3PagerText, H, wc3HoverCard
    ; only on its own page: it shows its cards, and called from elsewhere (a window that
    ; closed over another page) it drew them over that page
    if currentPage != "wc3"
        return SetTimer(Wc3Tick, 0)
    Freeze()
    for tab, b in wc3TabBtns
        Wc3SetSelected(b, tab = wc3Tab)
    ; the game module row: 1.28f only
    withModule := wc3Ver = "128"
    for c in wc3ModuleRow
        SetShown(c, withModule)
    Wc3SetSwitch(wc3ModuleBtn, gameModule.enabled)
    SetIf(wc3ModuleText, "Game module: " gameModule.statusText())
    wc3TabBtns[Wc3Tabs()[1][1]].GetPos(&tx, &ty, , &th)
    topY := ty + th + 12                            ; right under the tabs
    hintY := H - 40                                 ; the bottom line
    ; the tab's cards on this version, two a row, in pages of as many rows as fit
    inTab := 0
    for card in wc3Cards
        inTab += card.f.tab = wc3Tab && Wc3OnVersion(card.f, wc3Ver)
    perPage := 2 * Max(1, (hintY - 4 - topY + (WC3_ROW - WC3_CARD_H)) // WC3_ROW)
    pageCount := Max(1, Ceil(inTab / perPage))
    pk := wc3Tab wc3Ver, pageNo := wc3PageNo.Get(pk, 1)
    pageNo := pageNo < 1 ? pageCount : pageNo > pageCount ? 1 : pageNo
    wc3PageNo[pk] := pageNo
    for c in wc3PagerCtls
        SetShown(c, pageCount > 1)
    wc3PagerText.Text := pageNo " / " pageCount
    idx := 0
    for card in wc3Cards {
        vis := card.f.tab = wc3Tab && Wc3OnVersion(card.f, wc3Ver)
        idx += vis
        vis := vis && idx > (pageNo - 1) * perPage && idx <= pageNo * perPage
        card.shown := vis
        card.box.Visible := vis
        for c in card.ctrls
            c.Visible := vis
        for b in [card.sw, card.ob]
            if b
                SetShown(b, vis)
        if !vis
            continue
        k := idx - (pageNo - 1) * perPage - 1
        Wc3MoveCard(card, tx + Mod(k, 2) * (WC3_COL_W + 12), topY + (k // 2) * WC3_ROW)
        if card.sw
            Wc3SetSwitch(card.sw, card.f.on())
        SetIf(card.ctrls[2], Wc3BadgeText(card.f, wc3Ver))
        SetIf(card.ctrls[3], Wc3Short(card.f.status()))
    }
    if !inTab
        wc3HoverCard := 0
    wc3Planned.Move(, hintY)
    Wc3HintLine()
    if !inTab
        SetIf(wc3Planned, "Nothing here yet.  " Wc3PlannedText(wc3Tab, wc3Ver))
    Thaw()
    ; live status lines while the page is open
    SetTimer(Wc3Tick, currentPage = "wc3" ? 1000 : 0)
}
; once a second: just the status lines and switches (no repaint of the rest)
Wc3Tick() {
    global currentPage, mainGui, wc3Tab, wc3Cards, wc3ModuleBtn, wc3ModuleText, gameModule, wc3Ver, wc3HoverCard
    if currentPage != "wc3" || !DllCall("IsWindowVisible", "ptr", mainGui.Hwnd)
        return SetTimer(Wc3Tick, 0)
    SetIf(wc3ModuleText, "Game module: " gameModule.statusText())
    if (wc3ModuleBtn.Text = "On") != !!gameModule.enabled
        Wc3SetSwitch(wc3ModuleBtn, gameModule.enabled)
    for card in wc3Cards
        if card.shown {
            SetIf(card.ctrls[3], Wc3Short(card.f.status()))
            if card.sw && (card.sw.Text = "On") != !!card.f.on()
                Wc3SetSwitch(card.sw, card.f.on())
        }
    if wc3HoverCard
        Wc3HintLine()
}
SetIf(ctl, text) {
    if ctl.Text != text
        ctl.Text := text
}
