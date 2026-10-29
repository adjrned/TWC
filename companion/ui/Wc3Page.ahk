#Requires AutoHotkey v2.0
; ============================================================================
;  WC3 page - features that read or change the running game, in one place.
;  At the top right, the version switch: 1.28f | Reforged. The page shows only what
;  works on that version (and "Both" features); opening the page picks the
;  running game's version. 1.28f features use the game module (injected;
;  its row is only on the 1.28f side); Reforged ones only read the screen.
;  Three tabs set where every feature goes, now and later (quickcast is on
;  the Remap page, with its keys: a switch and Options per version):
;    Timers    what's ready and what's running out: cooldowns, buff timers,
;              buff alerts
;    Display   how the game looks: health bars (size, colours, numbers, mana
;              bars), game keys, hiding the UI, widescreen, the widescreen UI,
;              fast menu, detailed tooltips, FPS unlock
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
global wc3Ver := Ini("Wc3", "view", "128"), wc3VerBtns := Map(), wc3VerText, wc3ModuleRow := []
global wc3PageNo := Map(), wc3PagerCtls := [], wc3PagerText       ; tab + version -> the page shown
global wc3HoverCard := 0                                           ; the card under the cursor
global WC3_COL_W := 335, WC3_CARD_H := 48, WC3_ROW := 54

Wc3Tabs() => [["display", "Display"], ["timers", "Timers"], ["combat", "Combat"], ["hosting", "Hosting"]]
; the two versions: key, switch label
Wc3Versions() => [["128", "1.28f"], ["reforged", "Reforged"]]
Wc3VerBadge(ver) => ver = "128" ? "1.28f" : "Reforged"
; the running game's version ("128" / "reforged"), "" if none
Wc3RunningVer() => (k := WC3WindowKey()) = "" ? "" : InStr(k, "reforged") = 1 ? "reforged" : "128"
; does a feature show on the version in view?
Wc3OnVersion(f, ver) => f.badge = "Both" || f.badge = Wc3VerBadge(ver)

; what each tab will hold later on each version (on the line at the bottom)
Wc3PlannedText(tab, ver) {
    static p := Map(
        "timers128", "",
        "timersreforged", "Planned: cooldown and buff timers read from the screen. To help build them: tray menu > Debug: save HUD pictures, in a game, then send the folder.",
        "display128", "",
        "displayreforged", "Nothing planned yet.",
        "combat128", "Next: the map's own total damage, read from the game (how its ability shows it: to find out).",
        "combatreforged", "Nothing planned yet.",
        "hosting128", "",
        "hostingreforged", "Nothing planned: Battle.net hosts Reforged games.")
    return p[tab ver]
}

; Every feature on the page. Keys: tab, title, badge ("1.28f" / "Reforged" /
; "Both"), desc (what it does: the hover line and its window's intro),
; status() -> text; optional on() / set(v) for the switch, and either
; opts(d) (rows added to the feature's standard Options window, see Opt*)
; or window() (a window of its own).
Wc3Features() {
    global gameModule, timersHud, quickcast, gameCmds, buffWatch, healthBars, gameDisplay, bnetLogin, dmgMeter
    static list := 0
    if list
        return list
    list := [
        { tab: "timers", title: "Cooldowns", badge: "1.28f",
            desc: "Seconds left on abilities and items, drawn on their buttons in the game.",
            on: (*) => timersHud.cooldowns, set: (v) => timersHud.setCooldowns(v), status: (*) => timersHud.cooldownStatus(),
            opts: (d) => (OptSlider(d, "Size", (*) => timersHud.cdSize, (v) => timersHud.setCdSize(v), 0.75, 1.5, 0.05, BarSizeText),
                OptSlider(d, "Gold from", (*) => timersHud.cdGold, (v) => timersHud.setCdGold(v), 0, 30, 1),
                OptNote(d, "Seconds left when the number turns gold (0 = always white). Every number has a black outline."),
                OptCheck(d, "'Ready' in green for a moment when a cooldown is over", timersHud.cdReady, (v) => timersHud.setCdReady(v)),
                OptCheck(d, "Our own cooldown sweep", timersHud.cdSweep, (v) => timersHud.setCdSweep(v)),
                OptNote(d, "The game's clock redrawn as the plain dark sweep, without TWRPG's clock badge and timer."),
                OptCheck(d, "Minutes as m:ss", timersHud.cdMinutes, (v) => timersHud.setMinutes("cdMinutes", v)),
                OptNote(d, "1:35 rather than 95 from a minute up."),
                OptDivider(d),
                OptCheck(d, "Allied units' abilities and cooldowns too", timersHud.allies, (v) => timersHud.setAllies(v)),
                OptNote(d, "As WFE's ally ability bar: select an ally's unit to see its command card. Clicking its buttons does nothing."),
                OptCheck(d, "Alt + click an ability or item: tell your allies its cooldown", timersHud.pings, (v) => timersHud.setPings(v)),
                OptNote(d, "As WFE's ping: 'Paladin >> Holy Light | Cooldown: 7', '| Ready!' or '| Not enough mana!' to your allies (who gets it: the game's Chat dialog).")) },
        { tab: "timers", title: "Buff timers", badge: "1.28f",
            desc: "Seconds left on buffs, drawn under their icons in the game's buff bar.",
            on: (*) => timersHud.buffs, set: (v) => timersHud.setBuffs(v), status: (*) => timersHud.buffStatus(),
            opts: (d) => (OptSlider(d, "Size", (*) => timersHud.bfSize, (v) => timersHud.setBfSize(v), 0.75, 1.5, 0.05, BarSizeText),
                OptSlider(d, "Gold from", (*) => timersHud.bfGold, (v) => timersHud.setBfGold(v), 0, 30, 1),
                OptNote(d, "Seconds left when the number turns gold (0 = always white). Every number has a black outline."),
                OptCheck(d, "Seconds on auras too", timersHud.bfAuras, (v) => timersHud.setBfAuras(v)),
                OptNote(d, "Once you're out of an aura's range: the seconds before it wears off (in range it's kept up: no number). Buffs the map gives again on a beat get none while it does."),
                OptCheck(d, "Minutes as m:ss", timersHud.buffMinutes, (v) => timersHud.setMinutes("buffMinutes", v)),
                OptNote(d, "1:35 rather than 95 from a minute up.")) },
        { tab: "timers", title: "Buff alerts", badge: "Both",
            desc: "A line over the game when a buff on your hero is missing or running out.",
            on: (*) => buffWatch.enabled, set: (v) => buffWatch.setEnabled(v), status: (*) => buffWatch.statusText(),
            window: (*) => BuffWatchDialog() },
        { tab: "display", title: "Health bar size", badge: "1.28f",
            desc: "Bigger health bars (and mana bars) on every unit. Width is experimental.",
            on: (*) => healthBars.enabled, set: (v) => healthBars.setEnabled(v), status: (*) => healthBars.statusText(),
            window: (*) => BarSizeDialog() },
        { tab: "display", title: "Health bar colours", badge: "1.28f",
            desc: "By owner (your colour or each player's own) or by health left.",
            on: (*) => healthBars.colours, set: (v) => healthBars.setColours(v), status: (*) => healthBars.colourStatus(),
            window: (*) => BarColoursDialog() },
        { tab: "display", title: "Health numbers", badge: "1.28f",
            desc: "A number over every health bar: current, current / max or percent (Storm.dll).",
            on: (*) => healthBars.numbers, set: (v) => healthBars.setNumbers(v), status: (*) => healthBars.numberStatus(),
            opts: (d) => OptChoice(d, "Show", [[1, "Current"], [2, "Current / max"], [3, "Percent"]], (*) => healthBars.numberMode, (v) => healthBars.setNumberMode(v)) },
        { tab: "display", title: "Mana bars", badge: "1.28f",
            desc: "A mana bar under the health bar of every unit with mana (Storm.dll).",
            on: (*) => healthBars.mana, set: (v) => healthBars.setMana(v), status: (*) => healthBars.manaStatus(),
            window: (*) => BarSizeDialog() },
        { tab: "display", title: "Game keys", badge: "1.28f",
            desc: "Keys that wipe the trigger messages or the chat, and minimise the multiboard.",
            on: (*) => gameCmds.enabled, set: (v) => gameCmds.setEnabled(v), status: (*) => gameCmds.statusText(),
            opts: (d) => (OptKey(d, "Clear messages", "clearMessages"), OptKey(d, "Clear chat", "clearChat"), OptKey(d, "Multiboard", "multiboard"),
                OptNote(d, "Esc while setting one: no key.")) },
        { tab: "display", title: "Hide the UI", badge: "1.28f",
            desc: "As WFE: the black console goes, the world shows through; the minimap stays.",
            on: (*) => gameDisplay.hideUi, set: (v) => gameDisplay.setHideUi(v), status: (*) => gameDisplay.hideStatus(),
            opts: (d) => OptCheck(d, "Hide the upper menu bar's buttons too", gameDisplay.hideMenu, (v) => gameDisplay.setHideMenu(v)) },
        { tab: "display", title: "Widescreen", badge: "1.28f",
            desc: "As WFE's: the world isn't stretched. Steps aside for a widescreen mix file.",
            on: (*) => gameDisplay.widescreen, set: (v) => gameDisplay.setWidescreen(v), status: (*) => gameDisplay.wsStatus() },
        { tab: "display", title: "Widescreen UI", badge: "1.28f",
            desc: "As WFE's Upgraded UI: on a wide window the UI isn't stretched.",
            on: (*) => gameDisplay.wideUi, set: (v) => gameDisplay.setWideUi(v), status: (*) => gameDisplay.wideUiStatus(),
            opts: (d) => (OptCheck(d, "Raise the buff bar over the console", gameDisplay.buffBarUp, (v) => gameDisplay.setBuffBarUp(v)),
                OptNote(d, "As WFE's upgraded buff bar: it floats above the command card, without its label.")) },
        { tab: "display", title: "Bigger buff bar", badge: "1.28f",
            desc: "The buff bar and its icons bigger, x1 to x2. It grows left and up from its corner.",
            on: (*) => gameDisplay.buffBar, set: (v) => gameDisplay.setBuffBar(v), status: (*) => gameDisplay.buffBarStatus(),
            opts: (d) => (OptSlider(d, "Size", (*) => gameDisplay.buffBarScale, (v) => gameDisplay.setBuffBarScale(v), 1, 2, 0.05, BarSizeText),
                OptNote(d, "Times the game's own size. Still 8 buffs at most: the game has 8 buff icons. With the Widescreen UI on, it grows to the right instead.")) },
        { tab: "display", title: "Hide hover names", badge: "1.28f",
            desc: "As WFE's Hero Overhead Tip off: no name over the unit under the mouse.",
            on: (*) => gameDisplay.unitNames, set: (v) => gameDisplay.setUnitNames(v), status: (*) => gameDisplay.unitNamesStatus() },
        { tab: "display", title: "Fast menu", badge: "1.28f",
            desc: "As WFE's: the menus' screens change at once, without their slow animations.",
            on: (*) => gameDisplay.fastMenu, set: (v) => gameDisplay.setFastMenu(v), status: (*) => gameDisplay.fastMenuStatus() },
        { tab: "display", title: "Detailed tooltips", badge: "1.28f",
            desc: "As WFE's: the damage and armor tooltips show cooldown, attacks a second, speed.",
            on: (*) => gameDisplay.tooltips, set: (v) => gameDisplay.setTooltips(v), status: (*) => gameDisplay.tooltipsStatus(),
            opts: (d) => (OptCheck(d, "Portrait: HP and mana with their regen per second", healthBars.portrait, (v) => healthBars.setPortrait(v)),
                OptCheck(d, "and the percent", healthBars.portraitPercent, (v) => healthBars.setPortraitPercent(v), 22),
                OptNote(d, "The portrait lines go with this switch.")) },
        { tab: "display", title: "FPS unlock", badge: "1.28f",
            desc: "Lifts the game's frame rate cap, up to the limit you pick. Off puts it back.",
            on: (*) => gameDisplay.fps, set: (v) => gameDisplay.setFps(v), status: (*) => gameDisplay.fpsStatus(),
            opts: (d) => (OptSlider(d, "Limit", (*) => gameDisplay.fpsLimit, (v) => gameDisplay.setFpsLimit(v), 64, 1000, 1),
                OptNote(d, "Frames a second, 64 to 1000.")) },
        { tab: "combat", title: "Damage meter", badge: "1.28f",
            desc: "Damage by player over the game: total, DPS and share for each fight.",
            on: (*) => dmgMeter.enabled, set: (v) => dmgMeter.setEnabled(v), status: (*) => dmgMeter.statusText(),
            opts: (d) => (OptSlider(d, "Rows", (*) => dmgMeter.rowCount, (v) => dmgMeter.setRows(v), 3, 12, 1),
                OptSlider(d, "Fight ends", (*) => dmgMeter.idleSecs, (v) => dmgMeter.setIdle(v), 1, 30, 0.5, SecsText),
                OptNote(d, "After this long with no damage a fight is over: its numbers stay until the next one starts."),
                OptSlider(d, "Opacity", (*) => dmgMeter.opacity, (v) => dmgMeter.setOpacity(v), 30, 100, 1),
                OptDivider(d),
                OptButtons(d, [["Show the meter", (*) => (dmgMeter.setHidden(false), RefreshWc3())], ["Show a sample", (*) => dmgMeter.setSample(true)], ["Hide the sample", (*) => dmgMeter.setSample(false)], ["Reset", (*) => (dmgMeter.reset(), dmgMeter.tick())]]),
                OptNote(d, "Its ✕ hides it (it keeps counting); Show the meter brings it back. The sample is made-up players fighting: drag the meter where you want it, an edge or corner to size it.")) },
        { tab: "hosting", title: "Lobby latency", badge: "1.28f",
            desc: "Games you host answer orders sooner: a shorter turn time, as WFE's.",
            on: (*) => gameDisplay.latency, set: (v) => gameDisplay.setLatency(v), status: (*) => gameDisplay.latencyStatus(),
            opts: (d) => (OptSlider(d, "Latency", (*) => gameDisplay.latencyMs, (v) => gameDisplay.setLatencyMs(v), 5, 1000, 1),
                OptNote(d, "Milliseconds, 5 to 1000. The game's own is 100, as is WFE's default.")) },
        { tab: "hosting", title: "Start countdown", badge: "1.28f",
            desc: "As WFE's: games you host start this long after Start Game, not 6 s.",
            on: (*) => gameDisplay.countdown, set: (v) => gameDisplay.setCountdown(v), status: (*) => gameDisplay.countdownStatus(),
            opts: (d) => (OptSlider(d, "Seconds", (*) => gameDisplay.countdownSecs, (v) => gameDisplay.setCountdownSecs(v), 0, 6, 0.1, SecsText),
                OptNote(d, "From 0 to 6 s; the game's own is 6. WFE adds 0.1 s, so does this.")) },
        { tab: "hosting", title: "Battle.net login", badge: "1.28f",
            desc: "Straight to Battle.net, logged in, and into your game (or the custom games).",
            on: (*) => bnetLogin.enabled, set: (v) => bnetLogin.setEnabled(v), status: (*) => bnetLogin.statusText(),
            window: (*) => BattleNetLoginDialog() },
    ]
    return list
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
    ; the version switch, at the far right of the title row (page space is
    ; shifted by CX - 40, CY - 160), what's running just left of it
    local vx := TB_R - (CX - 40) - 2 * 86 + 4
    for i, v in Wc3Versions() {
        local b := MkButton(v[2], vx + (i - 1) * 86, TB_Y + 1 - CY + 160, 82, 26, C.chip, C.muted, Wc3ShowVersion.Bind(v[1]))
        wc3VerBtns[v[1]] := b
        AddToPage("wc3", b)
    }
    wc3VerText := mainGui.AddText("x" (vx - 8 - 270) " y" (TB_Y + 5 - CY + 160) " w270 h18 Right 0x200 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3VerText, "s8")
    AddToPage("wc3", wc3VerText)
    ; tabs, like the Overlay page's dock switch
    for i, t in Wc3Tabs() {
        local b := MkButton(t[2], x + (i - 1) * 96, y, 90, 28, C.chip, C.muted, Wc3ShowTab.Bind(t[1]))
        wc3TabBtns[t[1]] := b
        AddToPage("wc3", b)
    }
    ; the game module (1.28f side only): its master switch and log
    local gl := mainGui.AddText("x" x " y" (y + 40) " w170 h22 0x200 +Background" C.panel " c" C.text, "Game module (1.28f)")
    UISetFont(gl, "s10 w600")
    wc3ModuleText := mainGui.AddText("x" (x + 176) " y" (y + 40) " w" (cw - 176 - 246) " h22 0x200 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3ModuleText, "s8")
    local chkBtn := MkButton("Check", x + cw - 236, y + 38, 70, 26, C.chip, C.text, (*) => ModuleCheckDialog())
    wc3ModuleBtn := MkButton("Off", x + cw - 160, y + 38, 70, 26, C.chip, C.muted, (*) => (gameModule.setEnabled(!gameModule.enabled), RefreshWc3()))
    local logBtn := MkButton("Log", x + cw - 84, y + 38, 70, 26, C.chip, C.text, (*) => Wc3OpenLog())
    AddToPage("wc3", gl, wc3ModuleText, chkBtn, wc3ModuleBtn, logBtn)
    wc3ModuleRow := [gl, wc3ModuleText, chkBtn, wc3ModuleBtn, logBtn]
    ; feature cards, all built at one spot: RefreshWc3 shows the tab's and
    ; version's own and lays them out in two columns
    for f in Wc3Features() {
        local top := y + 82, cwd := WC3_COL_W, right := x + cwd - 12 - 64
        local card := Box("wc3", x, top, cwd, WC3_CARD_H, C.card, C.border, 6)
        local tt := mainGui.AddText("x" (x + 12) " y" (top + 6) " w200 h20 0x200 +Background" C.card " c" C.text, f.title)
        UISetFont(tt, "s10 w600")
        local tw := Min(TextWidth(tt, f.title), cwd - 12 - 90 - 70)
        tt.Move(, , tw + 4)
        local bd := mainGui.AddText("x" (x + 20 + tw) " y" (top + 8) " w62 h16 0x200 +Background" C.card " c" C.accent, f.badge)
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
        SetIf(wc3Planned, hc.f.title " (" hc.f.badge "): " hc.f.desc "`n" hc.f.status())
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
    d := Wc3Dialog("Buff alerts", "A line over the game when a buff you watch is missing on your hero, or running out.", 480)
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
    d := Wc3Dialog("Battle.net login", "At the main menu, the game goes to Battle.net and logs in with your account: on the gateway chosen in the game (eurobattle.net).", 460)
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
    OptCheck(d, "Open the custom games", bnetLogin.customGames, (v) => bnetLogin.setCustomGames(v))
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
; a checkbox; indent moves it right (a sub-option)
OptCheck(d, text, on, set, indent := 0) {
    global C
    cb := d.g.AddCheckbox("x" (d.x + indent) " y" d.y " w" (d.tw - indent) " h24 +Background" C.card " c" C.text (on ? " Checked" : ""), " " text)
    cb.OnEvent("Click", (src, *) => set(src.Value))
    d.y += 30
    return cb
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
    g := d.g, bx := d.x + 80, btns := []
    lb := g.AddText("x" d.x " y" (d.y + 3) " w76 h22 0x200 +Background" C.card " c" C.text, label)
    for ch in choices {
        b := g.AddText("x" bx " y" d.y " w60 h26 Center 0x200 +Background" C.chip " c" C.muted, ch[2])
        UISetFont(b, "s9 w600")
        bw := Max(70, TextWidth(b, ch[2]) + 22), b.Move(, , bw), Box.Round(b, bw, 26, 4)
        btns.Push({ ctl: b, v: ch[1] })
        bx += bw + 6
    }
    paint() {
        for it in btns
            it.ctl.Opt("+Background" (it.v = get() ? C.navOn : C.chip) " +c" (it.v = get() ? C.accent : C.muted)), it.ctl.Redraw()
    }
    for it in btns
        it.ctl.OnEvent("Click", ((v, *) => (set(v), paint())).Bind(it.v))
    paint()
    d.y += 34
}
; a row of buttons: [[text, click], ...]
OptButtons(d, list) {
    global C
    bx := d.x
    for b in list {
        bt := d.g.AddText("x" bx " y" d.y " w60 h28 Center 0x200 +Background" C.chip " c" C.text, b[1])
        UISetFont(bt, "s9 w600")
        bw := Max(90, TextWidth(bt, b[1]) + 24), bt.Move(, , bw), Box.Round(bt, bw, 28, 4)
        bt.OnEvent("Click", b[2])
        bx += bw + 8
    }
    d.y += 36
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
    cb := g.AddCheckbox("x" (d.x + 146 + 60 + 14) " y" (d.y + 1) " w" (d.tw - 146 - 60 - 14) " h26 +Background" C.card " c" C.text (col = "player" ? " Checked" : ""), " " boxText)
    paint() => (cur := get(), sw.Opt("+Background" (cur = "player" ? C.card : cur)), sw.Redraw(), cb.Value := cur = "player")
    sw.OnEvent("Click", (*) => (pick() != "" && paint()))
    cb.OnEvent("Click", (src, *) => (check(src.Value), paint()))
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
    d := Wc3Dialog("Health and mana bar size", "Health bars: times the game's own size (Health bar size switch). Mana bars: times their health bar's.", 460)
    g := d.g
    for sec in [["HEALTH BARS", [["height", "Height"], ["width", "Width"]]], ["MANA BARS", [["manaHeight", "Height"], ["manaWidth", "Width"]]]] {
        if sec[1] = "MANA BARS"
            OptDivider(d)
        OptHeader(d, sec[1])
        for r in sec[2] {
            lim := HealthBarsEngine.SIZES[r[1]]
            OptSlider(d, r[2], ((k, *) => healthBars.size(k)).Bind(r[1]), ((k, v) => healthBars.setSize(k, v)).Bind(r[1]), lim[2], lim[3], 0.01, BarSizeText)
        }
        OptNote(d, sec[1] = "HEALTH BARS" ? "×0.25 to ×4; ×1 is the game's own. The width is experimental." : "×0.25 to ×2 of the health bar; shown with the Mana bars switch.")
    }
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
    d := Wc3Dialog("Health bar colours", "By owner (your own colour, or each owner's player colour), or by health left.", 440)
    g := d.g
    OptChoice(d, "Colour", [["owner", "By owner"], ["health", "By health"]], (*) => healthBars.colourMode, (v) => healthBars.setColourMode(v))
    OptNote(d, "By health: green, to yellow at half, to red.")
    OptDivider(d)
    OptHeader(d, "BY OWNER")
    for o in HealthBarsEngine.OWNERS
        OptColour(d, o[3], ((key, *) => healthBars.colour(key)).Bind(o[1]), BarPickColour.Bind(o[1], g), "Player colour",
            ((key, def, on) => BarPlayerColour(key, def, on)).Bind(o[1], o[2]))
    OptNote(d, "Click a colour to change it. Player colour: each owner's own (the game's 12).")
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
    gameCmds.capture(name)
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
    if (r := Wc3RunningVer()) != "" && r != wc3Ver
        wc3Ver := r, SetIni(r, "Wc3", "view")
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
Wc3VerLine() {
    global wc3Ver
    r := Wc3RunningVer()
    return r = "" ? "No game running" : r = wc3Ver ? "● " Wc3VerBadge(r) " is running"
        : "● " Wc3VerBadge(r) " is running (this is the " Wc3VerBadge(wc3Ver) " side)"
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
    global wc3Ver, wc3VerBtns, wc3VerText, wc3ModuleRow, wc3PageNo, wc3PagerCtls, wc3PagerText, H, wc3HoverCard
    ; only on its own page: it shows its cards, and called from elsewhere (a window that
    ; closed over another page) it drew them over that page
    if currentPage != "wc3"
        return SetTimer(Wc3Tick, 0)
    Freeze()
    for ver, b in wc3VerBtns
        Wc3SetSelected(b, ver = wc3Ver)
    SetIf(wc3VerText, Wc3VerLine())
    for tab, b in wc3TabBtns
        Wc3SetSelected(b, tab = wc3Tab)
    ; the game module row: 1.28f only
    withModule := wc3Ver = "128"
    for c in wc3ModuleRow
        SetShown(c, withModule)
    Wc3SetSwitch(wc3ModuleBtn, gameModule.enabled)
    SetIf(wc3ModuleText, gameModule.statusText())
    wc3TabBtns[Wc3Tabs()[1][1]].GetPos(&tx, &ty, , &th)
    topY := ty + th + (withModule ? 44 : 12)        ; under the module row, or right under the tabs
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
    global currentPage, mainGui, wc3Tab, wc3Cards, wc3ModuleBtn, wc3ModuleText, gameModule, wc3Ver, wc3VerText, wc3HoverCard
    if currentPage != "wc3" || !DllCall("IsWindowVisible", "ptr", mainGui.Hwnd)
        return SetTimer(Wc3Tick, 0)
    SetIf(wc3VerText, Wc3VerLine())
    SetIf(wc3ModuleText, gameModule.statusText())
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
