#Requires AutoHotkey v2.0
; ============================================================================
;  HealthBarsEngine - health bar size on 1.28f, through the game module
;  (shared memory layout 5: it resizes every unit's health bar on the game's
;  thread, like WFE's HEALTHBAR HEIGHT). Height and width are multiples of
;  the game's own size; width is experimental (WFE never changes it).
;  Off by default (ini [HealthBars] on, height, width). Turning it off puts
;  the bars back.
;  Colours (layout 6, also off by default: [HealthBars] colours, colourMode):
;  by owner (yours / allies / enemies / neutral hostile / neutral passive,
;  ini keys yours, allies, enemies, hostile, passive as RRGGBB) or by health
;  (green, to yellow at half, to red). The module sets them right after the
;  game's own bar update.
;  Health numbers and mana bars (layout 11; they need the game's Storm.dll,
;  both off by default): a number over each health bar ([HealthBars] numbers,
;  numberMode current / max / percent) and a mana bar under the health bar
;  of each unit with mana ([HealthBars] mana, manaHeight: times the health
;  bar's height). Frames the module adds to the game; turning off takes them
;  away.
;  Portrait regen (layout 11, off by default, no Storm.dll needed): the
;  portrait's own HP / mana lines become "cur / max +regen" (and the percent,
;  [HealthBars] portraitPercent) right after the game writes them
;  ([HealthBars] portrait).
; ============================================================================
class HealthBarsEngine {
    section := "HealthBars"
    static STEPS := [1, 1.25, 1.5, 2, 2.5, 3]
    static NUMBER_MODES := [["current", "Current"], ["max", "Current / max"], ["percent", "Percent"]]
    static MANA_STEPS := [0.5, 0.75, 1]
    static OWNERS := [["yours", "00FF00"], ["allies", "0080FF"], ["enemies", "FF0000"], ["hostile", "FF8000"], ["passive", "A0A0A0"]]

    __New(gameModule) {
        this.gm := gameModule
        this.tickFn := ObjBindMethod(this, "push")
        SetTimer(this.tickFn, 1000)
    }
    enabled => Integer(Ini(this.section, "on", 0))
    height => Ini(this.section, "height", 1.5) + 0
    width => Ini(this.section, "width", 1) + 0
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
    cycleNumberMode() {
        SetIni(HealthBarsEngine.NUMBER_MODES[Mod(this.numberMode, 3) + 1][1], this.section, "numberMode")
        this.push()
    }
    numberModeLabel => HealthBarsEngine.NUMBER_MODES[this.numberMode][2]
    mana => Integer(Ini(this.section, "mana", 0))
    setMana(on) {
        SetIni(on ? 1 : 0, this.section, "mana")
        this.push()
    }
    manaHeight => Ini(this.section, "manaHeight", 0.75) + 0
    cycleManaHeight() {
        cur := this.manaHeight, next := HealthBarsEngine.MANA_STEPS[1]
        for v in HealthBarsEngine.MANA_STEPS
            if v > cur + 0.001 {
                next := v
                break
            }
        SetIni(next, this.section, "manaHeight")
        this.push()
    }
    manaHeightLabel => "Height " HealthBarsEngine.Fmt(this.manaHeight)
    portrait => Integer(Ini(this.section, "portrait", 0))
    setPortrait(on) {
        SetIni(on ? 1 : 0, this.section, "portrait")
        this.push()
    }
    portraitPercent => Integer(Ini(this.section, "portraitPercent", 0))
    togglePortraitPercent() {
        SetIni(this.portraitPercent ? 0 : 1, this.section, "portraitPercent")
        this.push()
    }
    portraitPercentLabel => this.portraitPercent ? "Percent: on" : "Percent: off"
    ; the next step up (wrapping back to 1x): "height" / "width"
    cycle(which) {
        cur := this.%which%, next := HealthBarsEngine.STEPS[1]
        for v in HealthBarsEngine.STEPS
            if v > cur + 0.001 {
                next := v
                break
            }
        SetIni(next, this.section, which)
        this.push()
    }
    static Fmt(v) => "×" RTrim(RTrim(Format("{:.2f}", v), "0"), ".")
    label(which) => (which = "height" ? "Height " : "Width ") HealthBarsEngine.Fmt(this.%which%)

    ; the wanted sizes to the module in the running game (once a second, and on changes)
    push() {
        if !(v := this.gm.live()) || NumGet(v, 4, "uint") < 5
            return
        on := this.enabled && this.gm.enabled
        NumPut("float", this.height, v, 556), NumPut("float", this.width, v, 560)
        NumPut("uint", on ? 1 : 0, v, 552)                     ; last
        if NumGet(v, 4, "uint") < 6
            return
        for i, o in HealthBarsEngine.OWNERS
            NumPut("uint", 0xFF000000 | Integer("0x" Ini(this.section, o[1], o[2])), v, 588 + 4 * (i - 1))
        NumPut("uint", this.colourMode = "health" ? 1 : 0, v, 584)
        NumPut("uint", this.colours && this.gm.enabled ? 1 : 0, v, 580)   ; last
        if NumGet(v, 4, "uint") < 11
            return
        NumPut("uint", this.numberMode - 1, v, 704), NumPut("float", this.manaHeight, v, 716)
        NumPut("uint", this.numbers && this.gm.enabled ? 1 : 0, v, 700)
        NumPut("uint", this.mana && this.gm.enabled ? 1 : 0, v, 712)
        NumPut("uint", this.portraitPercent, v, 784)
        NumPut("uint", this.portrait && this.gm.enabled ? 1 : 0, v, 780)
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
        return NumGet(v, 684, "uint") = 2 ? "On · the game has no Storm.dll loaded: the module can't add frames"
            : st = 1 ? "On · " what(v) : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for a game"
    }
    portraitStatus() {
        if !this.portrait
            return "Off"
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        s := this.gm.state()
        if !WinExist(WarcraftIII) || !s.loaded
            return "On · starts with a 1.28f game"
        if s.layout < 11
            return "On · the game has an older module loaded: restart the game"
        st := NumGet(this.gm.live(), 788, "uint")
        return st = 1 ? "On · regen next to the portrait's HP and mana" : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for a game"
    }
    numberStatus() => this.frameStatus(this.numbers, 708, (v) => "numbers over the health bars (" NumGet(v, 724, "uint") " now)")
    manaStatus() => this.frameStatus(this.mana, 720, (v) => "mana bars under the health bars (" NumGet(v, 728, "uint") " now)")
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
        st := NumGet(this.gm.live(), 608, "uint")
        mode := this.colourMode = "owner" ? "yours green, allies blue, enemies red, neutral orange / grey" : "green, to yellow at half, to red"
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
        v := this.gm.live(), st := NumGet(v, 564, "uint")
        return st = 1 ? "On · bars resized (the game's own: " Format("{:.4f}", NumGet(v, 568, "float")) " high)"
            : st = 2 ? "On · no health bars seen yet (in a game?)"
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
}
