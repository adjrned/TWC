#Requires AutoHotkey v2.0
; ============================================================================
;  MacrosEngine - configurable hotkey macros that type chat lines in Warcraft III
;  (one per row of their text). Another kind of macro is an extension's
;  (MacrosEngine.ext): without it such a macro is kept in the settings but does
;  nothing.
; ============================================================================
class MacrosEngine {
    section := "Macros"
    macros := []             ; [{hotkey, text, kind}]
    registered := Map()
    static ext := 0          ; the extension for the other kinds (0: none)

    __New() {
        this.reload()
    }

    ; -- RPC endpoints -------------------------------------------------------
    list(args := 0) {
        out := []
        for m in this.macros
            out.Push({
                hotkey: m.hotkey,
                label: ReadableHotkey(m.hotkey),
                text: m.text,
                kind: m.kind,
                summary: MacrosEngine.Summary(m)
            })
        return out
    }

    capture(args := 0) {
        combo := KeyWaitCombo()
        if combo == "Escape" || combo = ""                  ; "": cancelled (the key stays as it was)
            return { hotkey: "", label: "" }
        hk := "$" combo
        return { hotkey: hk, label: ReadableHotkey(hk) }
    }

    save(args) {
        index := args.Has("index") ? Integer(args["index"]) : -1
        entry := { hotkey: args["hotkey"], text: args["text"], kind: args.Has("kind") ? args["kind"] : "chat" }
        if index >= 1 && index <= this.macros.Length
            this.macros[index] := entry
        else
            this.macros.Push(entry)
        this.persist()
        this.reload()
        return { ok: 1 }
    }

    ; drag to reorder: the macro at from ends up at to
    move(args) {
        from := Integer(args["from"]), to := Integer(args["to"])
        if from < 1 || from > this.macros.Length || to < 1 || to > this.macros.Length || from = to
            return { ok: 0 }
        m := this.macros.RemoveAt(from)
        this.macros.InsertAt(to, m)
        this.persist()
        this.reload()
        return { ok: 1 }
    }

    delete(args) {
        index := Integer(args["index"])
        if index >= 1 && index <= this.macros.Length
            this.macros.RemoveAt(index)
        this.persist()
        this.reload()
        return { ok: 1 }
    }

    ; one line for lists and messages: the first chat line (another kind: its extension's)
    static Summary(m) {
        if m.kind != "chat"
            return MacrosEngine.ext ? MacrosEngine.ext.summary(m) : "(not available in this version)"
        for l in StrSplit(StrReplace(m.text, "`r"), "`n")
            if Trim(l) != ""
                return l
        return ""
    }
    ; -- persistence ---------------------------------------------------------
    encode(text) => StrReplace(StrReplace(text, "`r`n", "`n"), "`n", "\n")
    decode(text) => StrReplace(text, "\n", "`n")

    persist() {
        gap := Ini(this.section, "keyGap", "")
        IniDelete(iniFile, this.section)
        if gap != ""
            SetIni(gap, this.section, "keyGap")
        SetIni(this.macros.Length, this.section, "count")
        for i, m in this.macros {
            SetIni(m.hotkey, this.section, "hk" i)
            SetIni(this.encode(m.text), this.section, "tx" i)
            if m.kind != "chat"
                SetIni(m.kind, this.section, "kd" i)
        }
    }

    reload() {
        this.macros := []
        count := Integer(Ini(this.section, "count", -1))
        if count == -1 {
            this.seedDefaults()
            count := Integer(Ini(this.section, "count", 0))
        }
        loop count {
            hk := Ini(this.section, "hk" A_Index, "")
            tx := this.decode(Ini(this.section, "tx" A_Index, ""))
            kd := Ini(this.section, "kd" A_Index, "chat")
            if tx                       ; a macro whose key was cleared stays, off
                this.macros.Push({ hotkey: hk, text: tx, kind: kd })
        }
        this.registerAll()
    }

    seedDefaults() {
        defaults := [
            { hotkey: "$F5", text: "-recall" },
            { hotkey: "$F6", text: "-rf" },
            { hotkey: "$F7", text: "-chest play MA and you will forever be goated but be hated by people because u outdps them by right clicking" }
        ]
        SetIni(defaults.Length, this.section, "count")
        for i, d in defaults {
            SetIni(d.hotkey, this.section, "hk" i)
            SetIni(this.encode(d.text), this.section, "tx" i)
        }
    }

    ; -- hotkey registration -------------------------------------------------
    registerAll() {
        for _, reg in this.registered {
            reg.enable := false
            reg.refresh()
        }
        this.registered := Map()
        for m in this.macros {
            if !m.hotkey
                continue
            if m.kind != "chat" && !MacrosEngine.ext
                continue                            ; another kind, no extension: kept, off
            fn := m.kind != "chat" ? MacrosEngine.ext.hotkeyFn(m)
                : this.sendLines.Bind(this, StrSplit(StrReplace(m.text, "`r", ""), "`n"))
            this.registered.Set(m.hotkey, RegisterHotkey(m.hotkey, fn, WarcraftIII, true))
        }
    }

    sendLines(lines) {
        for line in lines
            if line != ""
                wc3Chat(line)
    }

    refresh() {
        for _, reg in this.registered
            reg.refresh()
        if MacrosEngine.ext && MacrosEngine.ext.HasMethod("refresh")
            MacrosEngine.ext.refresh()
    }
}
