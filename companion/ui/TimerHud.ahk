#Requires AutoHotkey v2.0
; ============================================================================
;  TimerHud - cooldown and buff countdowns drawn over the game, like WFE's
;  Cooldown UI and BUFFUI, but in a see-through, click-through window of the
;  companion's own (nothing is drawn inside the game).
;  1.28f: the times come from the game module (GameModuleEngine.timers).
;  Where they go: the command card from the quickcast setup, the buff bar
;  from its own two-press setup (setupStart), both per game window size.
;  Or drawn in the game itself ([Timers] where = game): the module makes text
;  frames on the buttons and buff icons (layout 11, needs the game's
;  Storm.dll) and no setup is needed; until the module draws them, the
;  overlay does.
;  Off by default (ini [Timers] show; WC3 page > Timers).
; ============================================================================
class TimerHud {
    section := "Timers"
    static KEY := "010203"          ; the see-through colour
    gui := 0, cds := [], buffs := []    ; { text, shadow, color } controls
    sizes := { cd: 0, buff: 0 }         ; font sizes in use
    shown := false
    cal := 0                        ; the buff bar setup in progress: { step, p1 }
    calHotkey := "$Space"
    static STEPS := ["Point at the middle of your hero's first buff icon (left) and press Space",
        "Point at the middle of the buff slot right of it (empty is fine) and press Space"]

    __New(gameModule, quickcast) {
        this.gm := gameModule, this.qc := quickcast
        this.tickFn := ObjBindMethod(this, "tick")
        if this.enabled
            this.start()
    }
    enabled => Integer(Ini(this.section, "show", 0))
    setEnabled(on) {
        SetIni(on ? 1 : 0, this.section, "show")
        on ? this.start() : this.stop()
    }
    start() => SetTimer(this.tickFn, 100)
    stop() {
        SetTimer(this.tickFn, 0)
        this.hide()
        this.gm.timersWanted(false)
        this.pushGame()
    }
    ; drawn over the game (overlay) or in it (game)
    inGame => Ini(this.section, "where", "overlay") = "game"
    toggleWhere() {
        SetIni(this.inGame ? "overlay" : "game", this.section, "where")
        this.pushGame()
    }
    whereLabel => this.inGame ? "In the game" : "Overlay"
    ; the switch to the module (layout 11)
    pushGame() {
        if (v := this.gm.live()) && NumGet(v, 4, "uint") >= 11
            NumPut("uint", this.enabled && this.inGame && this.gm.enabled ? 1 : 0, v, 688)
    }
    ; the module's own drawing: 0 off, 1 drawing, 2 waiting, 3 refused; -1 no module that can
    gameState() {
        if !(v := this.gm.live()) || NumGet(v, 4, "uint") < 11
            return -1
        return NumGet(v, 692, "uint")
    }

    ; the buff bar for the game window as it is now: { x, y, dx } (fractions of
    ; the client area: the first icon's middle, the step to the next) or 0
    buffBar() {
        if !(k := WC3WindowKey()) || (v := Ini(this.section, "buff_" k, "")) = ""
            return 0
        p := StrSplit(v, ",")
        return p.Length = 3 ? { x: p[1] + 0, y: p[2] + 0, dx: p[3] + 0 } : 0
    }

    ; one line for the Quickcast window
    statusText() {
        if !this.enabled
            return "Off"
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        s := this.gm.state()
        if !WinExist(WarcraftIII) || !s.loaded
            return "On · starts with a 1.28f game"
        if s.layout < 3
            return "On · the game has an older module loaded: restart the game"
        if s.probe != 1
            return "On · the module's check failed: no timers"
        if this.inGame {
            st := this.gameState(), storm := s.layout >= 11 ? NumGet(this.gm.live(), 684, "uint") : 0
            if st = 1
                return "On · drawn in the game"
            why := st = -1 ? "the game has an older module loaded (restart the game)"
                : storm = 2 ? "the game has no Storm.dll loaded"
                : st = 3 ? "refused by the module's checks (see the log)" : ""
            if why = ""
                return "On · in the game: waiting for a game"
            return "On · " why ", so over the game" (this.qc.current() && this.buffBar() ? "" : " (needs the setups)")
        }
        t := this.gm.timers(), miss := []
        if !this.qc.current()
            miss.Push("Quickcast Setup (cooldowns)")
        if !this.buffBar()
            miss.Push("buff bar setup")
        return "On" (miss.Length ? " · needs " Join(" and ", miss*) : " · ready")
            . (t && t.flags & 0x100 ? " · some game timers refused (see twc-game.log)" : "")
    }

    ; -- drawing --------------------------------------------------------------
    ; Whole seconds, tenths under 1 s, m:ss from a minute (as WFE shows them)
    static Fmt(s) => s <= 0 ? "" : s < 1 ? Format("{:.1f}", s) : s < 60 ? Ceil(s) : Format("{}:{:02}", Ceil(s) // 60, Mod(Ceil(s), 60))

    build() {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000", "twc-timers")   ; click-through, never takes focus
        g.BackColor := TimerHud.KEY
        g.MarginX := 0, g.MarginY := 0
        mk() {
            sh := g.AddText("x0 y0 w60 h24 Center +BackgroundTrans c000000", "")
            tx := g.AddText("x0 y0 w60 h24 Center +BackgroundTrans cFFFFFF", "")
            return { text: tx, shadow: sh, color: "FFFFFF" }
        }
        loop 12
            this.cds.Push(mk())
        loop 16
            this.buffs.Push(mk())
        this.gui := g
        WinSetTransColor(TimerHud.KEY, g)
    }
    hide() {
        if this.gui && this.shown
            this.gui.Hide(), this.shown := false
    }
    ; a label centred on (cx, cy) in the window, sized by the button pitch
    place(c, cx, cy, pitch, txt, color) {
        w := Round(pitch), h := Round(pitch * 0.6)
        if c.text.Text != txt
            c.text.Text := txt, c.shadow.Text := txt
        if c.color != color
            c.text.Opt("c" color), c.color := color
        c.text.Move(Round(cx - w / 2), Round(cy - h / 2), w, h)
        c.shadow.Move(Round(cx - w / 2) + 1, Round(cy - h / 2) + 1, w, h)
    }

    ; the labels' font, when the button size changed
    resize(list, key, size) {
        if this.sizes.%key% = size
            return
        this.sizes.%key% := size
        for c in list
            UISetFont(c.text, "s" size " w700 q3"), UISetFont(c.shadow, "s" size " w700 q3")
    }
    clear(c) {
        if c.text.Text != ""
            c.text.Text := "", c.shadow.Text := ""
    }

    tick() {
        this.pushGame()
        if this.cal || !WinActive(WarcraftIII) || !this.gm.enabled
            return this.hide()
        if this.inGame && this.gameState() = 1
            return this.hide()              ; the module draws them
        s := this.gm.state()
        if !s.live || s.probe != 1 || s.layout < 3
            return this.hide()
        this.gm.timersWanted(true)
        if !(t := this.gm.timers())
            return this.hide()
        cal := this.qc.current(), bar := this.buffBar()
        if !cal && !bar
            return this.hide()
        if !this.gui
            this.build()
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        ; command card: the quickcast setup's grid
        pitch := cal ? (cal.p2[1] - cal.p1[1]) * cw / 3 : 0
        this.resize(this.cds, "cd", Max(8, Round(pitch * 0.3)))
        for i, c in this.cds {
            txt := cal ? TimerHud.Fmt(t.cd[i].left) : ""
            if txt != "" {
                p := this.qc.slotAt(cal, i)
                this.place(c, p[1] * cw, p[2] * ch, pitch, txt, "FFFFFF")
            } else
                this.clear(c)
        }
        ; buff bar: a row from the first icon (more rows, if any, below it)
        bpitch := bar ? bar.dx * cw : 0, per := 8   ; a row of 8 (1.28's bar); more would wrap below
        this.resize(this.buffs, "buff", Max(7, Round(bpitch * 0.4)))
        for i, c in this.buffs {
            b := bar && i <= t.buffs.Length ? t.buffs[i] : 0
            txt := b ? TimerHud.Fmt(b.left) : ""
            if txt != "" {
                col := Mod(i - 1, per), row := (i - 1) // per
                ; under 3 s: orange, about to run out
                this.place(c, (bar.x * cw) + col * bpitch, (bar.y * ch) + row * bpitch, bpitch, txt, b.left < 3 ? "FFA040" : "FFFFFF")
            } else
                this.clear(c)
        }
        this.gui.Show("NA x" wx " y" wy " w" cw " h" ch)
        this.shown := true
    }

    ; -- the buff bar setup (two presses of Space in game) --------------------
    ; Remaps and macros pause meanwhile (qcCalibrating, as in the quickcast
    ; setup). Esc cancels.
    setupStart() {
        global qcCalibrating
        if !WinExist(WarcraftIII)
            return Toast("Start Warcraft III first, in a game with your hero selected", "error")
        this.cal := { step: 1 }
        qcCalibrating := true, RefreshHotkeys()
        HotIfWinActive(WarcraftIII)
        Hotkey(this.calHotkey, (*) => this.setupStep(), "On")
        HotIfWinActive()
        WinActivate(WarcraftIII)
        this.stepToast(1)
    }
    stepToast(n) => Toast("Buff bar setup " n "/2  ·  " TimerHud.STEPS[n] "  ·  Esc cancels", "", 0)
    setupStep() {
        if !(c := this.cal)
            return
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        p := [(mx - wx) / cw, (my - wy) / ch]
        if c.step = 1 {
            c.p1 := p, c.step := 2
            return this.stepToast(2)
        }
        dx := p[1] - c.p1[1]
        if dx < 0.005 || Abs(p[2] - c.p1[2]) > 0.02
            return this.setupEnd(0, "The second point wasn't just right of the first. Run the setup again.")
        SetIni(Format("{:.5f},{:.5f},{:.5f}", c.p1[1], c.p1[2], dx), this.section, "buff_" WC3WindowKey())
        this.setupEnd(1, "Buff bar set up for " StrReplace(WC3WindowKey(), "_", " "))
    }
    setupEnd(ok, msg) {
        global qcCalibrating
        if !this.cal
            return
        HotIfWinActive(WarcraftIII)
        try Hotkey(this.calHotkey, "Off")
        HotIfWinActive()
        qcCalibrating := false, RefreshHotkeys()
        this.cal := 0
        DebugLog("buff bar setup ended: " msg)
        Toast(msg, ok ? "" : "error")
    }
}
