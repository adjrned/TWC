#Requires AutoHotkey v2.0
; ============================================================================
;  RemapEngine - your keys for the WC3 command card, inventory and mouse.
;  Slots follow the HUD: the 4x3 command card (TWRPG's layout), the 2x3
;  inventory and the two mouse buttons. A slot you give a key to sends that
;  slot's game key; a slot without one is left alone (the game's key works).
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

    __New() {
        this.migrate()
        this.registerAll()
    }

    ; -- reading -------------------------------------------------------------
    gameKey(group, i) {
        return group = "card" ? RemapEngine.CARD[i].game : group = "inv" ? RemapEngine.INV_TARGETS[i] : RemapEngine.MOUSE[i]
    }
    yourKey(group, i) => Ini(this.section, group i, "")
    count(group) => group = "card" ? 12 : group = "inv" ? 6 : 2
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
        for c in [["f8", "the show / hide window key"], ["f10", "the tool toggle"], ["pause", "the pause key"],
                  ["enter", "the chat key"], ["numpadenter", "the chat key"], ["escape", "WC3's cancel key"]]
            if k = c[1]
                return c[2]
        if IsSet(macros) && macros
            for m in macros.list()
                if Norm(m.hotkey) = k
                    return "a macro (" StrSplit(m.text, "`n")[1] ")"
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
                ; quickcast repeats while held: its key-up ends the repeat
                if qc && group != "mouse"
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
    }

    ; Quickcast: the ability goes off at the cursor. Held, it repeats until the
    ; key is let go (one hotkey thread loops; the key's auto-repeat is ignored).
    ; It stops on the first of: the key's own key-up, the key no longer down,
    ; the game losing focus (overlay, alt-tab), the tool going Off or chat
    ; opening, or 20 s as a last resort, so a key-up that went missing (focus
    ; moving mid-press) can never leave it casting forever.
    castQuick(game, yourKey) {
        global quickcast
        static hinted := false
        q := this.queued(yourKey), base := HotkeyBase(yourKey), s := quickcast.get()
        cal := quickcast.current()
        ; not set up for this game window: the key alone, with a one-time hint
        if !cal && !hinted {
            hinted := true
            Toast("Quickcast isn't set up for this game window: Remap > Quickcast setup", "", 5000)
        }
        this.holding[base] := true, start := A_TickCount
        loop {
            if cal
                this.quickSmart(game, q, cal)
            else
                SendInput(q this.keyText(game))
            if !s.repeat || !this.stillHeld(base, start)
                break
            Sleep(s.interval)
            if !this.stillHeld(base, start)
                break
        }
        this.holding[base] := false
    }
    released(base) {
        this.holding[base] := false
    }
    stillHeld(base, start) {
        global toolEnabled, chatting, inGame
        return this.holding.Get(base, false) && GetKeyState(base, "P") && WinActive(WarcraftIII)
            && toolEnabled && !chatting && inGame && A_TickCount - start < 20000
    }
    ; send the key, then click only once the game waits for a target: an
    ; instant spell, a cooldown or "not enough mana" never gets a stray click
    quickSmart(game, q, cal) {
        global quickcast
        SendInput(q this.keyText(game))
        t := A_TickCount
        while A_TickCount - t < 90 {        ; the card changes a frame or two later
            Sleep(10)
            if quickcast.targeting(cal) {
                SendInput(q "{Click}")
                return true
            }
        }
        return false
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
