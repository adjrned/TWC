#Requires AutoHotkey v2.0
; ============================================================================
;  TimerHud - the 1.28f cooldown and buff timers, drawn in the game itself by
;  the game module (layout 11, needs the game's Storm.dll), as WFE's Cooldown
;  UI and BUFFUI: seconds left on the command card and inventory buttons, and
;  under the buff bar's icons. Two switches, off by default (ini [Timers]
;  cooldowns, buffs; sent as the module's itOn bits 1 and 2).
;  No screen reading on 1.28f: that's for Reforged (planned, see the WC3
;  page's Timers tab). The buff bar setup here (two presses in game, per
;  window size: [Timers] buff_<window>) is the buff alerts' (BuffWatch).
; ============================================================================
class TimerHud {
    section := "Timers"
    cal := 0                        ; the buff bar setup in progress: { step, p1 }
    calHotkey := "$Space"
    static STEPS := ["Point at the middle of your hero's first buff icon (left) and press Space",
        "Point at the middle of the buff slot right of it (empty is fine) and press Space"]

    __New(gameModule) {
        this.gm := gameModule
        ; before the split (one switch for both): it carries over to both
        if (old := Ini(this.section, "show", "")) != "" {
            for k in ["cooldowns", "buffs"]
                if Ini(this.section, k, "") = ""
                    SetIni(old, this.section, k)
            try IniDelete(iniFile, this.section, "show")
            try IniDelete(iniFile, this.section, "where")
        }
        this.pushFn := ObjBindMethod(this, "pushGame")
        SetTimer(this.pushFn, 1000)
    }
    cooldowns => Integer(Ini(this.section, "cooldowns", 0))
    buffs => Integer(Ini(this.section, "buffs", 0))
    setCooldowns(on) {
        SetIni(on ? 1 : 0, this.section, "cooldowns")
        this.pushGame()
    }
    setBuffs(on) {
        SetIni(on ? 1 : 0, this.section, "buffs")
        this.pushGame()
    }
    ; the switches to the module (layout 11): bit 1 cooldowns (command card, items), bit 2 buffs
    pushGame() {
        if (v := this.gm.live()) && NumGet(v, Shm.layout, "uint") >= 11
            NumPut("uint", this.gm.enabled ? (this.cooldowns ? 1 : 0) | (this.buffs ? 2 : 0) : 0, v, Shm.itOn)
    }
    ; the module's own drawing: 0 off, 1 drawing, 2 waiting, 3 refused; -1 no module that can
    gameState() {
        if !(v := this.gm.live()) || NumGet(v, Shm.layout, "uint") < 11
            return -1
        return NumGet(v, Shm.itState, "uint")
    }

    ; the buff bar for the game window as it is now: { x, y, dx } (fractions of
    ; the client area: the first icon's middle, the step to the next) or 0
    buffBar() {
        if !(k := WC3WindowKey()) || (v := Ini(this.section, "buff_" k, "")) = ""
            return 0
        p := StrSplit(v, ",")
        return p.Length = 3 ? { x: p[1] + 0, y: p[2] + 0, dx: p[3] + 0 } : 0
    }

    cooldownStatus() => this.statusOf(this.cooldowns, "on the command card and items")
    buffStatus() => this.statusOf(this.buffs, "under the buff icons")
    statusOf(on, where) {
        if !on
            return "Off"
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        s := this.gm.state()
        if !WinExist(WarcraftIII) || !s.loaded
            return "On · starts with a 1.28f game"
        if s.layout < 11
            return "On · the game has an older module loaded: restart the game"
        if s.probe != 1
            return "On · the module's check failed"
        st := this.gameState(), storm := NumGet(this.gm.live(), Shm.stState, "uint"), t := this.gm.timers()
        return storm = 2 ? "On · the game has no Storm.dll loaded: no timers"
            : st = 3 ? "On · refused by the module's checks (see the log)"
            : st = 1 ? "On · drawn " where (t && t.flags & 0x100 ? " · some game timers refused (see the log)" : "")
            : "On · waiting for a game"
    }

    ; -- the buff bar setup (two presses of Space in game) --------------------
    ; Remaps and macros pause meanwhile (qcCalibrating, as in the quickcast
    ; setup). Esc cancels.
    setupStart() {
        global qcCalibrating
        if !WinExist(WarcraftIII)
            return Toast("Start Warcraft III first, in a game with your hero selected", "error")
        this.cal := { step: 1 }
        qcCalibrating := true, RefreshHotkeys()
        HotIfWinActive(WarcraftIII)
        Hotkey(this.calHotkey, (*) => this.setupStep(), "On")
        HotIfWinActive()
        WinActivate(WarcraftIII)
        this.stepToast(1)
    }
    stepToast(n) => Toast("Buff bar setup " n "/2  ·  " TimerHud.STEPS[n] "  ·  Esc cancels", "", 0)
    setupStep() {
        if !(c := this.cal)
            return
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        p := [(mx - wx) / cw, (my - wy) / ch]
        if c.step = 1 {
            c.p1 := p, c.step := 2
            return this.stepToast(2)
        }
        dx := p[1] - c.p1[1]
        if dx < 0.005 || Abs(p[2] - c.p1[2]) > 0.02
            return this.setupEnd(0, "The second point wasn't just right of the first. Run the setup again.")
        SetIni(Format("{:.5f},{:.5f},{:.5f}", c.p1[1], c.p1[2], dx), this.section, "buff_" WC3WindowKey())
        this.setupEnd(1, "Buff bar set up for " StrReplace(WC3WindowKey(), "_", " "))
    }
    setupEnd(ok, msg) {
        global qcCalibrating
        if !this.cal
            return
        HotIfWinActive(WarcraftIII)
        try Hotkey(this.calHotkey, "Off")
        HotIfWinActive()
        qcCalibrating := false, RefreshHotkeys()
        this.cal := 0
        DebugLog("buff bar setup ended: " msg)
        Toast(msg, ok ? "" : "error")
    }
}
