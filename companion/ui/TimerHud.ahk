#Requires AutoHotkey v2.0
; ============================================================================
;  TimerHud - the 1.28f cooldown and buff timers, drawn in the game itself by
;  the game module (layout 11, needs the game's Storm.dll), as WFE's Cooldown
;  UI and BUFFUI: seconds left on the command card and inventory buttons, and
;  under the buff bar's icons. Two switches, off by default (ini [Timers]
;  cooldowns, buffs; sent as the module's itOn bits 1 and 2).
;  Cooldowns' options (layout 18): allied units' abilities and cooldowns on
;  the command card too, as WFE's ISALLYABILITYBAR ([Timers] allies), and
;  WFE's cooldown ping: Alt + click an ability or item and your allies read
;  "<unit> >> <ability> | Cooldown: 7" / "| Ready!" / "| Not enough mana!" in
;  chat ([Timers] ping, on by default; the module says which button is under
;  the cursor and writes the line, the companion types it with Enter: the
;  game opens the chat to the Chat dialog's recipient, allies unless changed).
;  WFE's DISPLAYMINUTES per switch (layout 19, [Timers] cdMinutes /
;  buffMinutes, off as WFE's: 95 rather than 1:35). The buffs' own size and
;  gold from, seconds on auras (WFE's ISDRAWAURADURATION, off) and our ring
;  around them (layout 22, [Timers] bfSize / bfGold / bfAuras / bfRing).
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
        ; the ping: Alt + click on a button the module says is under the cursor (else the click is the game's)
        HotIf(ObjBindMethod(this, "pingActive"))
        Hotkey("<!LButton", (*) => this.ping(), "On")
        HotIf()
    }
    allies => Integer(Ini(this.section, "allies", 0))
    pings => Integer(Ini(this.section, "ping", 1))
    setAllies(on) {
        SetIni(on ? 1 : 0, this.section, "allies")
        this.pushGame()
    }
    setPings(on) {
        SetIni(on ? 1 : 0, this.section, "ping")
        this.pushGame()
    }
    pingActive(*) {
        global toolEnabled, chatting
        if !this.cooldowns || !this.pings || !toolEnabled || chatting || !WinActive(WarcraftIII)
            return false
        v := this.gm.live()
        return v && NumGet(v, Shm.layout, "uint") >= 18 && NumGet(v, Shm.hover, "uint") = 1
    }
    ; ask the module for the hovered button's line, and say it in the allies' chat (once a second at most)
    ping() {
        static last := 0
        if A_TickCount - last < 1000
            return
        last := A_TickCount
        r := this.gm.commandWait(this.gm.command(5), 1000)
        text := r = 1 && (v := this.gm.live()) ? StrGet(v + Shm.pingText, 128, "UTF-8") : ""
        DebugLog("cooldown ping: " (text != "" ? text : "nothing to ping (" r ")"))
        if text = ""
            return
        ; Alt + Enter would switch the game's window mode; with Shift the chat opens to all, with Ctrl to allies
        for held in ["LAlt", "Shift", "Ctrl"]
            KeyWait(held, "T1")
        names := ["", "all", "allies", "observers", "one player"]
        dest := (v := this.gm.live()) && NumGet(v, Shm.layout, "uint") >= 19 ? NumGet(v, Shm.pingChat, "uint") : 0
        if dest && dest != 2
            DebugLog("cooldown ping: the game's Chat dialog sends to " names[dest + 1] ", not allies: the line goes there")
        wc3Chat(text)
    }
    ; how the cooldowns look (layout 20): size x0.75-1.5, gold from n s left (0 = never), "Ready" when over
    cdSize => Min(Max(Float(Ini(this.section, "cdSize", 1)), 0.75), 1.5)
    cdGold => Min(Max(Integer(Ini(this.section, "cdGold", 5)), 0), 30)
    cdReady => Integer(Ini(this.section, "cdReady", 1))
    setCdSize(v) => IsNumber(v) && (SetIni(Round(Min(Max(v + 0, 0.75), 1.5), 2), this.section, "cdSize"), this.pushGame(), true)
    setCdGold(v) => IsNumber(v) && (SetIni(Round(Min(Max(v + 0, 0), 30)), this.section, "cdGold"), this.pushGame(), true)
    setCdReady(on) => (SetIni(on ? 1 : 0, this.section, "cdReady"), this.pushGame())
    ; the game's number badge on the command card (a map's counters, shop stock) hidden while cooldowns are drawn (layout 21)
    cdNoBadge => Integer(Ini(this.section, "cdNoBadge", 1))
    setCdNoBadge(on) => (SetIni(on ? 1 : 0, this.section, "cdNoBadge"), this.pushGame())
    ; and the game's cooldown clock (the sweep) on the buttons (layout 21, cdNoBadge bit 2)
    cdNoSweep => Integer(Ini(this.section, "cdNoSweep", 1))       ; on by default since the user's pick: our sweep shows the countdown instead
    ; our own countdown: a line around the button that runs out with the cooldown (cdNoBadge bit 4)
    cdRing => Integer(Ini(this.section, "cdRing", 0))
    setCdRing(on) => (SetIni(on ? 1 : 0, this.section, "cdRing"), this.pushGame())
    setCdNoSweep(on) => (SetIni(on ? 1 : 0, this.section, "cdNoSweep"), this.pushGame())
    ; with the game's clock hidden, our sweep in its place: Blizzard's own model, without the map's clock badge and timer (on by default; cdNoBadge bit 8 = none)
    cdShade => Integer(Ini(this.section, "cdShade", 1))
    setCdShade(on) => (SetIni(on ? 1 : 0, this.section, "cdShade"), this.pushGame())
    ; how the buff seconds look (layout 22): their own size and gold from, seconds on auras too
    ; (WFE's ISDRAWAURADURATION, off), our countdown ring around the buffs (bfOpts bits 1, 2)
    bfSize => Min(Max(Float(Ini(this.section, "bfSize", 1)), 0.75), 1.5)
    bfGold => Min(Max(Integer(Ini(this.section, "bfGold", 5)), 0), 30)
    bfAuras => Integer(Ini(this.section, "bfAuras", 0))
    bfRing => Integer(Ini(this.section, "bfRing", 0))
    setBfSize(v) => IsNumber(v) && (SetIni(Round(Min(Max(v + 0, 0.75), 1.5), 2), this.section, "bfSize"), this.pushGame(), true)
    setBfGold(v) => IsNumber(v) && (SetIni(Round(Min(Max(v + 0, 0), 30)), this.section, "bfGold"), this.pushGame(), true)
    setBfAuras(on) => (SetIni(on ? 1 : 0, this.section, "bfAuras"), this.pushGame())
    setBfRing(on) => (SetIni(on ? 1 : 0, this.section, "bfRing"), this.pushGame())
    cdMinutes => Integer(Ini(this.section, "cdMinutes", 0))
    buffMinutes => Integer(Ini(this.section, "buffMinutes", 0))
    setMinutes(key, on) {
        SetIni(on ? 1 : 0, this.section, key)
        this.pushGame()
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
        if v && NumGet(v, Shm.layout, "uint") >= 18 {
            NumPut("uint", this.gm.enabled && this.cooldowns && this.allies ? 1 : 0, v, Shm.alOn)
            NumPut("uint", this.gm.enabled && this.cooldowns && this.pings ? 1 : 0, v, Shm.pingOn)
        }
        if v && NumGet(v, Shm.layout, "uint") >= 19
            NumPut("uint", (this.cdMinutes ? 1 : 0) | (this.buffMinutes ? 2 : 0), v, Shm.tmMinutes)
        if v && NumGet(v, Shm.layout, "uint") >= 20
            NumPut("float", this.cdSize, v, Shm.cdSize), NumPut("float", this.cdGold, v, Shm.cdGold), NumPut("uint", this.cdReady ? 1 : 0, v, Shm.cdReady)
        if v && NumGet(v, Shm.layout, "uint") >= 21
            NumPut("uint", (this.cdNoBadge ? 1 : 0) | (this.cdNoSweep ? 2 : 0) | (this.cdRing ? 4 : 0) | (this.cdShade ? 0 : 8), v, Shm.cdNoBadge)
        if v && NumGet(v, Shm.layout, "uint") >= 22
            NumPut("float", this.bfSize, v, Shm.bfSize), NumPut("float", this.bfGold, v, Shm.bfGold), NumPut("uint", (this.bfAuras ? 1 : 0) | (this.bfRing ? 2 : 0), v, Shm.bfOpts)
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

    cooldownStatus() {
        st := this.statusOf(this.cooldowns, "on the command card and items")
        if st = "Off" || !(v := this.gm.live()) || NumGet(v, Shm.layout, "uint") < 18
            return st
        al := NumGet(v, Shm.alState, "uint")
        return st (this.allies ? al = 3 ? " · allies' abilities refused (see the log)" : al = 1 ? " · allies' too" : "" : "")
            . (this.pings ? " · Alt + click pings" : "")
    }
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
