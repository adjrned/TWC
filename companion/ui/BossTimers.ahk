; Boss timers (1.28f, layout 36; the user's pick, 2026-10-30: "boss timers that learn the fight")
;  The game module notes every enemy's spell as the game fires its SPELL_EFFECT (the caster, its type,
;  the ability, its HP then). An attempt: the enemy caster with the most HP (at least "Bosses from" HP,
;  or the meter's pinned type), from the players' first hit on it (the meter's hits; else its first
;  cast) until it dies (a kill) or 30 s pass without a hit on it or a cast of its (a reset).
;  What each ability did is learned per boss type, in tw-companion-bosses.ini next to the settings:
;  when it first came (seconds from the pull, and the boss's HP then) and the gaps between its casts.
;  The bars: each ability's next cast. After a cast: the last one + the median gap. Before the first:
;  the median first time; or, when it always came at the same HP and not at the same time, that HP
;  ("at 50%"). "~" when the samples spread over 2 s; red for the last "Warn at" seconds.
class BossTimers {
    section := "BossTimers"
    static W := 270, HEAD := 30, ROW := 24, MAX_ROWS := 8, KEEP_FIRST := 10, KEEP_GAP := 24, IDLE := 30000
    gui := 0
    rows := []
    gm := 0
    castSeq := -1, hitSeq := -1
    typeNames := Map(), typeN := 0
    hitsOn := Map()                 ; unit (address) -> { first, last }: the players' hits on it (tick counts)
    fight := 0                      ; the attempt on: { unit, type, start, engaged, last, casts: Map(ability -> [secs]), hpAt: Map(), hp, hpMax, seenAlive, logged }
    learned := Map()                ; boss type -> { name, attempts, kills, abilities: Map(ability -> { first: [], hp: [], gap: [] }) }
    sample := false
    sampleFn := 0
    pinned := ""                    ; the meter's pinned unit type (a boss whatever its HP)

    __New(gameModule := 0) {
        this.gm := gameModule
        this.tickFn := ObjBindMethod(this, "tick")
        SetTimer(this.tickFn, 250)
    }
    enabled => Integer(Ini(this.section, "on", 0))
    hidden => Integer(Ini(this.section, "hidden", 0))
    rowCount => Max(3, Min(BossTimers.MAX_ROWS, Integer(Ini(this.section, "rows", 5))))
    warnSecs => Max(0, Min(10, Ini(this.section, "warn", 3) + 0))
    minHp => Max(0, Integer(Ini(this.section, "minHp", 5000)))
    opacity => Max(30, Min(100, Integer(Ini(this.section, "opacity", 92))))
    setEnabled(on) => (SetIni(on ? 1 : 0, this.section, "on"), this.tick())
    setHidden(on) => (SetIni(on ? 1 : 0, this.section, "hidden"), this.tick())
    setNumber(key, v, lo, hi, rebuild := false) {
        if !IsNumber(v)
            return false
        SetIni(Round(Max(lo, Min(hi, v + 0)), 1), this.section, key)
        if rebuild
            this.rebuild()
        return true
    }

    ; -- what was learned ----------------------------------------------------------------
    static StorePath() {
        global iniFile
        SplitPath(iniFile, , &dir)
        return dir "\tw-companion-bosses.ini"
    }
    static Nums(text) {
        out := []
        for v in StrSplit(text, ",")
            if IsNumber(v := Trim(v))
                out.Push(v + 0)
        return out
    }
    static Join(arr, digits) {
        t := ""
        for v in arr
            t .= (t = "" ? "" : ",") Format("{:." digits "f}", v)
        return t
    }
    static Median(arr) {
        if !arr.Length
            return 0
        s := arr.Clone()
        loop s.Length - 1 {                     ; insertion sort (a few dozen at most)
            i := A_Index + 1, cur := s[i], j := i - 1
            while j >= 1 && s[j] > cur
                s[j + 1] := s[j], j--
            s[j + 1] := cur
        }
        k := s.Length
        return Mod(k, 2) ? s[(k + 1) // 2] : (s[k // 2] + s[k // 2 + 1]) / 2
    }
    static Spread(arr) {
        if !arr.Length
            return 0
        lo := arr[1], hi := arr[1]
        for v in arr
            lo := Min(lo, v), hi := Max(hi, v)
        return hi - lo
    }
    static Keep(arr, v, most) {
        arr.Push(v)
        while arr.Length > most
            arr.RemoveAt(1)
    }
    storeOf(type) {
        if this.learned.Has(type)
            return this.learned[type]
        st := { name: "", attempts: 0, kills: 0, abilities: Map() }
        text := ""
        try text := IniRead(BossTimers.StorePath(), type)
        for line in StrSplit(text, "`n", "`r") {
            if !(eq := InStr(line, "="))
                continue
            key := SubStr(line, 1, eq - 1), val := SubStr(line, eq + 1)
            if key = "name"
                st.name := val
            else if key = "attempts" || key = "kills"
                st.%key% := IsNumber(val) ? Integer(val) : 0
            else if RegExMatch(key, "^(\w{4})\.(first|hp|gap)$", &m) {
                if !st.abilities.Has(m[1])
                    st.abilities[m[1]] := { first: [], hp: [], gap: [] }
                st.abilities[m[1]].%m[2]% := BossTimers.Nums(val)
            }
        }
        this.learned[type] := st
        return st
    }
    save(type) {
        st := this.storeOf(type)
        text := "name=" st.name "`nattempts=" st.attempts "`nkills=" st.kills
        for ab, L in st.abilities
            text .= "`n" ab ".first=" BossTimers.Join(L.first, 1) "`n" ab ".hp=" BossTimers.Join(L.hp, 3) "`n" ab ".gap=" BossTimers.Join(L.gap, 1)
        try IniDelete(BossTimers.StorePath(), type)
        IniWrite(text, BossTimers.StorePath(), type)
    }
    forget() {
        try FileDelete(BossTimers.StorePath())
        this.learned := Map()
        DebugLog("boss timers: everything learned forgotten")
        this.tick()
    }
    learnedCount() {
        try names := Trim(IniRead(BossTimers.StorePath()), "`n")
        return IsSet(names) && names != "" ? StrSplit(names, "`n").Length : 0
    }
    typeName(code) => code = "" ? "?" : this.typeNames.Has(code) && this.typeNames[code] != "" ? this.typeNames[code] : code

    ; -- the attempt ---------------------------------------------------------------------
    ; a module tick count (32 bits) as A_TickCount's
    static Tick64(at, now := A_TickCount) => now - ((now - at) & 0xFFFFFFFF)
    ; an enemy's cast { unit, type, ability, hp, hpMax } at tick `at`
    cast(x, at) {
        qualifies := x.type = this.pinned || x.hpMax >= this.minHp
        f := this.fight
        if qualifies && (!f || x.unit != f.unit && x.hpMax > f.hpMax * 1.2) {
            if f
                this.endFight("a bigger enemy cast")
            this.startFight(x, at)
        }
        f := this.fight
        if !f || x.unit != f.unit
            return
        secs := (at - f.start) / 1000
        if !f.casts.Has(x.ability)
            f.casts[x.ability] := []
        f.casts[x.ability].Push(secs)
        if f.casts[x.ability].Length = 1 && x.hpMax > 0
            f.hpAt[x.ability] := x.hp / x.hpMax
        f.last := Max(f.last, at), f.hp := x.hp, f.hpMax := Max(f.hpMax, x.hpMax)
        if f.logged++ < 12
            DebugLog("boss timers: '" this.typeName(f.type) "' cast '" this.typeName(x.ability) "' (" x.ability ") at " Format("{:.1f}", secs) " s, "
                (x.hpMax > 0 ? Round(100 * x.hp / x.hpMax) "% HP" : "HP not read"))
    }
    startFight(x, at) {
        h := this.hitsOn.Has(x.unit) ? this.hitsOn[x.unit] : 0
        engaged := h && at - h.last < BossTimers.IDLE
        this.fight := { unit: x.unit, type: x.type, start: engaged ? Min(h.first, at) : at, engaged: engaged, last: at, casts: Map(), hpAt: Map(),
            hp: x.hp, hpMax: x.hpMax, seenAlive: false, logged: 0 }
        if this.gm
            this.gm.bossWatch(x.unit)
        st := this.storeOf(x.type)
        if st.name = "" && this.typeName(x.type) != x.type
            st.name := this.typeName(x.type)
        DebugLog("boss timers: engaged '" this.typeName(x.type) "' (" x.type ", unit " Format("{:X}", x.unit) ", " Round(x.hpMax) " HP): attempt " (st.attempts + 1)
            ", " st.abilities.Count " abilities known; timed from " (engaged ? "the first hit on it, " Format("{:.1f}", (at - h.first) / 1000) " s before its first cast" : "its first cast (no hit on it seen)"))
    }
    ; the attempt over: what it showed learned (why: "kill", "reset", ...)
    endFight(why) {
        if !(f := this.fight)
            return
        this.fight := 0
        if this.gm
            this.gm.bossWatch(0)
        n := 0
        st := this.storeOf(f.type)
        for ab, list in f.casts {
            if !st.abilities.Has(ab)
                st.abilities[ab] := { first: [], hp: [], gap: [] }
            L := st.abilities[ab], n += list.Length
            if f.engaged
                BossTimers.Keep(L.first, list[1], BossTimers.KEEP_FIRST)
            if f.hpAt.Has(ab)
                BossTimers.Keep(L.hp, f.hpAt[ab], BossTimers.KEEP_FIRST)
            loop list.Length - 1
                BossTimers.Keep(L.gap, list[A_Index + 1] - list[A_Index], BossTimers.KEEP_GAP)
        }
        if n {
            st.attempts += 1, st.kills += why = "kill"
            try this.save(f.type)
            catch as e
                DebugLog("boss timers: saving what was learned failed: " e.Message)
        }
        secs := (f.last - f.start) / 1000
        DebugLog("boss timers: '" this.typeName(f.type) "' attempt over (" why ") after " Floor(secs / 60) ":" Format("{:02}", Floor(Mod(secs, 60)))
            ": " n " casts of " f.casts.Count " abilities" (n ? " learned (" st.attempts " attempts, " st.kills " kills)" : ", nothing to learn"))
    }

    ; -- the feed ------------------------------------------------------------------------
    feed(now := A_TickCount) {
        global dmgMeter
        if !this.gm || this.sample              ; (the sample's fight is made up: nothing read, nothing learned)
            return
        on := this.enabled && !this.sample
        if !this.gm.bossCastsWanted(on) || !on {
            this.gm.damageWanted(false, "boss")
            this.castSeq := -1, this.hitSeq := -1
            this.endFight(on ? "no game module" : "off")
            return
        }
        this.gm.damageWanted(true, "boss")      ; the hits: when the pull was
        if (t := this.gm.damageTypes(this.typeN)) {
            if t.n < this.typeN
                this.typeN := 0, t := this.gm.damageTypes(0)
            for k, n in t.names
                this.typeNames[k] := n
            this.typeN := t.n
        }
        try this.pinned := dmgMeter.filter
        if (r := this.gm.damageHits(this.hitSeq)) {
            if this.hitSeq < 0 || r.seq >= this.hitSeq
                for hit in r.hits {
                    if hit.from <= 11 && hit.to > 11 {
                        if !this.hitsOn.Has(hit.target)
                            this.hitsOn[hit.target] := { first: now, last: now }
                        this.hitsOn[hit.target].last := now
                        if this.fight && hit.target = this.fight.unit
                            this.fight.last := now
                    } else if this.fight && hit.to <= 11 && hit.src = this.fight.type
                        this.fight.last := now
                }
            this.hitSeq := r.seq
        }
        if (cs := this.gm.bossCasts(this.castSeq)) {
            if this.castSeq >= 0 && cs.seq < this.castSeq        ; a new module (its count back at 0)
                this.endFight("a new game module"), cs := this.gm.bossCasts(0)
            for x in cs.casts
                this.cast(x, BossTimers.Tick64(x.at, now))
            this.castSeq := cs.seq
        }
        if (f := this.fight) && (w := this.gm.bossWatched()) && w.unit = f.unit {
            if w.alive
                f.seenAlive := true, f.hp := w.hp, f.hpMax := Max(f.hpMax, w.max)
            else if f.seenAlive
                return this.endFight("kill")
        }
        if this.fight && now - this.fight.last > BossTimers.IDLE
            this.endFight("reset: 30 s without a hit on it or a cast")
        for u, hs in this.hitsOn.Clone()
            if now - hs.last > 60000
                this.hitsOn.Delete(u)
    }

    ; -- the bars: each ability's next cast ---------------------------------------------
    ; -> [{ ability, name, kind ("time" | "hp" | "seen"), left, total, at, rough, n }], the soonest first
    predict(now := A_TickCount) {
        if !(f := this.fight)
            return []
        st := this.storeOf(f.type), t := (now - f.start) / 1000, hpNow := f.hpMax > 0 ? f.hp / f.hpMax : 1
        abilities := Map()
        for ab in st.abilities
            abilities[ab] := 1
        for ab in f.casts
            abilities[ab] := 1
        times := [], hps := [], seen := []
        for ab in abilities {
            L := st.abilities.Has(ab) ? st.abilities[ab] : { first: [], hp: [], gap: [] }
            mine := f.casts.Has(ab) ? f.casts[ab] : []
            r := { ability: ab, name: this.typeName(ab), left: 0, total: 0, at: 0, rough: false, n: 0 }
            if mine.Length {
                gaps := L.gap.Clone()
                loop mine.Length - 1
                    gaps.Push(mine[A_Index + 1] - mine[A_Index])
                if !gaps.Length {
                    r.kind := "seen", seen.Push(r)
                    continue
                }
                g := BossTimers.Median(gaps)
                r.kind := "time", r.total := g, r.left := mine[mine.Length] + g - t, r.rough := BossTimers.Spread(gaps) > 2, r.n := gaps.Length
                if r.left >= -10                    ; long overdue: it doesn't come that way (a phase over)
                    times.Push(r)
            } else if L.hp.Length >= 2 && BossTimers.Spread(L.hp) <= 0.06
                && (L.first.Length < 2 || BossTimers.Spread(L.first) > Max(4, 0.25 * BossTimers.Median(L.first))) {
                r.kind := "hp", r.at := BossTimers.Median(L.hp), r.n := L.hp.Length
                if hpNow > r.at - 0.03
                    hps.Push(r)
            } else if L.first.Length {
                fm := BossTimers.Median(L.first)
                r.kind := "time", r.total := fm, r.left := fm - t, r.rough := BossTimers.Spread(L.first) > 2, r.n := L.first.Length
                if r.left >= -10
                    times.Push(r)
            }
        }
        BossTimers.SortBy(times, (a, b) => a.left > b.left)
        BossTimers.SortBy(hps, (a, b) => a.at < b.at)        ; the next HP mark (the highest) first
        out := []
        for list in [times, hps, seen]
            for r in list
                out.Push(r)
        return out
    }
    static SortBy(list, after) {
        loop list.Length - 1 {
            i := A_Index + 1, cur := list[i], j := i - 1
            while j >= 1 && after(list[j], cur)
                list[j + 1] := list[j], j--
            list[j + 1] := cur
        }
    }
    ; a bar's right-hand text: "~6s", "now", "at 50%", "learning"
    static LeftText(r) => r.kind = "hp" ? "at " Round(r.at * 100) "%" : r.kind = "seen" ? "learning" : r.left > 0.5 ? (r.rough ? "~" : "") Ceil(r.left) "s" : "now"

    ; -- the window ----------------------------------------------------------------------
    wanted() {
        global toolEnabled
        if this.sample
            return true
        return this.enabled && !this.hidden && toolEnabled && this.fight && WinActive(WarcraftIII)
    }
    tick() {
        try this.feed()
        catch as e {                        ; logged once per message (a silent failure leaves no bars)
            static said := Map()
            if !said.Has(e.Message) && said.Count < 10
                said[e.Message] := 1, DebugLog("boss timers: reading the game module failed: " e.Message " (" e.What ", line " e.Line ")")
        }
        if !this.wanted() {
            if this.gui
                this.gui.Hide()
            return
        }
        if !this.gui
            this.build()
        this.paint()
        if !DllCall("IsWindowVisible", "ptr", this.gui.Hwnd)
            this.show()
    }
    height() => BossTimers.HEAD + this.rowCount * BossTimers.ROW + 6
    show() {
        x := Ini(this.section, "x", ""), y := Ini(this.section, "y", "")
        pos := IsNumber(x) && IsNumber(y) ? "x" x " y" y : "x" (A_ScreenWidth // 2 - BossTimers.W // 2) " y" 120
        this.gui.Show("NA " pos " w" BossTimers.W " h" this.height())
        WinSetTransparent(Round(this.opacity * 2.55), this.gui)
    }
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
        global C, ICON_FONT
        Critical()
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000", "TW Companion - boss timers")    ; never takes the focus
        MakeScalable(g, "bosstimers")
        OnRescale(g, (*) => this.savePlace())
        g.MarginX := 0, g.MarginY := 0, g.BackColor := C.card
        wid := BossTimers.W, hgt := this.height()
        for r in [[0, 0, wid, 1], [0, hgt - 1, wid, 1], [0, 0, 1, hgt], [wid - 1, 0, 1, hgt]]
            g.AddText("x" r[1] " y" r[2] " w" r[3] " h" r[4] " +Background" C.frame)
        this.title := g.AddText("x10 y7 w44 h18 +Background" C.card " c" C.text, "BOSS")
        this.title.SetFont("s9 w700 q4", "Cinzel")
        this.bossText := g.AddText("x56 y8 w" (wid - 56 - 74) " h16 +Background" C.card " c" C.accent, "")
        UISetFont(this.bossText, "s8 w600")
        this.clock := g.AddText("x" (wid - 74) " y8 w40 h16 Right +Background" C.card " c" C.muted, "")
        UISetFont(this.clock, "s8")
        x := g.AddText("x" (wid - 30) " y4 w24 h22 Center 0x200 +Background" C.chip " c" C.muted, Chr(0xE711))
        x.SetFont("s8", ICON_FONT), Box.Round(x, 24, 22, 4)
        x.OnEvent("Click", (*) => (this.sample ? this.setSample(false) : this.setHidden(true)))
        g.AddText("x10 y" (BossTimers.HEAD - 2) " w" (wid - 20) " h1 +Background" C.border)
        loop this.rowCount {
            y := BossTimers.HEAD + (A_Index - 1) * BossTimers.ROW
            row := {}
            row.name := g.AddText("x12 y" (y + 3) " w" (wid - 90) " h16 +Background" C.card " c" C.text, "")
            UISetFont(row.name, "s9 w600")
            row.left := g.AddText("x" (wid - 74) " y" (y + 3) " w62 h16 Right +Background" C.card " c" C.text, "")
            UISetFont(row.left, "s9 w600")
            row.track := g.AddText("x12 y" (y + 19) " w" (wid - 24) " h3 +Background" C.chip)
            row.bar := g.AddText("x12 y" (y + 19) " w1 h3 +Background" C.accent)
            row.look := ""
            this.rows.Push(row)
        }
        this.empty := g.AddText("x12 y" (BossTimers.HEAD + 3) " w" (wid - 24) " h32 +Background" C.card " c" C.dim, "")
        UISetFont(this.empty, "s8")
        OnMessage(0x232, ObjBindMethod(this, "moved"))        ; WM_EXITSIZEMOVE: its place kept
        this.gui := g
        Critical("Off")
    }
    moved(wParam, lParam, msg, hwnd) {
        if this.gui && hwnd = this.gui.Hwnd
            this.savePlace()
    }
    paint(now := A_TickCount) {
        global C
        if !this.gui || !(f := this.fight)
            return
        list := this.predict(now), st := this.storeOf(f.type)
        secs := Max(0, (now - f.start) / 1000)
        DamageMeter.SetText(this.bossText, this.typeName(f.type) (f.hpMax > 0 ? "  " Round(100 * f.hp / f.hpMax) "%" : ""))
        DamageMeter.SetText(this.clock, DamageMeter.Clock(secs))
        DamageMeter.SetText(this.empty, "Learning its spells: attempt " (st.attempts + 1) ".`nThe bars come once it has cast them.")
        this.empty.Visible := !list.Length
        barW := BossTimers.W - 24, warn := this.warnSecs
        for i, row in this.rows {
            r := i <= list.Length ? list[i] : 0
            for ctl in [row.name, row.left, row.track, row.bar]
                ctl.Visible := !!r
            if !r
                continue
            soon := r.kind = "time" && r.left <= warn || r.kind = "hp" && f.hpMax > 0 && f.hp / f.hpMax <= r.at + 0.05
            colour := soon ? "E5484D" : r.kind = "seen" ? C.dim : C.accent
            DamageMeter.SetText(row.name, r.name)
            DamageMeter.SetText(row.left, BossTimers.LeftText(r))
            frac := r.kind = "time" ? (r.total > 0 ? Max(0, Min(1, r.left / r.total)) : 0)
                : r.kind = "hp" && f.hpMax > 0 ? Max(0, Min(1, (f.hp / f.hpMax - r.at) / Max(0.01, 1 - r.at))) : 0
            if row.look != colour
                row.bar.Opt("+Background" colour), row.left.Opt("c" (soon ? colour : C.text)), row.look := colour, row.left.Redraw()
            row.bar.Move(, , Max(1, Round(barW * frac)))
            row.bar.Redraw()
        }
    }

    ; -- the sample (made-up boss, to place the window) --------------------------------
    setSample(on) {
        this.sample := on
        if on {
            this.endFight("the sample")
            this.typeNames["SMPL"] := "Lich King", this.typeNames["SMP1"] := "Frost Nova", this.typeNames["SMP2"] := "Death Coil"
            this.typeNames["SMP3"] := "Army of the Dead", this.typeNames["SMP4"] := "Frozen Throne"
            ab := Map("SMP1", { first: [6, 6.5], hp: [0.98, 0.97], gap: [12, 12.4, 11.8] }, "SMP2", { first: [10, 9], hp: [0.95, 0.96], gap: [8, 9.5, 7] },
                "SMP3", { first: [40, 70], hp: [0.5, 0.51], gap: [] }, "SMP4", { first: [20], hp: [0.9], gap: [] })
            this.learned["SMPL"] := { name: "Lich King", attempts: 3, kills: 1, abilities: ab }
            this.sampleFight()
            if !this.sampleFn
                this.sampleFn := ObjBindMethod(this, "sampleFight")
            SetTimer(this.sampleFn, 30000)
        } else {
            if this.sampleFn
                SetTimer(this.sampleFn, 0)
            this.fight := 0, this.learned.Delete("SMPL")
        }
        this.tick()
    }
    sampleFight() {
        now := A_TickCount
        this.fight := { unit: 1, type: "SMPL", start: now - 8000, engaged: true, last: now + 600000, casts: Map("SMP1", [6]),
            hpAt: Map(), hp: 72, hpMax: 100, seenAlive: true, logged: 99 }
    }

    statusText() {
        if this.sample
            return "Showing a sample: drag it where you want it"
        if !this.enabled
            return "Off"
        if !this.gm || !this.gm.live()
            return "On · waiting for a 1.28f game (with the game module on)"
        st := this.gm.bossCastsState()
        if st = -1
            return "On · the game module is an older one: restart Warcraft III"
        if st = 3
            return "Refused: the game's spell calls aren't where 1.28f has them (see the log)"
        n := this.learnedCount()
        if (f := this.fight)
            return "On · " this.typeName(f.type) ": attempt " (this.storeOf(f.type).attempts + 1) (this.hidden ? " (hidden: Options > Show the timers)" : "")
        return "On · waiting for a boss" (n ? " (" n " learned)" : "")
    }
}
