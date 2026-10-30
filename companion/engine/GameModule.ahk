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
;  The game loads a copy, native\twc-game.<stamp>.dll (stamp: the build's PE
;  time stamp), so an update can replace twc-game.dll while the game runs. A
;  module from layout 13 on is swapped live for a newer one: asked to unload
;  (it turns everything off and gives it all back), then the new copy goes in
;  and the switches are pushed to it as usual; nothing is pushed meanwhile.
;  An older module needs the game restarted.
; ============================================================================
class GameModuleEngine {
    section := "Game"
    tried := Map()              ; game pid -> { n, at, done, fresh }: loading tried n times (a failed one again after 10 s; after 3, once a minute)
    views := Map()              ; game pid -> { map, view } of its shared memory
    wakes := Map()              ; game pid -> its quickcast event (0 if it has none)
    swapping := 0               ; the game pid whose module is being replaced (0 = none)
    swapAt := 0

    enabled => Integer(Ini(this.section, "module", 1))      ; on by default since 2026-10-26: its quickcast is 1.28f's
    dir => A_ScriptDir "\native"

    setEnabled(on) {
        SetIni(on ? 1 : 0, this.section, "module")
        if on
            this.check()
    }

    ; a dll's build stamp: its PE header's TimeDateStamp (0 if it can't be read)
    static FileStamp(path) {
        try {
            f := FileOpen(path, "r")
            f.Pos := 0x3C, pe := f.ReadUInt(), f.Pos := pe + 8, t := f.ReadUInt()
            f.Close()
            return t
        }
        return 0
    }
    ; the copy of twc-game.dll the game loads (made if missing; other copies not in use go).
    ; fresh n: a copy under another name (twc-game.<stamp>-n.dll), for a game that holds a
    ; retired module of this very build: the game would hand that one back for the same name
    loadCopy(fresh := 0) {
        dll := this.dir "\twc-game.dll"
        if !(st := GameModuleEngine.FileStamp(dll))
            return ""
        copy := this.dir "\twc-game." Format("{:08x}", st) (fresh ? "-" fresh : "") ".dll"
        loop files this.dir "\twc-game.*.dll"
            if A_LoopFileFullPath != copy
                try FileDelete(A_LoopFileFullPath)              ; a game that has it loaded keeps it
        if !FileExist(copy)
            try FileCopy(dll, copy)
            catch
                return ""
        return copy
    }

    ; 1.28 game running and not loaded yet -> load it; a module that's older
    ; than native\twc-game.dll (layout 13 on) -> swap it (the timer calls this)
    check() {
        if !this.enabled || !(hwnd := WinExist(WarcraftIII)) || !InStr(WC3WindowKey(), "classic")
            return
        pid := WinGetPID(hwnd)
        if this.swapping
            return this.swapStep(this.swapping)
        if (v := this.view(pid)) {
            if this.dropUnloaded(pid, v)
                return                          ; loaded again on the next round
            try remap.pushKeys()                ; the quickcast keys (a new module starts without them)
            if NumGet(v, Shm.magic, "uint") = 0x54574331 && NumGet(v, Shm.layout, "uint") >= 13 && NumGet(v, Shm.status, "uint") = 1
                && !NumGet(v, Shm.unload, "uint") && (st := GameModuleEngine.FileStamp(this.dir "\twc-game.dll")) && NumGet(v, Shm.stamp, "uint") != st {
                this.swapping := pid, this.swapAt := A_TickCount
                NumPut("uint", 1, v, Shm.unload)
                DebugLog("game module: a newer one is here: asking the game's to unload (pid " pid ")")
            }
            return
        }
        ; once per game, but a load that failed (files being updated, the injector) is tried again:
        ; before, one failure left the game without its module (and 1.28f without quickcast) until a restart.
        ; After 3 failures in a row, once a minute (it stopped for good: quickcast went screen-only until
        ; the companion was restarted)
        t := this.tried.Get(pid, 0)
        if t && (t.done || A_TickCount - t.at < (t.n >= 3 ? 60000 : 10000))
            return
        if !t
            this.tried[pid] := t := { n: 0, at: 0, done: false, fresh: 0 }
        t.n++, t.at := A_TickCount
        try exeName := WinGetProcessName(hwnd)
        catch
            exeName := ""
        if exeName != "Warcraft III.exe" && exeName != "war3.exe"
            return (t.done := true, DebugLog("game module: the window is " exeName "'s, not the game's: not loading"))   ; e.g. the crash reporter
        this.injectOnce(pid, t)
    }
    ; one try at loading the module into the game (t: its tried entry)
    injectOnce(pid, t) {
        exe := this.dir "\twc-inject.exe"
        if !(dll := this.loadCopy(t.fresh)) || !FileExist(exe)
            return DebugLog("game module: native\ files missing (try " t.n ")")
        try code := this.runInjector(exe, pid, dll)
        catch as e
            return DebugLog("game module: couldn't start twc-inject: " e.Message " (try " t.n ")")
        if code = 2 && !this.view(pid) {
            ; "already in", but no module answers: a retired one of this build (a live swap back to
            ; it) holds that file name, and the game would hand it back. A copy under another name loads
            t.fresh++, t.at := 0, t.n -= t.fresh <= 2
            return DebugLog("game module: a retired module of this build is in the game: loading a fresh copy (pid " pid ")")
        }
        t.done := code = 0 || code = 2
        DebugLog("game module: " (code = 0 ? "loaded into" : code = 2 ? "already in" : "couldn't load into") " the game (pid " pid ", code " code
            . (t.done ? "" : t.n < 3 ? ", try " t.n " of 3" : ", try " t.n ": again in a minute") ")")
    }
    runInjector(exe, pid, dll) => RunWait('"' exe '" ' pid ' "' dll '"', this.dir, "Hide")

    ; while swapping: the old module unloaded (status 3) -> load the new one; it stays (5) or takes too long -> give up
    swapStep(pid) {
        v := this.views.Has(pid) ? this.views[pid].view : 0
        st := v ? NumGet(v, Shm.status, "uint") : 3
        if st = 3 {
            this.drop(pid), this.swapping := 0
            if this.tried.Has(pid)
                this.tried.Delete(pid)
            DebugLog("game module: the old one unloaded: loading the new one")
            return this.check()
        }
        ; unload 2: it can't go and carries on (status 1 again since 2026-10-27: quickcast keeps working)
        if st = 5 || (v && NumGet(v, Shm.unload, "uint") = 2) || A_TickCount - this.swapAt > 20000 || !WinExist("ahk_pid " pid) {
            this.swapping := 0
            DebugLog("game module: the old one stays (status " st "): restart the game for the new one")
        }
    }
    ; An unloaded module's memory (status 3): let go of it, and load again.
    ; After a live swap the old module writes 3 a moment before it closes its
    ; name: a view opened in between is the old one's, and kept, it held the
    ; name, so the new module was never loaded (quickcast stopped working).
    dropUnloaded(pid, v) {
        if NumGet(v, Shm.magic, "uint") != 0x54574331 || NumGet(v, Shm.status, "uint") != 3
            return false
        this.drop(pid)
        if this.tried.Has(pid)
            this.tried.Delete(pid)
        DebugLog("game module: the game's module memory says unloaded: let go, loading again")
        return true
    }
    ; let go of a game's shared memory and event (the module's name is free again)
    drop(pid) {
        if this.views.Has(pid) {
            DllCall("UnmapViewOfFile", "ptr", this.views[pid].view)
            DllCall("CloseHandle", "ptr", this.views[pid].map)
            this.views.Delete(pid)
        }
        if this.wakes.Has(pid) {
            if this.wakes[pid]
                DllCall("CloseHandle", "ptr", this.wakes[pid])
            this.wakes.Delete(pid)
        }
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
        if this.swapping || !(hwnd := WinExist(WarcraftIII)) || !(v := this.view(WinGetPID(hwnd)))
            return 0
        return NumGet(v, Shm.magic, "uint") = 0x54574331 ? v : 0          ; 'TWC1'
    }

    ; -> { loaded, layout, build, status, live, targeting, probe, ui, probeText, beat, qc } for the running 1.28 game
    ; probe: 0 not run, 1 passed, 2 failed (probeText says why); ui: 1 once the game UI checked out; beat: ms
    ; since the module's last heartbeat; qc (layout 27, else 0): { state, asked, clicked, noTarget, notFront, cancelled }
    state() {
        out := { loaded: 0, layout: 0, build: 0, status: -1, live: 0, targeting: 0, probe: 0, ui: 0, probeText: "", beat: 0, qc: 0, qk: 0 }
        if !(v := this.live())
            return out
        out.loaded := 1, out.layout := NumGet(v, Shm.layout, "uint")
        out.build := NumGet(v, Shm.build, "uint"), out.status := NumGet(v, Shm.status, "uint")
        out.beat := (A_TickCount - NumGet(v, Shm.heartbeat, "uint")) & 0xFFFFFFFF      ; 32-bit ticks (the module's)
        out.live := out.status = 1 && out.beat < 1000
        out.targeting := NumGet(v, Shm.targeting, "uint")
        if out.layout >= 2
            out.probe := NumGet(v, Shm.probe, "uint"), out.ui := NumGet(v, Shm.ui, "uint"), out.probeText := StrGet(v + Shm.probeText, 112, "CP0")
        out.qk := out.layout >= 28 ? { state: NumGet(v, Shm.qkState, "uint"), on: NumGet(v, Shm.qkOn, "uint"),
            pressed: NumGet(v, Shm.qkPressed, "uint"), clicked: NumGet(v, Shm.qkClicked, "uint") } : 0
        if out.layout >= 27
            out.qc := { state: NumGet(v, Shm.qcState, "uint"), asked: NumGet(v, Shm.qcAsked, "uint"), clicked: NumGet(v, Shm.qcClicked, "uint"),
                noTarget: NumGet(v, Shm.qcNoTarget, "uint"), notFront: NumGet(v, Shm.qcNotFront, "uint"), cancelled: NumGet(v, Shm.qcCancelled, "uint") }
        return out
    }

    ; -- quickcast in the game ---------------------------------------------------
    ; On by default (ini [Game] quickcast): on 1.28f it's the only quickcast (the screen's is Reforged's).
    ; The companion sends the ability's key, then asks the module for a click:
    ; it clicks at the cursor the moment the game waits for a target, or gives
    ; up at the deadline. Requests are numbered; the module answers the latest.
    quickcast => Integer(Ini(this.section, "quickcast", 1))
    setQuickcast(on) => SetIni(on ? 1 : 0, this.section, "quickcast")
    ; on, loaded in this game, alive, and its probe passed
    qcReady() {
        if !this.enabled || !this.quickcast
            return false
        s := this.state()
        return s.live && s.layout >= 2 && s.probe = 1
    }
    ; -- quickcast keys as WFE does them (layout 28) ------------------------------
    ; The module presses a quickcast key's own button on the game thread as the
    ; key comes (KeyCast) and clicks at once if the game wants a target: the
    ; companion only sends the key. vks: the game key of each slot (12 card, row
    ; by row, then 6 inventory; 0 = not quickcast); on: 0 while chat is open etc.
    pushKeys(vks, on) {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 28
            return
        loop 20
            NumPut("uchar", A_Index <= vks.Length ? vks[A_Index] : 0, v, Shm.qkVk + A_Index - 1)
        NumPut("uint", on ? 1 : 0, v, Shm.qkOn)
    }
    ; the module is handling the keys (qcReady too: alive, checked)
    keyCastReady() => this.qcReady() && (v := this.live()) && NumGet(v, Shm.layout, "uint") >= 28 && NumGet(v, Shm.qkState, "uint") = 1
    ; why qcReady is false ("" when it's true), for the log and the Module check
    qcWhyNot() {
        if !this.enabled
            return "the game module is off"
        if !this.quickcast
            return "quickcast through the game is off"
        if this.swapping
            return "the module is being replaced (a newer one)"
        s := this.state()
        return !s.loaded ? "no module in this game (not loaded yet)"
            : s.layout < 2 ? "an older module (layout " s.layout ")"
            : s.status != 1 ? "the module's status is " s.status (s.status = 2 ? " (not 1.28f)" : s.status = 4 ? " (unloading)" : s.status = 3 ? " (unloaded)" : "")
            : !s.live ? "the module's heartbeat is " s.beat " ms old"
            : s.probe != 1 ? "the module's address check " (s.probe = 2 ? "failed: " s.probeText : "hasn't run yet")
            : ""
    }
    ; one line for quickcast's state in the game (layout 27): the module's view
    static QcStateText(st) => st = 1 ? "ready" : st = 0 ? "waiting: no game UI (not in a game)" : st = 2 ? "waiting: the game UI isn't there yet / any more (a game starting or ending)"
        : st = 3 ? "waiting: reading the game UI faulted" : st = 4 ? "off: the address check failed" : "state " st
    ; ask for a click within ms (keepShift: a queued order) -> the request's number (0 = no module)
    qcAsk(ms, keepShift) {
        if !(v := this.live())
            return 0
        seq := NumGet(v, Shm.qcSeq, "int") + 1
        NumPut("uint", A_TickCount + ms, v, Shm.qcUntil), NumPut("uint", keepShift ? 1 : 0, v, Shm.qcFlags)
        NumPut("int", seq, v, Shm.qcSeq)                                  ; last: the module acts on it
        this.wake()
        return seq
    }
    ; 0 = still open, 1 = clicked, 2 = the game didn't want a target in time,
    ; 3 = it did, but the game wasn't in front (a newer request answers older ones with 2)
    qcResult(seq) {
        if !seq || !(v := this.live())
            return 2
        done := NumGet(v, Shm.qcDone, "int")
        return done = seq ? NumGet(v, Shm.qcResult, "uint") : done > seq ? 2 : 0
    }
    qcMs() => (v := this.live()) ? NumGet(v, Shm.qcMs, "uint") : 0
    ; wait for the answer (at most ms more than the request's own deadline)
    qcWait(seq, ms) {
        endAt := A_TickCount + ms + 250
        while !(r := this.qcResult(seq)) && A_TickCount < endAt
            Sleep(5)
        return r ? r : 2
    }
    qcCancel(seq) {
        if seq && (v := this.live()) && NumGet(v, Shm.qcSeq, "int") = seq
            NumPut("uint", 0, v, Shm.qcUntil)
    }
    ; one line for the Quickcast window
    qcStatusText() {
        if !this.quickcast
            return "Off: quickcast keys send their key alone"
        if !this.enabled
            return "On · needs the game module (top of this page)"
        s := this.state()
        return !WinExist(WarcraftIII) || !s.loaded ? "On · starts with a 1.28f game"
            : s.layout < 2 ? "On · the game has an older module loaded: restart the game"
            : s.probe = 2 ? "On · the module's check failed: keys go alone (see the log)"
            : s.live && s.probe = 1 ? "On · the game says when it waits for a target" (s.ui ? "" : " (seen in a game: not yet)")
            : "On · the module isn't running: keys go alone"
    }

    ; -- cooldown and buff timers (layout 3) ------------------------------------
    ; The module reads them only while asked (tmWant), 10 times a second.
    ; Several features can ask (who: the timer display, the buff alerts); it
    ; reads while any of them wants them. Offsets: Shared in native\twc-game.cpp.
    tmWho := Map()
    timersWanted(on, who := "hud") {
        if on
            this.tmWho[who] := 1
        else if this.tmWho.Has(who)
            this.tmWho.Delete(who)
        if (v := this.live()) && NumGet(v, Shm.layout, "uint") >= 3
            NumPut("uint", this.tmWho.Count ? 1 : 0, v, Shm.tmWant)
    }
    ; -> { seq, flags, cd: [{ left, total }] x12 (command card, row by row),
    ;      buffs: [{ left, total, aura, id }] (buff bar, left to right; 0 = empty) }
    ;    or 0 without a module that has them. flags: 1 cooldowns read, 2 buffs
    ;    read, 0x100 a game getter was refused (its times stay 0; see twc-game.log)
    timers() {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 3
            return 0
        out := { seq: NumGet(v, Shm.tmSeq, "int"), flags: NumGet(v, Shm.tmFlags, "uint"), cd: [], buffs: [] }
        loop 12
            out.cd.Push({ left: NumGet(v, Shm.cdLeft + 4 * (A_Index - 1), "float"), total: NumGet(v, Shm.cdTotal + 4 * (A_Index - 1), "float") })
        n := Min(16, NumGet(v, Shm.buffCount, "uint"))
        loop n {
            o := 4 * (A_Index - 1), f := NumGet(v, Shm.buffFlags + o, "uint")
            out.buffs.Push(f & 1 ? { left: NumGet(v, Shm.buffLeft + o, "float"), total: NumGet(v, Shm.buffTotal + o, "float"), aura: f & 2 ? 1 : 0, keptUp: f & 4 ? 1 : 0, id: NumGet(v, Shm.buffId + o, "uint") } : 0)
        }
        return out
    }

    ; -- the damage meter's feed (layout 29) ----------------------------------------
    ; -> { state, seq, total: [16], hits: [16], names: [16], colours: [16], local } (totals since the module started; colours:
    ; the game's player colour, -1 none; local: your slot, -1 none; 0: an older module)
    damage() {
        if !(v := this.live()) || (lay := NumGet(v, Shm.layout, "uint")) < 29
            return 0
        out := { state: NumGet(v, Shm.dmState, "uint"), seq: NumGet(v, Shm.dmSeq, "int"), total: [], hits: [], names: [], colours: [],
            local: lay >= 31 ? NumGet(v, Shm.dmLocal, "int") : -1 }
        loop 16 {
            i := A_Index - 1
            out.total.Push(NumGet(v, Shm.dmTotal + 8 * i, "double")), out.hits.Push(NumGet(v, Shm.dmHits + 4 * i, "uint"))
            out.names.Push(StrGet(v + Shm.dmName + 32 * i, 31, "UTF-8"))
            out.colours.Push(lay >= 30 ? NumGet(v, Shm.dmColour + 4 * i, "int") : -1)
        }
        return out
    }
    ; the hits one by one (layout 33): those after `since` (the ring's count, -1 = only where it is now)
    ; -> { seq, lost, hits: [{ amount, src, tgt, target, from, to, attack, ranged, srcHero, tgtHero, dmgType, atkType, ability, how }] }
    ; (src / tgt: unit type rawcodes 'Hpal'; dmgType 255 none; layout 34: ability a spell hit's rawcode, "" none, how 1 the
    ; spell event it was dealt in, 2 the source's last cooldown, 3 the map timer it was dealt in (started in that spell),
    ; 4 inside your own hit's damage (an on-hit effect: "" after an attack), 5 inside a hit on your unit); 0: no module, or an older one
    static RING := 2048, HIT := 24
    damageHits(since) {
        if !(v := this.live()) || (lay := NumGet(v, Shm.layout, "uint")) < 33
            return 0
        seq := NumGet(v, Shm.dmRingSeq, "int")
        out := { seq: seq, lost: 0, hits: [] }
        if since < 0 || seq - since <= 0
            return out
        n := seq - since
        if n > GameModuleEngine.RING - 64                 ; the module writes on while this reads: the oldest are gone
            out.lost := n - (GameModuleEngine.RING - 64), n := GameModuleEngine.RING - 64
        loop n {
            k := Mod(seq - n + A_Index - 1, GameModuleEngine.RING), p := v + Shm.dmRing + GameModuleEngine.HIT * k
            f := NumGet(p, 18, "uchar"), ab := lay >= 34 ? NumGet(v, Shm.dmRingAbility + 4 * k, "uint") : 0
            out.hits.Push({ amount: NumGet(p, 0, "float"), src: GameModuleEngine.Rawcode(NumGet(p, 4, "uint")), tgt: GameModuleEngine.Rawcode(NumGet(p, 8, "uint")),
                target: NumGet(p, 12, "uint"), from: NumGet(p, 16, "uchar"), to: NumGet(p, 17, "uchar"),
                attack: f & 1, ranged: f & 2 ? 1 : 0, srcHero: f & 4 ? 1 : 0, tgtHero: f & 8 ? 1 : 0,
                dmgType: NumGet(p, 19, "uchar"), atkType: NumGet(p, 20, "uchar"),
                ability: GameModuleEngine.Rawcode(ab), how: lay >= 34 ? NumGet(p, 22, "uchar") : 0 })
        }
        return out
    }
    ; 'Hpal' from its number (the bytes the other way round in memory)
    static Rawcode(id) => id ? Chr(id >> 24 & 255) Chr(id >> 16 & 255) Chr(id >> 8 & 255) Chr(id & 255) : ""
    ; unit types the module has named, from entry `have` on -> { n, names: Map(rawcode -> name) } (0: older module)
    damageTypes(have) {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 33
            return 0
        lay := NumGet(v, Shm.layout, "uint")
        n := Min(NumGet(v, Shm.dmTypeN, "int"), lay >= 34 ? 256 : 128), out := { n: n, names: Map() }
        loop Max(0, n - have) {                     ; (layout 34: 128 on in the second table)
            i := have + A_Index - 1, j := Mod(i, 128), id := i < 128 ? Shm.dmTypeId : Shm.dmTypeId2, nm := i < 128 ? Shm.dmTypeName : Shm.dmTypeName2
            out.names[GameModuleEngine.Rawcode(NumGet(v, id + 4 * j, "uint"))] := StrGet(v + nm + 32 * j, 31, "UTF-8")
        }
        return out
    }
    ; your selection's active unit -> { unit, type, owner } (unit 0: none; 0: older module)
    damageSelection() {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 33
            return 0
        return { unit: NumGet(v, Shm.dmSelUnit, "uint"), type: GameModuleEngine.Rawcode(NumGet(v, Shm.dmSelType, "uint")), owner: NumGet(v, Shm.dmSelOwner, "int") }
    }
    ; the map's text lines after `since` (layout 33) -> { seq, lines: [] } (the last 8 at most; 0: older module)
    mapText(since) {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 33
            return 0
        seq := NumGet(v, Shm.mtSeq, "int"), out := { seq: seq, lines: [] }
        loop Min(Max(0, seq - since), 8)
            out.lines.Push(StrGet(v + Shm.mtText + 128 * Mod(seq - Min(seq - since, 8) + A_Index - 1, 8), 127, "UTF-8"))
        return out
    }
    ; the switch (layout 29), on while anyone wants the hits (the meter, the boss timers: who); false: no module, or an older one
    damageWanted(on, who := "meter") {
        static wants := Map()
        wants[who] := on
        any := false
        for , w in wants
            any := any || w
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 29
            return false
        NumPut("uint", any ? 1 : 0, v, Shm.dmOn)
        return true
    }

    ; -- the boss timers' feed (layout 36) ----------------------------------------------
    ; the switch; false: no module, or an older one
    bossCastsWanted(on) {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 36
            return false
        NumPut("uint", on ? 1 : 0, v, Shm.bcOn)
        return true
    }
    ; 0 off, 1 on, 3 refused; -1 no module or an older one
    bossCastsState() => (v := this.live()) && NumGet(v, Shm.layout, "uint") >= 36 ? NumGet(v, Shm.bcState, "uint") : -1
    ; the enemies' casts after `since` (the ring's count; -1 = only where it is now)
    ; -> { seq, lost, casts: [{ at, unit, type, ability, hp, hpMax, owner }] } (at: the tick count; 0: no module, or an older one)
    static CAST_RING := 128, CAST := 28
    bossCasts(since) {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 36
            return 0
        seq := NumGet(v, Shm.bcSeq, "int"), out := { seq: seq, lost: 0, casts: [] }
        if since < 0 || seq - since <= 0
            return out
        n := seq - since
        if n > GameModuleEngine.CAST_RING - 8
            out.lost := n - (GameModuleEngine.CAST_RING - 8), n := GameModuleEngine.CAST_RING - 8
        loop n {
            p := v + Shm.bcRing + GameModuleEngine.CAST * Mod(seq - n + A_Index - 1, GameModuleEngine.CAST_RING)
            out.casts.Push({ at: NumGet(p, 0, "uint"), unit: NumGet(p, 4, "uint"), type: GameModuleEngine.Rawcode(NumGet(p, 8, "uint")),
                ability: GameModuleEngine.Rawcode(NumGet(p, 12, "uint")), hp: NumGet(p, 16, "float"), hpMax: NumGet(p, 20, "float"), owner: NumGet(p, 24, "uchar") })
        }
        return out
    }
    ; the effect probe (layout 37): the map's ground effects near your hero logged; false: no module, or an older one
    effectProbe(on) {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 37
            return false
        NumPut("uint", on ? 1 : 0, v, Shm.fxOn)
        return true
    }
    ; the dash combo (layout 38): on, its dash ability and orb unit type (rawcodes 'A107' / 'e05P'), how far south it
    ; ends, how close to an orb before the next (layout 39); false: no module, or an older one
    dashCombo(on, dash, orb, south, reach := 190, key := 0) {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 38
            return false
        if NumGet(v, Shm.layout, "uint") >= 40          ; its key, read in the game (vk | 0x100 Ctrl | 0x200 Alt | 0x400 Shift)
            NumPut("uint", key, v, Shm.ocKey)
        if NumGet(v, Shm.layout, "uint") >= 39
            NumPut("float", reach, v, Shm.ocReach)
        NumPut("uint", GameModuleEngine.Id(dash), v, Shm.ocDash), NumPut("uint", GameModuleEngine.Id(orb), v, Shm.ocOrb)
        NumPut("float", south, v, Shm.ocSouth), NumPut("uint", on ? 1 : 0, v, Shm.ocOn)
        return true
    }
    ; a run now; false: no module, an older one, or it's off
    dashComboGo() {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 38 || !NumGet(v, Shm.ocOn, "uint")
            return false
        NumPut("int", NumGet(v, Shm.ocGo, "int") + 1, v, Shm.ocGo)
        return true
    }
    ; 'A107' -> its number (0: not 4 characters)
    static Id(code) => StrLen(code) = 4 ? Ord(SubStr(code, 1, 1)) << 24 | Ord(SubStr(code, 2, 1)) << 16 | Ord(SubStr(code, 3, 1)) << 8 | Ord(SubStr(code, 4, 1)) : 0
    ; the unit to follow (0 none); false: no module, or an older one
    bossWatch(unit) {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 36
            return false
        NumPut("uint", unit, v, Shm.bcWatch)
        return true
    }
    ; the unit followed now -> { unit, hp, max, alive } (0: no module, or an older one)
    bossWatched() {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 36
            return 0
        return { unit: NumGet(v, Shm.bcWatch, "uint"), hp: NumGet(v, Shm.bcWatchHp, "float"), max: NumGet(v, Shm.bcWatchMax, "float"), alive: NumGet(v, Shm.bcWatchAlive, "uint") }
    }

    ; -- the buffs' map timer lengths kept for good (layout 32) ---------------------------
    ; the table to the module: Map(rawcode -> seconds); false: no module, or an older one
    pushBuffTimers(known) {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 32
            return false
        n := 0
        for id, len in known {
            if n >= 64
                break
            NumPut("uint", GameModuleEngine.IdValue(id), v, Shm.btKnownId + 4 * n), NumPut("float", len, v, Shm.btKnownLen + 4 * n), n++
        }
        NumPut("uint", n, v, Shm.btKnownN)
        NumPut("int", NumGet(v, Shm.btKnownSeq, "int") + 1, v, Shm.btKnownSeq)
        return true
    }
    ; -> { seq, list: [{ id, len }] } of what the module learned after seq (16 at most), or 0
    learnedBuffTimers(seq) {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 32
            return 0
        now := NumGet(v, Shm.btNewSeq, "int"), out := { seq: now, list: [] }
        from := Max(seq, now - 16)
        loop now - from {
            i := Mod(from + A_Index - 1, 16)
            out.list.Push({ id: GameModuleEngine.IdText(NumGet(v, Shm.btNewId + 4 * i, "uint")), len: NumGet(v, Shm.btNewLen + 4 * i, "float") })
        }
        return out
    }
    ; 'Binf' -> its value as the game holds it
    static IdValue(id) {
        v := 0
        loop Min(4, StrLen(id))
            v := (v << 8) | Ord(SubStr(id, A_Index, 1))
        return v
    }

    ; -- your hero's buffs (layout 22) --------------------------------------------
    ; Read from the hero unit itself, whatever is selected, with the other timers
    ; (so timersWanted must be on too): rawcode, the game's name, times.
    heroWanted(on) {
        if (v := this.live()) && NumGet(v, Shm.layout, "uint") >= 22
            NumPut("uint", on ? 1 : 0, v, Shm.hrWant)
    }
    ; -> { hero: its type id ("Hpal", "" = none), alive, buffs: [{ id: "Binf", name, left, total, aura, positive }] }
    ;    or 0 without a module that reads them (name: the game's, "" if it has none)
    heroBuffs() {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 22
            return 0
        h := NumGet(v, Shm.hrHero, "uint")
        out := { hero: h ? GameModuleEngine.IdText(h) : "", alive: NumGet(v, Shm.hrAlive, "uint"), buffs: [] }
        loop Min(24, NumGet(v, Shm.hrCount, "uint")) {
            o := 4 * (A_Index - 1), f := NumGet(v, Shm.hrFlags + o, "uint")
            if f & 1
                out.buffs.Push({ id: GameModuleEngine.IdText(NumGet(v, Shm.hrId + o, "uint")), name: StrGet(v + Shm.hrName + 48 * (A_Index - 1), 47, "UTF-8"),
                    left: NumGet(v, Shm.hrLeft + o, "float"), total: NumGet(v, Shm.hrTotal + o, "float"), aura: f & 2 ? 1 : 0, positive: f & 4 ? 1 : 0, keptUp: f & 16 ? 1 : 0 })
        }
        return out
    }
    ; a rawcode as it's written ('Binf'; its bytes are the other way round in memory)
    static IdText(id) {
        s := ""
        loop 4
            if (c := (id >> (8 * (4 - A_Index))) & 0xFF)
                s .= Chr(c)
        return s
    }

    ; -- commands on the game's thread (layout 4) ---------------------------------
    ; 1 clear messages, 2 clear chat, 3 multiboard, 4 autocast toggle (arg: the
    ; command card slot 0-11, layout 8). Answered within about a second.
    cmdReady() {
        s := this.state()
        return this.enabled && s.live && s.probe = 1 && s.layout >= 4
    }
    command(cmd, arg := 0) {
        if !(v := this.live()) || NumGet(v, Shm.layout, "uint") < 4
            return 0
        seq := NumGet(v, Shm.cmdSeq, "int") + 1
        if NumGet(v, Shm.layout, "uint") >= 8
            NumPut("uint", arg, v, Shm.cmdArg)
        NumPut("uint", cmd, v, Shm.cmd)
        NumPut("int", seq, v, Shm.cmdSeq)                                 ; last: the module acts on it
        this.wake()
        return seq
    }
    ; 1 done, 2 refused, 3 the game thread didn't run it in time (0 seq: 2)
    commandWait(seq, ms) {
        if !seq
            return 2
        endAt := A_TickCount + ms
        while A_TickCount < endAt {
            if (v := this.live()) && NumGet(v, Shm.cmdDone, "int") = seq
                return NumGet(v, Shm.cmdResult, "uint")
            Sleep(10)
        }
        return 3
    }
    ; the module's wake event: it looks at once, not on its next round
    wake() {
        pid := WinGetPID(WarcraftIII)
        if !this.wakes.Get(pid, 0)              ; not kept while it fails: the module makes it just after its memory
            this.wakes[pid] := DllCall("OpenEvent", "uint", 0x2, "int", 0, "str", "Local\TWC_GameQc_" pid, "ptr")  ; EVENT_MODIFY_STATE
        if this.wakes[pid]
            DllCall("SetEvent", "ptr", this.wakes[pid])
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
