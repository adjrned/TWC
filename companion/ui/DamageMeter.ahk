#Requires AutoHotkey v2.0
; ============================================================================
;  DamageMeter - a damage meter over the game, drawn by the companion: a row
;  per player in their colour (damage, DPS, share, a bar against the top one),
;  the fight's time and a reset. A fight starts with the first hit and ends
;  after a few seconds with none (its numbers stay until the next one starts).
;  Never takes the focus from the game; drag it to move it, an edge or corner
;  to resize it (WindowScale, kept as ini [Window] meterScale); its place:
;  ini [DamageMeter] x / y. Shown while it's on and Warcraft III is the active
;  window, or with "Show a sample" (made-up players fighting, to place it).
;  What it shows (the user's picks, 2026-10-29):
;   - Dealt | Taken: damage each player's units dealt, or took (from anyone,
;     the creeps and bosses too).
;   - ‹ ›: the last fights (HISTORY of them) and the whole game (its time:
;     the fights' lengths added up). A new game (no game UI for 10 s, then one
;     again) starts it all over.
;   - a row clicked: that player's breakdown, Sources (attacks, and spells by
;     damage type, per unit type: hero, summons, the map's dummies) or Targets
;     (unit types hit; on Taken: which of yours were hit), with hits and the
;     biggest hit. ‹ or the player's name goes back.
;   - the pin: only the selected unit's type (a boss): damage dealt to it, or
;     taken from it. Again: all.
;   - the speech bubble: the top 5 (or the breakdown's), a line each, into the chat (Enter
;     opens it to your allies, as the cooldown ping).
;  The hits come from the game module (layout 33: each hit with the units'
;  types and the record's attack / damage type, read 4 times a second); an
;  older module's per-player totals still give Dealt (no breakdown).
;  Its ✕ hides it (it keeps counting; Options > Show the meter brings it back).
;  ini [DamageMeter]: on, hidden, rows (3-12), idle (s), opacity (%).
; ============================================================================
class DamageMeter {
    section := "DamageMeter"
    static W := 280, HEAD := 54, ROW := 22, MAX_ROWS := 12, HISTORY := 5
    ; the game's player colours (1.28f: 12 players)
    static COLOURS := ["FF0303", "0042FF", "1CE6B9", "540081", "FFFC00", "FE8A0E", "20C000", "E55BB0", "959697", "7EBFF1", "106246", "4E2A04"]
    ; DAMAGE_TYPE_* (common.j), the module's dmgType
    static DMG_TYPES := Map(4, "Normal", 5, "Enhanced", 8, "Fire", 9, "Cold", 10, "Lightning", 11, "Poison", 12, "Disease", 13, "Divine",
        14, "Magic", 15, "Sonic", 16, "Acid", 17, "Force", 18, "Death", 19, "Mind", 20, "Plant", 21, "Defensive", 22, "Demolition",
        23, "Slow poison", 24, "Spirit link", 25, "Shadow strike", 26, "Universal")
    gui := 0
    rows := []
    shown := []                     ; the players' rows as last painted (a click opens that one's breakdown)
    sample := false
    sampleFn := 0
    dirty := true

    gm := 0
    colours := Map()                ; player -> the game's colour for them (the module's; else their slot's)
    typeNames := Map()              ; unit type rawcode -> its name (the module's)
    typeN := 0                      ; the module's type names read so far
    seen := 0                       ; an older module's totals last read (its differences are the hits)
    feedSeq := 0, feedHits := 0
    ringSeq := -1                   ; the module's hits read up to here (-1: not yet)
    lost := 0                       ; hits the ring had dropped before they were read
    outSince := 0                   ; no game UI since then (a new game after 10 s of it)

    ; what's shown
    page := 0                       ; 0 the fight on (or the last), k the k-th before it, -1 the whole game
    mode := "dealt"                 ; or "taken"
    detail := -1                    ; the player whose breakdown is shown (-1: the players)
    detailKind := "src"             ; "src" sources or "tgt" targets
    filter := "", filterName := ""  ; a unit type (the pin): only hits on it / from it
    note := "", noteUntil := 0      ; a word in the title row for a moment ("select a unit first")

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
    ; a fight: its start and last hit; per player (slot 0-11) what they dealt and took
    static NewFight(at) => { start: at, last: at, dealt: Map(), taken: Map() }
    ; a player's (or a source's) count: damage, hits, the biggest hit
    static Count(e, amount) {
        e.dmg += amount, e.hits += 1
        if amount > e.max
            e.max := amount
        return e
    }
    static Entry(m, k, h := 0) {
        if !m.Has(k)
            m[k] := { dmg: 0, hits: 0, max: 0, attack: h ? h.attack : 0, dmgType: h ? h.dmgType : 255, src: h ? h.src : "",
                ability: h && h.HasOwnProp("ability") ? h.ability : "", guessed: 0 }
        return m[k]
    }
    static PlayerOf(m, p) {
        if !m.Has(p)
            m[p] := { dmg: 0, hits: 0, max: 0, by: Map(), on: Map(), src: Map() }
        return m[p]
    }
    ; one hit into a fight: dealt by its owner (a player), taken by the target's (a player).
    ; by: per source (attack or a damage type, and the unit type); on: per target type; src: per source type
    static AddTo(f, h) {
        detailed := !h.HasOwnProp("old")
        for side in [["dealt", h.from], ["taken", h.to]] {
            if side[2] > 11
                continue
            p := DamageMeter.Count(DamageMeter.PlayerOf(f.%side[1]%, side[2]), h.amount)
            if !detailed
                continue
            ; a spell with its ability (layout 34): one row per ability, whoever's unit dealt it
            ab := !h.attack && h.HasOwnProp("ability") && h.ability != "" ? h.ability : ""
            e := DamageMeter.Count(DamageMeter.Entry(p.by, ab != "" ? "b" ab : (h.attack ? "a" : "s" h.dmgType) "|" h.src, h), h.amount)
            if ab != "" && h.how = 2
                e.guessed += h.amount                   ; credited by the source's last cooldown, not the spell event
            if h.tgt != ""
                DamageMeter.Count(DamageMeter.Entry(p.on, h.tgt), h.amount)
            if h.src != ""
                DamageMeter.Count(DamageMeter.Entry(p.src, h.src), h.amount)
        }
    }
    ; a hit (the module's: { amount, src, tgt, from, to, attack, dmgType, ... }); a new fight after the idle time
    addHit(h, at := A_TickCount) {
        if h.amount <= 0
            return
        if !this.cur || at - this.cur.last > this.idleSecs * 1000 {
            if this.cur && (this.cur.dealt.Count || this.cur.taken.Count) {
                this.gameDone += this.fightSecs(at, this.cur)
                this.fights.InsertAt(1, this.cur)
                if this.fights.Length > DamageMeter.HISTORY
                    this.fights.Pop()
                if this.page > 0                        ; an older fight on show stays on show
                    this.page := Min(this.page + 1, this.fights.Length)
            }
            this.cur := DamageMeter.NewFight(at)
        }
        this.cur.last := at
        DamageMeter.AddTo(this.cur, h), DamageMeter.AddTo(this.game, h)
        this.dirty := true
    }
    ; player: the game's slot (0-11); amount: damage dealt (an older module's totals: no details)
    hit(player, amount, at := A_TickCount) => this.addHit({ amount: amount, from: player, to: 255, old: 1 }, at)
    reset() {
        this.fights := [], this.cur := 0, this.game := DamageMeter.NewFight(0), this.gameDone := 0
        this.page := 0, this.detail := -1, this.dirty := true
    }
    ; the fight on show: the one on (or the last), an older one, or the whole game
    viewFight() => this.page = -1 ? this.game : this.page = 0 ? this.cur : this.page <= this.fights.Length ? this.fights[this.page] : 0
    ; a fight's length in seconds: running, or as it ended; the whole game's: its fights' added up
    fightSecs(now := A_TickCount, f := "") {
        f := f = "" ? this.cur : f
        if !f
            return 0
        if f = this.game
            return this.gameDone + (this.cur ? this.fightSecs(now, this.cur) : 0)
        endAt := f = this.cur && now - f.last <= this.idleSecs * 1000 ? now : f.last
        return Max(1, (endAt - f.start) / 1000)
    }
    ; a player's count as the pin has it: all, or only on (dealt) / from (taken) the pinned type
    countOf(p) {
        if this.filter = ""
            return p
        m := this.mode = "dealt" ? p.on : p.src
        return m.Has(this.filter) ? m[this.filter] : 0
    }
    ; the rows, most damage first: [{ player, name, dmg, dps, share, hits, max }]
    standings(now := A_TickCount) {
        list := [], total := 0, f := this.viewFight(), secs := this.fightSecs(now, f)
        if f
            for pl, p in f.%this.mode%
                if (e := this.countOf(p)) && e.dmg > 0
                    list.Push({ player: pl, dmg: e.dmg, hits: e.hits, max: e.max }), total += e.dmg
        DamageMeter.SortByDmg(list)
        for r in list {
            r.name := this.playerName(r.player)
            r.dps := secs ? r.dmg / secs : 0, r.share := total ? r.dmg / total : 0
        }
        return list
    }
    ; a player's breakdown in the fight on show: [{ name, dmg, dps, share, hits, max }], most first
    breakdown(player, kind := "", now := A_TickCount) {
        kind := kind = "" ? this.detailKind : kind
        list := [], f := this.viewFight(), secs := this.fightSecs(now, f)
        if !f || !f.%this.mode%.Has(player)
            return list
        p := f.%this.mode%[player]
        for k, e in (kind = "src" ? p.by : p.on)
            list.Push({ name: kind = "src" ? this.sourceName(e) : this.typeName(k), dmg: e.dmg, hits: e.hits, max: e.max })
        DamageMeter.SortByDmg(list)
        for r in list
            r.dps := secs ? r.dmg / secs : 0, r.share := p.dmg ? r.dmg / p.dmg : 0
        return list
    }
    ; insertion sort, most first (a few dozen at most)
    static SortByDmg(list) {
        loop list.Length - 1 {
            i := A_Index + 1, cur := list[i], j := i - 1
            while j >= 1 && list[j].dmg < cur.dmg
                list[j + 1] := list[j], j--
            list[j + 1] := cur
        }
    }
    typeName(code) => code = "" ? "?" : this.typeNames.Has(code) && this.typeNames[code] != "" ? this.typeNames[code] : code
    ; "Attack · Paladin", "Magic spell · Paladin", "Spell · Dummy"; a spell's ability: "Chain Lightning",
    ; "~Chain Lightning" when most of it was credited by the last cooldown (a guess)
    sourceName(e) {
        if e.ability != ""
            return (e.guessed * 2 > e.dmg ? "~" : "") this.typeName(e.ability)
        kind := e.attack ? "Attack" : DamageMeter.DMG_TYPES.Has(e.dmgType) ? DamageMeter.DMG_TYPES[e.dmgType] " spell" : "Spell"
        return kind (e.src != "" ? " · " this.typeName(e.src) : "")
    }
    playerName(p) => this.names.Has(p) ? this.names[p] : "Player " (p + 1)
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

    ; -- what's shown: pages, Dealt | Taken, a breakdown, the pin -----------------------------
    ; the pages oldest first: the whole game, the fights before, the one on
    pages() {
        p := [-1]
        loop this.fights.Length
            p.Push(this.fights.Length - A_Index + 1)
        p.Push(0)
        return p
    }
    stepPage(d) {
        p := this.pages(), at := p.Length
        for i, v in p
            if v = this.page
                at := i
        this.page := p[Max(1, Min(p.Length, at + d))]
        this.dirty := true, this.paint()
    }
    pageLabel(now := A_TickCount) {
        f := this.viewFight()
        t := f ? " · " DamageMeter.Clock(this.fightSecs(now, f)) : ""
        return this.page = -1 ? "Whole game" t
            : this.page > 0 ? "Fight " (this.page + 1) " ago" t
            : !this.cur ? "No fight yet"
            : (now - this.cur.last > this.idleSecs * 1000 ? "Last fight" : "This fight") t
    }
    setMode(m) {
        if this.detail >= 0
            this.detailKind := m = "dealt" ? "src" : "tgt"      ; in a breakdown the two chips are Sources | Targets
        else
            this.mode := m
        this.dirty := true, this.paint()
    }
    openDetail(i) {
        if this.detail >= 0 || i > this.shown.Length
            return
        this.detail := this.shown[i].player, this.detailKind := "src"
        this.dirty := true, this.paint()
    }
    closeDetail() {
        if this.detail < 0
            return
        this.detail := -1, this.dirty := true, this.paint()
    }
    ; the pin: the selected unit's type, or all again
    togglePin() {
        if this.filter != "" {
            this.filter := "", this.filterName := ""
        } else if this.sample {
            this.filter := "nogl", this.filterName := this.typeName("nogl")
        } else {
            s := this.gm ? this.gm.damageSelection() : 0
            if !s
                return this.say("needs a newer game module")
            if !s.unit || s.type = ""
                return this.say("select a unit first")
            this.filter := s.type, this.filterName := this.typeName(s.type)
        }
        this.dirty := true, this.paint()
    }
    say(text) {
        this.note := text, this.noteUntil := A_TickCount + 2500, this.dirty := true
        this.paint()
    }

    ; -- report to chat ---------------------------------------------------------------------
    ; A line each (the user's ask, 2026-10-30: one long line was hard to read):
    ;   "Damage on Ogre Lord (fight 1:23):"
    ;   "1. Ruzai 1.2M (45%, 14.5K/s)"   ... the top REPORT_ROWS
    static REPORT_ROWS := 5
    reportLines(now := A_TickCount) {
        f := this.viewFight()
        if !f
            return []
        when := (this.page = -1 ? "game " : "fight ") DamageMeter.Clock(this.fightSecs(now, f))
        if this.detail >= 0 {
            list := this.breakdown(this.detail, , now)
            head := this.playerName(this.detail) (this.mode = "dealt" ? "'s damage" : "'s damage taken")
                . (this.detailKind = "tgt" ? (this.mode = "dealt" ? " by target" : " by unit") : "")
        } else {
            list := this.standings(now)
            head := (this.mode = "dealt" ? "Damage" : "Damage taken") (this.filter != "" ? (this.mode = "dealt" ? " on " : " from ") this.filterName : "")
        }
        if !list.Length
            return []
        out := [head " (" when "):"]
        for i, r in list {
            if i > DamageMeter.REPORT_ROWS
                break
            out.Push(i ". " StrReplace(r.name, " · ", " ") " " DamageMeter.Short(r.dmg) " (" Round(r.share * 100) "%, " DamageMeter.Short(r.dps) "/s)")
        }
        for i, l in out
            out[i] := StrReplace(l, "|", "/")       ; a | starts the game's colour codes
        return out
    }
    chatFn := wc3Chat
    sleepFn := Sleep
    report() {
        global chatting
        lines := this.reportLines()
        if !lines.Length
            return this.say("nothing to report")
        for i, l in lines {
            if !WinActive(WarcraftIII) || IsSet(chatting) && chatting
                return this.say(i = 1 ? "not now: the game isn't in front" : "report cut short: the game left the front")
            if i > 1
                (this.sleepFn)(120)                 ; the chat box closes before it opens again
            (this.chatFn)(l)
        }
        DebugLog("damage meter: reported " lines.Length " lines: " lines[1])
    }

    ; -- the sample: made-up players fighting --------------------------------------------
    setSample(on) {
        this.sample := on
        if on {
            this.reset()
            for i, n in ["Ruzai", "Kaelith", "Morrow", "Sunbeam", "Tyrael", "Oxide"]
                this.names[i - 1] := n
            for k, n in Map("Hpal", "Paladin", "Hblm", "Blood Mage", "Obla", "Blademaster", "Ewar", "Warden", "Hmkg", "Mountain King",
                    "Ofar", "Far Seer", "osw1", "Spirit Wolf", "nogl", "Ogre Lord", "ngh1", "Ghoul",
                    "AHtb", "Storm Bolt", "AHfs", "Flame Strike", "AOcl", "Chain Lightning")
                this.typeNames[k] := n
            this.sampleFn := this.sampleFn ? this.sampleFn : ObjBindMethod(this, "sampleHits")
            SetTimer(this.sampleFn, 200)
        } else {
            if this.sampleFn
                SetTimer(this.sampleFn, 0)
            this.reset(), this.names := Map(), this.colours := Map(), this.filter := "", this.filterName := ""
        }
        this.tick()
    }
    sampleHits() {
        static weight := [1.6, 1.25, 1.0, 0.8, 0.55, 0.3], heroes := ["Hpal", "Hblm", "Obla", "Ewar", "Hmkg", "Ofar"], abilities := ["AHtb", "AHfs", "AOcl"]
        for i, w in weight {
            if !Random(0, 3)
                continue
            attack := Random(0, 2) = 0, src := i = 6 && Random(0, 1) ? "osw1" : heroes[i]
            k := Random(1, 3)
            this.addHit({ amount: Round(Random(800, 2400) * w), from: i - 1, to: 12, src: src, tgt: Random(0, 2) ? "nogl" : "ngh1",
                attack: attack, dmgType: attack ? 4 : 26, ability: attack ? "" : abilities[k], how: k = 3 ? 2 : 1 })
            if !Random(0, 4)
                this.addHit({ amount: Random(300, 900), from: 12, to: i - 1, src: "nogl", tgt: heroes[i], attack: 1, dmgType: 4 })
        }
    }

    ; -- the feed ------------------------------------------------------------------------
    wanted() {
        global toolEnabled
        if this.sample
            return true
        return this.enabled && !this.hidden && toolEnabled && WinActive(WarcraftIII)      ; only over the game in front (the user's ask)
    }
    ; a new game: no game UI for 10 s, then one again (the module's quickcast state, layout 27)
    followGame(v, now := A_TickCount) {
        if !v || NumGet(v, Shm.layout, "uint") < 27
            return
        st := NumGet(v, Shm.qcState, "uint")
        if st = 4
            return                                  ; the module's game UI check is off: no telling
        if st != 1 {
            if !this.outSince
                this.outSince := now
            return
        }
        if this.outSince && now - this.outSince > 10000 && (this.game.dealt.Count || this.game.taken.Count)
            this.reset(), DebugLog("damage meter: a new game: the fights and the game's total start over")
        this.outSince := 0
    }
    ; the module's feed: switched as the meter is, its hits into addHit()
    feed() {
        if !this.gm
            return
        on := this.enabled && !this.sample
        if !this.gm.damageWanted(on) || !on {
            this.seen := 0, this.ringSeq := -1
            return
        }
        d := this.gm.damage()
        if !d || d.state != 1
            return
        for i, n in d.names {               ; the game's names now (they follow the map's -convert)
            if n != ""
                this.names[i - 1] := n
            if d.colours[i] >= 0
                this.colours[i - 1] := d.colours[i]
        }
        this.followGame(this.gm.live())
        if (t := this.gm.damageTypes(this.typeN)) {
            if t.n < this.typeN                     ; a new module: its names from the start
                this.typeN := 0, t := this.gm.damageTypes(0)
            for k, n in t.names
                this.typeNames[k] := n
            this.typeN := t.n
        }
        if (r := this.gm.damageHits(this.ringSeq)) {
            if this.ringSeq >= 0 && r.seq < this.ringSeq     ; a new module (its count back at 0)
                r := this.gm.damageHits(0)
            for h in r.hits
                this.addHit(h)
            this.lost += r.lost, this.ringSeq := r.seq
        } else if this.seen && d.seq != this.feedSeq {      ; an older module: the totals' differences
            for i, t in d.total
                if (dt := t - this.seen[i]) > 0
                    this.hit(i - 1, dt)
        }
        ; a new module (totals back at 0) or the first read: from here on
        this.seen := d.total, this.feedSeq := d.seq
        this.feedHits := 0
        for h in d.hits
            this.feedHits += h
    }
    tick() {
        try this.feed()
        catch as e {                        ; logged once per message: a silent failure here left the meter empty
            static said := Map()
            if !said.Has(e.Message) && said.Count < 10
                said[e.Message] := 1, DebugLog("damage meter: reading the game module failed: " e.Message " (" e.What ", line " e.Line ")")
        }
        if !this.wanted() {
            if this.gui
                this.gui.Hide()
            return
        }
        if !this.gui
            this.build()
        if this.dirty || this.cur || this.noteUntil
            this.paint()
        if !DllCall("IsWindowVisible", "ptr", this.gui.Hwnd)
            this.show()
    }

    ; -- the window ----------------------------------------------------------------------
    show() {
        x := Ini(this.section, "x", ""), y := Ini(this.section, "y", "")
        pos := IsNumber(x) && IsNumber(y) ? "x" x " y" y : "x" (A_ScreenWidth - 350) " y" 160
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
    ; a small icon button in the title row
    iconButton(g, x, glyph, size, fn) {
        global C, ICON_FONT
        b := g.AddText("x" x " y4 w26 h22 Center 0x200 +Background" C.chip " c" C.muted, Chr(glyph))
        b.SetFont("s" size, ICON_FONT), Box.Round(b, 26, 22, 4)
        b.OnEvent("Click", fn)
        return b
    }
    build() {
        global C
        Critical()                          ; the 250 ms tick mustn't build a second one halfway
        g := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000", "TW Companion - damage meter")   ; never takes the focus
        MakeScalable(g, "meter")
        OnRescale(g, (*) => this.savePlace())                 ; a corner dragged moves its top left too
        g.MarginX := 0, g.MarginY := 0, g.BackColor := C.card
        w := DamageMeter.W, h := this.height()
        for r in [[0, 0, w, 1], [0, h - 1, w, 1], [0, 0, 1, h], [w - 1, 0, 1, h]]
            g.AddText("x" r[1] " y" r[2] " w" r[3] " h" r[4] " +Background" C.frame)
        this.title := g.AddText("x12 y7 w70 h18 +Background" C.card " c" C.text, "DAMAGE")
        this.title.SetFont("s9 w700 q4", "Cinzel")
        this.pinText := g.AddText("x82 y9 w" (w - 82 - 128) " h16 +Background" C.card " c" C.accent, "")
        UISetFont(this.pinText, "s8")
        this.pinBtn := this.iconButton(g, w - 124, 0xE718, 9, (*) => this.togglePin())          ; pin: the selected unit's type
        this.iconButton(g, w - 94, 0xE8BD, 9, (*) => SetTimer(() => this.report(), -1))        ; message: report to chat
        this.iconButton(g, w - 64, 0xE72C, 9, (*) => (this.reset(), this.paint()))              ; refresh: reset
        this.iconButton(g, w - 34, 0xE711, 8, (*) => (this.sample ? this.setSample(false) : this.setHidden(true)))   ; cancel: hide
        ; the second row: ‹ the page (or the breakdown's player) › and Dealt | Taken (Sources | Targets)
        y2 := 30
        this.prevBtn := g.AddText("x8 y" y2 " w16 h18 Center 0x200 +Background" C.card " c" C.muted, "‹")
        UISetFont(this.prevBtn, "s11 w700"), this.prevBtn.OnEvent("Click", (*) => this.detail >= 0 ? this.closeDetail() : this.stepPage(-1))
        this.pageText := g.AddText("x26 y" (y2 + 2) " w" (w - 26 - 124) " h16 +Background" C.card " c" C.muted, "")
        UISetFont(this.pageText, "s8"), this.pageText.OnEvent("Click", (*) => this.closeDetail())
        this.nextBtn := g.AddText("x" (w - 120) " y" y2 " w16 h18 Center 0x200 +Background" C.card " c" C.muted, "›")
        UISetFont(this.nextBtn, "s11 w700"), this.nextBtn.OnEvent("Click", (*) => this.detail >= 0 ? 0 : this.stepPage(1))
        this.chips := []
        for i, m in ["dealt", "taken"] {
            ch := g.AddText("x" (w - 100 + (i - 1) * 46) " y" (y2 + 1) " w44 h17 Center 0x200 +Background" C.chip " c" C.muted, "")
            UISetFont(ch, "s8"), Box.Round(ch, 44, 17, 4)
            ch.OnEvent("Click", ((m, *) => this.setMode(m)).Bind(m))
            this.chips.Push(ch)
        }
        g.AddText("x10 y" (DamageMeter.HEAD - 3) " w" (w - 20) " h1 +Background" C.border)
        loop this.rowCount {
            y := DamageMeter.HEAD + (A_Index - 1) * DamageMeter.ROW
            row := {}
            row.strip := g.AddText("x10 y" (y + 3) " w3 h14 +Background" C.card)
            row.name := g.AddText("x18 y" (y + 2) " w122 h16 +Background" C.card " c" C.text, "")
            UISetFont(row.name, "s9 w600")
            row.dmg := g.AddText("x142 y" (y + 2) " w56 h16 Right +Background" C.card " c" C.text, "")
            UISetFont(row.dmg, "s9 w600")
            row.dps := g.AddText("x200 y" (y + 3) " w44 h15 Right +Background" C.card " c" C.muted, "")
            UISetFont(row.dps, "s8")
            row.share := g.AddText("x" (w - 34) " y" (y + 3) " w26 h15 Right +Background" C.card " c" C.dim, "")
            UISetFont(row.share, "s8")
            row.bar := g.AddText("x18 y" (y + 18) " w1 h2 +Background" C.card)
            row.color := ""
            ri := A_Index                   ; (the for loop below has its own A_Index: every row's name opened row 1)
            for ctl in [row.name, row.dmg, row.dps, row.share]
                ctl.OnEvent("Click", ((i, *) => this.openDetail(i)).Bind(ri))
            row.index := ri
            this.rows.Push(row)
        }
        this.empty := g.AddText("x18 y" (DamageMeter.HEAD + 2) " w" (w - 36) " h16 +Background" C.card " c" C.dim, "No damage yet")
        UISetFont(this.empty, "s9")
        OnMessage(0x232, ObjBindMethod(this, "moved"))        ; WM_EXITSIZEMOVE: its place kept
        this.gui := g, this.dirty := true, this.shown := []
        Critical("Off")                     ; it's the caller's whole thread otherwise
    }
    moved(wParam, lParam, msg, hwnd) {
        if this.gui && hwnd = this.gui.Hwnd
            this.savePlace()
    }
    static SetText(ctl, t) {
        if ctl.Text != t
            ctl.Text := t
    }
    ; a control's colours, redrawn only when they change (kept on the control)
    static Look(ctl, opts) {
        if ctl.HasOwnProp("look") && ctl.look = opts
            return
        ctl.look := opts, ctl.Opt(opts), ctl.Redraw()
    }
    paint() {
        global C
        if !this.gui
            return
        now := A_TickCount
        if this.noteUntil && now > this.noteUntil
            this.note := "", this.noteUntil := 0
        inDetail := this.detail >= 0
        list := inDetail ? this.breakdown(this.detail, , now) : this.standings(now)
        this.shown := inDetail ? [] : list
        barW := DamageMeter.W - 18 - 10, top := list.Length ? list[1].dmg : 0
        DamageMeter.SetText(this.title, this.mode = "dealt" ? "DAMAGE" : "TAKEN")
        DamageMeter.SetText(this.pinText, this.note != "" ? this.note : this.filter != "" ? (this.mode = "dealt" ? "on " : "from ") this.filterName : "")
        DamageMeter.Look(this.pinBtn, "c" (this.filter != "" ? C.accent : C.muted))
        if inDetail {
            f := this.viewFight(), p := f && f.%this.mode%.Has(this.detail) ? f.%this.mode%[this.detail] : 0
            DamageMeter.SetText(this.pageText, this.playerName(this.detail) (p ? " · " p.hits " hits · top " DamageMeter.Short(p.max) : ""))
        } else
            DamageMeter.SetText(this.pageText, this.pageLabel(now))
        pg := this.pages(), at := 0
        for i, v in pg
            if v = this.page
                at := i
        DamageMeter.Look(this.prevBtn, "c" (inDetail || at > 1 ? C.text : C.border))
        this.nextBtn.Visible := !inDetail
        DamageMeter.Look(this.nextBtn, "c" (at < pg.Length ? C.text : C.border))
        labels := inDetail ? ["Sources", "Targets"] : ["Dealt", "Taken"]
        for i, ch in this.chips {
            on := inDetail ? (i = 1) = (this.detailKind = "src") : (i = 1) = (this.mode = "dealt")
            DamageMeter.SetText(ch, labels[i])
            DamageMeter.Look(ch, "+Background" (on ? C.navOn : C.chip) " c" (on ? C.accent : C.muted))
        }
        DamageMeter.SetText(this.empty, inDetail ? "No breakdown (an older game module)" : this.filter != "" ? "Nothing " (this.mode = "dealt" ? "on " : "from ") this.filterName " yet"
            : this.mode = "dealt" ? "No damage yet" : "No damage taken yet")
        this.empty.Visible := !list.Length
        pc := inDetail ? DamageMeter.COLOURS[Mod(this.colours.Has(this.detail) ? this.colours[this.detail] : this.detail, 12) + 1] : ""
        for i, row in this.rows {
            r := i <= list.Length ? list[i] : 0
            for ctl in [row.strip, row.name, row.dmg, row.dps, row.share, row.bar]
                ctl.Visible := !!r
            if !r
                continue
            colour := inDetail ? pc : DamageMeter.COLOURS[Mod(this.colours.Has(r.player) ? this.colours[r.player] : r.player, 12) + 1]
            if row.color != colour {
                row.strip.Opt("+Background" colour), row.bar.Opt("+Background" colour), row.color := colour
                row.strip.Redraw()
            }
            DamageMeter.SetText(row.name, r.name)
            DamageMeter.SetText(row.dmg, DamageMeter.Short(r.dmg))
            DamageMeter.SetText(row.dps, DamageMeter.Short(r.dps) "/s")
            DamageMeter.SetText(row.share, Round(r.share * 100) "%")
            row.bar.Move(, , Max(1, Round(barW * (top ? r.dmg / top : 0))))
            row.bar.Redraw()
        }
        this.dirty := false
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
            : d.state = 1 ? "On · counting (" this.feedHits " hits seen" (!this.gm.damageSelection() ? "; an older module: no Taken or breakdown" : "") (this.lost ? ", " this.lost " missed" : "") ")"
            : "On · starting"
    }
}
