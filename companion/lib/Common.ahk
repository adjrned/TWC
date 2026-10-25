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
; while waiting for a key (and briefly after), Esc is an answer, not "hide"
global keyCapturing := false, keyCaptureEnd := 0
KeyCaptureActive() => keyCapturing || A_TickCount - keyCaptureEnd < 400

KeyWaitAny() {
    global keyCapturing := true, keyCaptureEnd
    ihGlobal.VisibleNonText := false
    ihGlobal.KeyOpt("{All}", "E")
    ihGlobal.Start()
    try ihGlobal.Wait()
    finally keyCapturing := false, keyCaptureEnd := A_TickCount
    return ihGlobal.EndKey
}

; A key or combo, or one of the extra mouse buttons (an InputHook only sees the
; keyboard, so those are caught by hotkeys while it waits). Left and right
; click are never taken: they're how you click.
KeyWaitCombo() {
    global keyCapturing := true, keyCaptureEnd, capturedMouse := ""
    ihGlobal.VisibleNonText := false
    ihGlobal.KeyOpt("{All}", "E")
    ihGlobal.KeyOpt("{LCtrl}{RCtrl}{LAlt}{RAlt}{LShift}{RShift}{LWin}{RWin}", "-E")
    CaptureMouse(true)
    ihGlobal.Start()
    try ihGlobal.Wait()
    finally {
        CaptureMouse(false)
        keyCapturing := false, keyCaptureEnd := A_TickCount
    }
    if capturedMouse
        return (GetKeyState("Ctrl") ? "^" : "") (GetKeyState("Alt") ? "!" : "") (GetKeyState("Shift") ? "+" : "") capturedMouse
    return ihGlobal.EndMods . ihGlobal.EndKey
}
global capturedMouse := ""
CaptureMouse(on) {
    HotIf()                                     ; anywhere (capture happens in the companion window)
    for k in MouseKeys()
        try Hotkey("*" k, CaptureMouseHit.Bind(k), on ? "On" : "Off")
}
CaptureMouseHit(k, *) {
    global capturedMouse := k
    ihGlobal.Stop()
}
MouseKeys() => ["XButton1", "XButton2", "MButton", "WheelUp", "WheelDown", "WheelLeft", "WheelRight"]
IsWheel(key) => RegExMatch(key, "i)Wheel(Up|Down|Left|Right)$")

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
    static names := Map("xbutton1", "Mouse 4", "xbutton2", "Mouse 5", "mbutton", "Middle click",
        "wheelup", "Wheel up", "wheeldown", "Wheel down", "wheelleft", "Wheel left", "wheelright", "Wheel right")
    if names.Has(StrLower(key))
        return mods names[StrLower(key)]
    key := StrLen(key) = 1 || RegExMatch(key, "i)^F\d+$") ? StrUpper(key) : StrUpper(SubStr(key, 1, 1)) StrLower(SubStr(key, 2))
    return mods key
}

; ---- misc helpers ----------------------------------------------------------
; Game keys from remaps, quickcast and keys macros. 1.28 can ignore a sent
; Numpad 4 (Item 3) while it takes the other five item keys; the same key
; posted to its window gets through, so that one goes that way there.
; [Remap] postItem3=0 sends it like the others.
SendGameKeys(keys) {
    if InStr(keys, "{Numpad4}") && InStr(WC3WindowKey(), "classic") && Integer(Ini("Remap", "postItem3", 1)) {
        ControlSend(keys, , WarcraftIII)
        return "posted"
    }
    SendInput(keys)
    return "sent"
}

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
; Each game version has its own way, since the companion can tell them apart:
;  1.28      one SendInput per line (Enter, text, Enter), so nothing you press
;            can land in the middle of it. Works smoothly.
;  Reforged  opens its chat box 15-50 ms after Enter and loses what's typed
;            before, and fast Shift key presses don't take (capitals and #$%&@?
;            in load codes come out wrong). So: Enter, wait for the box on
;            screen, then the text in {Text} mode (the characters themselves,
;            no Shift; as in LCH's loader, github.com/Lch3181/Warcraft-lll_TWrpg_AHKs,
;            MIT), Enter, and wait for the box to close before the next line.
wc3Chat(text) {
    if InStr(WC3WindowKey(), "reforged")
        return wc3ChatReforged(text)
    SendInput("{Enter}" RegExReplace(text, "[\^!+#{}]", "{$0}") "{Enter}")
}
wc3ChatReforged(text) {
    global chatBox
    g := IsSet(chatBox) && chatBox ? chatBox.current() : 0
    SendInput("{Enter}")
    t := A_TickCount
    while A_TickCount - t < 300 && !(g && chatBox.isOpen(g))
        Sleep(10)
    opened := A_TickCount - t
    Sleep(g ? 30 : 200)                     ; let its text field take focus (no box known: just wait)
    SendInput("{Text}" text)
    Sleep(30)
    global debugGui
    if IsSet(debugGui) && debugGui          ; tray Debug on: keep what the box shows (chat-*.bmp)
        try ChatBoxSnapshot(g)
    SendInput("{Enter}")
    t := A_TickCount
    while A_TickCount - t < 200 && g && chatBox.isOpen(g)
        Sleep(10)
    try DebugLog("chat line (Reforged): box " (!g ? "position unknown" : opened < 300 ? "open after " opened " ms" : "NOT SEEN in 300 ms")
        . ", closed after " (A_TickCount - t) " ms: " SubStr(text, 1, 12) "…")
}

; Save the chat box as it looks now to chat-<time>.bmp next to the debug log,
; to see what Reforged actually received. Kept to the last 20.
ChatBoxSnapshot(g) {
    if !g || !WinExist(WarcraftIII)
        return
    WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
    x := Round(wx + g.l * cw) - 4, y := Round(wy + g.t * ch) - 4
    w := Round((g.r - g.l) * cw) + 9, h := Round((g.b - g.t) * ch) + 9
    s := ScreenGrab(x, y, w, h)
    dir := A_ScriptDir "\debug"
    DirCreate(dir)
    files := []
    loop files dir "\chat-*.bmp"
        files.Push(A_LoopFileFullPath)
    while files.Length >= 20
        FileDelete(files.RemoveAt(1))
    ; a bottom-up 32-bit BMP: 14-byte file header, 40-byte info header, pixels
    size := w * h * 4, bmp := Buffer(54 + size, 0)
    NumPut("ushort", 0x4D42, "uint", 54 + size, "uint", 0, "uint", 54, bmp)
    NumPut("uint", 40, "int", w, "int", h, "ushort", 1, "ushort", 32, bmp, 14)
    loop h
        DllCall("RtlMoveMemory", "ptr", bmp.Ptr + 54 + (A_Index - 1) * w * 4, "ptr", s.buf.Ptr + (h - A_Index) * w * 4, "uptr", w * 4)
    f := FileOpen(dir "\chat-" FormatTime(, "HHmmss") "-" A_MSec ".bmp", "w")
    f.RawWrite(bmp), f.Close()
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
        global chatting, inGame, qcCalibrating
        live := toolEnabled && !(IsSet(chatting) && chatting) && (!IsSet(inGame) || inGame)
            && !(IsSet(qcCalibrating) && qcCalibrating)
        active := this.enable && (!this.gated || live)
        HotIfWinActive(this.win)
        cb := (*) => this.fn.Call()
        try Hotkey(this.key, cb, active ? "On" : "Off")
        HotIfWinActive()
    }
}
