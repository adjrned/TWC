; The host bots (engine\Host.ahk): leebot the only one it comes with; a bot picked before the list was cut is kept
; as one you added (deletable). The Settings page's overlay key, and the tray menu (2026-10-31).
TwcHostRun() {
    global host, setOvKeyBtn, webOverlay, trayDebug
    for k in ["botName", "botNameList"]
        try IniDelete(iniFile, host.section, k)
    b0 := host.bots(), s0 := host.selected
    TwcCheck(b0.Length = 1 && b0[1] = "leebot" && s0 = "leebot" && host.isKnown("leebot"), "fresh: only leebot, selected")
    IniWrite("geybot", iniFile, host.section, "botName")
    s1 := host.selected, b1 := host.bots()
    TwcCheck(s1 = "geybot" && b1.Length = 2 && b1[2] = "geybot" && !host.isKnown("geybot"), "geybot picked before: kept, as a bot you added")
    host.removeBot("geybot")
    TwcCheck(host.selected = "leebot" && host.bots().Length = 1, "removed: back to leebot")
    for k in ["botName", "botNameList"]
        try IniDelete(iniFile, host.section, k)
    ShowPage("settings")
    TwcCheck(setOvKeyBtn.Text = ReadableHotkey(webOverlay.get().hotkey), "Settings: the overlay key shown (" setOvKeyBtn.Text ")")
    ; the open / hide key: F8 by default, settable; the key it's set to is refused for macros / remaps
    global remap, setShowKeyBtn
    f8 := ShowKey() = "F8" && remap.reserved("F8") != "" && setShowKeyBtn.Text = "F8"
    IniWrite("F9", iniFile, "Settings", "showKey"), ApplyShowKey(), RefreshSettings()
    f9 := setShowKeyBtn.Text = "F9" && InStr(remap.reserved("F9"), "open / hide") && remap.reserved("F8") = ""
    IniDelete(iniFile, "Settings", "showKey"), ApplyShowKey(), RefreshSettings()
    TwcCheck(f8 && f9 && setShowKeyBtn.Text = "F8", "the open / hide key: F8 by default; set to F9, F9 is taken and F8 free; back to F8")
    items := ""
    loop DllCall("GetMenuItemCount", "ptr", A_TrayMenu.Handle) {
        buf := Buffer(256 * 2, 0)
        DllCall("GetMenuStringW", "ptr", A_TrayMenu.Handle, "uint", A_Index - 1, "ptr", buf, "int", 256, "uint", 0x400)
        items .= (A_Index > 1 ? "|" : "") StrGet(buf)
    }
    TwcCheck(items = "Open TW Companion|Open the TWRPG overlay||Check for updates|Debug||Exit" && A_TrayMenu.ClickCount = 1,
        "the tray menu: " items "; a click opens the companion")
    TwcCheckDone()
}
SetTimer(TwcHostRun, -6000)
