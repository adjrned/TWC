#Requires AutoHotkey v2.0
; ============================================================================
;  GameCommandsEngine - hotkeys that ask the 1.28f game module to do something
;  on the game's own thread: clear the trigger messages, clear the chat (as
;  WFE's Clear Messages / Clear Chat), minimise / maximise the multiboard (its
;  Toggle Multiboard State). One switch for the three, off by default (ini
;  [Game] clear); the keys are in [GameKeys] and are bound only while it's on.
;  They only act in Warcraft III with the module ready and chat closed;
;  otherwise the key goes to the game as usual.
;  (WFE's Self Cast and AutoCast toggle keys were here until 2026-10-26: the
;  user didn't need them. The game module still has both (shared memory
;  scHeld / command 4), unused; the companion side is in git: 216507f,
;  09365b5.)
; ============================================================================
class GameCommandsEngine {
    section := "GameKeys"
    ; ini key -> [command, the [Game] switch it belongs to]
    static CMDS := Map("clearMessages", [1, "clear"], "clearChat", [2, "clear"], "multiboard", [3, "clear"])
    bound := []                     ; { hk, cond } bound now

    __New(gameModule) {
        this.gm := gameModule
        this.hotIfFn := ObjBindMethod(this, "active")
        this.bind()
    }
    switchOn(flag) => Integer(Ini("Game", flag, 0))
    setSwitch(flag, on) {
        SetIni(on ? 1 : 0, "Game", flag)
        this.bind()
    }
    enabled => this.switchOn("clear")
    setEnabled(on) => this.setSwitch("clear", on)
    key(name) => Ini(this.section, name, "")

    ; the keys act only when this is true (else they reach the game)
    active(*) {
        global toolEnabled, chatting
        return toolEnabled && !chatting && WinActive(WarcraftIII) && this.gm.cmdReady()
    }
    bind() {
        for b in this.bound {
            HotIf(b.cond)
            try Hotkey(b.hk, "Off")
        }
        this.bound := []
        HotIf(this.hotIfFn)
        for name, c in GameCommandsEngine.CMDS
            if this.switchOn(c[2]) && (k := this.key(name)) != ""
                this.add("$" k, this.run.Bind(this, c[1], name), this.hotIfFn)
        HotIf()
    }
    add(hk, fn, cond) {
        HotIf(cond)
        try {
            Hotkey(hk, fn, "On")
            this.bound.Push({ hk: hk, cond: cond })
        }
    }
    ; ask for a new key (Esc = none); false: cancelled, the key stays as it was
    capture(name) {
        combo := RegExReplace(KeyWaitCombo(), "[<>]")
        if combo = ""
            return false
        SetIni(combo = "Escape" ? "" : combo, this.section, name)
        this.bind()
        return true
    }
    run(cmd, name, *) {
        r := this.gm.commandWait(this.gm.command(cmd), 1500)
        DebugLog("game command " name ": " (r = 1 ? "done" : r = 3 ? "the game thread didn't take it in time" : "refused (see twc-game.log)"))
    }
    keyText(name) => (k := this.key(name)) != "" ? ReadableHotkey(k) : "no key"

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
    ; "" when the module in the running game takes commands of this layout (or no game runs)
    readyText(layout) {
        s := this.gm.state()
        return !WinExist(WarcraftIII) || s.live && s.probe = 1 && s.layout >= layout ? ""
            : s.loaded && s.layout < layout ? " · restart the game (older module)" : " · module not ready"
    }
}
