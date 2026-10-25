#Requires AutoHotkey v2.0
; ============================================================================
;  HealthBarsEngine - health bar size on 1.28f, through the game module
;  (shared memory layout 5: it resizes every unit's health bar on the game's
;  thread, like WFE's HEALTHBAR HEIGHT). Height and width are multiples of
;  the game's own size; width is experimental (WFE never changes it).
;  Off by default (ini [HealthBars] on, height, width). Turning it off puts
;  the bars back.
; ============================================================================
class HealthBarsEngine {
    section := "HealthBars"
    static STEPS := [1, 1.25, 1.5, 2, 2.5, 3]

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
