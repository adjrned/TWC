#Requires AutoHotkey v2.0
; ============================================================================
;  RemapEngine - your keys for the WC3 command card and inventory.
;  Slots follow the HUD: the 4x3 command card (TWRPG's layout) and the 2x3
;  inventory. A slot you give a key to sends that slot's game key; a slot
;  without one is left alone (the game's key works). (The two mouse-button
;  slots were dropped on 2026-10-26, the user's call: count("mouse") is 0, so
;  they're neither shown nor bound; old [Remap] mouse keys are ignored.)
; ============================================================================
class RemapEngine {
    section := "Remap"
    ; command card, row by row as on screen; game = the key WC3 / TWRPG uses
    static CARD := [
        { name: "Move",    game: "M" }, { name: "Stop",    game: "S" }, { name: "Hold",    game: "H" }, { name: "Attack",  game: "A" },
        { name: "Patrol",  game: "P" }, { name: "Skill D", game: "D" }, { name: "Skill T", game: "T" }, { name: "Skill F", game: "F" },
        { name: "Skill Q", game: "Q" }, { name: "Skill W", game: "W" }, { name: "Skill E", game: "E" }, { name: "Skill R", game: "R" }]
    ; inventory slots 1-6 (left to right, top to bottom) are numpad keys in WC3
    static INV_TARGETS := ["Numpad7","Numpad8","Numpad4","Numpad5","Numpad1","Numpad2"]
    static MOUSE := ["Left", "Right"]
    static NO_QC := Map(2, 1, 3, 1)        ; Stop and Hold never take a target
    registered := []
    holding := Map()            ; quickcast key -> held (cleared by its key-up hotkey)
    qcRecent := [], qcMissRun := 0      ; the last 10 quickcast hit delays (ms); misses in a row
    qcLate := 0                         ; the late-reticle watch running after a miss (lateWatch)
    qcTry := 0, qcStart := 0, qcBase := ""   ; the press being served: its try (1 = the press, 2+ = repeats while held), start, key

    __New() {
        this.migrate()
        this.registerAll()
    }

    ; -- reading -------------------------------------------------------------
    gameKey(group, i) {
        return group = "card" ? RemapEngine.CARD[i].game : group = "inv" ? RemapEngine.INV_TARGETS[i] : RemapEngine.MOUSE[i]
    }
    yourKey(group, i) => Ini(this.section, group i, "")
    count(group) => group = "card" ? 12 : group = "inv" ? 6 : 0
    slotName(group, i) => group = "card" ? RemapEngine.CARD[i].name : group = "inv" ? "Item " i : RemapEngine.MOUSE[i] " click"
    qcAllowed(group, i) => group = "inv" || (group = "card" && !RemapEngine.NO_QC.Has(i))

    ; every slot, in HUD order: card 1-12, inventory 1-6, mouse 1-2
    get(args := 0) {
        slots := []
        for group in ["card", "inv", "mouse"]
            loop this.count(group) {
                i := A_Index, k := this.yourKey(group, i), g := this.gameKey(group, i)
                slots.Push({ group: group, index: i, name: this.slotName(group, i),
                    game: g, gameLabel: group = "inv" ? "Num " SubStr(g, 7) : group = "mouse" ? "" : ReadableHotkey(g),
                    key: k, keyLabel: ReadableHotkey(k),
                    qc: this.qcAllowed(group, i) ? Integer(Ini(this.section, group "QC" i, 0)) : 0,
                    qcAllowed: this.qcAllowed(group, i) })
            }
        for s in slots
            s.note := this.note(s, slots)
        return { slots: slots }
    }

    ; what to know about a slot's binding, as one line ("" = nothing)
    note(s, slots) {
        ; its own game key was taken by another slot, so the game key alone no longer reaches it
        if !s.key && s.group != "mouse"
            for o in slots
                if o.key && Norm(o.key) = Norm(s.game)
                    return "Your " o.keyLabel " key now does " o.name ". Give " s.name " a key of its own."
        if !s.key
            return ""
        k := Norm(s.key)
        if RegExMatch(k, "^\d$")
            return k " no longer selects control group " k " (Ctrl+" k " still sets it)."
        if RegExMatch(k, "^f[1-3]$")
            return s.keyLabel " no longer selects hero " SubStr(k, 2) "."
        for o in slots
            if o.group = "card" && o != s && Norm(o.game) = k && !o.key
                return s.keyLabel " was " o.name "'s key. It now does " s.name "."
        return ""
    }

    ; -- capture / editing ---------------------------------------------------
    ; Esc / Backspace / Delete clear the slot (key "-")
    capture(args := 0) {
        key := RegExReplace(KeyWaitCombo(), "[<>]")    ; either Shift/Ctrl/Alt
        if key = "Escape" || key = "Backspace" || key = "Delete"
            return { key: "-", label: "" }
        return { key: key, label: ReadableHotkey(key) }
    }

    ; your key for a slot ("-" = clear). Returns { ok, msg }: msg says what
    ; else changed, or why it was refused.
    setKey(args) {
        group := args["group"], i := Integer(args["index"]), key := args["key"]
        if key = "-" {
            SetIni("", this.section, group i)
            this.registerAll()
            return { ok: 1, msg: "" }
        }
        if why := this.reserved(key)
            return { ok: 0, msg: ReadableHotkey(key) " is " why "." }
        msg := ""
        ; one key, one slot: take it from wherever it was
        for g in ["card", "inv", "mouse"]
            loop this.count(g)
                if !(g = group && A_Index = i) && (o := this.yourKey(g, A_Index)) && Norm(o) = Norm(key) {
                    SetIni("", this.section, g A_Index)
                    msg := ReadableHotkey(key) " moved from " this.slotName(g, A_Index) "."
                }
        SetIni("$" key, this.section, group i)
        this.registerAll()
        return { ok: 1, msg: msg }
    }

    ; keys the companion already uses for something else
    reserved(key) {
        global macros, webOverlay
        k := Norm(key)
        for c in [["f8", "the show / hide window key"], ["pause", "the pause key"],
                  ["enter", "the chat key"], ["numpadenter", "the chat key"], ["escape", "WC3's cancel key"]]
            if k = c[1]
                return c[2]
        if IsSet(macros) && macros
            for m in macros.list()
                if Norm(m.hotkey) = k
                    return "a macro (" m.summary ")"
        if IsSet(webOverlay) && webOverlay {
            s := webOverlay.get()
            if s.hotkey && Norm(s.hotkey) = k
                return "the overlay key"
            if s.pinHotkey && Norm(s.pinHotkey) = k
                return "the overlay pin key"
        }
        return ""
    }

    setQc(args) {
        SetIni(args["value"], this.section, args["group"] "QC" Integer(args["index"]))
        this.registerAll()
        return { ok: 1 }
    }

    ; older settings: per-group switches and game key overrides are dropped, the old list
    ; (Spell 1-12: your key -> game key) becomes card slots, by game key
    migrate() {
        for k in ["enableSpells", "enableInv", "enableMouse"]     ; per-group switches, gone
            try IniDelete(iniFile, this.section, k)
        loop 12                                                  ; per-slot game key overrides, gone
            try IniDelete(iniFile, this.section, "cardGame" A_Index)
        if Ini(this.section, "spellNew1", "") = "" && Ini(this.section, "spellOrig1", "") = ""
            return
        loop 12 {
            r := A_Index
            n := Ini(this.section, "spellNew" r, ""), o := Ini(this.section, "spellOrig" r, "")
            qc := Ini(this.section, "spellQC" r, 0)
            if n && o && Norm(n) != Norm(o)
                for i, c in RemapEngine.CARD
                    if Norm(c.game) = Norm(o) && this.yourKey("card", i) = "" {
                        SetIni(n, this.section, "card" i)
                        SetIni(qc, this.section, "cardQC" i)
                        break
                    }
            for k in ["spellNew", "spellOrig", "spellQC"]
                try IniDelete(iniFile, this.section, k r)
        }
    }

    ; -- registration --------------------------------------------------------
    registerAll() {
        for reg in this.registered {
            reg.enable := false
            reg.refresh()
        }
        this.registered := []
        used := Map()                           ; every key a slot was given
        for group in ["card", "inv", "mouse"]
            loop this.count(group)
                if k := this.yourKey(group, A_Index)
                    used[Norm(k)] := 1
        for group in ["card", "inv", "mouse"] {
            loop this.count(group) {
                i := A_Index, key := this.yourKey(group, i), game := this.gameKey(group, i)
                qc := this.qcAllowed(group, i) && Integer(Ini(this.section, group "QC" i, 0))
                ; quickcast on a slot without a key of its own: its game key quickcasts
                ; (unless another slot was given that key)
                if !key && qc && !used.Has(Norm(game))
                    key := "$" game
                if !key
                    continue
                fn := group = "mouse" ? this.clickMouse.Bind(this, game, key)
                    : qc ? this.castQuick.Bind(this, game, key)
                    : this.castPlain.Bind(this, game, key)
                this.registered.Push(RegisterHotkey(key, fn, WarcraftIII, true))
                ; quickcast repeats while held: its key-up ends the repeat (a wheel
                ; notch has no "up" and can't be held)
                if qc && group != "mouse" && !IsWheel(key)
                    this.registered.Push(RegisterHotkey(key " up", this.released.Bind(this, HotkeyBase(key)), WarcraftIII, true))
            }
        }
    }

    refresh() {
        for reg in this.registered
            reg.refresh()
    }

    ; -- actions -------------------------------------------------------------
    ; "{q}", never "{Q}": an upper-case letter is sent with Shift (a queued order)
    keyText(key) {
        key := RegExReplace(key, "[$*~]")
        return "{" (StrLen(key) = 1 ? StrLower(key) : key) "}"
    }
    ; Shift held on a key that doesn't use Shift itself = WC3's queue (shift-queue)
    queued(yourKey) => GetKeyState("Shift", "P") && !InStr(HotkeyMods(yourKey), "+") ? "+" : ""

    castPlain(game, yourKey) {
        SendInput(this.queued(yourKey) this.keyText(game))
        DebugLog("remap " ReadableHotkey(yourKey) " -> " game " (" WC3WindowKey() ")")
    }

    ; Quickcast: the ability goes off at the cursor. Held, it repeats until the
    ; key is let go (one hotkey thread loops; the key's auto-repeat is ignored).
    ; It stops on the first of: the key's own key-up, the key no longer down,
    ; the game losing focus (overlay, alt-tab), the tool going Off or chat
    ; opening, or 20 s as a last resort, so a key-up that went missing (focus
    ; moving mid-press) can never leave it casting forever. After a cast it
    ; waits castGap (450 ms) before pressing again: the hero may still be
    ; turning or walking into range, and each press reopens the reticle (its
    ; animation and sound) and gives the order again.
    ; Two ways to know the game waits for a target: the game hook (1.28f
    ; only: the injected game module asks the game; no setup) and the screen
    ; (1.28f and Reforged: reads the command card; set up per window size).
    ; On 1.28f the hook goes first, the screen when the hook is off or not
    ; ready. Neither: the key goes alone.
    castQuick(game, yourKey) {
        global quickcast, gameModule
        static hinted := Map()          ; window keys already hinted about
        q := this.queued(yourKey), base := HotkeyBase(yourKey), s := quickcast.get()
        reforged := InStr(WC3WindowKey(), "reforged") = 1
        hookOn := !reforged && gameModule.quickcast, screenOn := QuickcastScreenOn()
        inGameQc := hookOn && gameModule.qcReady()
        ; the game hook going (not) ready, logged when it changes, with why: a quickcast that
        ; stops working shows here when and why it went to the screen or the key alone
        static wasReady := -1
        if hookOn && inGameQc != wasReady {
            if wasReady != -1 || !inGameQc
                DebugLog("quickcast: the game hook " (inGameQc ? "is ready again" : "isn't ready: " gameModule.qcWhyNot()))
            wasReady := inGameQc
        }
        cal := !inGameQc && screenOn ? quickcast.current() : 0
        ; neither: the key alone, with a hint once per window (a fullscreen /
        ; windowed switch or a resize changes it; none when both switches are off)
        if (hookOn || screenOn) && !inGameQc && !cal && !hinted.Has(k := WC3WindowKey()) {
            hinted[k] := true
            DebugLog("quickcast: " (hookOn ? "the game hook isn't ready, " : "") (screenOn ? "the screen isn't set up for " k : "the screen is off") ": the key alone")
            Toast(hookOn ? "Quickcast: the game hook isn't ready (" gameModule.qcStatusText() ")" (screenOn ? "; or set up Screen quickcast: Remap page > Screen > Options" : "")
                : "Quickcast isn't set up for this window size (" WC3WindowName(k) "): Remap page > Screen > Options", "", 6000)
        }
        this.holding[base] := true, start := A_TickCount
        this.qcStart := start, this.qcBase := base
        hits := 0
        loop {
            this.qcTry := A_Index, hit := false
            if inGameQc
                hit := this.quickModule(game, q, A_Index > 1)
            else if cal
                hit := this.quickSmart(game, q, cal, A_Index > 1)
            else
                SendInput(q this.keyText(game)), DebugLog("quickcast " game ": not set up for " WC3WindowKey() ", key only" this.tryTag())
            hits += hit
            if !s.repeat {
                why := "repeat while held is off"
                break
            }
            if (why := this.waitHeld(base, start, hit ? Max(s.interval, s.castGap) : s.interval)) != ""
                break
        }
        ; how the press ended; a repeat logs it always, a single press only when not let go as usual
        tries := this.qcTry
        if tries > 1 || why != "the key was let go"
            DebugLog("quickcast " game ": done after " tries (tries = 1 ? " try" : " tries") " (" hits " cast) in "
                . Round((A_TickCount - start) / 1000, 1) " s: " why)
        this.holding[base] := false, this.qcTry := 0
    }
    ; wait ms while the key stays held (checked often, so letting go ends it at
    ; once) -> "" if it still is, or why the repeat ends (heldWhy)
    waitHeld(base, start, ms) {
        endAt := A_TickCount + ms
        loop {
            if (why := this.heldWhy(base, start)) != ""
                return why
            if A_TickCount >= endAt
                return ""
            Sleep(Min(15, endAt - A_TickCount))
        }
    }
    released(base) {
        this.holding[base] := false
    }
    ; "" while the key is held and the repeat may go on, else why not
    heldWhy(base, start) {
        global toolEnabled, chatting, inGame
        try down := !IsWheel(base) && GetKeyState(base, "P")
        catch
            down := false
        return !this.holding.Get(base, false) ? "the key was let go"
            : !down ? "the key isn't down any more (its key-up never came)"
            : !WinActive(WarcraftIII) ? "the game isn't in front"
            : !toolEnabled ? "the tool went off"
            : chatting ? "the chat is open"
            : !inGame ? "not in a game"
            : A_TickCount - start >= 20000 ? "20 s held, the most a repeat lasts"
            : ""
    }
    ; for the log: which try of a held key this is (the press itself: nothing),
    ; and whether the key was still down then, to tell a repeat from a lone press
    tryTag() {
        if this.qcTry <= 1
            return ""
        try down := GetKeyState(this.qcBase, "P")
        catch
            down := false
        return " [repeat " (this.qcTry - 1) ", " Round((A_TickCount - this.qcStart) / 1000, 1) " s after the press, key "
            . (down ? "down" : "up") (this.holding.Get(this.qcBase, false) ? "" : ", key-up seen") "]"
    }
    ; send the key, then click only once the game waits for a target: an
    ; instant spell, a cooldown or "not enough mana" never gets a stray click
    ; The card changes a frame or two after the key; it's read back to back
    ; from right after the key (no waits in between), and a targeted cast clicks
    ; the moment it's seen. How long to keep looking adapts: 3x the typical
    ; delay of the last hits (60-150 ms), so a cooldown or the T menu gives up
    ; quickly and a held key repeats sooner. Misses don't stretch it (holding a
    ; key on cooldown used to push every look to 200 ms); every third miss in a
    ; row looks for 200 ms once, in case the game got slower. The log line says
    ; what was seen.
    ; again: a repeat while the key is held. A busy game can draw the reticle
    ; after the look gave up; if it's up from the last press, it's clicked
    ; instead of pressing the key over it.
    quickSmart(game, q, cal, again := false) {
        global quickcast
        this.stopLate()
        if again && quickcast.targeting(cal) {
            SendInput(q "{Click}")
            this.qcMissRun := 0
            DebugLog("quickcast " game ": the reticle from the last press came up late (a busy game): clicked" this.tryTag())
            return true
        }
        limit := this.lookLimit()
        SendInput(q this.keyText(game))
        t := QpcMs(), checks := 0, best := { same: -1, diffs: "" }
        while QpcMs() - t < limit {
            checks++
            hit := quickcast.targeting(cal)
            if quickcast.seen.same > best.same
                best := quickcast.seen
            if hit {
                quickcast.learnCapture(cal, true)       ; (first hit only: tests the window read, still targeting)
                SendInput(q "{Click}")
                this.qcMissRun := 0, quickcast.noteHit()
                ms := QpcMs() - t
                this.noteHit(ms)
                DebugLog("quickcast " game ": clicked " Round(ms, 1) " ms after the key (" checks " reads, "
                    . (quickcast.fromWindow.Get(WC3WindowKey(), false) ? "game window" : "screen") ")" this.tryTag())
                return true
            }
        }
        ; either way of reading (the screen, the game window) can go stale, its
        ; picture no longer updating: one look the other way tells. If that one
        ; shows targeting, click and read that way from now on. (A key on
        ; cooldown looks the same both ways, so it never switches for that.)
        k := WC3WindowKey(), win := quickcast.fromWindow.Get(k, false)
        if quickcast.targeting(cal, !win) {
            quickcast.fromWindow[k] := !win, quickcast.misses := 0
            SendInput(q "{Click}")
            DebugLog("quickcast " game ": the " (win ? "game window's" : "screen's") " picture was stale, the "
                . (win ? "screen" : "game window") " shows targeting: clicked, reading that way from now on" this.tryTag())
            this.qcMissRun := 0
            return true
        }
        quickcast.learnCapture(cal, false)
        quickcast.noteMiss(cal, best.same)
        this.qcMissRun++
        this.lateWatch(game, q, cal, t)
        static lastDiffs := "", frozen := 0
        frozen := best.diffs != "" && best.diffs == lastDiffs ? frozen + 1 : 0
        lastDiffs := best.diffs
        if frozen = 5 {
            ; 6 misses with the very same card (fine on a cooldown; if the reticle
            ; was up, the picture is stuck both ways): what both ways see, and the window
            quickcast.targeting(cal, false), viaScreen := quickcast.seen.diffs
            quickcast.targeting(cal, true), viaWindow := quickcast.seen.diffs
            hwnd := WinExist(WarcraftIII), WinGetClientPos(&cx, &cy, &cw, &ch, hwnd)
            try proc := WinGetProcessName(hwnd)
            catch
                proc := "?"
            DebugLog("quickcast: the same card 6 misses in a row (reading the " (win ? "game window" : "screen") "). Screen "
                . viaScreen " / game window " viaWindow " / window " Format("0x{:X}", hwnd) " " proc ' "' WinGetTitle(hwnd) '" at ' cx "," cy " " cw "x" ch)
        }
        DebugLog("quickcast " game ": no click, not targeting: best " best.same "/11 slots empty (needs 8) in " checks
            . " reads / " Round(QpcMs() - t) " ms (gives up at " Round(limit) "); slot differences " best.diffs this.tryTag())
        return false
    }
    ; how long to look for the reticle after the key (see quickSmart)
    lookLimit() {
        limit := 150
        if this.qcRecent.Length >= 3 {
            sorted := this.qcRecent.Clone(), SortBy(sorted, (a, b) => a - b)
            limit := Max(60, Min(150, 3 * sorted[(sorted.Length + 1) // 2]))
        }
        if this.qcMissRun >= 3 && Mod(this.qcMissRun, 3) = 0
            limit := 200
        return limit
    }
    ; quickSmart through the 1.28 game module: send the key, then the module
    ; clicks the moment the game waits for a target, or gives up at the
    ; deadline (same adaptive look as the screen's). A repeat first asks for a
    ; click on a reticle still up from the last press. After a miss the late
    ; watch keeps asking for 500 ms, as with the screen.
    quickModule(game, q, again := false) {
        global gameModule
        this.stopLate()
        if again && gameModule.qcWait(seq := gameModule.qcAsk(20, q != ""), 20) = 1 {
            this.qcMissRun := 0
            DebugLog("quickcast " game ": the reticle from the last press came up late (a busy game): the game module clicked" this.tryTag())
            return true
        }
        limit := this.lookLimit()
        SendInput(q this.keyText(game))
        t := QpcMs(), seq := gameModule.qcAsk(limit, q != "")
        r := gameModule.qcWait(seq, limit)
        if r = 1 {
            ms := gameModule.qcMs()
            this.qcMissRun := 0, this.noteHit(ms)
            DebugLog("quickcast " game ": the game module clicked " ms " ms after the key" this.tryTag())
            return true
        }
        this.qcMissRun++
        DebugLog("quickcast " game ": no click, " (r = 3 ? "the game wanted a target but wasn't in front" : "the game didn't want a target") " within " Round(limit) " ms (game module)" this.tryTag())
        if r = 2
            this.lateWatch(game, q, 0, t)
        return false
    }
    ; end a late watch still running (and its game module request)
    stopLate() {
        global gameModule
        if !this.qcLate
            return
        SetTimer(this.qcLate.fn, 0), this.qcLate.ih.Stop()
        gameModule.qcCancel(this.qcLate.seq)
        this.qcLate := 0
    }
    noteHit(ms) {
        this.qcRecent.Push(ms)
        if this.qcRecent.Length > 10
            this.qcRecent.RemoveAt(1)
    }
    ; After a miss the reticle may still come up (a busy game draws it late):
    ; watched for 500 ms and clicked if it shows, unless you pressed a key or a
    ; mouse button meanwhile (then what's on screen is yours). The delay counts
    ; as a hit, so the looks grow longer while the game is slow.
    ; cal = 0: through the game module (it clicks; this only ends the request early)
    lateWatch(game, q, cal, t) {
        global quickcast, gameModule
        endAt := A_TickCount + 500, ih := InputHook("V"), tag := this.tryTag()
        seq := cal ? 0 : gameModule.qcAsk(500, q != "")
        ih.MinSendLevel := 1                    ; your keys, not the companion's own
        ih.KeyOpt("{All}", "N")
        ih.OnKeyDown := (*) => (ih.Stop())
        ih.Start()
        tick() {
            global chatting, toolEnabled
            if !ih.InProgress || A_TickCount > endAt || GetKeyState("LButton", "P") || GetKeyState("RButton", "P")
                || !WinActive(WarcraftIII) || chatting || !toolEnabled {
                SetTimer(tick, 0), ih.Stop(), gameModule.qcCancel(seq), this.qcLate := 0
                return
            }
            if !cal {
                if !(r := gameModule.qcResult(seq))
                    return
                SetTimer(tick, 0), ih.Stop(), this.qcLate := 0
                if r = 1 {
                    ms := QpcMs() - t
                    this.noteHit(ms), this.qcMissRun := 0
                    DebugLog("quickcast " game ": the reticle came up late, " Round(ms) " ms after the key (a busy game): the game module clicked" tag)
                }
                return
            }
            if quickcast.targeting(cal) {
                SetTimer(tick, 0), ih.Stop(), this.qcLate := 0
                SendInput(q "{Click}")
                ms := QpcMs() - t
                this.noteHit(ms), this.qcMissRun := 0
                DebugLog("quickcast " game ": the reticle came up late, " Round(ms) " ms after the key (a busy game): clicked" tag)
            }
        }
        this.qcLate := { fn: tick, ih: ih, seq: seq }
        SetTimer(tick, 15)
    }
    clickMouse(side, yourKey) {
        SendInput(this.queued(yourKey) "{Click " side "}")
    }
}

; "$*<^+q" -> "^+q": the modifiers and key, without hotkey options or sides
Norm(key) => StrLower(RegExReplace(key, "[$*~<>]"))
; just the modifier symbols of a hotkey ("^+" for "$^+q")
HotkeyMods(key) => RegExMatch(Norm(key), "^[#!^+]*(?=.)", &m) ? m[0] : ""
; just the key of a hotkey ("q" for "$^+q"), for GetKeyState
HotkeyBase(key) => SubStr(Norm(key), StrLen(HotkeyMods(key)) + 1)
