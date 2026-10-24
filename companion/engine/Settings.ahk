#Requires AutoHotkey v2.0
; ============================================================================
;  SettingsEngine - startup behaviour, load timing, reset.
; ============================================================================
class SettingsEngine {
    section := "Settings"
    static BOOLS := ["enableToolOnStart", "enableToolAfterLoad", "summonBagAfterLoad", "hideOnStart", "autoToggleTool"]

    get(args := 0) {
        out := {}
        for k in SettingsEngine.BOOLS
            out.%k% := Integer(Ini(this.section, k, k == "autoToggleTool" ? 1 : 0))
        out.loadDelay := Integer(Ini(this.section, "loadDelay", 200))
        out.postLoadDelay := Integer(Ini(this.section, "postLoadDelay", 1000))
        return out
    }

    set(args) {
        key := args["key"], value := args["value"]
        SetIni(value, this.section, key)
        if key == "loadDelay" || key == "postLoadDelay"
            SetKeyDelay(Integer(Ini(this.section, "keyDelay", 10)))
        return { ok: 1 }
    }

    reset(args := 0) {
        try FileDelete(iniFile)
        Reload
        return { ok: 1 }
    }
}
