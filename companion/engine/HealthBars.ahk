#Requires AutoHotkey v2.0
; ============================================================================
;  HealthBarsEngine - health bar size on 1.28f, through the game module
;  (shared memory layout 5: it resizes every unit's health bar on the game's
;  thread, like WFE's HEALTHBAR HEIGHT). Height and width are multiples of
;  the game's own size (x0.25 to x4, typed or on a slider: BarSizeDialog);
;  width is experimental (WFE never changes it).
;  Off by default (ini [HealthBars] on, height, width). Turning it off puts
;  the bars back.
;  Colours (layout 6, also off by default: [HealthBars] colours, colourMode):
;  by owner (yours / allies / enemies / neutral hostile / neutral passive,
;  ini keys yours, allies, enemies, hostile, passive as RRGGBB) or by health
;  (green, to yellow at half, to red). Each owner's colour can be "player":
;  the unit owner's own player colour (layout 12; BarColoursDialog). The
;  module sets them right after the game's own bar update.
;  Health numbers and mana bars (layout 11; they need the game's Storm.dll;
;  numbers off by default, mana bars always on since 2026-11-01): a number over each health bar ([HealthBars] numbers,
;  numberMode total / truncated / percent) and a mana bar under the health bar
;  of each unit with mana ([HealthBars] mana, manaHeight / manaWidth: times
;  the health bar's height / width, x0.25 to x2; width from layout 12).
;  Frames the module adds to the game; turning off takes them away.
;  Portrait regen (layout 11): taken out of the companion on 2026-11-01 (the
;  user's ask), always pushed off; the module's code for it stays.
; ============================================================================
class HealthBarsEngine {
    section := "HealthBars"
    ; the numbers' value, colour and whose bars (the user, 2026-11-01): [ini value, name, the module's value]
    ; (truncated: 13k, the module's hnMode 3; an older module shows it as the total)
    static NUMBER_MODES := [["current", "Total", 0], ["short", "Truncated", 3], ["percent", "Percent", 2]]
    ; (layout 43) dynamic: green, to yellow at half, to red; owner: its bar's colour (the bars' own, or the owner's player colour)
    static NUMBER_COLOURS := [["health", "Dynamic", 1], ["bar", "Owner", 2], ["custom", "Custom", 3]]
    ; enemies: the creeps too (neutral hostile), as the bars' Enemies do in TWRPG
    static NUMBER_WHO := [["numYours", "Player", 1], ["numAllies", "Allies", 2], ["numEnemies", "Enemies", 4 | 8]]
    ; [ini key, default RRGGBB or "player", name]
    static OWNERS := [["yours", "00FF00", "Yours"], ["allies", "0080FF", "Allies"], ["enemies", "FF0000", "Enemies"],
        ["hostile", "FF8000", "Neutral hostile"], ["passive", "A0A0A0", "Neutral passive"]]
    ; size key -> [default, smallest, largest]
    static SIZES := Map("height", [1.5, 0.25, 4], "width", [1, 0.25, 4], "manaHeight", [0.75, 0.25, 2], "manaWidth", [1, 0.25, 2])

    __New(gameModule) {
        this.gm := gameModule
        this.tickFn := ObjBindMethod(this, "push")
        SetTimer(this.tickFn, 1000)
    }
    enabled => Integer(Ini(this.section, "on", 0))
    height => this.size("height")
    width => this.size("width")
    ; a size (times the game's own, or the health bar's for mana), within its limits
    size(which) {
        d := HealthBarsEngine.SIZES[which], v := Ini(this.section, which, d[1])
        return IsNumber(v) ? Min(d[3], Max(d[2], v + 0)) : d[1]
    }
    setSize(which, v) {
        d := HealthBarsEngine.SIZES[which]
        if !IsNumber(v)
            return false
        SetIni(Round(Min(d[3], Max(d[2], v + 0)), 2), this.section, which)
        this.push()
        return true
    }
    sizeLabel => "Size " HealthBarsEngine.Fmt(this.height) " / " HealthBarsEngine.Fmt(this.width)
    setNumberMode(i) {
        SetIni(HealthBarsEngine.NUMBER_MODES[i][1], this.section, "numberMode")
        this.push()
    }
    setColourMode(mode) {
        SetIni(mode = "health" ? "health" : "owner", this.section, "colourMode")
        this.push()
    }
    manaSizeLabel => "Size " HealthBarsEngine.Fmt(this.manaHeight) " / " HealthBarsEngine.Fmt(this.size("manaWidth"))
    ; an owner's colour: "player" or RRGGBB
    colour(key) {
        for o in HealthBarsEngine.OWNERS
            if o[1] = key {
                v := Ini(this.section, key, o[2])
                return v = "player" ? "player" : RegExMatch(v, "^[0-9A-Fa-f]{6}$") ? StrUpper(v) : o[2]
            }
        return ""
    }
    setColour(key, v) {
        SetIni(v, this.section, key)
        this.push()
    }
    setEnabled(on) {
        SetIni(on ? 1 : 0, this.section, "on")
        this.push()
    }
    colours => Integer(Ini(this.section, "colours", 0))
    colourMode => Ini(this.section, "colourMode", "owner") = "health" ? "health" : "owner"
    setColours(on) {
        SetIni(on ? 1 : 0, this.section, "colours")
        this.push()
    }
    toggleColourMode() {
        SetIni(this.colourMode = "owner" ? "health" : "owner", this.section, "colourMode")
        this.push()
    }
    colourModeLabel => this.colourMode = "owner" ? "By owner" : "By health"
    numbers => Integer(Ini(this.section, "numbers", 0))
    setNumbers(on) {
        SetIni(on ? 1 : 0, this.section, "numbers")
        this.push()
    }
    ; 1-3, in NUMBER_MODES order
    numberMode {
        get {
            m := Ini(this.section, "numberMode", "current")
            for i, n in HealthBarsEngine.NUMBER_MODES
                if n[1] = m
                    return i
            return 1
        }
    }
    numberShows(key) => Integer(Ini(this.section, key, 1))
    setNumberShows(key, on) => (SetIni(on ? 1 : 0, this.section, key), this.push())
    numberWho {
        get {
            bits := 0
            for w in HealthBarsEngine.NUMBER_WHO
                bits |= this.numberShows(w[1]) ? w[3] : 0
            return bits
        }
    }
    numberColour {                      ; one of NUMBER_COLOURS (the old White: Dynamic)
        get {
            v := Ini(this.section, "numberColour", "health")
            for c in HealthBarsEngine.NUMBER_COLOURS
                if c[1] = v
                    return v
            return "health"
        }
    }
    setNumberColour(v) => (SetIni(v, this.section, "numberColour"), this.push())
    numberCustom => Ini(this.section, "numberCustom", "FFD700")
    setNumberCustom(rgb) => (SetIni(rgb, this.section, "numberCustom"), this.push())
    ; mana bars: always on, no option (the user, 2026-11-01; [HealthBars] mana isn't read any more)
    mana => 1
    manaHeight => this.size("manaHeight")
    static Fmt(v) => "×" RTrim(RTrim(Format("{:.2f}", v), "0"), ".")
    ; Reset to default: the whole card (every [HealthBars] key), the sizes, or the bars' colours
    reset(part := "all") {
        global iniFile
        if part = "all" {
            try IniDelete(iniFile, this.section)
        } else {
            for k in part = "sizes" ? ["height", "width", "manaHeight", "manaWidth"] : this.colourKeys()
                try IniDelete(iniFile, this.section, k)
        }
        this.push()
    }
    colourKeys() {
        keys := ["colourMode"]
        for o in HealthBarsEngine.OWNERS
            keys.Push(o[1], o[1] "Own")
        return keys
    }

    ; the wanted sizes to the module in the running game (once a second, and on changes)
    push() {
        if !(v := this.gm.live()) || NumGet(v, Shm.layout, "uint") < 5
            return
        on := this.enabled && this.gm.enabled
        NumPut("float", this.height, v, Shm.hbHeight), NumPut("float", this.width, v, Shm.hbWidth)
        NumPut("uint", on ? 1 : 0, v, Shm.hbOn)                     ; last
        if NumGet(v, Shm.layout, "uint") < 6
            return
        for i, o in HealthBarsEngine.OWNERS          ; 0 = the owner's player colour (layout 12)
            NumPut("uint", (col := this.colour(o[1])) = "player" ? 0 : 0xFF000000 | Integer("0x" col), v, Shm.hcColours + 4 * (i - 1))
        NumPut("uint", this.colourMode = "health" ? 1 : 0, v, Shm.hcMode)
        NumPut("uint", this.colours && this.gm.enabled ? 1 : 0, v, Shm.hcOn)   ; last
        if NumGet(v, Shm.layout, "uint") < 11
            return
        NumPut("uint", HealthBarsEngine.NUMBER_MODES[this.numberMode][3], v, Shm.hnMode), NumPut("float", this.manaHeight, v, Shm.mbHeight)
        NumPut("uint", this.numbers && this.gm.enabled ? 1 : 0, v, Shm.hnOn)
        NumPut("uint", this.mana && this.gm.enabled ? 1 : 0, v, Shm.mbOn)
        NumPut("uint", 0, v, Shm.prMode), NumPut("uint", 0, v, Shm.prOn)     ; the portrait's regen: taken out (2026-11-01)
        if NumGet(v, Shm.layout, "uint") >= 12
            NumPut("float", this.size("manaWidth"), v, Shm.mbWidth)
        if NumGet(v, Shm.layout, "uint") >= 43 {
            ci := 1
            for c in HealthBarsEngine.NUMBER_COLOURS
                ci := c[1] = this.numberColour ? c[3] : ci
            ; (none ticked: still a bit, so it isn't read as the older companion's 0 = all)
            NumPut("uint", (w := this.numberWho) ? w : 0x80000000, v, Shm.hnWho), NumPut("uint", ci, v, Shm.hnColour)
            NumPut("uint", Integer("0x" this.numberCustom), v, Shm.hnCustom)
        }
    }
    ; the status line of a frame feature: its state at stateOff; what(view) says what's on
    frameStatus(on, stateOff, what) {
        if !on
            return "Off"
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        s := this.gm.state()
        if !WinExist(WarcraftIII) || !s.loaded
            return "On · starts with a 1.28f game"
        if s.layout < 11
            return "On · the game has an older module loaded: restart the game"
        if !s.live || s.probe != 1
            return "On · the module isn't ready"
        v := this.gm.live(), st := NumGet(v, stateOff, "uint")
        return NumGet(v, Shm.stState, "uint") = 2 ? "On · the game has no Storm.dll loaded: the module can't add frames"
            : st = 1 ? "On · " what(v) : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for a game"
    }
    numberStatus() => this.frameStatus(this.numbers, Shm.hnState, (v) => "numbers over the health bars (" NumGet(v, Shm.hnCount, "uint") " now)")
    manaStatus() => this.frameStatus(this.mana, Shm.mbState, (v) => "mana bars under the health bars (" NumGet(v, Shm.mbCount, "uint") " now)")
    colourStatus() {
        if !this.colours
            return "Off"
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        s := this.gm.state()
        if !WinExist(WarcraftIII) || !s.loaded
            return "On · starts with a 1.28f game"
        if s.layout < 6
            return "On · the game has an older module loaded: restart the game"
        st := NumGet(this.gm.live(), Shm.hcState, "uint"), players := []
        for o in HealthBarsEngine.OWNERS
            if this.colour(o[1]) = "player"
                players.Push(StrLower(o[3]))
        mode := this.colourMode = "health" ? "green, to yellow at half, to red"
            : "by owner" (players.Length ? " (player colours: " Join(", ", players*) ")" : "")
        if players.Length && s.layout < 12
            mode .= " · the game has an older module: player colours after a restart"
        return st = 1 ? "On · " mode : st = 2 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }

    statusText() {
        if !this.enabled
            return "Off"
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        s := this.gm.state()
        if !WinExist(WarcraftIII) || !s.loaded
            return "On · starts with a 1.28f game"
        if s.layout < 5
            return "On · the game has an older module loaded: restart the game"
        if !s.live || s.probe != 1
            return "On · the module isn't ready"
        v := this.gm.live(), st := NumGet(v, Shm.hbState, "uint")
        return st = 1 ? "On · bars resized (the game's own: " Format("{:.4f}", NumGet(v, Shm.hbDefHeight, "float")) " high)"
            : st = 2 ? "On · no health bars seen yet (in a game?)"
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
}
