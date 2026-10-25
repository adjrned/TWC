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
; ============================================================================
class GameDisplayEngine {
    section := "Display"
    static LIMITS := [120, 144, 165, 200, 240, 300]
    static LATENCIES := [25, 50, 75, 100, 150, 200]

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

    ; the switches to the module in the running game (once a second, and on changes)
    push() {
        if !(v := this.gm.live()) || NumGet(v, 4, "uint") < 7
            return
        NumPut("uint", this.fpsLimit, v, 624)
        NumPut("uint", this.fps && this.gm.enabled ? 1 : 0, v, 620)
        NumPut("uint", this.widescreen && this.gm.enabled ? 1 : 0, v, 612)
        if NumGet(v, 4, "uint") < 9
            return
        NumPut("uint", this.latencyMs, v, 656)
        NumPut("uint", this.latency && this.gm.enabled ? 1 : 0, v, 652)
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
        st := NumGet(this.gm.live(), 616, "uint")
        return st = 1 ? "On · 16:9 in this game" : st = 2 ? "On · waiting for a game"
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
    latencyStatus() {
        if !this.latency
            return "Off"
        if (w := this.moduleWait(9)) != ""
            return w
        v := this.gm.live(), st := NumGet(v, 660, "uint")
        own := st = 1 ? " (the game's own: LAN " NumGet(v, 664, "int") ", Battle.net " NumGet(v, 672, "int") ")" : ""
        return st = 1 ? "On · " this.latencyMs " ms in games you host" own
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
    fpsStatus() {
        if !this.fps
            return "Off"
        if (w := this.moduleWait()) != ""
            return w
        v := this.gm.live(), st := NumGet(v, 628, "uint"), own := NumGet(v, 632, "uint")
        return st = 1 ? "On · unlocked up to " this.fpsLimit (own ? " (the game's own setting: " own ")" : "")
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
}
