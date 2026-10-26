#Requires AutoHotkey v2.0
; ============================================================================
;  GameDisplayEngine - widescreen and FPS unlock on 1.28f, through the game
;  module (shared memory layout 7; both run on the game's thread, as WFE's).
;  Widescreen: the game's own 16:9 setting, set again at each game start and
;  after the window changes size. FPS unlock: the game's frame limiter is
;  switched off and its frame limit setting raised to the limit here (64 at
;  least); turning it off puts both back.
;  Both off by default (ini [Display] widescreen, fps, fpsLimit).
;  Also, on the same path: the lobby latency of games you host (WC3 page >
;  Hosting; WFE's [DELAY]): the game's LAN, single player and Battle.net
;  latency getters return the ms set here. Off by default (ini [Hosting]
;  latency, latencyMs).
;  And hiding parts of the UI (layout 10, WFE's INTERFACE keys for the parts
;  it hides with their own calls): time of day, minimap, upper menu bar,
;  resource bar, idle workers. Off by default (ini [Display] hideUi, and
;  hideParts: the parts as bits, in PARTS order).
; ============================================================================
class GameDisplayEngine {
    section := "Display"
    static LIMITS := [120, 144, 165, 200, 240, 300]
    static LATENCIES := [25, 50, 75, 100, 150, 200]
    static PARTS := ["Time of day", "Minimap", "Upper menu bar", "Resource bar", "Idle workers"]

    __New(gameModule) {
        this.gm := gameModule
        this.tickFn := ObjBindMethod(this, "push")
        SetTimer(this.tickFn, 1000)
    }
    widescreen => Integer(Ini(this.section, "widescreen", 0))
    setWidescreen(on) {
        SetIni(on ? 1 : 0, this.section, "widescreen")
        this.push()
    }
    fps => Integer(Ini(this.section, "fps", 0))
    setFps(on) {
        SetIni(on ? 1 : 0, this.section, "fps")
        this.push()
    }
    fpsLimit => Integer(Ini(this.section, "fpsLimit", 200))
    ; the next limit up (wrapping back to the lowest)
    cycleLimit() {
        cur := this.fpsLimit, next := GameDisplayEngine.LIMITS[1]
        for v in GameDisplayEngine.LIMITS
            if v > cur {
                next := v
                break
            }
        SetIni(next, this.section, "fpsLimit")
        this.push()
    }
    limitLabel => "Limit " this.fpsLimit
    latency => Integer(Ini("Hosting", "latency", 0))
    setLatency(on) {
        SetIni(on ? 1 : 0, "Hosting", "latency")
        this.push()
    }
    latencyMs => Integer(Ini("Hosting", "latencyMs", 50))
    cycleLatency() {
        cur := this.latencyMs, next := GameDisplayEngine.LATENCIES[1]
        for v in GameDisplayEngine.LATENCIES
            if v > cur {
                next := v
                break
            }
        SetIni(next, "Hosting", "latencyMs")
        this.push()
    }
    latencyLabel => this.latencyMs " ms"
    hideUi => Integer(Ini(this.section, "hideUi", 0))
    setHideUi(on) {
        SetIni(on ? 1 : 0, this.section, "hideUi")
        this.push()
    }
    hideParts => Integer(Ini(this.section, "hideParts", 0)) & 0x1f
    setPart(i, on) {
        m := this.hideParts
        SetIni(on ? m | (1 << (i - 1)) : m & ~(1 << (i - 1)), this.section, "hideParts")
        this.push()
    }
    partsCount() {
        n := 0
        loop GameDisplayEngine.PARTS.Length
            n += (this.hideParts >> (A_Index - 1)) & 1
        return n
    }
    partsLabel => "Parts: " this.partsCount() " of " GameDisplayEngine.PARTS.Length

    ; the switches to the module in the running game (once a second, and on changes)
    push() {
        if !(v := this.gm.live()) || NumGet(v, Shm.layout, "uint") < 7
            return
        NumPut("uint", this.fpsLimit, v, Shm.fpsLimit)
        NumPut("uint", this.fps && this.gm.enabled ? 1 : 0, v, Shm.fpsOn)
        NumPut("uint", this.widescreen && this.gm.enabled ? 1 : 0, v, Shm.wsOn)
        if NumGet(v, Shm.layout, "uint") < 9
            return
        NumPut("uint", this.latencyMs, v, Shm.latMs)
        NumPut("uint", this.latency && this.gm.enabled ? 1 : 0, v, Shm.latOn)
        if NumGet(v, Shm.layout, "uint") < 10
            return
        NumPut("uint", this.hideUi && this.gm.enabled ? this.hideParts : 0, v, Shm.uiHide)
    }

    ; the common part of both status lines ("" = the module is there to ask)
    moduleWait(layout := 7) {
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        s := this.gm.state()
        if !WinExist(WarcraftIII) || !s.loaded
            return "On · starts with a 1.28f game"
        if s.layout < layout
            return "On · the game has an older module loaded: restart the game"
        if !s.live || s.probe != 1
            return "On · the module isn't ready"
        return ""
    }
    wsStatus() {
        if !this.widescreen
            return "Off"
        if (w := this.moduleWait()) != ""
            return w
        st := NumGet(this.gm.live(), Shm.wsState, "uint")
        return st = 1 ? "On · 16:9 in this game" : st = 2 ? "On · waiting for a game"
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
    hideStatus() {
        if !this.hideUi
            return "Off"
        if !this.hideParts
            return "On · pick the parts to hide"
        if (w := this.moduleWait(10)) != ""
            return w
        st := NumGet(this.gm.live(), Shm.uiState, "uint"), names := []
        for i, n in GameDisplayEngine.PARTS
            if st & (1 << (i - 1))
                names.Push(StrLower(n))
        return st & 0x80000000 ? "On · one part was refused by the module's checks (see the log)"
            : names.Length ? "On · hidden: " Join(", ", names*) : "On · waiting for a game"
    }
    latencyStatus() {
        if !this.latency
            return "Off"
        if (w := this.moduleWait(9)) != ""
            return w
        v := this.gm.live(), st := NumGet(v, Shm.latState, "uint")
        own := st = 1 ? " (the game's own: LAN " NumGet(v, Shm.latGame, "int") ", Battle.net " NumGet(v, Shm.latGame + 8, "int") ")" : ""
        return st = 1 ? "On · " this.latencyMs " ms in games you host" own
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
    fpsStatus() {
        if !this.fps
            return "Off"
        if (w := this.moduleWait()) != ""
            return w
        v := this.gm.live(), st := NumGet(v, Shm.fpsState, "uint"), own := NumGet(v, Shm.fpsGameLimit, "uint")
        return st = 1 ? "On · unlocked up to " this.fpsLimit (own ? " (the game's own setting: " own ")" : "")
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
}
