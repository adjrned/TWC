#Requires AutoHotkey v2.0
; ============================================================================
;  WC3 page - features that read or change the running game, in one place.
;  Four tabs set where every feature goes, now and later:
;    Casting   how abilities go off: quickcast (screen or game module), later
;              a self-cast key, an autocast toggle key
;    Timers    what's ready and what's running out: cooldown and buff timers,
;              later buff alerts
;    Display   how the game looks: later health bar size, hero tracker and
;              range ring, widescreen, FPS, clearing messages, hiding UI parts,
;              detailed tooltips
;    Hosting   games you host: later lobby latency, start countdown
;  Each feature is one entry in Wc3Features(): a card with its version badge,
;  an On/Off switch (if it has one), a live status line and a setup button.
;  A feature that needs the 1.28 game module says so in its status. The
;  page's top line is the game module itself (its master switch).
;  Built in the pages' (40, 160) layout space like the other pages.
; ============================================================================

global wc3Tab := "casting", wc3TabBtns := Map(), wc3Cards := [], wc3ModuleBtn, wc3ModuleText, wc3Planned

Wc3Tabs() => [["casting", "Casting"], ["timers", "Timers"], ["display", "Display"], ["hosting", "Hosting"]]

; what each tab will hold later (shown under its cards)
Wc3PlannedText(tab) {
    static p := Map(
        "casting", "Planned: a self-cast key (the next ability goes on your hero), an autocast toggle key.",
        "timers", "Planned: buff alerts (a buff you want is missing or about to run out), Reforged timers read from the screen.",
        "display", "Planned: health bar size, a hero tracker and range ring (Reforged), widescreen, FPS unlock, clearing messages and chat, the multiboard, hiding parts of the UI, detailed tooltips.",
        "hosting", "Planned (1.28f): lobby latency and the game start countdown when you host.")
    return p[tab]
}

; Every feature on the page. Keys: tab, title, badge ("1.28f" / "Reforged" /
; "Both"), desc, status() -> text; optional on() / set(v) for the switch,
; setupLabel + setup() for the button.
Wc3Features() {
    global gameModule, timersHud, quickcast
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
    ; tabs, like the Overlay page's dock switch
    for i, t in Wc3Tabs() {
        local b := MkButton(t[2], x + (i - 1) * 96, y, 90, 28, C.chip, C.muted, Wc3ShowTab.Bind(t[1]))
        wc3TabBtns[t[1]] := b
        AddToPage("wc3", b)
    }
    ; the game module: the page's master switch
    local gl := mainGui.AddText("x" x " y" (y + 44) " w170 h22 0x200 +Background" C.panel " c" C.text, "Game module (1.28f)")
    UISetFont(gl, "s10 w600")
    wc3ModuleText := mainGui.AddText("x" (x + 176) " y" (y + 44) " w" (cw - 176 - 170) " h22 0x200 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3ModuleText, "s8")
    wc3ModuleBtn := MkButton("Off", x + cw - 160, y + 42, 70, 26, C.chip, C.muted, (*) => (gameModule.setEnabled(!gameModule.enabled), RefreshWc3()))
    local logBtn := MkButton("Log", x + cw - 84, y + 42, 70, 26, C.chip, C.text, (*) => Wc3OpenLog())
    AddToPage("wc3", gl, wc3ModuleText, wc3ModuleBtn, logBtn)
    ; feature cards, per tab in the same area (only the tab's own are shown)
    local slot := Map()
    for f in Wc3Features() {
        local n := slot.Get(f.tab, 0), cy := y + 82 + n * 80
        slot[f.tab] := n + 1
        local card := Box("wc3", x, cy, cw, 70, C.card, C.border, 6)
        local tt := mainGui.AddText("x" (x + 14) " y" (cy + 8) " w300 h20 0x200 +Background" C.card " c" C.text, f.title)
        UISetFont(tt, "s10 w600")
        local tw := TextWidth(tt, f.title)
        tt.Move(, , tw + 4)
        local bd := mainGui.AddText("x" (x + 22 + tw) " y" (cy + 10) " w70 h16 0x200 +Background" C.card " c" C.accent, f.badge)
        UISetFont(bd, "s8 w600")
        local ds := mainGui.AddText("x" (x + 14) " y" (cy + 29) " w" (cw - 200) " h16 +Background" C.card " c" C.dim, f.desc)
        UISetFont(ds, "s8")
        local st := mainGui.AddText("x" (x + 14) " y" (cy + 47) " w" (cw - 200) " h16 +Background" C.card " c" C.muted, "")
        UISetFont(st, "s8")
        local sw := 0, sb := 0
        if f.HasProp("on") {
            sw := MkButton("Off", x + cw - 84, cy + 10, 70, 24, C.chip, C.muted, Wc3Switch.Bind(f))
            AddToPage("wc3", sw)
        }
        if f.HasProp("setup") {
            ; under the switch, or alone in the middle; as wide as its label, right-aligned
            sb := MkButton(f.setupLabel, x + cw - 84, cy + (f.HasProp("on") ? 38 : 22), 70, 24, C.chip, C.text, f.setup)
            local need := Max(70, TextWidth(sb, f.setupLabel) + 20)
            sb.Move(x + cw - 14 - need, , need)
            AddToPage("wc3", sb)
        }
        AddToPage("wc3", tt, bd, ds, st)
        wc3Cards.Push({ f: f, box: card, ctrls: [tt, bd, ds, st], sw: sw, sb: sb })
    }
    wc3Planned := mainGui.AddText("x" x " y" (y + 82 + 4 * 80) " w" cw " h34 +Background" C.panel " c" C.dim, "")
    UISetFont(wc3Planned, "s8")
    AddToPage("wc3", wc3Planned)
    ; the planned line sits under the last card of the tab (moved in RefreshWc3)
}

Wc3ShowTab(tab, *) {
    global wc3Tab := tab
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
    global C, boxes
    b.Text := on ? "On" : "Off"
    bg := on ? C.navOn : C.chip
    b.Opt("+Background" bg " +c" (on ? C.accent : C.muted)), b.Redraw()
    if boxes.Has(b.Hwnd)
        boxes[b.Hwnd].Fill := bg
}

RefreshWc3() {
    global wc3Tab, wc3TabBtns, wc3Cards, wc3ModuleBtn, wc3ModuleText, wc3Planned, gameModule, C, boxes, currentPage
    for tab, b in wc3TabBtns {
        on := tab = wc3Tab, bg := on ? C.navOn : C.chip
        b.Opt("+Background" bg " +c" (on ? C.accent : C.muted)), b.Redraw()
        if boxes.Has(b.Hwnd)
            boxes[b.Hwnd].Fill := bg
    }
    Wc3SetSwitch(wc3ModuleBtn, gameModule.enabled)
    wc3ModuleText.Text := gameModule.statusText()
    shownOnTab := 0, lastBottom := 0
    for card in wc3Cards {
        vis := card.f.tab = wc3Tab
        card.box.Visible := vis
        for c in card.ctrls
            c.Visible := vis
        if card.sw
            SetShown(card.sw, vis)
        if card.sb
            SetShown(card.sb, vis)
        if !vis
            continue
        shownOnTab++
        card.box.outer.GetPos(, &by, , &bh)
        lastBottom := Max(lastBottom, by + bh)
        if card.sw
            Wc3SetSwitch(card.sw, card.f.on())
        card.ctrls[4].Text := card.f.status()
    }
    wc3Planned.Text := (shownOnTab ? "" : "Nothing here yet.  ") Wc3PlannedText(wc3Tab)
    if lastBottom
        wc3Planned.Move(, lastBottom + 12)
    else {
        wc3ModuleText.GetPos(, &my)
        wc3Planned.Move(, my + 40)
    }
    ; live status lines while the page is open
    SetTimer(Wc3Tick, currentPage = "wc3" ? 1000 : 0)
}
; once a second: just the status lines and switches (no repaint of the rest)
Wc3Tick() {
    global currentPage, mainGui, wc3Tab, wc3Cards, wc3ModuleBtn, wc3ModuleText, gameModule
    if currentPage != "wc3" || !DllCall("IsWindowVisible", "ptr", mainGui.Hwnd)
        return SetTimer(Wc3Tick, 0)
    SetIf(wc3ModuleText, gameModule.statusText())
    if (wc3ModuleBtn.Text = "On") != !!gameModule.enabled
        Wc3SetSwitch(wc3ModuleBtn, gameModule.enabled)
    for card in wc3Cards
        if card.f.tab = wc3Tab {
            SetIf(card.ctrls[4], card.f.status())
            if card.sw && (card.sw.Text = "On") != !!card.f.on()
                Wc3SetSwitch(card.sw, card.f.on())
        }
}
SetIf(ctl, text) {
    if ctl.Text != text
        ctl.Text := text
}
