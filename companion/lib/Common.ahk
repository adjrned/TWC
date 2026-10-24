#Requires AutoHotkey v2.0
; ============================================================================
;  Common.ahk - shared globals and helpers for TW Companion.
;  UI lives in WebView2; this file is pure engine plumbing (no GUI controls).
; ============================================================================

global iniFile     := A_ScriptDir "\tw-companion.ini"
global WarcraftIII := "Warcraft III"
global ihGlobal    := InputHook("V", "{Esc}")

; ---- INI helpers -----------------------------------------------------------
Ini(section, key, default := "") => IniRead(iniFile, section, key, default)
SetIni(value, section, key) => IniWrite(value, iniFile, section, key)

; ---- input capture ---------------------------------------------------------
KeyWaitAny() {
    ihGlobal.VisibleNonText := false
    ihGlobal.KeyOpt("{All}", "E")
    ihGlobal.Start()
    ihGlobal.Wait()
    return ihGlobal.EndKey
}

KeyWaitCombo() {
    ihGlobal.VisibleNonText := false
    ihGlobal.KeyOpt("{All}", "E")
    ihGlobal.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-E")
    ihGlobal.Start()
    ihGlobal.Wait()
    return ihGlobal.EndMods . ihGlobal.EndKey
}

; ---- hotkey display --------------------------------------------------------
ReadableHotkey(hotkey, fullName := false) {
    if !hotkey
        return ""
    ; "^+Space" -> "Ctrl+Shift+Space", "<!f5" -> "LAlt+F5"
    sideMap := Map("<", "L", ">", "R")
    shortMap := Map("#", "Win+", "!", "Alt+", "^", "Ctrl+", "+", "Shift+")
    hotkey := StrReplace(StrReplace(StrReplace(hotkey, "$"), "~"), "*")
    mods := "", side := "", i := 1
    while i < StrLen(hotkey) && InStr("<>#!^+", ch := SubStr(hotkey, i, 1)) {
        if sideMap.Has(ch)
            side := sideMap[ch]
        else
            mods .= side shortMap[ch], side := ""
        i++
    }
    key := SubStr(hotkey, i)
    key := StrLen(key) = 1 || RegExMatch(key, "i)^F\d+$") ? StrUpper(key) : StrUpper(SubStr(key, 1, 1)) StrLower(SubStr(key, 2))
    return mods key
}

; ---- misc helpers ----------------------------------------------------------
SelectFolder() => DirSelect(, 0)

ArrayItemExist(item, params*) {
    for _, p in params
        if p == item
            return true
    return false
}

Join(sep, params*) {
    if !params || params.Length == 0
        return ""
    str := ""
    for _, p in params
        str .= p . sep
    return SubStr(str, 1, -StrLen(sep))
}

; ---- warcraft chat ---------------------------------------------------------
; one SendInput per line, so nothing you press can land in the middle of it
wc3Chat(text) {
    SendInput("{Enter}" RegExReplace(text, "[\^!+#{}]", "{$0}") "{Enter}")
}

FocusWarcraft() {
    if WinExist(WarcraftIII) {
        WinActivate(WarcraftIII)
        return true
    }
    return false
}

; ============================================================================
;  RegisterHotkey - self-managing hotkey binding.
;  gated=true  -> active only while the master tool toggle is ON (gameplay).
;  gated=false -> active whenever enabled (control binds).
; ============================================================================
class RegisterHotkey {
    key := ""
    fn := ""
    win := ""
    enable := false
    gated := true

    __New(key := "", fn := "", win := "", enable := false, gated := true) {
        this.key := key ? "*" . key : ""
        this.fn := fn
        this.win := win
        this.enable := enable
        this.gated := gated
        if key
            this.refresh()
    }

    refresh() {
        global toolEnabled
        if !this.key
            return
        active := this.enable && (!this.gated || toolEnabled)
        HotIfWinActive(this.win)
        cb := (*) => this.fn.Call()
        try Hotkey(this.key, cb, active ? "On" : "Off")
        HotIfWinActive()
    }
}
