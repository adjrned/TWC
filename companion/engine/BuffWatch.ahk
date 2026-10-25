#Requires AutoHotkey v2.0
; ============================================================================
;  BuffWatchEngine - buff alerts from the screen (Reforged and 1.28 alike;
;  the idea is Crinix's buff alert). You capture a buff once: point at it on
;  the buff bar in game and press Space. While a game runs, the buff bar is
;  looked at 4 times a second and a line over the game says when a watched
;  buff is missing ("Frost Armor missing"). On 1.28f with the game module, it
;  also says when one is about to run out ("Frost Armor 4 s"): the module's
;  buff timer for the slot the buff was seen in. Names and the warning time
;  are set in the Buffs dialog (WC3 page > Timers).
;  Where the buff bar is: TimerHud's buff bar setup (per window size).
;  A buff is 25 colour samples over the middle of its icon; a slot holds it
;  when the typical (median) difference is small, so the cursor or a number
;  drawn over part of the icon doesn't hide it.
;  Off by default (ini [BuffWatch] show; warn = seconds left to warn at, 0 = never).
; ============================================================================
class BuffWatchEngine {
    section := "BuffWatch"
    static SLOTS := 8               ; a row of 8 (the buff bar)
    static MATCH := 40              ; median colour difference (0-765) for "it's this buff"
    gui := 0, label := 0, shown := false
    capturing := false
    calHotkey := "$Space"

    __New(timersHud) {
        this.hud := timersHud
        this.tickFn := ObjBindMethod(this, "tick")
        if this.enabled
            SetTimer(this.tickFn, 250)
    }
    enabled => Integer(Ini(this.section, "show", 0))
    setEnabled(on) {
        SetIni(on ? 1 : 0, this.section, "show")
        SetTimer(this.tickFn, on ? 250 : 0)
        if !on
            this.hide(), this.hud.gm.timersWanted(false, "buffs")
    }

    ; the watched buffs: [{ name, samples: [25 colours] }]
    buffs() {
        out := []
        loop Integer(Ini(this.section, "count", 0)) {
            p := StrSplit(Ini(this.section, "buff" A_Index, ""), "|")
            if p.Length = 2 {
                s := []
                for v in StrSplit(p[2], ",")
                    s.Push(Integer("0x" v))
                if s.Length = 25
                    out.Push({ name: p[1], samples: s })
            }
        }
        return out
    }
    save(list) {
        for i, b in list {
            hex := ""
            for v in b.samples
                hex .= (A_Index > 1 ? "," : "") Format("{:06X}", v)
            SetIni(b.name "|" hex, this.section, "buff" i)
        }
        try IniDelete(iniFile, this.section, "buff" (list.Length + 1))
        SetIni(list.Length, this.section, "count")
    }
    remove(i) {
        list := this.buffs()
        if i >= 1 && i <= list.Length
            list.RemoveAt(i), this.save(list)
    }
    ; a name for the alert line ("|" is the ini's separator; empty -> "Buff i")
    rename(i, name) {
        list := this.buffs()
        name := Trim(StrReplace(name, "|"))
        if i >= 1 && i <= list.Length
            list[i].name := name != "" ? name : "Buff " i, this.save(list)
    }
    warnAt => Integer(Ini(this.section, "warn", 5))
    setWarnAt(s) => SetIni(Max(0, Min(120, Integer(s))), this.section, "warn")
    ; the game module's buff timers, if it's there to read them (1.28f)
    moduleTimers() {
        gm := this.hud.gm
        s := gm.state()
        if !this.warnAt || !gm.enabled || !s.live || s.probe != 1 || s.layout < 3 {
            gm.timersWanted(false, "buffs")
            return 0
        }
        gm.timersWanted(true, "buffs")
        return gm.timers()
    }

    ; 25 points over the middle 60% of a slot's icon (centre cx, cy, icon pitch p)
    static Points(cx, cy, p) {
        pts := []
        loop 5 {
            dy := (A_Index - 3) * p * 0.15
            loop 5
                pts.Push([Round(cx + (A_Index - 3) * p * 0.15), Round(cy + dy)])
        }
        return pts
    }
    ; the colours at a slot (screen grab g, slot centre in screen coordinates)
    static Sample(g, cx, cy, p) {
        out := []
        for pt in BuffWatchEngine.Points(cx - g.ox, cy - g.oy, p)
            out.Push(g.pixel(pt[1], pt[2]))
        return out
    }
    ; how far two sample sets are apart: the median point difference
    static Distance(a, b) {
        d := []
        loop 25
            d.Push(ColorDiff(a[A_Index], b[A_Index]))
        SortBy(d, (x, y) => x - y)
        return d[13]
    }

    ; the buff bar on screen now: { grab, x, y, p } (x, y: slot 1's centre) or 0
    look() {
        if !(bar := this.hud.buffBar()) || !WinExist(WarcraftIII)
            return 0
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        p := bar.dx * cw, x := wx + bar.x * cw, y := wy + bar.y * ch
        gx := Round(x - p), gy := Round(y - p)
        g := ScreenGrab(gx, gy, Round(p * (BuffWatchEngine.SLOTS + 1)), Round(p * 2))
        g.ox := gx, g.oy := gy
        return { grab: g, x: x, y: y, p: p }
    }

    tick() {
        global inGame, chatting
        if this.capturing || !WinActive(WarcraftIII) || !inGame
            return this.hide()
        list := this.buffs()
        if !list.Length || !(l := this.look())
            return this.hide()
        t := this.moduleTimers(), warn := this.warnAt
        missing := [], ending := []
        for b in list {
            slot := 0
            loop BuffWatchEngine.SLOTS
                if BuffWatchEngine.Distance(BuffWatchEngine.Sample(l.grab, l.x + (A_Index - 1) * l.p, l.y, l.p), b.samples) <= BuffWatchEngine.MATCH {
                    slot := A_Index
                    break
                }
            if !slot
                missing.Push(b.name)
            else if t && slot <= t.buffs.Length && t.buffs[slot] && (left := t.buffs[slot].left) > 0 && left <= warn
                ending.Push(b.name " " Ceil(left) " s")
        }
        parts := []
        if missing.Length
            parts.Push(Join(", ", missing*) " missing")
        if ending.Length
            parts.Push(Join(", ", ending*))
        if parts.Length
            this.show(Join("  ·  ", parts*))
        else
            this.hide()
    }

    ; the alert line: click-through, never takes focus, over the middle of the game
    show(text) {
        if !this.gui {
            g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20 +E0x08000000", "twc-buffwatch")
            g.BackColor := "010203"
            g.MarginX := 0, g.MarginY := 0
            g.SetFont("s14 w700 q3", "Segoe UI")
            this.shadow := g.AddText("x1 y1 w600 h30 Center +BackgroundTrans c000000", "")
            this.label := g.AddText("x0 y0 w600 h30 Center +BackgroundTrans cFFA040", "")
            this.gui := g
            WinSetTransColor("010203", g)
        }
        if this.label.Text != text
            this.label.Text := text, this.shadow.Text := text
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        this.gui.Show("NA x" Round(wx + cw / 2 - 300) " y" Round(wy + ch * 0.62) " w600 h32")
        this.shown := true
    }
    hide() {
        if this.gui && this.shown
            this.gui.Hide(), this.shown := false
    }

    ; -- adding a buff (in game: point at it, press Space) ---------------------
    ; It snaps to the nearest slot of the buff bar setup. Remaps and macros
    ; pause meanwhile (qcCalibrating). Esc cancels.
    captureStart() {
        global qcCalibrating
        if !WinExist(WarcraftIII)
            return Toast("Start Warcraft III first, in a game with the buff on your hero", "error")
        if !this.hud.buffBar()
            return Toast("Set up the buff bar first (WC3 page > Timers)", "error")
        this.capturing := true
        qcCalibrating := true, RefreshHotkeys()
        HotIfWinActive(WarcraftIII)
        Hotkey(this.calHotkey, (*) => this.captureStep(), "On")
        HotIfWinActive()
        WinActivate(WarcraftIII)
        Toast("Add a buff  ·  Point at the buff's icon on the buff bar and press Space  ·  Esc cancels", "", 0)
    }
    captureStep() {
        if !this.capturing || !(l := this.look())
            return
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        i := Round((mx - l.x) / l.p)
        if i < 0 || i >= BuffWatchEngine.SLOTS || Abs(my - l.y) > l.p
            return this.captureEnd(0, "That wasn't on the buff bar. Try again from the WC3 page.")
        list := this.buffs()
        name := "Buff " (list.Length + 1)
        list.Push({ name: name, samples: BuffWatchEngine.Sample(l.grab, l.x + i * l.p, l.y, l.p) })
        this.save(list)
        this.captureEnd(1, name " added (slot " (i + 1) "): an alert shows while it's missing")
    }
    captureEnd(ok, msg) {
        global qcCalibrating
        if !this.capturing
            return
        HotIfWinActive(WarcraftIII)
        try Hotkey(this.calHotkey, "Off")
        HotIfWinActive()
        qcCalibrating := false, RefreshHotkeys()
        this.capturing := false
        DebugLog("buff watch: " msg)
        Toast(msg, ok ? "" : "error")
    }

    statusText() {
        list := this.buffs()
        names := []
        for b in list
            names.Push(b.name)
        return (this.enabled ? "On" : "Off") " · " (list.Length ? "watching " Join(", ", names*) : "no buffs yet: Add buff")
            . (this.hud.buffBar() || !WinExist(WarcraftIII) ? "" : " · needs the buff bar setup (Timers)")
            . (list.Length && this.warnAt && this.hud.gm.enabled ? " · warns at " this.warnAt " s on 1.28f" : "")
    }
}
