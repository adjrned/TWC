#Requires AutoHotkey v2.0
; ============================================================================
;  WC3 page - features that read or change the running game, in one place.
;  At the top, the version switch: 1.28f | Reforged. The page shows only what
;  works on that version (and "Both" features); opening the page picks the
;  running game's version. 1.28f features may use the game module (injected;
;  its row is only on the 1.28f side); Reforged ones only read the screen.
;  Four tabs set where every feature goes, now and later:
;    Casting   how abilities go off: quickcast (screen or game module), later
;              a self-cast key, an autocast toggle key
;    Timers    what's ready and what's running out: cooldown and buff timers,
;              buff alerts
;    Display   how the game looks: clearing messages; later health bar size,
;              hero tracker and range ring, widescreen, FPS, hiding UI parts,
;              detailed tooltips
;    Hosting   games you host: later lobby latency, start countdown
;  Each feature is one entry in Wc3Features(): a card with its version
;  (badge), an On/Off switch (if it has one), a live status line and its
;  buttons. Built in the pages' (40, 160) layout space like the other pages.
; ============================================================================

global wc3Tab := "casting", wc3TabBtns := Map(), wc3Cards := [], wc3ModuleBtn, wc3ModuleText, wc3Planned
global wc3Ver := Ini("Wc3", "view", "128"), wc3VerBtns := Map(), wc3VerText, wc3ModuleRow := []

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
        "casting128", "Planned: a self-cast key (the next ability goes on your hero), an autocast toggle key.",
        "castingreforged", "Planned: a self-cast key (the next ability goes on your hero).",
        "timers128", "Planned: naming your buffs, alerts for a buff about to run out, timers drawn inside the game.",
        "timersreforged", "Planned: cooldown and buff timers read from the screen, naming your buffs.",
        "display128", "Planned: widescreen, FPS unlock, the multiboard, hiding parts of the UI, health bar colours and mana bars, detailed tooltips.",
        "displayreforged", "Planned: health bar size, a hero tracker and range ring.",
        "hosting128", "Planned: lobby latency and the game start countdown when you host.",
        "hostingreforged", "Nothing planned: Battle.net hosts Reforged games.")
    return p[tab ver]
}

; Every feature on the page. Keys: tab, title, badge ("1.28f" / "Reforged" /
; "Both"), desc, status() -> text; optional on() / set(v) for the switch,
; setupLabel + setup() for one button, or buttons: [[label, click], ...]
; (a label can be a function: it's refreshed with the status).
Wc3Features() {
    global gameModule, timersHud, quickcast, gameCmds, buffWatch
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
        { tab: "timers", title: "Cooldown and buff timers", badge: "1.28f",
            desc: "Seconds left on the command card and buff bar, over the game. Uses the quickcast setup.",
            on: (*) => timersHud.enabled, set: (v) => timersHud.setEnabled(v), status: (*) => timersHud.statusText(),
            setupLabel: "Set up buff bar", setup: (*) => (WinExist(WarcraftIII) && HideMainWindow(), timersHud.setupStart()) },
        { tab: "timers", title: "Buff alerts", badge: "Both",
            desc: "A line over the game when a buff you added is missing.",
            on: (*) => buffWatch.enabled, set: (v) => buffWatch.setEnabled(v), status: (*) => buffWatch.statusText(),
            buttons: [["Buff bar", (*) => (WinExist(WarcraftIII) && HideMainWindow(), timersHud.setupStart())],
                ["Add buff", (*) => (WinExist(WarcraftIII) && HideMainWindow(), buffWatch.captureStart())],
                ["Remove last", (*) => (buffWatch.removeLast(), RefreshWc3())]] },
        { tab: "display", title: "Clear messages and chat", badge: "1.28f",
            desc: "A key wipes the trigger messages or the chat off the screen.",
            on: (*) => gameCmds.enabled, set: (v) => gameCmds.setEnabled(v), status: (*) => gameCmds.statusText(),
            buttons: [[(*) => "Messages: " gameCmds.keyText("clearMessages"), (*) => Wc3Capture("clearMessages")],
                [(*) => "Chat: " gameCmds.keyText("clearChat"), (*) => Wc3Capture("clearChat")]] },
    ]
    return list
}

Wc3ScreenQcStatus(*) {
    global quickcast
    s := quickcast.get()
    where := StrReplace(StrReplace(StrReplace(s.window, "_", " "), "classic", "1.28"), "reforged", "Reforged")
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
    wc3ModuleText := mainGui.AddText("x" (x + 176) " y" (y + 44) " w" (cw - 176 - 170) " h22 0x200 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3ModuleText, "s8")
    wc3ModuleBtn := MkButton("Off", x + cw - 160, y + 42, 70, 26, C.chip, C.muted, (*) => (gameModule.setEnabled(!gameModule.enabled), RefreshWc3()))
    local logBtn := MkButton("Log", x + cw - 84, y + 42, 70, 26, C.chip, C.text, (*) => Wc3OpenLog())
    AddToPage("wc3", gl, wc3ModuleText, wc3ModuleBtn, logBtn)
    wc3ModuleRow := [gl, wc3ModuleText, wc3ModuleBtn, logBtn]
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
        wc3Cards.Push({ f: f, box: card, ctrls: [tt, bd, ds, st], sw: sw, btns: btns, top: 0 })
    }
    wc3Planned := mainGui.AddText("x" x " y" (y + 82 + 4 * 80) " w" cw " h34 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3Planned, "s8")
    AddToPage("wc3", wc3Planned)
}

Wc3Label(l) => HasMethod(l) ? l() : l
Wc3Capture(name) {
    global gameCmds
    Toast("Press the key for it (Esc = none)", "", 0)
    gameCmds.capture(name)
    Toast("Key set: " gameCmds.keyText(name), "", 1500)
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
    f.set(!f.on())
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
    global wc3Ver, wc3VerBtns, wc3VerText, wc3ModuleRow
    Freeze()
    for ver, b in wc3VerBtns
        Wc3SetSelected(b, ver = wc3Ver)
    SetIf(wc3VerText, Wc3VerLine())
    for tab, b in wc3TabBtns
        Wc3SetSelected(b, tab = wc3Tab)
    ; the game module row: 1.28f only
    mod := wc3Ver = "128"
    for c in wc3ModuleRow
        SetShown(c, mod)
    Wc3SetSwitch(wc3ModuleBtn, gameModule.enabled)
    SetIf(wc3ModuleText, gameModule.statusText())
    wc3TabBtns["casting"].GetPos(, &ty, , &th)
    nextY := ty + th + (mod ? 56 : 14)          ; under the module row, or right under the tabs
    shown := 0, lastBottom := 0
    for card in wc3Cards {
        vis := card.f.tab = wc3Tab && Wc3OnVersion(card.f, wc3Ver)
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
    wc3Planned.Text := (shown ? "" : "Nothing here yet.  ") Wc3PlannedText(wc3Tab, wc3Ver)
    wc3Planned.Move(, lastBottom ? lastBottom + 12 : nextY)
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
        if card.f.tab = wc3Tab && Wc3OnVersion(card.f, wc3Ver) {
            SetIf(card.ctrls[4], card.f.status())
            if card.sw && (card.sw.Text = "On") != !!card.f.on()
                Wc3SetSwitch(card.sw, card.f.on())
        }
}
SetIf(ctl, text) {
    if ctl.Text != text
        ctl.Text := text
}
