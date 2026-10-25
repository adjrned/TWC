#Requires AutoHotkey v2.0
; ============================================================================
;  GameModuleEngine - the in-game module for Warcraft III 1.28f (native\).
;  Off by default (Settings > Game module). When on, every few seconds: if a
;  1.28 game window is open and the module isn't in it yet, native\twc-inject
;  loads native\twc-game.dll into it. The DLL does nothing unless the game is
;  exactly 1.28f, and reports back through shared memory "Local\TWC_Game_<pid>"
;  (layout: Shared in native\twc-game.cpp), read here. Its quickcast (off by
;  default, Quickcast window) clicks when the game itself says it waits for
;  a target; until it's on and the module's check passed, the screen is read.
;  Reforged and other patches are left alone.
; ============================================================================
class GameModuleEngine {
    section := "Game"
    tried := Map()              ; game pid -> true once loading was tried (once per game)
    views := Map()              ; game pid -> { map, view } of its shared memory
    wakes := Map()              ; game pid -> its quickcast event (0 if it has none)

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

    ; the module's shared memory for a game, mapped once (0 = not loaded).
    ; Read and write: quickcast requests go the other way.
    view(pid) {
        if this.views.Has(pid)
            return this.views[pid].view
        h := DllCall("OpenFileMapping", "uint", 0x6, "int", 0, "str", "Local\TWC_Game_" pid, "ptr")   ; FILE_MAP_READ | WRITE
        if !h
            return 0
        v := DllCall("MapViewOfFile", "ptr", h, "uint", 0x6, "uint", 0, "uint", 0, "uptr", 0, "ptr")   ; all of it (layout 1 was smaller)
        if !v {
            DllCall("CloseHandle", "ptr", h)
            return 0
        }
        this.views[pid] := { map: h, view: v }
        return v
    }
    ; the running game's view, if the module in it is ours (0 if not)
    live() {
        if !(hwnd := WinExist(WarcraftIII)) || !(v := this.view(WinGetPID(hwnd)))
            return 0
        return NumGet(v, 0, "uint") = 0x54574331 ? v : 0          ; 'TWC1'
    }

    ; -> { loaded, layout, build, status, live, targeting, probe, ui, probeText } for the running 1.28 game
    ; probe: 0 not run, 1 passed, 2 failed (probeText says why); ui: 1 once the game UI checked out
    state() {
        out := { loaded: 0, layout: 0, build: 0, status: -1, live: 0, targeting: 0, probe: 0, ui: 0, probeText: "" }
        if !(v := this.live())
            return out
        out.loaded := 1, out.layout := NumGet(v, 4, "uint")
        out.build := NumGet(v, 8, "uint"), out.status := NumGet(v, 12, "uint")
        out.live := out.status = 1 && A_TickCount - NumGet(v, 16, "uint") < 1000
        out.targeting := NumGet(v, 20, "uint")
        if out.layout >= 2
            out.probe := NumGet(v, 24, "uint"), out.ui := NumGet(v, 28, "uint"), out.probeText := StrGet(v + 56, 112, "CP0")
        return out
    }

    ; -- quickcast in the game ---------------------------------------------------
    ; Off by default (ini [Game] quickcast); the screen quickcast is used otherwise.
    ; The companion sends the ability's key, then asks the module for a click:
    ; it clicks at the cursor the moment the game waits for a target, or gives
    ; up at the deadline. Requests are numbered; the module answers the latest.
    quickcast => Integer(Ini(this.section, "quickcast", 0))
    setQuickcast(on) => SetIni(on ? 1 : 0, this.section, "quickcast")
    ; on, loaded in this game, alive, and its probe passed
    qcReady() {
        if !this.enabled || !this.quickcast
            return false
        s := this.state()
        return s.live && s.layout >= 2 && s.probe = 1
    }
    ; ask for a click within ms (keepShift: a queued order) -> the request's number (0 = no module)
    qcAsk(ms, keepShift) {
        if !(v := this.live())
            return 0
        seq := NumGet(v, 32, "int") + 1
        NumPut("uint", A_TickCount + ms, v, 36), NumPut("uint", keepShift ? 1 : 0, v, 40)
        NumPut("int", seq, v, 32)                                  ; last: the module acts on it
        pid := WinGetPID(WarcraftIII)
        if !this.wakes.Has(pid)
            this.wakes[pid] := DllCall("OpenEvent", "uint", 0x2, "int", 0, "str", "Local\TWC_GameQc_" pid, "ptr")  ; EVENT_MODIFY_STATE
        if this.wakes[pid]
            DllCall("SetEvent", "ptr", this.wakes[pid])            ; wakes the module now, not on its next look
        return seq
    }
    ; 0 = still open, 1 = clicked, 2 = the game didn't want a target in time,
    ; 3 = it did, but the game wasn't in front (a newer request answers older ones with 2)
    qcResult(seq) {
        if !seq || !(v := this.live())
            return 2
        done := NumGet(v, 44, "int")
        return done = seq ? NumGet(v, 48, "uint") : done > seq ? 2 : 0
    }
    qcMs() => (v := this.live()) ? NumGet(v, 52, "uint") : 0
    ; wait for the answer (at most ms more than the request's own deadline)
    qcWait(seq, ms) {
        endAt := A_TickCount + ms + 250
        while !(r := this.qcResult(seq)) && A_TickCount < endAt
            Sleep(5)
        return r ? r : 2
    }
    qcCancel(seq) {
        if seq && (v := this.live()) && NumGet(v, 32, "int") = seq
            NumPut("uint", 0, v, 36)
    }
    ; one line for the Quickcast window
    qcStatusText() {
        if !this.enabled
            return "Needs Settings > Game module for 1.28"
        if !this.quickcast
            return "Off: the screen quickcast is used"
        s := this.state()
        return !WinExist(WarcraftIII) || !s.loaded ? "On · starts with a 1.28f game"
            : s.layout < 2 ? "On · the game has an older module loaded: restart the game"
            : s.probe = 2 ? "On · the module's check failed, so the screen quickcast is used"
            : s.live && s.probe = 1 ? "On · the game says when it waits for a target" (s.ui ? "" : " (seen in a game: not yet)")
            : "On · the module isn't running, so the screen quickcast is used"
    }

    ; -- cooldown and buff timers (layout 3) ------------------------------------
    ; The module reads them only while asked (tmWant), 10 times a second.
    ; Offsets: Shared in native\twc-game.cpp.
    timersWanted(on) {
        if (v := this.live()) && NumGet(v, 4, "uint") >= 3
            NumPut("uint", on ? 1 : 0, v, 168)
    }
    ; -> { seq, flags, cd: [{ left, total }] x12 (command card, row by row),
    ;      buffs: [{ left, total, aura, id }] (buff bar, left to right; 0 = empty) }
    ;    or 0 without a module that has them. flags: 1 cooldowns read, 2 buffs
    ;    read, 0x100 a game getter was refused (its times stay 0; see twc-game.log)
    timers() {
        if !(v := this.live()) || NumGet(v, 4, "uint") < 3
            return 0
        out := { seq: NumGet(v, 172, "int"), flags: NumGet(v, 176, "uint"), cd: [], buffs: [] }
        loop 12
            out.cd.Push({ left: NumGet(v, 180 + 4 * (A_Index - 1), "float"), total: NumGet(v, 228 + 4 * (A_Index - 1), "float") })
        n := Min(16, NumGet(v, 276, "uint"))
        loop n {
            o := 4 * (A_Index - 1), f := NumGet(v, 408 + o, "uint")
            out.buffs.Push(f & 1 ? { left: NumGet(v, 280 + o, "float"), total: NumGet(v, 344 + o, "float"), aura: f & 2 ? 1 : 0, id: NumGet(v, 472 + o, "uint") } : 0)
        }
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
            : !s.live ? "On · loaded, not responding"
            : s.probe = 1 ? "On · running in the game (1.28f), check passed"
            : s.probe = 2 ? "On · check failed: " s.probeText
            : "On · running in the game (1.28f)"
    }
}
