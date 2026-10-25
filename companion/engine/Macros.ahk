#Requires AutoHotkey v2.0
; ============================================================================
;  MacrosEngine - configurable hotkey macros, of two kinds:
;    chat  types chat lines in Warcraft III (one per row of its text)
;    keys  presses game keys in a row, e.g. items 1-5 at once (its text is the
;          keys, space separated: "Numpad7 Numpad8 q ^1")
; ============================================================================
class MacrosEngine {
    section := "Macros"
    macros := []             ; [{hotkey, text, kind}]
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
                text: m.text,
                kind: m.kind,
                summary: MacrosEngine.Summary(m)
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

    ; -- keys macros -----------------------------------------------------------
    static Keys(text) {
        out := []
        for t in StrSplit(Trim(text), " ")
            if t != ""
                out.Push(t)
        return out
    }
    ; "Numpad7" -> "Item 1", "q" -> "Skill Q", "^1" -> "Ctrl+1"
    static KeyLabel(t) {
        for i, k in RemapEngine.INV_TARGETS
            if t = k
                return "Item " i
        for c in RemapEngine.CARD
            if t = c.game
                return c.name
        return ReadableHotkey(t)
    }
    ; one line for lists and messages: the first chat line, or the keys
    static Summary(m) {
        if m.kind = "keys" {
            labels := []
            for t in MacrosEngine.Keys(m.text)
                labels.Push(MacrosEngine.KeyLabel(t))
            return Join(" " Chr(0xB7) " ", labels*)
        }
        for l in StrSplit(StrReplace(m.text, "`r"), "`n")
            if Trim(l) != ""
                return l
        return ""
    }
    ; a key as SendInput text: modifiers, then "{q}" (never "{Q}", which is Shift+q)
    static KeyInput(t) {
        RegExMatch(t, "^([\^!+#]*)(.+)$", &m)
        return m[1] "{" (StrLen(m[2]) = 1 ? StrLower(m[2]) : m[2]) "}"
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

    ; ready-made macros (Macros page > Presets): TWRPG's chat commands, from
    ; its patch notes, and a keys one. [label, kind, text]
    static PRESETS := [
        ["-save   save your hero", "chat", "-save"],
        ["-asave   save account-wide items", "chat", "-asave"],
        ["-recall", "chat", "-recall"],
        ["-rf   refresh", "chat", "-rf"],
        ["-r   damage record of the boss fight", "chat", "-r"],
        ["-rs / -re   start / end a damage record", "chat", "-rs"],
        ["-a   the selected unit's information", "chat", "-a"],
        ["-t   show / hide your teammates' icons", "chat", "-t"],
        ["-recipe", "chat", "-recipe"],
        ["-skip   skip cinematics on / off", "chat", "-skip"],
        ["-fog   special fog off", "chat", "-fog"],
        ["-flash   screen flashing off", "chat", "-flash"],
        ["-sound   resummon sounds off", "chat", "-sound"],
        ["-colorblind   colour-blind mode", "chat", "-colorblind"],
        ["Use all 6 items   (keys)", "keys", "Numpad7 Numpad8 Numpad4 Numpad5 Numpad1 Numpad2"],
    ]

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
            if !m.hotkey
                continue
            fn := m.kind = "keys" ? this.sendKeys.Bind(this, MacrosEngine.Keys(m.text))
                : this.sendLines.Bind(this, StrSplit(StrReplace(m.text, "`r", ""), "`n"))
            this.registered.Set(m.hotkey, RegisterHotkey(m.hotkey, fn, WarcraftIII, true))
        }
    }

    sendLines(lines) {
        for line in lines
            if line != ""
                wc3Chat(line)
    }

    ; the keys one after another, a few ms apart so the game sees each one
    ; (keyGap in [Macros], default 15). Sent keys never trigger the companion's
    ; own hotkeys, so these are game keys.
    sendKeys(keys) {
        gap := Integer(Ini(this.section, "keyGap", 15))
        for i, t in keys {
            if i > 1 && gap > 0
                Sleep(gap)
            SendInput(MacrosEngine.KeyInput(t))
        }
    }

    refresh() {
        for _, reg in this.registered
            reg.refresh()
    }
}
