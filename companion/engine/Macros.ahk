#Requires AutoHotkey v2.0
; ============================================================================
;  MacrosEngine - configurable hotkey -> chat-line macros.
; ============================================================================
class MacrosEngine {
    section := "Macros"
    macros := []             ; [{hotkey, text}]
    registered := Map()

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
                text: m.text
            })
        return out
    }

    capture(args := 0) {
        combo := KeyWaitCombo()
        if combo == "Escape"
            return { hotkey: "", label: "" }
        hk := "$" combo
        return { hotkey: hk, label: ReadableHotkey(hk) }
    }

    save(args) {
        index := args.Has("index") ? Integer(args["index"]) : -1
        entry := { hotkey: args["hotkey"], text: args["text"] }
        if index >= 1 && index <= this.macros.Length
            this.macros[index] := entry
        else
            this.macros.Push(entry)
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

    ; -- persistence ---------------------------------------------------------
    encode(text) => StrReplace(StrReplace(text, "`r`n", "`n"), "`n", "\n")
    decode(text) => StrReplace(text, "\n", "`n")

    persist() {
        IniDelete(iniFile, this.section)
        SetIni(this.macros.Length, this.section, "count")
        for i, m in this.macros {
            SetIni(m.hotkey, this.section, "hk" i)
            SetIni(this.encode(m.text), this.section, "tx" i)
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
            if hk && tx
                this.macros.Push({ hotkey: hk, text: tx })
        }
        this.registerAll()
    }

    seedDefaults() {
        defaults := [
            { hotkey: "$F5", text: "-recall" },
            { hotkey: "$F6", text: "-a" },
            { hotkey: "$^x", text: "-chest im lagging" },
            { hotkey: "$^z", text: "GET GOOD     GET GOOD`nGE                  GE`nGE   GOOD     GE   GOOD`nGET GOOD     GET GOOD" }
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
            lines := StrSplit(StrReplace(m.text, "`r", ""), "`n")
            this.registered.Set(m.hotkey,
                RegisterHotkey(m.hotkey, this.sendLines.Bind(this, lines), WarcraftIII, true))
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
    }
}
