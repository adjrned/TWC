#Requires AutoHotkey v2.0
; ============================================================================
;  GameDisplayEngine - widescreen and FPS unlock on 1.28f, through the game
;  module (shared memory layout 7; both run on the game's thread, as WFE's).
;  Widescreen (WFE's WIDESCREEN): the world isn't stretched sideways on a
;  wide window, you see more of it (the camera's projection is narrowed by
;  the window's shape; the 2D UI stays the game's 4:3 one). FPS unlock: the game's frame limiter is
;  switched off and its frame limit setting raised to the limit here (64 at
;  least); turning it off puts both back.
;  Both off by default (ini [Display] widescreen, fps, fpsLimit).
;  Also, on the same path: the lobby latency of games you host (WC3 page >
;  Hosting; WFE's [DELAY]): the game's LAN, single player and Battle.net
;  latency getters return the ms set here. Off by default (ini [Hosting]
;  latency, latencyMs). And their start countdown (WFE's [DELAY] GAMESTART):
;  the seconds set here instead of the game's 6 (ini [Hosting] countdown,
;  countdownSecs, 0 by default as WFE's).
;  And hiding the UI (layout 10, WFE's INTERFACE keys for the parts it hides
;  with their own calls): one switch, as WFE looks with its UI hidden: the
;  console's black background goes (the world shows through), and the time
;  of day, upper menu bar, resource bar, idle workers and buff bar with it; the
;  minimap, portrait, command card and inventory stay; the upper menu bar's
;  buttons can stay too ([Display] hideMenu 0). Off by default (ini
;  [Display] hideUi).
;  And the widescreen UI layout (layout 14, WFE's Upgraded UI): on a wide
;  window the module lays the UI frames out again as WFE does, so the 4:3 UI
;  isn't stretched. Off by default ([Display] wideUi); the buff bar can be
;  raised over the console as WFE's ISUPGRADEDBUFFBAR ([Display] buffBarUp).
; ============================================================================
class GameDisplayEngine {
    section := "Display"
    static LIMITS := [120, 144, 165, 200, 240, 300]
    static LATENCIES := [25, 50, 75, 100, 150, 200]
    ; the module's uiHide bits, in order; HIDE: the ones the switch hides (all but the minimap)
    static PARTS := ["Time of day", "Minimap", "Upper menu bar", "Resource bar", "Idle workers", "The console's background", "Buff bar"]
    static HIDE := 0x7D

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
    ; the game start countdown of games you host (WFE's [DELAY] GAMESTART): layout 17, ini [Hosting] countdown, countdownSecs
    countdown => Integer(Ini("Hosting", "countdown", 0))
    setCountdown(on) {
        SetIni(on ? 1 : 0, "Hosting", "countdown")
        this.push()
    }
    countdownSecs {
        get {
            v := Ini("Hosting", "countdownSecs", 0)
            return IsNumber(v) ? Min(Max(v + 0, 0), 6) : 0
        }
    }
    ; typed or slid: 0-6 s, tenths (false if it isn't a number)
    setCountdownSecs(v) {
        if !IsNumber(v)
            return false
        SetIni(Round(Min(Max(v + 0, 0), 6), 1), "Hosting", "countdownSecs")
        this.push()
        return true
    }
    countdownLabel => "Countdown: " SecsText(this.countdownSecs) " s"
    countdownStatus() {
        if !this.countdown
            return "Off"
        if (w := this.moduleWait(17)) != ""
            return w
        v := this.gm.live(), st := NumGet(v, Shm.csState, "uint"), own := NumGet(v, Shm.csGame, "float")
        return st = 1 ? "On · games you host start " SecsText(this.countdownSecs) " s after Start Game" (own ? " (the game's own: " SecsText(own) " s)" : "")
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
    hideUi => Integer(Ini(this.section, "hideUi", 0))
    hideMenu => Integer(Ini(this.section, "hideMenu", 1))
    toggleHideMenu() {
        SetIni(this.hideMenu ? 0 : 1, this.section, "hideMenu")
        this.push()
    }
    menuLabel => this.hideMenu ? "Menu buttons: hidden" : "Menu buttons: shown"
    hideMask => this.hideMenu ? GameDisplayEngine.HIDE : GameDisplayEngine.HIDE & ~4
    ; WFE's widescreen UI layout (its Upgraded UI): layout 14, ini [Display] wideUi
    wideUi => Integer(Ini(this.section, "wideUi", 0))
    setWideUi(on) {
        SetIni(on ? 1 : 0, this.section, "wideUi")
        this.push()
    }
    ; WFE's [BUFFUI] ISUPGRADEDBUFFBAR with it: the buff bar raised over the console (ulOn bit 2)
    buffBarUp => Integer(Ini(this.section, "buffBarUp", 0))
    toggleBuffBarUp() {
        SetIni(this.buffBarUp ? 0 : 1, this.section, "buffBarUp")
        this.push()
    }
    buffBarLabel => this.buffBarUp ? "Buff bar: raised" : "Buff bar: in place"
    wideUiStatus() {
        if !this.wideUi
            return "Off"
        if (w := this.moduleWait(14)) != ""
            return w
        v := this.gm.live(), st := NumGet(v, Shm.ulState, "uint")
        return st = 1 ? "On · " NumGet(v, Shm.ulCount, "uint") " frames laid out for the wide window"
            : st = 2 ? "On · waits for a game in a wide window (4:3 is left as it is)"
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
    ; fast menus (WFE's Fast Menu): layout 16, ini [Display] fastMenu
    fastMenu => Integer(Ini(this.section, "fastMenu", 0))
    setFastMenu(on) {
        SetIni(on ? 1 : 0, this.section, "fastMenu")
        this.push()
    }
    fastMenuStatus() {
        if !this.fastMenu
            return "Off"
        if (w := this.moduleWait(16)) != ""
            return w
        st := NumGet(this.gm.live(), Shm.fmState, "uint")
        return st = 1 ? "On · the menus switch at once"
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
    ; detailed tooltips (the info panel's damage / armor icons): layout 15, ini [Display] tooltips
    tooltips => Integer(Ini(this.section, "tooltips", 0))
    setTooltips(on) {
        SetIni(on ? 1 : 0, this.section, "tooltips")
        this.push()
    }
    tooltipsStatus() {
        if !this.tooltips
            return "Off"
        if (w := this.moduleWait(15)) != ""
            return w
        st := NumGet(this.gm.live(), Shm.ttState, "uint")
        return st = 1 ? "On · hover the damage or armor icon of a unit"
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
    setHideUi(on) {
        SetIni(on ? 1 : 0, this.section, "hideUi")
        this.push()
    }

    ; the switches to the module in the running game (once a second, and on changes)
    push() {
        if !(v := this.gm.live()) || NumGet(v, Shm.layout, "uint") < 7
            return
        NumPut("uint", this.fpsLimit, v, Shm.fpsLimit)
        NumPut("uint", this.fps && this.gm.enabled ? 1 : 0, v, Shm.fpsOn)
        NumPut("uint", this.widescreen && this.gm.enabled ? 1 : 0, v, Shm.wsOn)   ; the module leaves it to another widescreen mod that's there (state 4)
        if NumGet(v, Shm.layout, "uint") < 9
            return
        NumPut("uint", this.latencyMs, v, Shm.latMs)
        NumPut("uint", this.latency && this.gm.enabled ? 1 : 0, v, Shm.latOn)
        if NumGet(v, Shm.layout, "uint") < 10
            return
        NumPut("uint", this.hideUi && this.gm.enabled ? this.hideMask : 0, v, Shm.uiHide)
        if NumGet(v, Shm.layout, "uint") >= 14
            NumPut("uint", this.wideUi && this.gm.enabled ? 1 | (this.buffBarUp ? 2 : 0) : 0, v, Shm.ulOn)
        if NumGet(v, Shm.layout, "uint") >= 15
            NumPut("uint", this.tooltips && this.gm.enabled ? 1 : 0, v, Shm.ttOn)
        if NumGet(v, Shm.layout, "uint") >= 16
            NumPut("uint", this.fastMenu && this.gm.enabled ? 1 : 0, v, Shm.fmOn)
        if NumGet(v, Shm.layout, "uint") >= 17 {
            NumPut("float", this.countdownSecs, v, Shm.csSecs)
            NumPut("uint", this.countdown && this.gm.enabled ? 1 : 0, v, Shm.csOn)
        }
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
        return st = 1 ? "On · the world fits the window" : st = 2 ? "On · waiting for the game window"
            : st = 4 ? "On · another widescreen mod (e.g. RenderEdge's mix file) already does it: left to it"
            : st = 3 ? "On · refused by the module's checks (see the log)" : "On · waiting for the game"
    }
    hideStatus() {
        if !this.hideUi
            return "Off"
        if (w := this.moduleWait(10)) != ""
            return w
        st := NumGet(this.gm.live(), Shm.uiState, "uint"), names := []
        for i, n in GameDisplayEngine.PARTS
            if st & (1 << (i - 1))
                names.Push(StrLower(n))
        return st & 0x80000000 ? "On · a part was refused by the module's checks (see the log)"
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
