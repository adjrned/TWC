#Requires AutoHotkey v2.0
; ============================================================================
;  GameCommandsEngine - hotkeys that ask the 1.28f game module to do something
;  on the game's own thread: clear the trigger messages, clear the chat (as
;  WFE's Clear Messages / Clear Chat), minimise / maximise the multiboard (its
;  Toggle Multiboard State). Off by default (ini [Game] clear, multiboard);
;  the keys are in [GameKeys] and are bound only while their switch is on.
;  They only act in Warcraft III with the module ready and chat closed;
;  otherwise the key goes to the game as usual.
; ============================================================================
class GameCommandsEngine {
    section := "GameKeys"
    ; ini key -> [command, the [Game] switch it belongs to]
    static CMDS := Map("clearMessages", [1, "clear"], "clearChat", [2, "clear"], "multiboard", [3, "multiboard"])
    bound := Map()                  ; ini key -> hotkey bound now

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
    multiboard => this.switchOn("multiboard")
    setMultiboard(on) => this.setSwitch("multiboard", on)
    key(name) => Ini(this.section, name, "")

    ; the keys act only when this is true (else they reach the game)
    active(*) {
        global toolEnabled, chatting
        return toolEnabled && !chatting && WinActive(WarcraftIII) && this.gm.cmdReady()
    }
    bind() {
        HotIf(this.hotIfFn)
        for name, hk in this.bound
            try Hotkey(hk, "Off")
        this.bound := Map()
        for name, c in GameCommandsEngine.CMDS
            if this.switchOn(c[2]) && (k := this.key(name)) != ""
                try Hotkey("$" k, this.run.Bind(this, c[1], name), "On"), this.bound[name] := "$" k
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
        return "On · " (keys.Length ? "keys: " Join(", ", keys*) : "set a key for each") this.readyText(4)
    }
    mbStatusText() {
        if !this.multiboard
            return "Off"
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        return "On · " (this.key("multiboard") != "" ? "key: " this.keyText("multiboard") : "set a key") this.readyText(7)
    }
    ; "" when the module in the running game takes commands of this layout (or no game runs)
    readyText(layout) {
        s := this.gm.state()
        return !WinExist(WarcraftIII) || s.live && s.probe = 1 && s.layout >= layout ? ""
            : s.loaded && s.layout < layout ? " · restart the game (older module)" : " · module not ready"
    }
}
