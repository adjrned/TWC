#Requires AutoHotkey v2.0
; ============================================================================
;  GameCommandsEngine - hotkeys that ask the 1.28f game module to do something
;  on the game's own thread: clear the trigger messages, clear the chat (as
;  WFE's Clear Messages / Clear Chat). Off by default (ini [Game] clear); the
;  keys are in [GameKeys]. They only act in Warcraft III with the module
;  ready and chat closed; otherwise the key goes to the game as usual.
; ============================================================================
class GameCommandsEngine {
    section := "GameKeys"
    static CMDS := Map("clearMessages", 1, "clearChat", 2)
    bound := Map()                  ; ini key -> hotkey bound now

    __New(gameModule) {
        this.gm := gameModule
        this.hotIfFn := ObjBindMethod(this, "active")
        this.bind()
    }
    enabled => Integer(Ini("Game", "clear", 0))
    setEnabled(on) => SetIni(on ? 1 : 0, "Game", "clear")
    key(name) => Ini(this.section, name, "")

    ; the keys act only when this is true (else they reach the game)
    active(*) {
        global toolEnabled, chatting
        return this.enabled && toolEnabled && !chatting && WinActive(WarcraftIII) && this.gm.cmdReady()
    }
    bind() {
        HotIf(this.hotIfFn)
        for name, hk in this.bound
            try Hotkey(hk, "Off")
        this.bound := Map()
        for name, cmd in GameCommandsEngine.CMDS
            if (k := this.key(name)) != ""
                try Hotkey("$" k, this.run.Bind(this, cmd, name), "On"), this.bound[name] := "$" k
        HotIf()
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
    keyText(name) => (k := this.key(name)) != "" ? ReadableHotkey(k) : "no key"

    statusText() {
        if !this.enabled
            return "Off"
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        keys := []
        for name in ["clearMessages", "clearChat"]
            if this.key(name) != ""
                keys.Push(name = "clearMessages" ? "messages " this.keyText(name) : "chat " this.keyText(name))
        s := this.gm.state()
        ready := s.live && s.probe = 1 && s.layout >= 4
        return "On · " (keys.Length ? "keys: " Join(", ", keys*) : "set a key for each")
            . (!WinExist(WarcraftIII) ? "" : ready ? "" : s.loaded && s.layout < 4 ? " · restart the game (older module)" : " · module not ready")
    }
}
