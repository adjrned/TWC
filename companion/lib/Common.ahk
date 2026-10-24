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
    sideMap := Map("<", "L", ">", "R")
    shortMap := Map("#", "Win+", "!", "Alt+", "^", "Ctrl+", "+", "Shift+")
    hotkey := StrUpper(hotkey)
    hotkey := StrReplace(hotkey, "$", "")
    hotkey := StrReplace(hotkey, "~", "")
    hotkey := StrReplace(hotkey, "*", "")
    for k, v in sideMap
        hotkey := StrReplace(hotkey, k, v)
    for k, v in shortMap {
        replaced := StrReplace(hotkey, k, v)
        if replaced != hotkey {
            hotkey := replaced
            break
        }
    }
    return hotkey
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
wc3Chat(text) {
    SendInput("{Enter}")
    SendInput("{Text}" text)
    SendInput("{Enter}")
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
