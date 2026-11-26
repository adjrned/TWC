#Requires AutoHotkey v2.0
; ============================================================================
;  LobbyCover - straight into the lobby: while the game module logs in and
;  joins (Battle.net login, layout 51), a black cover over the game's window
;  says what it's doing ("Logging in as ...", "Joining 'TWRPG' ...", "'TWRPG'
;  isn't there yet: trying again"), so the menus going by are never seen; it
;  goes the moment the lobby is up or a step stops (left to you). Only over a
;  game in a window (windowed or windowed full screen: a window over a full
;  screen game would knock it out of full screen) and while it's the window in
;  front; it never takes the focus or a click (the module's keys and clicks go
;  to the game as before). Hold Shift to see the menus under it. A step that
;  doesn't move for 45 s takes it off too. ini [Battle.net] cover (default 1).
; ============================================================================
class LobbyCover {
    static STUCK := 45000
    gui := 0
    text := 0
    shown := false
    at := ""                        ; the place it's shown at (x y w h)
    stepKey := "", stepSince := 0   ; the module's step and since when (the 45 s)

    __New(gameModule, login) {
        this.gm := gameModule, this.login := login
        this.tickFn := ObjBindMethod(this, "tick")
        SetTimer(this.tickFn, 150)
    }
    enabled => Integer(Ini("Battle.net", "cover", 1))
    setEnabled(on) => (SetIni(on ? 1 : 0, "Battle.net", "cover"), this.tick())

    ; -> the cover's line for the module's state, "" = no cover
    line(v) {
        b := this.login
        if !b.enabled || !this.enabled || NumGet(v, Shm.layout, "uint") < 51
            return ""
        if NumGet(v, Shm.blWindowed, "uint") != 1 || NumGet(v, Shm.blScreen, "uint") = 0xFFFFFFFF
            return ""                               ; full screen (or not known yet), or no menus (in a game)
        st := NumGet(v, Shm.blState, "uint"), game := StrGet(v + Shm.blGame, 32, "UTF-8")
        joining := b.customGames && game != ""
        key := st "|" NumGet(v, Shm.blTries, "uint")
        if key != this.stepKey
            this.stepKey := key, this.stepSince := A_TickCount
        if st != 9 && A_TickCount - this.stepSince > LobbyCover.STUCK
            return ""                               ; nothing moving: let the menus be seen
        switch st {
            case 0: return "Starting…"
            case 1: return "Connecting to Battle.net…"
            case 2: return "Logging in" (b.account != "" ? " as " b.account : "") "…"
            case 3: return joining ? "Logged in · joining '" game "'…" : ""
            case 7: return "Joining '" game "'…"
            case 9:
                why := StrGet(v + Shm.blWhy, 96, "UTF-8")
                return "'" game "' isn't there yet · trying again (try " NumGet(v, Shm.blTries, "uint") + 1 ")" (why != "" ? "`n" why : "") "`nHold Shift to stop"
        }
        return ""
    }
    tick() {
        if !(v := this.gm.live()) || (s := this.line(v)) = "" || !WinActive(WarcraftIII) || GetKeyState("Shift", "P")
            return this.hide()
        try WinGetClientPos(&wx, &wy, &ww, &wh, WarcraftIII)
        catch
            return this.hide()
        if ww < 200 || wh < 150
            return this.hide()
        this.show(s, wx, wy, ww, wh)
    }
    build() {
        global C
        g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000020", "TW Companion - joining")   ; no focus, clicks go through
        g.MarginX := 0, g.MarginY := 0, g.BackColor := "000000"
        this.text := g.AddText("x0 y0 w400 h120 Center +Background000000 c" C.text, "")
        UISetFont(this.text, "s14 w600")
        this.gui := g
    }
    show(s, wx, wy, ww, wh) {
        if !this.gui
            this.build()
        if this.text.Value != s
            this.text.Value := s
        place := wx " " wy " " ww " " wh
        if place != this.at || !this.shown {
            this.at := place
            this.text.Move(0, wh // 2 - 60, ww, 120)
            this.gui.Show("x" wx " y" wy " w" ww " h" wh " NoActivate")
            if !this.shown
                DebugLog("into the lobby: the cover is up (" s ")")
            this.shown := true
        }
    }
    hide() {
        if this.shown && this.gui
            this.gui.Hide(), DebugLog("into the lobby: the cover is off")
        this.shown := false
    }
}
