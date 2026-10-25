#Requires AutoHotkey v2.0
; ============================================================================
;  GameCommandsEngine - hotkeys that ask the 1.28f game module to do something
;  on the game's own thread: clear the trigger messages, clear the chat (as
;  WFE's Clear Messages / Clear Chat), minimise / maximise the multiboard (its
;  Toggle Multiboard State). Off by default (ini [Game] clear, multiboard);
;  the keys are in [GameKeys] and are bound only while their switch is on.
;  They only act in Warcraft III with the module ready and chat closed;
;  otherwise the key goes to the game as usual.
;  Two keys are held instead (WFE's Self Cast and AutoCast toggle keys; ini
;  [Game] selfcast, autocast; [GameKeys] selfcast, autocast), and kept from
;  the game while they act:
;    self-cast  held while you cast: the module clicks your portrait as the
;               game waits for a target, so it goes on your selected unit
;               (the module is told the key is held through shared memory)
;    autocast   held while you press a command card key: that button gets a
;               right click (autocast on / off) instead of the key
; ============================================================================
class GameCommandsEngine {
    section := "GameKeys"
    ; ini key -> [command, the [Game] switch it belongs to]
    static CMDS := Map("clearMessages", [1, "clear"], "clearChat", [2, "clear"], "multiboard", [3, "multiboard"])
    bound := []                     ; { hk, cond } bound now
    selfDown := false               ; the self-cast key is held (its own hotkeys say)

    __New(gameModule) {
        this.gm := gameModule
        this.hotIfFn := ObjBindMethod(this, "active")
        this.acHotIfFn := ObjBindMethod(this, "autocastHeld")
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
    multiboard => this.switchOn("multiboard")
    setMultiboard(on) => this.setSwitch("multiboard", on)
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
    selfCastHeld() => this.selfcast && this.selfDown && this.active() && this.gm.state().layout >= 8

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
            this.add("$*" k, (*) => (this.selfDown := true, this.push()), this.hotIfFn)
            this.add("$*" k " up", (*) => (this.selfDown := false, this.push()), this.hotIfFn)
        }
        if this.autocast && (ak := this.heldKey("autocast")) != "" && !IsWheel(ak) {
            this.add("$*" ak, (*) => 0, this.hotIfFn)
            ; each command card slot's key (yours, or the game's if no slot took it);
            ; Remap's own hotkeys hand theirs over too (Remap.toAutocast)
            HotIf(this.acHotIfFn)
            used := Map()
            loop 12
                if (y := remap.yourKey("card", A_Index)) != ""
                    used[Norm(HotkeyBase(y))] := 1
            loop 12 {
                y := remap.yourKey("card", A_Index), g := remap.gameKey("card", A_Index)
                base := y != "" ? HotkeyBase(y) : used.Has(Norm(g)) ? "" : g
                if base != "" && !IsWheel(base) && Norm(base) != Norm(ak)
                    this.add("$*" base, this.autocastSlot.Bind(this, A_Index), this.acHotIfFn)
            }
        }
        HotIf()
        this.push()
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
        if !(v := this.gm.live()) || NumGet(v, 4, "uint") < 8
            return
        k := this.heldKey("selfcast"), on := this.selfcast && this.gm.enabled && k != ""
        if this.selfDown && (!on || !GetKeyState(k, "P"))
            this.selfDown := false
        NumPut("uint", !on ? 0 : this.selfDown && this.active() ? 2 : 1, v, 636)
    }
    keyText(name) => (k := this.key(name)) != "" ? ReadableHotkey(k) : "no key"
    heldText(name) => (k := this.heldKey(name)) != "" ? ReadableHotkey(k) : "no key"

    statusText() {
        if !this.enabled
            return "Off"
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        keys := []
        for name in ["clearMessages", "clearChat"]
            if this.key(name) != ""
                keys.Push(name = "clearMessages" ? "messages " this.keyText(name) : "chat " this.keyText(name))
        return "On · " (keys.Length ? "keys: " Join(", ", keys*) : "set a key for each") this.readyText(4)
    }
    mbStatusText() => this.oneKeyStatus(this.multiboard, "multiboard", this.keyText("multiboard"), 7)
    selfStatusText() {
        t := this.oneKeyStatus(this.selfcast, "selfcast", this.heldText("selfcast"), 8)
        if this.selfcast && this.gm.enabled && (v := this.gm.live()) && NumGet(v, 4, "uint") >= 8 {
            st := NumGet(v, 640, "uint"), n := NumGet(v, 644, "uint")
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
