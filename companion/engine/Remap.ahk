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
    spent := Map()              ; quickcast key -> its hold ended with it still down (cleared by its key-up hotkey)
    pressAt := Map(), downAt := Map()   ; quickcast key -> when it was pressed, when it last came (its own repeat)
    sendFn := SendInput         ; how keyCastHeld sends (a check swaps it: never real keys)
    qcRecent := [], qcMissRun := 0      ; the last 10 quickcast hit delays (ms); misses in a row
    qcLate := 0                         ; the late-reticle watch running after a miss (lateWatch)
    qcTry := 0, qcStart := 0, qcBase := ""   ; the press being served: its try (1 = the press, 2+ = repeats while held), start, key
    qkVks := []                         ; the game key (virtual key) of each quickcast slot for the game module (pushKeys)
    qkSubVks := []                      ; and of each card slot in a sub menu (the Paladin's: WFE's "SA" keys; subKeys)

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
        if (sk := ShowKey()) != "" && Norm(sk) = k
            return "the open / hide window key"
        for c in [["pause", "the pause key"],
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
        this.qkVks := []
        for group in ["card", "inv"]
            loop this.count(group)
                this.qkVks.Push(this.qcAllowed(group, A_Index) && Integer(Ini(this.section, group "QC" A_Index, 0)) ? GetKeyVK(this.gameKey(group, A_Index)) : 0)
        on := this.subOn(), this.qkSubVks := []
        for k in this.subKeys()
            this.qkSubVks.Push(on && k != "" ? GetKeyVK(k) : 0)
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
                ; quickcast repeats while held: its key-up ends the repeat (a wheel
                ; notch has no "up" and can't be held), and so does the key's own
                ; repeat stopping: T2 lets each one reach castQuick while the repeat
                ; runs (with one thread they were dropped)
                held := qc && group != "mouse" && !IsWheel(key)
                this.registered.Push(RegisterHotkey(key, fn, WarcraftIII, true, true, held ? "T2" : ""))
                if held
                    this.registered.Push(RegisterHotkey(key " up", this.released.Bind(this, HotkeyBase(key)), WarcraftIII, true))
            }
        }
        this.pushKeys()
        global timersHud                        ; the pings' Ctrl + key follow your keys
        if IsSet(timersHud) && timersHud
            timersHud.pingKeysOn()
    }

    refresh() {
        for reg in this.registered
            reg.refresh()
        this.pushKeys()
    }
    ; the game module's quickcast keys (1.28f, as WFE: it presses the slot's button as
    ; the key comes): each slot's game key, on only while the companion's keys are
    ; (in a game, not paused, chat closed), since the keys also reach it straight
    pushKeys() {
        global gameModule, toolEnabled, chatting, inGame, gChatSending, inDialog
        if !IsSet(gameModule) || !gameModule
            return
        on := gameModule.enabled && gameModule.quickcast && toolEnabled && !chatting && !gChatSending && inGame && !inDialog && InStr(WC3WindowKey(), "reforged") != 1
        gameModule.pushKeys(this.qkVks, on, this.qkSubVks)
    }
    ; -- sub menus (the game hook only) ------------------------------------------
    ; A skill that opens a sub menu (the Paladin's) puts its buttons where the card's
    ; own were, so the card's keys would press the wrong ones (R its Cancel). While
    ; one is open the game module quickcasts by these keys instead, one per card slot
    ; ("" = none: the game's key), as WFE's "SA" keybinds. Default: Q W E R on the top
    ; row, where TWRPG's sub menus put their abilities.
    static SUB_DEFAULT := ["Q", "W", "E", "R", "", "", "", "", "", "", "", ""]
    subOn() => Integer(Ini(this.section, "subQC", 1))
    subKeys() {
        keys := []
        loop 12
            keys.Push(StrUpper(Ini(this.section, "sub" A_Index, RemapEngine.SUB_DEFAULT[A_Index])))
        return keys
    }
    ; on / off, or slot i's key ("" none); false: not a key
    setSub(i, key := 0) {
        if i = 0
            SetIni(key ? 1 : 0, this.section, "subQC")
        else {
            key := Trim(key)
            if key != "" && !GetKeyVK(key)
                return false
            SetIni(StrUpper(key), this.section, "sub" i)
        }
        this.registerAll()
        return true
    }

    ; -- profiles (the user, 2026-11-01: a set of keys per hero, switched by the save you load) ---------
    ; The keys in use stay in [Remap]; a profile is a copy of them in [RemapProfile <name>] (every slot's
    ; key and quickcast, the sub menus' keys). [RemapProfiles] list / current. Switching saves the keys
    ; in use into the current profile first, then copies the other one's in. The first is "Default".
    static PROFILE_KEYS() {
        keys := ["subQC"]
        loop 12
            keys.Push("card" A_Index, "cardQC" A_Index, "sub" A_Index)
        loop 6
            keys.Push("inv" A_Index, "invQC" A_Index)
        return keys
    }
    profile => Ini("RemapProfiles", "current", "Default")
    profiles() {
        out := []
        for n in StrSplit(Ini("RemapProfiles", "list", "Default"), "|")
            if Trim(n) != ""
                out.Push(Trim(n))
        return out.Length ? out : ["Default"]
    }
    hasProfile(name) {
        for n in this.profiles()
            if n = name
                return true
        return false
    }
    static ProfileName(name) => Trim(RegExReplace(name, "[|\[\]=;\r\n]"))
    ; the keys in use into a profile's own section
    storeProfile(name) {
        global iniFile
        sect := "RemapProfile " name
        for k in RemapEngine.PROFILE_KEYS() {
            v := Ini(this.section, k, Chr(1))
            if v = Chr(1) {
                try IniDelete(iniFile, sect, k)
            } else {
                SetIni(v, sect, k)
            }
        }
    }
    ; switch to a profile: true if it's the one in use now
    useProfile(name) {
        global iniFile
        if !this.hasProfile(name)
            return false
        if name = this.profile
            return true
        this.storeProfile(this.profile)
        sect := "RemapProfile " name
        for k in RemapEngine.PROFILE_KEYS() {
            v := Ini(sect, k, Chr(1))
            if v = Chr(1) {
                try IniDelete(iniFile, this.section, k)
            } else {
                SetIni(v, this.section, k)
            }
        }
        SetIni(name, "RemapProfiles", "current")
        this.registerAll()
        DebugLog("remap: profile " name)
        return true
    }
    ; a new profile, a copy of the keys in use (or empty), and in use: "" if the name is taken or empty
    newProfile(name, copy := true) {
        global iniFile
        name := RemapEngine.ProfileName(name)
        if name = "" || this.hasProfile(name)
            return ""
        this.storeProfile(this.profile)
        list := this.profiles(), list.Push(name)
        SetIni(Join("|", list*), "RemapProfiles", "list")
        if copy
            this.storeProfile(name)
        else
            try IniDelete(iniFile, "RemapProfile " name)
        if copy {
            SetIni(name, "RemapProfiles", "current")
            this.registerAll()
        } else
            this.useProfile(name)
        return name
    }
    renameProfile(old, name) {
        global iniFile, loader
        name := RemapEngine.ProfileName(name)
        if name = "" || !this.hasProfile(old) || (this.hasProfile(name) && name != old)
            return ""
        this.storeProfile(old)
        sect := "RemapProfile " old
        for k in RemapEngine.PROFILE_KEYS()
            if (v := Ini(sect, k, Chr(1))) != Chr(1)
                SetIni(v, "RemapProfile " name, k)
        if name != old
            try IniDelete(iniFile, sect)
        list := []
        for n in this.profiles()
            list.Push(n = old ? name : n)
        SetIni(Join("|", list*), "RemapProfiles", "list")
        if this.profile = old
            SetIni(name, "RemapProfiles", "current")
        if IsSet(loader) && loader
            loader.renameProfileLinks(old, name)
        return name
    }
    ; not the last one; the one in use: the first other one takes over
    deleteProfile(name) {
        global iniFile, loader
        list := this.profiles()
        if list.Length < 2 || !this.hasProfile(name)
            return false
        if this.profile = name {
            for n in list
                if n != name {
                    this.useProfile(n)
                    break
                }
        }
        rest := []
        for n in list
            if n != name
                rest.Push(n)
        SetIni(Join("|", rest*), "RemapProfiles", "list")
        try IniDelete(iniFile, "RemapProfile " name)
        if IsSet(loader) && loader
            loader.renameProfileLinks(name, "")
        return true
    }

    ; -- actions -------------------------------------------------------------
    ; "{q}", never "{Q}": an upper-case letter is sent with Shift (a queued order)
    keyText(key) {
        key := RegExReplace(key, "[$*~]")
        return "{" (StrLen(key) = 1 ? StrLower(key) : key) "}"
    }
    ; Shift held on a key that doesn't use Shift itself = WC3's queue (shift-queue)
    queued(yourKey) => GetKeyState("Shift", "P") && !InStr(HotkeyMods(yourKey), "+") ? "+" : ""

    ; the module takes quickcast keys now (cached 250 ms): 0, or the repeat settings { repeat, interval }
    keyCastNow() {
        global quickcast, gameModule
        static at := -1000, kc := 0, was := -1
        if A_TickCount - at < 250
            return kc
        at := A_TickCount
        ok := InStr(WC3WindowKey(), "reforged") != 1 && gameModule.qcReady() && gameModule.keyCastReady()
        if ok != was && was != -1
            DebugLog("quickcast: the game module's keys " (ok ? "are ready again" : "aren't ready: " gameModule.qcWhyNot()))
        was := ok
        s := ok ? quickcast.get("hook") : 0
        kc := ok ? { repeat: s.repeat, interval: s.interval, castGap: s.castGap } : 0
        return kc
    }
    ; The key to the game module, which presses its button and clicks (as WFE). Held, it goes again every
    ; [Quickcast] interval (80 ms) until let go (WFE's AutoCast repeats as long), unless repeat is off.
    ; Paced here, not by the key's own repeat: Windows waits its repeat delay (a quarter to half a second)
    ; before the first one, the pause after the first press a user felt on an item key (2026-10-29).
    ; Still held: a key-up the hook missed (Windows drops hook events while the script is busy) left it
    ; "down" and the loop pressed on by itself (a user's report, 2026-10-29): the key's own repeat stopping
    ; ends it (repeatGone). Not GetAsyncKeyState: the hotkey keeps the key from Windows, so it reads up
    ; while held. A key that isn't the one sent (F1 -> an item slot) goes until let go as WFE's; one sent
    ; as itself keeps the 20 s most a repeat lasts. t0: when the hotkey's thread started (QpcMs), for the timing line.
    gm() {
        global gameModule
        return gameModule
    }
    keyCastHeld(game, yourKey, base, kc, t0) {
        q := this.queued(yourKey)
        (this.sendFn)(q this.keyText(game))
        this.keyTiming(QpcMs() - t0)
        this.holding[base] := true, start := A_TickCount, presses := 1
        why := ""
        try this.keyCastRepeat(game, base, q, kc, start, &presses, &why)
        finally
            this.holding[base] := false
        this.spend(base, why)
        if presses > 1
            DebugLog("quickcast " game ": held, pressed " presses " times in " Round((A_TickCount - start) / 1000, 1) " s (every " kc.interval " ms): " why)
    }
    ; keyCastHeld's repeat while the key is held -> presses, why it ended
    keyCastRepeat(game, base, q, kc, start, &presses, &why) {
        static told := 0
        if told++ < 3
            DebugLog("quickcast " game ": the key to the game module, which presses its button and clicks (as WFE)")
        same := Norm(base) = Norm(RegExReplace(game, "[$*~]"))
        clicks := this.gm().keyClicks()
        while kc.repeat && !IsWheel(base) {
            if (why := this.waitHeld(base, same ? start : A_TickCount, kc.interval)) != ""
                break
            ; the module clicked (a cast): wait the rest of the after-cast gap (the hero still turning or walking into
            ; range, and each press reopens the reticle); the game hook's own, 400 ms by default
            if clicks >= 0 && (now := this.gm().keyClicks()) > clicks {
                clicks := now
                if kc.HasProp("castGap") && kc.castGap > kc.interval && (why := this.waitHeld(base, same ? start : A_TickCount, kc.castGap - kc.interval)) != ""
                    break
            }
            (this.sendFn)(q this.keyText(game)), presses++
        }
    }
    ; how long a press took from its hotkey to the key sent: every 25, the median and the slowest
    keyTiming(ms) {
        static list := []
        list.Push(ms)
        if list.Length < 25
            return
        sorted := list.Clone(), n := sorted.Length
        loop n - 1 {                            ; insertion sort (25)
            i := A_Index + 1, v := sorted[i], j := i - 1
            while j >= 1 && sorted[j] > v
                sorted[j + 1] := sorted[j], j--
            sorted[j + 1] := v
        }
        DebugLog("quickcast keys: the last 25 presses: sent " Round(sorted[13], 1) " ms after the hotkey (median), slowest " Round(sorted[n], 1) " ms")
        list := []
    }

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
    ; waits castGap (400 ms) before pressing again: the hero may still be
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
        t0 := QpcMs()
        ; the key's own repeat (T2: it comes while the press's thread runs): only noted, the press's
        ; thread presses again itself, and ends the repeat once these stop (repeatGone)
        ; A hold that already ended with the key still down (repeat off, 20 s, ...) takes no more: its
        ; repeats came here as new presses, ~30 a second
        base := HotkeyBase(yourKey)
        if !IsWheel(base) {
            last := this.downAt.Get(base, 0), this.downAt[base] := A_TickCount
            if this.holding.Get(base, false)
                return
            r := RemapEngine.keyRepeat()
            if this.spent.Get(base, false) && A_TickCount - last <= (last = this.pressAt.Get(base, 0) ? r.first : r.gap)
                return
            this.spent[base] := false, this.pressAt[base] := A_TickCount
        }
        ; the module's keys (as WFE), decided at most every 250 ms: the key goes out first, before anything is
        ; read (each press read ~10 ini settings and the game's state first: a delay a user felt, 2026-10-29)
        if (kc := this.keyCastNow())
            return this.keyCastHeld(game, yourKey, base, kc, t0)
        q := this.queued(yourKey)
        reforged := InStr(WC3WindowKey(), "reforged") = 1
        hookOn := !reforged && gameModule.quickcast, screenOn := QuickcastScreenOn()
        inGameQc := hookOn && gameModule.qcReady()
        s := quickcast.get(inGameQc ? "hook" : "screen")       ; (each method's own timings)
        ; the game hook going (not) ready, logged when it changes, with why: a quickcast that
        ; stops working shows here when and why it went to the screen or the key alone
        static wasReady := -1
        if hookOn && inGameQc != wasReady {
            if wasReady != -1 || !inGameQc
                DebugLog("quickcast: the game hook " (inGameQc ? "is ready again" : "isn't ready: " gameModule.qcWhyNot()))
            wasReady := inGameQc
        }
        ; 1.28f: the game module presses the slot's button as the key comes and clicks at once
        ; (as WFE): only the key goes. Held, it goes again every [Quickcast] interval (80 ms) until
        ; let go (WFE's AutoCast repeats as long), unless repeat is off. Paced here, not by the
        ; key's own repeat: Windows waits its repeat delay (a quarter to half a second) before the
        ; first one, the pause after the first press a user felt on an item key (2026-10-29)
        if inGameQc && gameModule.keyCastReady()
            return this.keyCastHeld(game, yourKey, base, { repeat: s.repeat, interval: s.interval, castGap: s.castGap }, t0)
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
        hits := 0, why := ""
        try loop {
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
        } finally
            this.holding[base] := false
        this.spend(base, why)
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
        this.holding[base] := false, this.spent[base] := false
    }
    ; a hold ended with the key still down (not let go): its repeats aren't new presses (castQuick);
    ; a tap let go before its press was done isn't (the next tap of a spam would be dropped)
    spend(base, why) {
        try down := !IsWheel(base) && GetKeyState(base, "P")
        catch
            down := false
        if down && why != "the key was let go"
            this.spent[base] := true
    }
    ; "" while the key is held and the repeat may go on, else why not
    heldWhy(base, start) {
        global toolEnabled, chatting, inGame
        try down := !IsWheel(base) && GetKeyState(base, "P")
        catch
            down := false
        return !this.holding.Get(base, false) ? "the key was let go"
            : !down ? "the key isn't down any more (its key-up never came)"
            : this.repeatGone(base) ? "its key repeat stopped (its key-up never came)"
            : !WinActive(WarcraftIII) ? "the game isn't in front"
            : !toolEnabled ? "the tool went off"
            : chatting ? "the chat is open"
            : !inGame ? "not in a game"
            : A_TickCount - start >= 20000 ? "20 s held, the most a repeat lasts"
            : ""
    }
    ; Windows repeats a held key (after its repeat delay, then at its repeat rate) and castQuick sees each
    ; one: none for longer than that = it isn't held. Key-up events can go missing (Windows drops hook
    ; events while the script is busy), and then the hook still says "down": a key that quickcasts as
    ; itself pressed on by itself for 20 s (~250 presses), and wasn't a quickcast again till then (a
    ; user's report, 2026-11-01). Generous margins: a busy script handles a repeat late, and ending
    ; early only means pressing again. Only said when sure: Windows repeats only the last key pressed,
    ; so any key after this one's last repeat (Shift for a queue, a second key held, any other key)
    ; leaves it to the key-up (A_TimeIdleKeyboard: the hook's last physical key, ups and repeats too);
    ; mouse buttons never repeat, and Filter Keys has repeat times of its own (or none).
    repeatGone(base, idle := A_TimeIdleKeyboard) {
        if !this.pressAt.Has(base) || RegExMatch(base, "i)^([LRM]Button|XButton[12])$") || !(r := RemapEngine.keyRepeat()).on
            return false
        last := this.downAt.Get(base, 0)
        if A_TickCount - idle > last + 5
            return false
        return A_TickCount - last > (last = this.pressAt[base] ? r.first : r.gap)
    }
    ; the keyboard's repeat (read once): first, the most a held key waits for its first repeat (the
    ; repeat delay, 250-1000 ms, + 400); gap, between repeats (2x the rate's period + 400); on: 0 while
    ; Filter Keys is on
    static keyRepeat() {
        static r := 0
        if r
            return r
        d := 1, sp := 31, fk := Buffer(24, 0), NumPut("uint", 24, fk)
        DllCall("SystemParametersInfo", "uint", 0x16, "uint", 0, "uint*", &d, "uint", 0)     ; SPI_GETKEYBOARDDELAY: 0-3
        DllCall("SystemParametersInfo", "uint", 0x0A, "uint", 0, "uint*", &sp, "uint", 0)    ; SPI_GETKEYBOARDSPEED: 0-31
        DllCall("SystemParametersInfo", "uint", 0x32, "uint", 24, "ptr", fk, "uint", 0)      ; SPI_GETFILTERKEYS
        return r := { first: (Min(d, 3) + 1) * 250 + 400, gap: 2 * Round(1000 / (2.5 + Min(sp, 31) * 27.5 / 31)) + 400,
            on: !(NumGet(fk, 4, "uint") & 1) }                                              ; FKF_FILTERKEYSON
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
        ; the request first, then the key: the module clicks as the game opens the target mode
        ; (on the game thread), which can be before a request written after the key
        limit := this.lookLimit()
        seq := gameModule.qcAsk(limit, q != "")
        SendInput(q this.keyText(game))
        t := QpcMs()
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
