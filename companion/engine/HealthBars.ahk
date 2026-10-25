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
; ============================================================================
class HealthBarsEngine {
    section := "HealthBars"
    static STEPS := [1, 1.25, 1.5, 2, 2.5, 3]
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
    }
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
