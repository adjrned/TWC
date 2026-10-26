#Requires AutoHotkey v2.0
; ============================================================================
;  GameCommandsEngine - hotkeys that ask the 1.28f game module to do something
;  on the game's own thread: clear the trigger messages, clear the chat (as
;  WFE's Clear Messages / Clear Chat), minimise / maximise the multiboard (its
;  Toggle Multiboard State). One switch for the three, off by default (ini
;  [Game] clear); the keys are in [GameKeys] and are bound only while it's on.
;  They only act in Warcraft III with the module ready and chat closed;
;  otherwise the key goes to the game as usual.
;  Two keys are held instead (WFE's Self Cast and AutoCast toggle keys; ini
;  [Game] selfcast, autocast; [GameKeys] selfcast, autocast), and kept from
;  the game while they act:
;    self-cast  held while you cast: your portrait is clicked as the game
;               waits for a target, so it goes on your selected unit. On 1.28f
;               with the module, the module clicks it in the game (it's told
;               the key is held through shared memory); otherwise (Reforged,
;               or no module) it's from the screen: the quickcast setup sees
;               the aim and the portrait spot (its own one-step setup, per
;               window size: [SelfCast] portrait_<window>) is clicked
;    autocast   held while you press a command card key: that button gets a
;               right click (autocast on / off) instead of the key
; ============================================================================
class GameCommandsEngine {
    section := "GameKeys"
    ; ini key -> [command, the [Game] switch it belongs to]
    static CMDS := Map("clearMessages", [1, "clear"], "clearChat", [2, "clear"], "multiboard", [3, "clear"])
    bound := []                     ; { hk, cond } bound now
    selfDown := false               ; the self-cast key is held (its own hotkeys say)

    __New(gameModule) {
        this.gm := gameModule
        this.hotIfFn := ObjBindMethod(this, "active")
        this.acHotIfFn := ObjBindMethod(this, "autocastHeld")
        this.scHotIfFn := ObjBindMethod(this, "selfActive")
        this.ssHotIfFn := ObjBindMethod(this, "screenSelfHeld")
        this.bind()
        this.pushFn := ObjBindMethod(this, "push")
        SetTimer(this.pushFn, 1000)
    }
    switchOn(flag) => Integer(Ini("Game", flag, 0))
    setSwitch(flag, on) {
        SetIni(on ? 1 : 0, "Game", flag)
        this.bind()
    }
    enabled => this.switchOn("clear")
    setEnabled(on) => this.setSwitch("clear", on)
    selfcast => this.switchOn("selfcast")
    setSelfcast(on) => this.setSwitch("selfcast", on)
    autocast => this.switchOn("autocast")
    setAutocast(on) => this.setSwitch("autocast", on)
    key(name) => Ini(this.section, name, "")
    ; a held key: its key alone (a captured Ctrl+X is X)
    heldKey(name) => (k := this.key(name)) != "" ? HotkeyBase(k) : ""

    ; the keys act only when this is true (else they reach the game)
    active(*) {
        global toolEnabled, chatting
        return toolEnabled && !chatting && WinActive(WarcraftIII) && this.gm.cmdReady()
    }
    ; the autocast key is held (the command card keys then toggle autocast)
    autocastHeld(*) {
        if !this.autocast || (k := this.heldKey("autocast")) = "" || !this.active() || this.gm.state().layout < 8
            return false
        try return GetKeyState(k, "P")
        return false
    }
    ; the self-cast key is held and the module can use it
    selfCastHeld() => this.selfcast && this.selfDown && this.moduleSelf()
    moduleSelf() => this.active() && this.gm.state().layout >= 8
    ; the self-cast key acts (in the game, chat closed): the module's way or the screen's
    selfActive(*) {
        global toolEnabled, chatting
        return this.selfcast && toolEnabled && !chatting && WinActive(WarcraftIII) && (this.moduleSelf() || this.screenSelfReady())
    }
    ; -- self-cast from the screen ---------------------------------------------
    ; the portrait spot for this window size, in screen pixels, or 0
    portraitSpot() {
        if !(k := WC3WindowKey()) || (v := Ini("SelfCast", "portrait_" k, "")) = "" || !WinExist(WarcraftIII)
            return 0
        p := StrSplit(v, ",")
        if p.Length != 2
            return 0
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        return { x: Round(wx + p[1] * cw), y: Round(wy + p[2] * ch) }
    }
    screenSelfReady() {
        global quickcast
        return !this.moduleSelf() && quickcast.current() && this.portraitSpot()
    }
    screenSelfHeld(*) => this.selfcast && this.selfDown && this.selfActive() && this.screenSelfReady()
    ; send the ability's key, and when the screen shows the game waiting for a
    ; target (within 300 ms), click the portrait and put the cursor back
    screenSelfCast(game, q := "") {
        global quickcast, remap
        cal := quickcast.current(), p := this.portraitSpot()
        SendInput(q remap.keyText(game))
        if !cal || !p
            return false
        t := A_TickCount
        while A_TickCount - t < 300 {
            if quickcast.targeting(cal) {
                CoordMode("Mouse", "Screen")
                MouseGetPos(&mx, &my)
                SendInput(q "{Click " p.x " " p.y "}{Click " mx " " my " 0}")
                DebugLog("self-cast " game ": clicked the portrait (screen) " (A_TickCount - t) " ms after the key")
                return true
            }
        }
        DebugLog("self-cast " game ": the game didn't want a target within 300 ms (screen)")
        return false
    }
    ; the one-step setup: point at your portrait in a game and press Space
    portraitSetupStart() {
        global qcCalibrating
        if !WinExist(WarcraftIII)
            return Toast("Start Warcraft III first, in a game", "error")
        this.settingUp := true
        qcCalibrating := true, RefreshHotkeys()
        HotIfWinActive(WarcraftIII)
        Hotkey("$Space", (*) => this.portraitSetupEnd(true), "On")
        HotIfWinActive()
        WinActivate(WarcraftIII)
        Toast("Self-cast  ·  Point at your hero's portrait (bottom middle) and press Space  ·  Esc cancels", "", 0)
    }
    settingUp := false
    portraitSetupEnd(ok) {
        global qcCalibrating
        if !this.settingUp
            return
        HotIfWinActive(WarcraftIII)
        try Hotkey("$Space", "Off")
        HotIfWinActive()
        qcCalibrating := false, RefreshHotkeys()
        this.settingUp := false
        if !ok
            return Toast("Cancelled", "", 1500)
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        if mx < wx || my < wy || mx > wx + cw || my > wy + ch
            return Toast("That wasn't in the game window. Try again from the WC3 page.", "error")
        SetIni(Format("{:.4f},{:.4f}", (mx - wx) / cw, (my - wy) / ch), "SelfCast", "portrait_" WC3WindowKey())
        DebugLog("self-cast: portrait spot set for " WC3WindowKey())
        Toast("Portrait spot set for this window size", "", 2500)
    }

    bind() {
        global remap
        for b in this.bound {
            HotIf(b.cond)
            try Hotkey(b.hk, "Off")
        }
        this.bound := []
        HotIf(this.hotIfFn)
        for name, c in GameCommandsEngine.CMDS
            if this.switchOn(c[2]) && (k := this.key(name)) != ""
                this.add("$" k, this.run.Bind(this, c[1], name), this.hotIfFn)
        ; the held keys: kept from the game while they act
        if this.selfcast && (k := this.heldKey("selfcast")) != "" && !IsWheel(k) {
            this.add("$*" k, (*) => (this.selfDown := true, this.push()), this.scHotIfFn)
            this.add("$*" k " up", (*) => (this.selfDown := false, this.push()), this.scHotIfFn)
            ; from the screen: the card keys Remap doesn't take send their key and click the portrait
            for ck in this.cardKeys(k)
                this.add("$*" ck.key, ((g, *) => this.screenSelfCast(g)).Bind(remap.gameKey("card", ck.i)), this.ssHotIfFn)
        }
        if this.autocast && (ak := this.heldKey("autocast")) != "" && !IsWheel(ak) {
            this.add("$*" ak, (*) => 0, this.hotIfFn)
            ; each command card slot's key; Remap's own hotkeys hand theirs over too (Remap.toAutocast)
            for ck in this.cardKeys(ak)
                this.add("$*" ck.key, this.autocastSlot.Bind(this, ck.i), this.acHotIfFn)
        }
        HotIf()
        this.push()
    }
    ; each command card slot's key: yours, or the game's if no slot took it
    ; (not the held key itself) -> [{ i, key }]
    cardKeys(held) {
        global remap
        used := Map(), out := []
        loop 12
            if (y := remap.yourKey("card", A_Index)) != ""
                used[Norm(HotkeyBase(y))] := 1
        loop 12 {
            y := remap.yourKey("card", A_Index), g := remap.gameKey("card", A_Index)
            base := y != "" ? HotkeyBase(y) : used.Has(Norm(g)) ? "" : g
            if base != "" && !IsWheel(base) && Norm(base) != Norm(held)
                out.Push({ i: A_Index, key: base })
        }
        return out
    }
    add(hk, fn, cond) {
        HotIf(cond)
        try {
            Hotkey(hk, fn, "On")
            this.bound.Push({ hk: hk, cond: cond })
        }
    }
    ; ask for a new key (Esc = none)
    capture(name) {
        combo := RegExReplace(KeyWaitCombo(), "[<>]")
        SetIni(combo = "Escape" ? "" : combo, this.section, name)
        this.bind()
    }
    run(cmd, name, *) {
        r := this.gm.commandWait(this.gm.command(cmd), 1500)
        DebugLog("game command " name ": " (r = 1 ? "done" : r = 3 ? "the game thread didn't take it in time" : "refused (see twc-game.log)"))
    }
    ; command card slot i (1-12): autocast on / off
    autocastSlot(i, *) {
        r := this.gm.commandWait(this.gm.command(4, i - 1), 1500)
        DebugLog("autocast toggle, card slot " i ": " (r = 1 ? "done" : r = 3 ? "the game thread didn't take it in time" : "refused (an empty slot, or see twc-game.log)"))
    }
    ; the self-cast state to the module (on key changes, and once a second in
    ; case a key-up went missing)
    push() {
        if !(v := this.gm.live()) || NumGet(v, Shm.layout, "uint") < 8
            return
        k := this.heldKey("selfcast"), on := this.selfcast && this.gm.enabled && k != ""
        if this.selfDown && (!on || !GetKeyState(k, "P"))
            this.selfDown := false
        NumPut("uint", !on ? 0 : this.selfDown && this.active() ? 2 : 1, v, Shm.scHeld)
    }
    keyText(name) => (k := this.key(name)) != "" ? ReadableHotkey(k) : "no key"
    heldText(name) => (k := this.heldKey(name)) != "" ? ReadableHotkey(k) : "no key"

    statusText() {
        if !this.enabled
            return "Off"
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        keys := []
        for k in [["clearMessages", "messages"], ["clearChat", "chat"], ["multiboard", "multiboard"]]
            if this.key(k[1]) != ""
                keys.Push(k[2] " " this.keyText(k[1]))
        return "On · " (keys.Length ? "keys: " Join(", ", keys*) : "set a key for each") this.readyText(this.key("multiboard") != "" ? 7 : 4)
    }
    selfStatusText() {
        global quickcast
        if this.selfcast && this.key("selfcast") != "" && !this.moduleSelf() && (WinExist(WarcraftIII) || !this.gm.enabled)
            return "On · key: " this.heldText("selfcast") " · from the screen: "
                . (!WinExist(WarcraftIII) ? "start Warcraft III to check its setup"
                : !quickcast.current() ? "needs the quickcast setup for this window"
                : !this.portraitSpot() ? "set the portrait spot (Portrait)" : "ready")
        t := this.oneKeyStatus(this.selfcast, "selfcast", this.heldText("selfcast"), 8)
        if this.selfcast && this.gm.enabled && (v := this.gm.live()) && NumGet(v, Shm.layout, "uint") >= 8 {
            st := NumGet(v, Shm.scState, "uint"), n := NumGet(v, Shm.scCount, "uint")
            t .= st = 3 ? " · refused by the module's checks (see the log)" : n ? " · " n " self-cast" (n = 1 ? "" : "s") " this game" : ""
        }
        return t
    }
    acStatusText() => this.oneKeyStatus(this.autocast, "autocast", this.heldText("autocast"), 8)
    oneKeyStatus(on, name, keyText, layout) {
        if !on
            return "Off"
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        return "On · " (this.key(name) != "" ? "key: " keyText : "set a key") this.readyText(layout)
    }
    ; "" when the module in the running game takes commands of this layout (or no game runs)
    readyText(layout) {
        s := this.gm.state()
        return !WinExist(WarcraftIII) || s.live && s.probe = 1 && s.layout >= layout ? ""
            : s.loaded && s.layout < layout ? " · restart the game (older module)" : " · module not ready"
    }
}
