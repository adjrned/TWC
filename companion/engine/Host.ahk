#Requires AutoHotkey v2.0
; ============================================================================
;  HostEngine - whisper a host bot to open a lobby.
; ============================================================================
class HostEngine {
    section := "Host"
    static FIELDS := ["botName", "trigger", "gameName", "exBefore", "exAfter"]
    static DEFAULTS := Map("botName", "geybot", "trigger", "!", "gameName", "sey", "exBefore", "", "exAfter", "")

    __New() {
        HotIfWinActive(WarcraftIII)
        Hotstring(":XB0:-h",       (*) => this.hostSaved(1))
        Hotstring(":XB0:-host",    (*) => this.hostSaved(1))
        Hotstring(":XB0:-hp",      (*) => this.hostSaved(0))
        Hotstring(":XB0:-hostpub", (*) => this.hostSaved(0))
        HotIfWinActive()
    }

    ; -- RPC endpoints -------------------------------------------------------
    get(args := 0) {
        fields := {}, lists := {}
        for name in HostEngine.FIELDS {
            fields.%name% := Ini(this.section, name, HostEngine.DEFAULTS[name])
            raw := Ini(this.section, name "List", "")
            lists.%name% := raw ? StrSplit(raw, "|") : []
        }
        return { fields: fields, lists: lists }
    }

    increment(args) {
        name := args["gameName"]
        if RegExMatch(name, "^(.*?)(\d+)$", &m) {
            digits := m[2]
            padded := Format("{:0" StrLen(digits) "}", Integer(digits) + 1)
            return { gameName: m[1] padded }
        }
        return { gameName: name "1" }
    }

    host(args) {
        for name in HostEngine.FIELDS
            SetIni(args.Has(name) ? args[name] : "", this.section, name)
        return this.doHost(Integer(args["private"]))
    }

    hostSaved(private) {
        this.doHost(private)
    }

    doHost(private) {
        bot := Ini(this.section, "botName", "")
        trig := Ini(this.section, "trigger", "")
        game := Ini(this.section, "gameName", "")
        if !bot || !trig || !game {
            Push("toast", { kind: "error", msg: "Bot name, trigger and game name are required" })
            return { error: "missing fields" }
        }
        if !FocusWarcraft() {
            Push("toast", { kind: "error", msg: "Warcraft III not found" })
            return { error: "no wc3" }
        }
        HideMainWindow()
        exBefore := Ini(this.section, "exBefore", "")
        exAfter := Ini(this.section, "exAfter", "")
        lobby := private ? "priv" : "pub"
        if exBefore
            wc3Chat("/w " bot " " trig exBefore)
        wc3Chat("/w " bot " " trig lobby " " game)
        if exAfter
            wc3Chat("/w " bot " " trig exAfter)
        wc3Chat("Game Name: " game)
        this.remember()
        Push("toast", { kind: "ok", msg: "Hosting " (private ? "private" : "public") " lobby: " game })
        return { ok: 1 }
    }

    remember() {
        for name in HostEngine.FIELDS {
            val := Ini(this.section, name, "")
            if !val
                continue
            raw := Ini(this.section, name "List", "")
            list := raw ? StrSplit(raw, "|") : []
            if !ArrayItemExist(val, list*) {
                list.Push(val)
                SetIni(Join("|", list*), this.section, name "List")
            }
        }
    }
}
