#Requires AutoHotkey v2.0
; ============================================================================
;  DamageMeter - a damage meter over the game, drawn by the companion: a row
;  per player in their colour (damage, DPS, share, a bar against the top one),
;  the fight's time and a reset. A fight starts with the first hit and ends
;  after a few seconds with none (its numbers stay until the next one starts).
;  Never takes the focus from the game; drag it to move it, an edge or corner
;  to resize it (WindowScale, kept as ini [Window] meterScale); its place:
;  ini [DamageMeter] x / y. Shown while it's on and Warcraft III is up, or
;  with "Show a sample" (made-up players fighting, to place and size it).
;  The hits come in through hit(player, amount): from the game module's damage
;  feed (layout 29: each player's total dealt to other players' units, read 4
;  times a second, the differences are the hits), the names its players'.
;  Its ✕ hides it (it keeps counting; Options > Show the meter brings it back).
;  ini [DamageMeter]: on, hidden, rows (3-12), idle (s), opacity (%).
; ============================================================================
class DamageMeter {
    section := "DamageMeter"
    static W := 250, HEAD := 30, ROW := 22, MAX_ROWS := 12
    ; the game's player colours (1.28f: 12 players)
    static COLOURS := ["FF0303", "0042FF", "1CE6B9", "540081", "FFFC00", "FE8A0E", "20C000", "E55BB0", "959697", "7EBFF1", "106246", "4E2A04"]
    gui := 0
    rows := []
    sample := false
    sampleFn := 0
    dirty := true

    gm := 0
    colours := Map()                ; player -> the game's colour for them (the module's; else their slot's)
    seen := 0                       ; the module's totals last read (its differences are the hits)
    feedSeq := 0, feedHits := 0

    __New(gameModule := 0) {
        this.gm := gameModule
        this.reset()
        this.names := Map()
        this.tickFn := ObjBindMethod(this, "tick")
        SetTimer(this.tickFn, 250)
    }
    enabled => Integer(Ini(this.section, "on", 0))
    hidden => Integer(Ini(this.section, "hidden", 0))
    ; hidden: the window put away, the counting goes on (the ✕ in its corner; Options > Show the meter)
    setHidden(on) {
        SetIni(on ? 1 : 0, this.section, "hidden")
        this.tick()
    }
    rowCount => Max(3, Min(DamageMeter.MAX_ROWS, Integer(Ini(this.section, "rows", 6))))
    idleSecs => Max(1, Min(60, Ini(this.section, "idle", 5) + 0))
    opacity => Max(30, Min(100, Integer(Ini(this.section, "opacity", 92))))
    setEnabled(on) {
        SetIni(on ? 1 : 0, this.section, "on")
        this.tick()
    }
    setRows(n) {
        if !IsNumber(n)
            return false
        SetIni(Round(Max(3, Min(DamageMeter.MAX_ROWS, n + 0))), this.section, "rows")
        this.rebuild()
        return true
    }
    setIdle(s) {
        if !IsNumber(s)
            return false
        SetIni(Round(Max(1, Min(60, s + 0)), 1), this.section, "idle")
        return true
    }
    setOpacity(p) {
        if !IsNumber(p)
            return false
        SetIni(Round(Max(30, Min(100, p + 0))), this.section, "opacity")
        if this.gui
            WinSetTransparent(Round(this.opacity * 2.55), this.gui)
        return true
    }

    ; -- the numbers ------------------------------------------------------------------
    ; player: the game's slot (0-11); amount: damage dealt
    hit(player, amount, at := A_TickCount) {
        if amount <= 0
            return
        if !this.fightStart || at - this.fightLast > this.idleSecs * 1000
            this.reset(), this.fightStart := at          ; a new fight
        this.fightLast := at
        if !this.dmg.Has(player)
            this.dmg[player] := 0
        this.dmg[player] += amount
        this.dirty := true
    }
    reset() {
        this.dmg := Map(), this.fightStart := 0, this.fightLast := 0, this.dirty := true
    }
    ; the fight's length in seconds: running, or as it ended
    fightSecs(now := A_TickCount) {
        if !this.fightStart
            return 0
        endAt := now - this.fightLast > this.idleSecs * 1000 ? this.fightLast : now
        return Max(1, (endAt - this.fightStart) / 1000)
    }
    ; the rows, most damage first: [{ player, name, dmg, dps, share }]
    standings(now := A_TickCount) {
        list := [], total := 0, secs := this.fightSecs(now)
        for p, v in this.dmg
            list.Push({ player: p, dmg: v }), total += v
        ; insertion sort, most first (a dozen at most)
        loop list.Length - 1 {
            i := A_Index + 1, cur := list[i], j := i - 1
            while j >= 1 && list[j].dmg < cur.dmg
                list[j + 1] := list[j], j--
            list[j + 1] := cur
        }
        for r in list {
            r.name := this.names.Has(r.player) ? this.names[r.player] : "Player " (r.player + 1)
            r.dps := secs ? r.dmg / secs : 0, r.share := total ? r.dmg / total : 0
        }
        return list
    }
    ; 1234567 -> "1.23M", 45600 -> "45.6K", 812 -> "812"
    static Short(v) {
        for u in [[1e9, "B"], [1e6, "M"], [1e3, "K"]]
            if v >= u[1] {
                d := v >= u[1] * 100 ? 0 : v >= u[1] * 10 ? 1 : 2
                t := Format("{:." d "f}", v / u[1])
                return (d ? RTrim(RTrim(t, "0"), ".") : t) u[2]     ; 1.20M -> 1.2M, but 250M stays
            }
        return Round(v) ""
    }
    static Clock(secs) => Format("{}:{:02}", Floor(secs / 60), Floor(Mod(secs, 60)))

    ; -- the sample: made-up players fighting --------------------------------------------
    setSample(on) {
        this.sample := on
        if on {
            this.reset()
            for i, n in ["Ruzai", "Kaelith", "Morrow", "Sunbeam", "Tyrael", "Oxide"]
                this.names[i - 1] := n
            this.sampleFn := this.sampleFn ? this.sampleFn : ObjBindMethod(this, "sampleHits")
            SetTimer(this.sampleFn, 200)
        } else {
            if this.sampleFn
                SetTimer(this.sampleFn, 0)
            this.reset(), this.names := Map(), this.colours := Map()
        }
        this.tick()
    }
    sampleHits() {
        static weight := [1.6, 1.25, 1.0, 0.8, 0.55, 0.3]
        for i, w in weight
            if Random(0, 3)
                this.hit(i - 1, Round(Random(800, 2400) * w))
    }

    ; -- the window ----------------------------------------------------------------------
    wanted() {
        global toolEnabled
        if this.sample
            return true
        return this.enabled && !this.hidden && toolEnabled && WinExist(WarcraftIII) && WinGetMinMax(WarcraftIII) != -1
    }
    ; the module's feed: switched as the meter is, its new damage into hit()
    feed() {
        if !this.gm
            return
        on := this.enabled && !this.sample
        if !this.gm.damageWanted(on) || !on {
            this.seen := 0
            return
        }
        d := this.gm.damage()
        if !d || d.state != 1
            return
        if !this.sample {
            for i, n in d.names {
                if n != ""
                    this.names[i - 1] := n
                if d.colours[i] >= 0
                    this.colours[i - 1] := d.colours[i]
            }
            ; your own row: your Battle.net account, whatever the map renamed you to (else the game's name)
            if d.local >= 0 && d.local <= 11 && (acc := this.account()) != ""
                this.names[d.local] := acc
        }
        if this.seen && d.seq != this.feedSeq
            for i, t in d.total
                if (dt := t - this.seen[i]) > 0
                    this.hit(i - 1, dt)
        ; a new module (totals back at 0) or the first read: from here on
        this.seen := d.total, this.feedSeq := d.seq
        this.feedHits := 0
        for h in d.hits
            this.feedHits += h
    }
    tick() {
        try this.feed()
        if !this.wanted() {
            if this.gui
                this.gui.Hide()
            return
        }
        if !this.gui
            this.build()
        if this.dirty || this.fightStart
            this.paint()
        if !DllCall("IsWindowVisible", "ptr", this.gui.Hwnd)
            this.show()
    }
    show() {
        x := Ini(this.section, "x", ""), y := Ini(this.section, "y", "")
        pos := IsNumber(x) && IsNumber(y) ? "x" x " y" y : "x" (A_ScreenWidth - 320) " y" 160
        this.gui.Show("NA " pos " w" DamageMeter.W " h" this.height())
        WinSetTransparent(Round(this.opacity * 2.55), this.gui)
    }
    height() => DamageMeter.HEAD + this.rowCount * DamageMeter.ROW + 8
    rebuild() {
        if this.gui {
            this.savePlace()
            g := this.gui, this.gui := 0, this.rows := []
            g.Destroy()
        }
        this.tick()
    }
    savePlace() {
        if this.gui && DllCall("IsWindowVisible", "ptr", this.gui.Hwnd) {
            WinGetPos(&x, &y, , , this.gui)
            SetIni(x, this.section, "x"), SetIni(y, this.section, "y")
        }
    }
    build() {
        global C, UI_FONT, ICON_FONT
        Critical()                          ; the 250 ms tick mustn't build a second one halfway
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000", "TW Companion - damage meter")   ; never takes the focus
        MakeScalable(g, "meter")
        OnRescale(g, (*) => this.savePlace())                 ; a corner dragged moves its top left too
        g.MarginX := 0, g.MarginY := 0, g.BackColor := C.card
        w := DamageMeter.W, h := this.height()
        for r in [[0, 0, w, 1], [0, h - 1, w, 1], [0, 0, 1, h], [w - 1, 0, 1, h]]
            g.AddText("x" r[1] " y" r[2] " w" r[3] " h" r[4] " +Background" C.frame)
        t := g.AddText("x12 y7 w90 h18 +Background" C.card " c" C.text, "DAMAGE")
        t.SetFont("s9 w700 q4", "Cinzel")
        this.timeText := g.AddText("x" (w - 132) " y8 w64 h16 Right +Background" C.card " c" C.muted, "")
        UISetFont(this.timeText, "s8")
        rs := g.AddText("x" (w - 64) " y4 w26 h22 Center 0x200 +Background" C.chip " c" C.muted, Chr(0xE72C))    ; refresh: reset
        rs.SetFont("s9", ICON_FONT), Box.Round(rs, 26, 22, 4)
        rs.OnEvent("Click", (*) => (this.reset(), this.paint()))
        hd := g.AddText("x" (w - 34) " y4 w26 h22 Center 0x200 +Background" C.chip " c" C.muted, Chr(0xE711))    ; cancel: hide
        hd.SetFont("s8", ICON_FONT), Box.Round(hd, 26, 22, 4)
        hd.OnEvent("Click", (*) => (this.sample ? this.setSample(false) : this.setHidden(true)))
        g.AddText("x10 y" (DamageMeter.HEAD - 3) " w" (w - 20) " h1 +Background" C.border)
        loop this.rowCount {
            y := DamageMeter.HEAD + (A_Index - 1) * DamageMeter.ROW
            row := {}
            row.strip := g.AddText("x10 y" (y + 3) " w3 h14 +Background" C.card)
            row.name := g.AddText("x18 y" (y + 2) " w96 h16 +Background" C.card " c" C.text, "")
            UISetFont(row.name, "s9 w600")
            row.dmg := g.AddText("x114 y" (y + 2) " w56 h16 Right +Background" C.card " c" C.text, "")
            UISetFont(row.dmg, "s9 w600")
            row.dps := g.AddText("x172 y" (y + 3) " w44 h15 Right +Background" C.card " c" C.muted, "")
            UISetFont(row.dps, "s8")
            row.share := g.AddText("x" (w - 34) " y" (y + 3) " w26 h15 Right +Background" C.card " c" C.dim, "")
            UISetFont(row.share, "s8")
            row.bar := g.AddText("x18 y" (y + 18) " w1 h2 +Background" C.card)
            row.color := ""
            this.rows.Push(row)
        }
        this.empty := g.AddText("x18 y" (DamageMeter.HEAD + 2) " w" (w - 36) " h16 +Background" C.card " c" C.dim, "No damage yet")
        UISetFont(this.empty, "s9")
        OnMessage(0x232, ObjBindMethod(this, "moved"))        ; WM_EXITSIZEMOVE: its place kept
        this.gui := g, this.dirty := true
        Critical("Off")                     ; it's the caller's whole thread otherwise
    }
    moved(wParam, lParam, msg, hwnd) {
        if this.gui && hwnd = this.gui.Hwnd
            this.savePlace()
    }
    paint() {
        global C
        if !this.gui
            return
        list := this.standings(), barW := DamageMeter.W - 18 - 10
        top := list.Length ? list[1].dmg : 0
        this.timeText.Text := this.fightStart ? DamageMeter.Clock(this.fightSecs()) : ""
        this.empty.Visible := !list.Length
        for i, row in this.rows {
            r := i <= list.Length ? list[i] : 0
            for ctl in [row.strip, row.name, row.dmg, row.dps, row.share, row.bar]
                ctl.Visible := !!r
            if !r
                continue
            colour := DamageMeter.COLOURS[Mod(this.colours.Has(r.player) ? this.colours[r.player] : r.player, 12) + 1]
            if row.color != colour {
                row.strip.Opt("+Background" colour), row.bar.Opt("+Background" colour), row.color := colour
                row.strip.Redraw()
            }
            row.name.Text := r.name
            row.dmg.Text := DamageMeter.Short(r.dmg)
            row.dps.Text := DamageMeter.Short(r.dps) "/s"
            row.share.Text := Round(r.share * 100) "%"
            row.bar.Move(, , Max(1, Round(barW * (top ? r.dmg / top : 0))))
            row.bar.Redraw()
        }
        this.dirty := false
    }
    ; your Battle.net account (the Battle.net login's; "" if it isn't set)
    account() {
        global bnetLogin
        return IsSet(bnetLogin) && IsObject(bnetLogin) ? Trim(bnetLogin.account) : ""
    }
    statusText() {
        if this.sample
            return "Showing a sample: drag it where you want it"
        if !this.enabled
            return "Off"
        if this.hidden
            return "Hidden (still counting): Options > Show the meter"
        if !this.gm || !this.gm.live()
            return "On · waiting for a 1.28f game (with the game module on)"
        d := this.gm.damage()
        return !d ? "On · the game module is an older one: restart Warcraft III"
            : d.state = 3 ? "Refused: the game's damage isn't where 1.28f has it (see the log)"
            : d.state = 1 ? "On · counting (" this.feedHits " hits seen)"
            : "On · starting"
    }
}
