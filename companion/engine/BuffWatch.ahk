#Requires AutoHotkey v2.0
; ============================================================================
;  BuffWatchEngine - buff alerts: a line over the game says when a watched
;  buff is missing on your hero ("Frost Armor missing"), or about to run out
;  ("Frost Armor 4 s"). The idea is Crinix's buff alert. Two kinds of buffs:
;  - 1.28f, with the game module: by rawcode ("Binf"), from your hero's own
;    buffs (the module reads the hero unit, whatever is selected): picked in
;    the Buffs dialog from the ones on your hero now, or typed. No capture,
;    no buff bar setup, any window size. The name is your label, else the
;    game's own (its Bufftip), else the rawcode. Nothing shows while your
;    hero is dead or there is none.
;  - Both versions: from the screen. You capture a buff once (point at it on
;    the buff bar in game, Space); the buff bar is looked at 4 times a
;    second (TimerHud's buff bar setup, per window size). A buff is 25 colour
;    samples over the middle of its icon; a slot holds it when the typical
;    (median) difference is small. On 1.28f the running-out warning takes
;    the module's buff timer for the slot (index = slot, one row of 8).
;  Off by default (ini [BuffWatch] show; warn = seconds left to warn at, 0 = never;
;  buffN = label|samples, or label|id|Binf|the game's name when added).
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
            this.hide(), this.hud.gm.timersWanted(false, "buffs"), this.heroBuffs(false)
    }

    ; the watched buffs: [{ name, samples: [25 colours] }] (from the screen) or
    ; [{ name, id: "Binf", gname }] (by rawcode; name: your label, "" = the game's)
    buffs() {
        out := []
        loop Integer(Ini(this.section, "count", 0)) {
            p := StrSplit(Ini(this.section, "buff" A_Index, ""), "|", , 4)
            if p.Length >= 3 && p[2] = "id" && BuffWatchEngine.IsId(p[3])
                out.Push({ name: p[1], id: p[3], gname: p.Length = 4 ? p[4] : "" })
            else if p.Length = 2 {
                s := []
                for v in StrSplit(p[2], ",")
                    s.Push(Integer("0x" v))
                if s.Length = 25
                    out.Push({ name: p[1], samples: s })
            }
        }
        return out
    }
    static IsId(id) => RegExMatch(id, "^[\x21-\x7E]{4}$") && !InStr(id, "|")
    save(list) {
        for i, b in list {
            if b.HasProp("id") {
                SetIni(b.name "|id|" b.id "|" b.gname, this.section, "buff" i)
                continue
            }
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
    ; a name for the alert line ("|" is the ini's separator; empty -> "Buff i", or the game's name for a rawcode)
    rename(i, name) {
        list := this.buffs()
        name := Trim(StrReplace(name, "|"))
        if i >= 1 && i <= list.Length
            list[i].name := name != "" || list[i].HasProp("id") ? name : "Buff " i, this.save(list)
    }
    ; watch a buff by its rawcode (1.28f); gname: the game's name for it, if known.
    ; -> false if it isn't a rawcode or it's watched already
    addId(id, gname := "") {
        id := Trim(id)
        if !BuffWatchEngine.IsId(id)
            return false
        list := this.buffs()
        for b in list
            if b.HasProp("id") && b.id == id
                return false
        list.Push({ name: "", id: id, gname: Trim(StrReplace(gname, "|")) })
        this.save(list)
        DebugLog("buff watch: watching '" id "' (" (gname != "" ? gname : "no name") ")")
        return true
    }
    ; what the alert line calls it: your label, else the game's name (now, or when added), else the rawcode
    static Label(b, gameName := "") => b.name != "" ? b.name : gameName != "" ? gameName : b.HasProp("gname") && b.gname != "" ? b.gname : b.HasProp("id") ? b.id : "Buff"
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
    ; can rawcode buffs be watched now: 1.28f, the module running and new enough
    moduleReady() {
        gm := this.hud.gm
        s := gm.state()
        return gm.enabled && s.live && s.probe = 1 && s.layout >= 22
    }
    ; your hero's buffs from the module (1.28f, layout 22), asked for only while it's wanted
    heroBuffs(want) {
        gm := this.hud.gm
        if !want || !this.moduleReady() {
            gm.heroWanted(false), gm.timersWanted(false, "hero")
            return 0
        }
        gm.timersWanted(true, "hero"), gm.heroWanted(true)
        return gm.heroBuffs()
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
        global inGame
        if this.capturing || !WinActive(WarcraftIII) || !inGame
            return this.hide()
        list := this.buffs()
        ids := [], screen := []
        for b in list
            (b.HasProp("id") ? ids : screen).Push(b)
        hb := this.heroBuffs(ids.Length > 0)
        missing := [], ending := [], warn := this.warnAt
        BuffWatchEngine.IdAlerts(ids, hb, warn, missing, ending)
        ; from the screen
        if !screen.Length
            this.hud.gm.timersWanted(false, "buffs")
        else if (l := this.look()) {
            t := this.moduleTimers()
            for b in screen {
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

    ; by rawcode: what's missing / running out on your hero (hb: GameModule.heroBuffs();
    ; nothing while the hero is dead or there's none)
    static IdAlerts(ids, hb, warn, missing, ending) {
        if !hb || hb.hero = "" || !hb.alive
            return
        for b in ids {
            have := 0
            for hx in hb.buffs
                if hx.id == b.id {
                    have := hx
                    break
                }
            if !have
                missing.Push(BuffWatchEngine.Label(b))
            else if warn && have.left > 0 && have.left <= warn
                ending.Push(BuffWatchEngine.Label(b, have.name) " " Ceil(have.left) " s")
        }
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
        names := [], ids := 0
        for b in list
            names.Push(BuffWatchEngine.Label(b)), ids += b.HasProp("id")
        return (this.enabled ? "On" : "Off") " · " (list.Length ? "watching " Join(", ", names*) : "no buffs yet: Options")
            . (list.Length > ids && !this.hud.buffBar() && WinExist(WarcraftIII) ? " · screen buffs need the buff bar setup" : "")
            . (ids && !this.hud.gm.enabled ? " · rawcode buffs need the game module" : "")
            . (list.Length && this.warnAt && this.hud.gm.enabled ? " · warns at " this.warnAt " s on 1.28f" : "")
    }
}
