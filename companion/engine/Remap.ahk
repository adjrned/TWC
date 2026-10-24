#Requires AutoHotkey v2.0
; ============================================================================
;  RemapEngine - spell / inventory / mouse remapping with quickcast.
; ============================================================================
class RemapEngine {
    section := "Remap"
    static SPELL_KEYS := ["Q","W","E","R","D","F","A","S","T","G","X","C"]
    static INV_TARGETS := ["Numpad7","Numpad8","Numpad4","Numpad5","Numpad1","Numpad2"]
    registered := []

    __New() {
        ; seed spell defaults on first run
        loop 12 {
            if Ini(this.section, "spellNew" A_Index, "") == ""
                SetIni("$" RemapEngine.SPELL_KEYS[A_Index], this.section, "spellNew" A_Index)
            if Ini(this.section, "spellOrig" A_Index, "") == ""
                SetIni(RemapEngine.SPELL_KEYS[A_Index], this.section, "spellOrig" A_Index)
        }
        this.registerAll()
    }

    ; -- RPC endpoints -------------------------------------------------------
    get(args := 0) {
        spells := []
        loop 12 {
            n := Ini(this.section, "spellNew" A_Index, "")
            o := Ini(this.section, "spellOrig" A_Index, "")
            spells.Push({
                new: n, newLabel: ReadableHotkey(n),
                orig: o, origLabel: ReadableHotkey(o),
                qc: Integer(Ini(this.section, "spellQC" A_Index, 0))
            })
        }
        inv := []
        loop 6 {
            n := Ini(this.section, "inv" A_Index, "")
            inv.Push({ new: n, newLabel: ReadableHotkey(n), target: RemapEngine.INV_TARGETS[A_Index] })
        }
        mouse := []
        sides := ["Left click", "Right click"]
        loop 2 {
            n := Ini(this.section, "mouse" A_Index, "")
            mouse.Push({ new: n, newLabel: ReadableHotkey(n), side: sides[A_Index] })
        }
        return {
            enableSpells: Integer(Ini(this.section, "enableSpells", 0)),
            enableInv: Integer(Ini(this.section, "enableInv", 0)),
            enableMouse: Integer(Ini(this.section, "enableMouse", 0)),
            spells: spells, inv: inv, mouse: mouse
        }
    }

    capture(args) {
        plain := args.Has("plain") ? args["plain"] : 0
        key := plain ? KeyWaitAny() : KeyWaitCombo()
        if key == "Escape"
            return { key: "", label: "" }
        return { key: key, label: ReadableHotkey(key) }
    }

    ; field: "new" (spell/inv/mouse hotkey) or "orig" (plain game key)
    setKey(args) {
        group := args["group"], index := Integer(args["index"]), field := args["field"], key := args["key"]
        stored := field == "orig" ? key : (key ? "$" key : "")
        iniKey := group == "spell" ? (field == "orig" ? "spellOrig" : "spellNew") index
                : group == "inv"   ? "inv" index
                : "mouse" index
        SetIni(stored, this.section, iniKey)
        this.registerAll()
        return { ok: 1 }
    }

    setQc(args) {
        SetIni(args["value"], this.section, "spellQC" Integer(args["index"]))
        this.registerAll()
        return { ok: 1 }
    }

    setEnable(args) {
        key := args["group"] == "spell" ? "enableSpells"
             : args["group"] == "inv"   ? "enableInv"
             : "enableMouse"
        SetIni(args["value"], this.section, key)
        this.registerAll()
        return { ok: 1 }
    }

    ; -- registration --------------------------------------------------------
    registerAll() {
        for reg in this.registered {
            reg.enable := false
            reg.refresh()
        }
        this.registered := []

        spellsOn := Integer(Ini(this.section, "enableSpells", 0))
        loop 12 {
            i := A_Index
            newKey := Ini(this.section, "spellNew" i, "")
            origKey := Ini(this.section, "spellOrig" i, "")
            if !newKey || !origKey
                continue
            qc := Integer(Ini(this.section, "spellQC" i, 0))
            fn := qc ? this.castQuick.Bind(this, origKey) : this.castPlain.Bind(this, origKey)
            this.registered.Push(RegisterHotkey(newKey, fn, WarcraftIII, spellsOn))
        }

        invOn := Integer(Ini(this.section, "enableInv", 0))
        loop 6 {
            i := A_Index
            newKey := Ini(this.section, "inv" i, "")
            if !newKey
                continue
            fn := this.castPlain.Bind(this, RemapEngine.INV_TARGETS[i])
            this.registered.Push(RegisterHotkey(newKey, fn, WarcraftIII, invOn))
        }

        mouseOn := Integer(Ini(this.section, "enableMouse", 0))
        sides := ["Left", "Right"]
        loop 2 {
            i := A_Index
            newKey := Ini(this.section, "mouse" i, "")
            if !newKey
                continue
            fn := this.clickMouse.Bind(this, sides[i])
            this.registered.Push(RegisterHotkey(newKey, fn, WarcraftIII, mouseOn))
        }
    }

    refresh() {
        for reg in this.registered
            reg.refresh()
    }

    ; -- actions -------------------------------------------------------------
    clean(key) => StrReplace(StrReplace(key, "$", ""), "*", "")

    castPlain(key) {
        SendInput("{" this.clean(key) "}")
    }

    castQuick(key) {
        SendInput("{Ctrl Down}{9}{0}{Ctrl Up}")
        SendInput("{" this.clean(key) "}")
        MouseClick("Left")
        SendInput("{9}{0}")
    }

    clickMouse(side) {
        MouseClick(side)
    }
}
