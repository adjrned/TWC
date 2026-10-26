#Requires AutoHotkey v2.0
; ============================================================================
;  WC3 page - features that read or change the running game, in one place.
;  At the top, the version switch: 1.28f | Reforged. The page shows only what
;  works on that version (and "Both" features); opening the page picks the
;  running game's version. 1.28f features may use the game module (injected;
;  its row is only on the 1.28f side); Reforged ones only read the screen.
;  Four tabs set where every feature goes, now and later:
;    Casting   how abilities go off: quickcast (screen or game module), the
;              self-cast and autocast toggle keys
;    Timers    what's ready and what's running out: cooldown and buff timers
;              (over the game or in it), buff alerts
;    Display   how the game looks: health bar size and colours, health
;              numbers, mana bars, portrait regen, game keys (messages, chat,
;              the multiboard), widescreen, FPS unlock, hiding the UI; later detailed tooltips
;    Hosting   games you host: lobby latency; later the start countdown
;  Each feature is one entry in Wc3Features(): a card with its version
;  (badge), an On/Off switch (if it has one), a live status line and its
;  buttons. Built in the pages' (40, 160) layout space like the other pages.
;  A tab with more cards than fit shows them in pages (‹ n/m › in the tab row).
; ============================================================================

global wc3Tab := "casting", wc3TabBtns := Map(), wc3Cards := [], wc3ModuleBtn, wc3ModuleText, wc3Planned
global wc3Ver := Ini("Wc3", "view", "128"), wc3VerBtns := Map(), wc3VerText, wc3ModuleRow := []
global wc3PageNo := Map(), wc3PagerCtls := [], wc3PagerText       ; tab + version -> the page shown

Wc3Tabs() => [["casting", "Casting"], ["timers", "Timers"], ["display", "Display"], ["hosting", "Hosting"]]
; the two versions: key, switch label
Wc3Versions() => [["128", "1.28f"], ["reforged", "Reforged"]]
Wc3VerBadge(ver) => ver = "128" ? "1.28f" : "Reforged"
; the running game's version ("128" / "reforged"), "" if none
Wc3RunningVer() => (k := WC3WindowKey()) = "" ? "" : InStr(k, "reforged") = 1 ? "reforged" : "128"
; does a feature show on the version in view?
Wc3OnVersion(f, ver) => f.badge = "Both" || f.badge = Wc3VerBadge(ver)

; what each tab will hold later on each version (shown under its cards)
Wc3PlannedText(tab, ver) {
    static p := Map(
        "casting128", "",
        "castingreforged", "",
        "timers128", "",
        "timersreforged", "Planned: cooldown and buff timers read from the screen. To help build them: tray menu > Debug: save HUD pictures, in a game, then send the folder.",
        "display128", "Planned: detailed tooltips.",
        "displayreforged", "Nothing planned yet.",
        "hosting128", "Planned: the game start countdown when you host.",
        "hostingreforged", "Nothing planned: Battle.net hosts Reforged games.")
    return p[tab ver]
}

; Every feature on the page. Keys: tab, title, badge ("1.28f" / "Reforged" /
; "Both"), desc, status() -> text; optional on() / set(v) for the switch,
; setupLabel + setup() for one button, or buttons: [[label, click], ...]
; (a label can be a function: it's refreshed with the status).
Wc3Features() {
    global gameModule, timersHud, quickcast, gameCmds, buffWatch, healthBars, gameDisplay
    static list := 0
    if list
        return list
    list := [
        { tab: "casting", title: "Quickcast from the screen", badge: "Both",
            desc: "Reads the command card to see when the game wants a target. On per key in Remap.",
            status: Wc3ScreenQcStatus, setupLabel: "Set up", setup: (*) => QuickcastSettings() },
        { tab: "casting", title: "Quickcast through the game", badge: "1.28f",
            desc: "The game itself says when it wants a target: no setup. Until then, the screen.",
            on: (*) => gameModule.quickcast, set: (v) => gameModule.setQuickcast(v), status: (*) => gameModule.qcStatusText() },
        { tab: "casting", title: "Self-cast key", badge: "Both",
            desc: "Hold it while you cast: the ability goes on your selected unit.",
            on: (*) => gameCmds.selfcast, set: (v) => gameCmds.setSelfcast(v), status: (*) => gameCmds.selfStatusText(),
            buttons: [[(*) => "Key: " gameCmds.heldText("selfcast"), (*) => Wc3Capture("selfcast")],
                ["Portrait", (*) => (WinExist(WarcraftIII) && HideMainWindow(), gameCmds.portraitSetupStart())]] },
        { tab: "casting", title: "Autocast toggle key", badge: "1.28f",
            desc: "Hold it and press an ability's key: its autocast turns on or off.",
            on: (*) => gameCmds.autocast, set: (v) => gameCmds.setAutocast(v), status: (*) => gameCmds.acStatusText(),
            buttons: [[(*) => "Key: " gameCmds.heldText("autocast"), (*) => Wc3Capture("autocast")]] },
        { tab: "timers", title: "Cooldown and buff timers", badge: "1.28f",
            desc: "Seconds left on abilities and buffs, over the game, or in it (items too).",
            on: (*) => timersHud.enabled, set: (v) => timersHud.setEnabled(v), status: (*) => timersHud.statusText(),
            buttons: [[(*) => timersHud.whereLabel, (*) => (timersHud.toggleWhere(), RefreshWc3())],
                ["Set up buff bar", (*) => (WinExist(WarcraftIII) && HideMainWindow(), timersHud.setupStart())]] },
        { tab: "timers", title: "Buff alerts", badge: "Both",
            desc: "A line over the game when a buff you added is missing, or (1.28f) running out.",
            on: (*) => buffWatch.enabled, set: (v) => buffWatch.setEnabled(v), status: (*) => buffWatch.statusText(),
            buttons: [["Buff bar", (*) => (WinExist(WarcraftIII) && HideMainWindow(), timersHud.setupStart())],
                ["Add buff", (*) => (WinExist(WarcraftIII) && HideMainWindow(), buffWatch.captureStart())],
                ["Buffs", (*) => BuffWatchDialog()]] },
        { tab: "display", title: "Health bar size", badge: "1.28f",
            desc: "Bigger health bars on every unit. Width is experimental.",
            on: (*) => healthBars.enabled, set: (v) => healthBars.setEnabled(v), status: (*) => healthBars.statusText(),
            buttons: [[(*) => healthBars.sizeLabel, (*) => BarSizeDialog("health")]] },
        { tab: "display", title: "Health bar colours", badge: "1.28f",
            desc: "By owner (your colour or each player's own) or by health left.",
            on: (*) => healthBars.colours, set: (v) => healthBars.setColours(v), status: (*) => healthBars.colourStatus(),
            buttons: [[(*) => healthBars.colourModeLabel, (*) => (healthBars.toggleColourMode(), RefreshWc3())],
                ["Colours", (*) => BarColoursDialog()]] },
        { tab: "display", title: "Health numbers", badge: "1.28f",
            desc: "A number over every health bar: current, current / max or percent (Storm.dll).",
            on: (*) => healthBars.numbers, set: (v) => healthBars.setNumbers(v), status: (*) => healthBars.numberStatus(),
            buttons: [[(*) => healthBars.numberModeLabel, (*) => (healthBars.cycleNumberMode(), RefreshWc3())]] },
        { tab: "display", title: "Mana bars", badge: "1.28f",
            desc: "A mana bar under the health bar of every unit with mana (Storm.dll).",
            on: (*) => healthBars.mana, set: (v) => healthBars.setMana(v), status: (*) => healthBars.manaStatus(),
            buttons: [[(*) => healthBars.manaSizeLabel, (*) => BarSizeDialog("mana")]] },
        { tab: "display", title: "Portrait regen", badge: "1.28f",
            desc: "The portrait's HP and mana lines with regen per second (and the percent).",
            on: (*) => healthBars.portrait, set: (v) => healthBars.setPortrait(v), status: (*) => healthBars.portraitStatus(),
            buttons: [[(*) => healthBars.portraitPercentLabel, (*) => (healthBars.togglePortraitPercent(), RefreshWc3())]] },
        { tab: "display", title: "Game keys", badge: "1.28f",
            desc: "Keys that wipe the trigger messages or the chat, and minimise the multiboard.",
            on: (*) => gameCmds.enabled, set: (v) => gameCmds.setEnabled(v), status: (*) => gameCmds.statusText(),
            buttons: [[(*) => "Messages: " gameCmds.keyText("clearMessages"), (*) => Wc3Capture("clearMessages")],
                [(*) => "Chat: " gameCmds.keyText("clearChat"), (*) => Wc3Capture("clearChat")],
                [(*) => "Multiboard: " gameCmds.keyText("multiboard"), (*) => Wc3Capture("multiboard")]] },
        { tab: "display", title: "Hide the UI", badge: "1.28f",
            desc: "As WFE: the black console goes, the world shows through; the minimap stays.",
            on: (*) => gameDisplay.hideUi, set: (v) => gameDisplay.setHideUi(v), status: (*) => gameDisplay.hideStatus(),
            buttons: [[(*) => gameDisplay.menuLabel, (*) => (gameDisplay.toggleHideMenu(), RefreshWc3())]] },
        { tab: "hosting", title: "Lobby latency", badge: "1.28f",
            desc: "Games you host answer orders sooner: a shorter turn time, as WFE's.",
            on: (*) => gameDisplay.latency, set: (v) => gameDisplay.setLatency(v), status: (*) => gameDisplay.latencyStatus(),
            buttons: [[(*) => gameDisplay.latencyLabel, (*) => (gameDisplay.cycleLatency(), RefreshWc3())]] },
        { tab: "display", title: "Widescreen", badge: "1.28f",
            desc: "As WFE's: the world isn't stretched on a wide screen. The UI stays 4:3.",
            on: (*) => gameDisplay.widescreen, set: (v) => gameDisplay.setWidescreen(v), status: (*) => gameDisplay.wsStatus() },
        { tab: "display", title: "Widescreen UI", badge: "1.28f",
            desc: "As WFE's Upgraded UI: on a wide window the UI isn't stretched.",
            on: (*) => gameDisplay.wideUi, set: (v) => gameDisplay.setWideUi(v), status: (*) => gameDisplay.wideUiStatus() },
        { tab: "display", title: "FPS unlock", badge: "1.28f",
            desc: "Lifts the game's frame rate cap, up to the limit you pick. Off puts it back.",
            on: (*) => gameDisplay.fps, set: (v) => gameDisplay.setFps(v), status: (*) => gameDisplay.fpsStatus(),
            buttons: [[(*) => gameDisplay.limitLabel, (*) => (gameDisplay.cycleLimit(), RefreshWc3())]] },
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
    ; the version switch, in the title row right after the title (its control
    ; is 150 wide from CX; page space is shifted by CX - 40, CY - 160)
    local vx := 150 + 10 + 40
    for i, v in Wc3Versions() {
        local b := MkButton(v[2], vx + (i - 1) * 86, TB_Y + 1 - CY + 160, 82, 26, C.chip, C.muted, Wc3ShowVersion.Bind(v[1]))
        wc3VerBtns[v[1]] := b
        AddToPage("wc3", b)
    }
    wc3VerText := mainGui.AddText("x" (vx + 2 * 86 + 8) " y" (TB_Y + 5 - CY + 160) " w270 h18 0x200 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3VerText, "s8")
    AddToPage("wc3", wc3VerText)
    ; tabs, like the Overlay page's dock switch
    for i, t in Wc3Tabs() {
        local b := MkButton(t[2], x + (i - 1) * 96, y, 90, 28, C.chip, C.muted, Wc3ShowTab.Bind(t[1]))
        wc3TabBtns[t[1]] := b
        AddToPage("wc3", b)
    }
    ; the game module (1.28f side only): its master switch and log
    local gl := mainGui.AddText("x" x " y" (y + 44) " w170 h22 0x200 +Background" C.panel " c" C.text, "Game module (1.28f)")
    UISetFont(gl, "s10 w600")
    wc3ModuleText := mainGui.AddText("x" (x + 176) " y" (y + 44) " w" (cw - 176 - 246) " h22 0x200 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3ModuleText, "s8")
    local chkBtn := MkButton("Check", x + cw - 236, y + 42, 70, 26, C.chip, C.text, (*) => ModuleCheckDialog())
    wc3ModuleBtn := MkButton("Off", x + cw - 160, y + 42, 70, 26, C.chip, C.muted, (*) => (gameModule.setEnabled(!gameModule.enabled), RefreshWc3()))
    local logBtn := MkButton("Log", x + cw - 84, y + 42, 70, 26, C.chip, C.text, (*) => Wc3OpenLog())
    AddToPage("wc3", gl, wc3ModuleText, chkBtn, wc3ModuleBtn, logBtn)
    wc3ModuleRow := [gl, wc3ModuleText, chkBtn, wc3ModuleBtn, logBtn]
    ; feature cards, all built at one spot: RefreshWc3 shows the tab's and
    ; version's own and stacks them
    for f in Wc3Features() {
        local top := y + 82
        local card := Box("wc3", x, top, cw, 70, C.card, C.border, 6)
        local tt := mainGui.AddText("x" (x + 14) " y" (top + 8) " w300 h20 0x200 +Background" C.card " c" C.text, f.title)
        UISetFont(tt, "s10 w600")
        local tw := TextWidth(tt, f.title)
        tt.Move(, , tw + 4)
        local bd := mainGui.AddText("x" (x + 22 + tw) " y" (top + 10) " w70 h16 0x200 +Background" C.card " c" C.accent, f.badge)
        UISetFont(bd, "s8 w600")
        local ds := mainGui.AddText("x" (x + 14) " y" (top + 29) " w" (cw - 200) " h16 +Background" C.card " c" C.dim, f.desc)
        UISetFont(ds, "s8")
        local st := mainGui.AddText("x" (x + 14) " y" (top + 47) " w" (cw - 200) " h16 +Background" C.card " c" C.muted, "")
        UISetFont(st, "s8")
        local sw := 0, btns := []
        if f.HasProp("on") {
            sw := MkButton("Off", x + cw - 84, top + 10, 70, 24, C.chip, C.muted, Wc3Switch.Bind(f))
            AddToPage("wc3", sw)
        }
        ; buttons: under the switch (or in the middle), right to left, each as
        ; wide as its label (a live label gets room to change)
        local defs := f.HasProp("buttons") ? f.buttons : f.HasProp("setup") ? [[f.setupLabel, f.setup]] : []
        local bx := x + cw - 14
        loop defs.Length {
            local d := defs[defs.Length - A_Index + 1], lbl := Wc3Label(d[1])
            local b := MkButton(lbl, 0, top + (sw ? 38 : 22), 70, 24, C.chip, C.text, d[2])
            local bw := HasMethod(d[1]) ? 116 : Max(70, TextWidth(b, lbl) + 20)
            bx -= bw
            b.Move(bx, , bw)
            bx -= 6
            AddToPage("wc3", b)
            btns.Push({ ctl: b, label: d[1] })
        }
        ; the text lines end where the buttons begin
        if btns.Length > 1
            ds.Move(, , bx - x - 24), st.Move(, , bx - x - 24)
        AddToPage("wc3", tt, bd, ds, st)
        wc3Cards.Push({ f: f, box: card, ctrls: [tt, bd, ds, st], sw: sw, btns: btns, top: 0, shown: false })
    }
    ; the pager, at the right end of the tab row (shown only when a tab has pages)
    local pr := MkButton("‹", x + cw - 108, y + 2, 28, 24, C.chip, C.text, Wc3Turn.Bind(-1))
    wc3PagerText := mainGui.AddText("x" (x + cw - 76) " y" (y + 2) " w44 h24 Center 0x200 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3PagerText, "s8")
    local nx := MkButton("›", x + cw - 28, y + 2, 28, 24, C.chip, C.text, Wc3Turn.Bind(1))
    AddToPage("wc3", pr, wc3PagerText, nx)
    wc3PagerCtls := [pr, wc3PagerText, nx]
    wc3Planned := mainGui.AddText("x" x " y" (y + 82 + 4 * 80) " w" cw " h34 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3Planned, "s8")
    AddToPage("wc3", wc3Planned)
}

; The buff alerts' Buffs window, in the Quickcast Setup window's style: a
; name for each watched buff (shown in the alert line), Remove, and the
; running-out warning (1.28f, game module). Names save as you type.
BuffWatchDialog() {
    global C, mainGui, buffWatch, UI_FONT
    static g := 0
    if g
        try g.Destroy()
    list := buffWatch.buffs(), w := 460, x := 26, tw := w - 52
    g := Gui("-Caption +ToolWindow +AlwaysOnTop +Owner" mainGui.Hwnd)
    g.BackColor := C.frame                           ; = the 1px border
    g.MarginX := 0, g.MarginY := 0
    card := g.AddText("x1 y1 w" (w - 2) " h10 +Background" C.card)
    t := g.AddText("x" x " y22 w" tw " h28 +Background" C.card " c" C.text, "Watched buffs")
    t.SetFont("s13 w700 q4", "Cinzel")
    intro := list.Length ? "Their names show in the alert line over the game." : "None yet: Add buff on the WC3 page, in a game with the buff on your hero."
    it := g.AddText("x" x " y56 w" tw " h18 +Background" C.card " c" C.dim, intro)
    UISetFont(it, "s9")
    y := 86
    g.SetFont("s10", UI_FONT)
    for i, b in list {
        n := g.AddText("x" x " y" (y + 2) " w24 h20 +Background" C.card " c" C.muted, i)
        UISetFont(n, "s9 w600")
        e := g.AddEdit("x" (x + 28) " y" y " w" (tw - 28 - 96) " h24 +Background" C.well " c" C.text, b.name)
        e.OnEvent("Change", ((i, src, *) => buffWatch.rename(i, src.Value)).Bind(i))
        r := g.AddText("x" (x + tw - 86) " y" y " w86 h24 Center 0x200 +Background" C.chip " c" C.text, "Remove")
        UISetFont(r, "s9 w600"), Box.Round(r, 86, 24, 4)
        r.OnEvent("Click", ((i, *) => (buffWatch.remove(i), BuffWatchDialog(), RefreshWc3())).Bind(i))
        y += 32
    }
    y += 8
    g.AddText("x" x " y" y " w" tw " h1 +Background" C.border)     ; divider
    y += 16
    wl := g.AddText("x" x " y" (y + 2) " w226 h20 +Background" C.card " c" C.text, "Warn when one has this left:")
    UISetFont(wl, "s10")
    wv := g.AddEdit("x" (x + 230) " y" y " w48 h22 Number Center +Background" C.well " c" C.text, buffWatch.warnAt)
    g.AddText("x" (x + 284) " y" (y + 2) " w120 h20 +Background" C.card " c" C.text, "s  (0 = never)")
    wv.OnEvent("Change", (src, *) => (src.Value != "" && buffWatch.setWarnAt(src.Value)))
    y += 28
    wn := g.AddText("x" x " y" y " w" tw " h18 +Background" C.card " c" C.dim, "1.28f with the game module: it reads how long each buff has left.")
    UISetFont(wn, "s8")
    y += 34
    close := g.AddText("x" (w - x - 104) " y" y " w104 h34 Center 0x200 +Background" C.chip " c" C.text, "Close")
    UISetFont(close, "s9 w600"), Box.Round(close, 104, 34, 4)
    close.OnEvent("Click", (*) => (g.Destroy(), RefreshWc3()))
    h := y + 34 + 24
    card.Move(, , , h - 2)
    g.OnEvent("Escape", (*) => (g.Destroy(), RefreshWc3()))
    WinGetPos(&ox, &oy, &ow, &oh, mainGui)
    g.Show("x" Round(ox + (ow - w * DPI_K) / 2) " y" Round(oy + (oh - h * DPI_K) / 2) " w" w " h" h)
}

; a dialog in the Buffs window's style: -> { g, card, x, tw, y } to add to, then Wc3DialogShow
Wc3Dialog(title, intro, w := 380) {
    global C, mainGui, UI_FONT
    x := 26, tw := w - 52
    g := Gui("-Caption +ToolWindow +AlwaysOnTop +Owner" mainGui.Hwnd)
    g.BackColor := C.frame                           ; = the 1px border
    g.MarginX := 0, g.MarginY := 0
    card := g.AddText("x1 y1 w" (w - 2) " h10 +Background" C.card)
    t := g.AddText("x" x " y22 w" tw " h28 +Background" C.card " c" C.text, title)
    t.SetFont("s13 w700 q4", "Cinzel")
    it := g.AddText("x" x " y56 w" tw " h18 +Background" C.card " c" C.dim, intro)
    UISetFont(it, "s9")
    g.SetFont("s10", UI_FONT)
    return { g: g, card: card, x: x, tw: tw, w: w, y: 86 }
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
    WinGetPos(&ox, &oy, &ow, &oh, mainGui)
    g.Show("x" Round(ox + (ow - w * DPI_K) / 2) " y" Round(oy + (oh - h * DPI_K) / 2) " w" w " h" h)
}

; Health bar / mana bar size: a slider and a box to type in, per side; it
; changes in the game as you go
BarSizeDialog(kind) {
    global C, healthBars
    static g := 0
    if g
        try g.Destroy()
    rows := kind = "mana" ? [["manaHeight", "Height"], ["manaWidth", "Width"]] : [["height", "Height"], ["width", "Width"]]
    d := Wc3Dialog(kind = "mana" ? "Mana bar size" : "Health bar size",
        kind = "mana" ? "Times the health bar's height and width." : "Times the game's own size. Width is experimental.")
    g := d.g
    for r in rows {
        lim := HealthBarsEngine.SIZES[r[1]]
        lb := g.AddText("x" d.x " y" (d.y + 2) " w60 h22 0x200 +Background" C.card " c" C.text, r[2])
        sl := g.AddSlider("x" (d.x + 64) " y" d.y " w" (d.tw - 64 - 70) " h26 NoTicks Range" Round(lim[2] * 100) "-" Round(lim[3] * 100)
            " +Background" C.card, Round(healthBars.size(r[1]) * 100))
        ed := g.AddEdit("x" (d.x + d.tw - 60) " y" (d.y + 1) " w60 h24 Center +Background" C.well " c" C.text, BarSizeText(healthBars.size(r[1])))
        busy := { on: false }
        sl.OnEvent("Change", ((key, ed, busy, src, *) => (healthBars.setSize(key, src.Value / 100), busy.on := true,
            ed.Value := BarSizeText(healthBars.size(key)), busy.on := false)).Bind(r[1], ed, busy))
        ed.OnEvent("Change", ((key, sl, busy, src, *) => (!busy.on && healthBars.setSize(key, StrReplace(Trim(src.Value), ",", "."))
            && (sl.Value := Round(healthBars.size(key) * 100)))).Bind(r[1], sl, busy))
        d.y += 36
    }
    lim := HealthBarsEngine.SIZES[rows[1][1]]
    nt := g.AddText("x" d.x " y" d.y " w" d.tw " h18 +Background" C.card " c" C.dim, "From ×" lim[2] " to ×" lim[3] "; ×1 is the game's own" (kind = "mana" ? " health bar's." : "."))
    UISetFont(nt, "s8")
    d.y += 22
    Wc3DialogShow(d)
    return g
}
BarSizeText(v) => RTrim(RTrim(Format("{:.2f}", v), "0"), ".")

; Health bar colours by owner: each a colour of your own, or the owner's player colour
BarColoursDialog() {
    global C, healthBars
    static g := 0
    if g
        try g.Destroy()
    d := Wc3Dialog("Health bar colours", "By owner. Player colour: the owner's own colour in the game.", 420)
    g := d.g
    for o in HealthBarsEngine.OWNERS {
        col := healthBars.colour(o[1])
        lb := g.AddText("x" d.x " y" (d.y + 2) " w130 h22 0x200 +Background" C.card " c" C.text, o[3])
        sw := g.AddText("x" (d.x + 136) " y" (d.y + 2) " w60 h22 +Border +Background" (col = "player" ? C.card : col), "")
        cb := g.AddCheckbox("x" (d.x + 210) " y" d.y " w" (d.tw - 210) " h26 +Background" C.card " c" C.text (col = "player" ? " Checked" : ""), " Player colour")
        sw.OnEvent("Click", ((key, sw, cb, *) => BarPickColour(key, sw, cb)).Bind(o[1], sw, cb))
        cb.OnEvent("Click", ((key, def, sw, src, *) => BarPlayerColour(key, def, sw, src.Value)).Bind(o[1], o[2], sw))
        d.y += 32
    }
    nt := g.AddText("x" d.x " y" d.y " w" d.tw " h18 +Background" C.card " c" C.dim, "Click a colour to change it.")
    UISetFont(nt, "s8")
    d.y += 22
    Wc3DialogShow(d)
    return g
}
BarPlayerColour(key, def, sw, on) {
    global healthBars, C
    last := Ini(healthBars.section, key "Own", def = "player" ? "FFFFFF" : def)
    healthBars.setColour(key, on ? "player" : last)
    sw.Opt("+Background" (on ? C.card : last)), sw.Redraw()
}
BarPickColour(key, sw, cb) {
    global healthBars
    col := healthBars.colour(key)
    if (rgb := ChooseColour(sw.Gui.Hwnd, col = "player" ? Ini(healthBars.section, key "Own", "FFFFFF") : col)) = ""
        return
    SetIni(rgb, healthBars.section, key "Own")
    healthBars.setColour(key, rgb)
    cb.Value := 0
    sw.Opt("+Background" rgb), sw.Redraw()
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

; move a card (its box, texts, switch, buttons and their boxes) to top y (window units)
Wc3MoveCard(card, y) {
    global boxes
    if !card.top
        card.box.outer.GetPos(, &t), card.top := t
    d := y - card.top
    if !d
        return
    card.top := y
    ctls := [card.box.outer, card.box.inner, card.ctrls*]
    if card.sw
        ctls.Push(card.sw)
    for b in card.btns
        ctls.Push(b.ctl)
    for c in ctls {
        c.GetPos(, &cTop)
        c.Move(, cTop + d)
        if boxes.Has(c.Hwnd) {
            bx := boxes[c.Hwnd]
            bx.Move(bx.x, bx.y + d, bx.w, bx.h)
        }
    }
}

RefreshWc3() {
    global wc3Tab, wc3TabBtns, wc3Cards, wc3ModuleBtn, wc3ModuleText, wc3Planned, gameModule, currentPage
    global wc3Ver, wc3VerBtns, wc3VerText, wc3ModuleRow, wc3PageNo, wc3PagerCtls, wc3PagerText, H
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
    wc3TabBtns["casting"].GetPos(, &ty, , &th)
    nextY := ty + th + (withModule ? 56 : 14)          ; under the module row, or right under the tabs
    ; the tab's cards on this version, in pages of as many as fit (70 high, 80 apart);
    ; the planned line goes under the last page's cards, or on a page of its own
    ; when they fill it
    inTab := 0
    for card in wc3Cards
        inTab += card.f.tab = wc3Tab && Wc3OnVersion(card.f, wc3Ver)
    perPage := Max(1, (H - nextY) // 80)
    pageCount := Max(1, Ceil(inTab / perPage))
    planned := Wc3PlannedText(wc3Tab, wc3Ver)
    if inTab && planned != "" && Mod(inTab, perPage) = 0 && nextY + perPage * 80 + 36 > H - 6
        pageCount++
    pk := wc3Tab wc3Ver, pageNo := wc3PageNo.Get(pk, 1)
    pageNo := pageNo < 1 ? pageCount : pageNo > pageCount ? 1 : pageNo
    wc3PageNo[pk] := pageNo
    for c in wc3PagerCtls
        SetShown(c, pageCount > 1)
    wc3PagerText.Text := pageNo " / " pageCount
    shown := 0, lastBottom := 0, idx := 0
    for card in wc3Cards {
        vis := card.f.tab = wc3Tab && Wc3OnVersion(card.f, wc3Ver)
        idx += vis
        vis := vis && idx > (pageNo - 1) * perPage && idx <= pageNo * perPage
        card.shown := vis
        card.box.Visible := vis
        for c in card.ctrls
            c.Visible := vis
        if card.sw
            SetShown(card.sw, vis)
        for b in card.btns {
            SetShown(b.ctl, vis)
            if vis
                SetIf(b.ctl, Wc3Label(b.label))
        }
        if !vis
            continue
        shown++
        Wc3MoveCard(card, nextY)
        nextY += 80, lastBottom := card.top + 70
        if card.sw
            Wc3SetSwitch(card.sw, card.f.on())
        SetIf(card.ctrls[4], card.f.status())
    }
    wc3Planned.Text := (inTab ? "" : "Nothing here yet.  ") planned
    wc3Planned.Move(, lastBottom ? lastBottom + 12 : nextY)
    wc3Planned.Visible := pageNo = pageCount
    Thaw()
    ; live status lines while the page is open
    SetTimer(Wc3Tick, currentPage = "wc3" ? 1000 : 0)
}
; once a second: just the status lines and switches (no repaint of the rest)
Wc3Tick() {
    global currentPage, mainGui, wc3Tab, wc3Cards, wc3ModuleBtn, wc3ModuleText, gameModule, wc3Ver, wc3VerText
    if currentPage != "wc3" || !DllCall("IsWindowVisible", "ptr", mainGui.Hwnd)
        return SetTimer(Wc3Tick, 0)
    SetIf(wc3VerText, Wc3VerLine())
    SetIf(wc3ModuleText, gameModule.statusText())
    if (wc3ModuleBtn.Text = "On") != !!gameModule.enabled
        Wc3SetSwitch(wc3ModuleBtn, gameModule.enabled)
    for card in wc3Cards
        if card.shown {
            SetIf(card.ctrls[4], card.f.status())
            if card.sw && (card.sw.Text = "On") != !!card.f.on()
                Wc3SetSwitch(card.sw, card.f.on())
        }
}
SetIf(ctl, text) {
    if ctl.Text != text
        ctl.Text := text
}
