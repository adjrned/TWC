#Requires AutoHotkey v2.0
; ============================================================================
;  GameModuleEngine - the in-game module for Warcraft III 1.28f (native\).
;  Off by default (Settings > Game module). When on, every few seconds: if a
;  1.28 game window is open and the module isn't in it yet, native\twc-inject
;  loads native\twc-game.dll into it. The DLL does nothing unless the game is
;  exactly 1.28f, and reports back through shared memory "Local\TWC_Game_<pid>"
;  (layout: Shared in native\twc-game.cpp), read here.
;  Reforged and other patches are left alone.
; ============================================================================
class GameModuleEngine {
    section := "Game"
    tried := Map()              ; game pid -> true once loading was tried (once per game)
    views := Map()              ; game pid -> { map, view } of its shared memory

    enabled => Integer(Ini(this.section, "module", 0))
    dir => A_ScriptDir "\native"

    setEnabled(on) {
        SetIni(on ? 1 : 0, this.section, "module")
        if on
            this.check()
    }

    ; 1.28 game running and not loaded yet -> load it (the timer calls this)
    check() {
        if !this.enabled || !(hwnd := WinExist(WarcraftIII)) || !InStr(WC3WindowKey(), "classic")
            return
        pid := WinGetPID(hwnd)
        if this.tried.Has(pid) || this.view(pid)
            return
        this.tried[pid] := true
        dll := this.dir "\twc-game.dll", exe := this.dir "\twc-inject.exe"
        if !FileExist(dll) || !FileExist(exe)
            return DebugLog("game module: native\ files missing")
        try code := RunWait('"' exe '" ' pid ' "' dll '"', this.dir, "Hide")
        catch as e
            return DebugLog("game module: couldn't start twc-inject: " e.Message)
        DebugLog("game module: " (code = 0 ? "loaded into" : code = 2 ? "already in" : "couldn't load into") " the game (pid " pid ", code " code ")")
    }

    ; the module's shared memory for a game, mapped once (0 = not loaded)
    view(pid) {
        if this.views.Has(pid)
            return this.views[pid].view
        h := DllCall("OpenFileMapping", "uint", 0x4, "int", 0, "str", "Local\TWC_Game_" pid, "ptr")   ; FILE_MAP_READ
        if !h
            return 0
        v := DllCall("MapViewOfFile", "ptr", h, "uint", 0x4, "uint", 0, "uint", 0, "uptr", 24, "ptr")
        if !v {
            DllCall("CloseHandle", "ptr", h)
            return 0
        }
        this.views[pid] := { map: h, view: v }
        return v
    }

    ; -> { loaded, build, status, live, targeting } for the running 1.28 game
    state() {
        out := { loaded: 0, build: 0, status: -1, live: 0, targeting: 0 }
        if !(hwnd := WinExist(WarcraftIII)) || !(v := this.view(WinGetPID(hwnd)))
            return out
        if NumGet(v, 0, "uint") != 0x54574331           ; 'TWC1'
            return out
        out.loaded := 1
        out.build := NumGet(v, 8, "uint"), out.status := NumGet(v, 12, "uint")
        out.live := out.status = 1 && A_TickCount - NumGet(v, 16, "uint") < 1000
        out.targeting := NumGet(v, 20, "uint")
        return out
    }

    ; one line for Settings
    statusText() {
        if !this.enabled
            return "Off"
        s := this.state()
        if !WinExist(WarcraftIII)
            return "On · waiting for Warcraft III 1.28"
        if !InStr(WC3WindowKey(), "classic")
            return "On · this game isn't 1.28 (Reforged is left alone)"
        return !s.loaded ? "On · not loaded yet"
            : s.status = 2 ? "On · loaded, but the game isn't 1.28f (build " s.build "): idle"
            : s.live ? "On · running in the game (1.28f)" : "On · loaded, not responding"
    }
}
