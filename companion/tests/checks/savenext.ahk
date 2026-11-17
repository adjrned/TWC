; -sn's save watch (LoaderEngine.watchSave, 2026-11-16): the file written in time = kept as the save to
; continue from; none = -ll / -sn back on the save before. And the chat guard (ChatGuard): a chat line
; with the game not in front throws WC3FocusLost before any key, and a macro stops on it.
; Never sends a key: the watch is driven directly (not through -sn), and the guard part only runs
; while Warcraft III is NOT the window in front (then the guard throws before the first SendInput).
TwcSaveNextRun() {
    global loader, macros
    dir := A_Temp "\twc-check-savenext"
    try DirDelete(dir, true)
    DirCreate(dir)
    keepFolder := Ini(loader.section, "folder", ""), keepSel := Ini(loader.section, "selectedFile", "")
    keepLast := loader.sessionLast, keepWait := LoaderEngine.SAVE_WAIT
    SetIni(dir, loader.section, "folder")
    LoaderEngine.SAVE_WAIT := 1500
    err := ""
    try {
        ; written 400 ms in: stays the save to continue from
        SetIni("knight#92.txt", loader.section, "selectedFile"), loader.sessionLast := "knight#92.txt"
        SetIni("knight#93.txt", loader.section, "selectedFile"), loader.sessionLast := "knight#93.txt"
        loader.watchSave("knight#93.txt", "knight#92.txt", "knight#92.txt")
        Sleep(400)
        FileAppend("----------Hero Inventory----------`n-load abc`n", dir "\knight#93.txt", "UTF-8")
        Sleep(2000)
        a := [Ini(loader.section, "selectedFile", ""), loader.sessionLast]
        ; never written: back to #93
        SetIni("knight#94.txt", loader.section, "selectedFile"), loader.sessionLast := "knight#94.txt"
        loader.watchSave("knight#94.txt", "knight#93.txt", "knight#93.txt")
        Sleep(2000)
        b := [Ini(loader.section, "selectedFile", ""), loader.sessionLast]
        ; never written, but another load came since: that one stays
        SetIni("knight#95.txt", loader.section, "selectedFile"), loader.sessionLast := "knight#95.txt"
        loader.watchSave("knight#95.txt", "knight#93.txt", "knight#93.txt")
        Sleep(300)
        SetIni("sniper.txt", loader.section, "selectedFile"), loader.sessionLast := "sniper.txt"
        Sleep(1800)
        c := [Ini(loader.section, "selectedFile", ""), loader.sessionLast]
    } catch as e
        err := e.Message
    if keepFolder != ""
        SetIni(keepFolder, loader.section, "folder")
    else
        try IniDelete(iniFile, loader.section, "folder")
    if keepSel != ""
        SetIni(keepSel, loader.section, "selectedFile")
    else
        try IniDelete(iniFile, loader.section, "selectedFile")
    loader.sessionLast := keepLast, LoaderEngine.SAVE_WAIT := keepWait
    try DirDelete(dir, true)
    TwcCheck(err = "" && a[1] = "knight#93.txt" && a[2] = "knight#93.txt", "-sn written: -ll / -sn stay on " a[1] " / " a[2] (err != "" ? " (error: " err ")" : ""))
    TwcCheck(err = "" && b[1] = "knight#93.txt" && b[2] = "knight#93.txt", "-sn never written: back to " b[1] " / " b[2])
    TwcCheck(err = "" && c[1] = "sniper.txt" && c[2] = "sniper.txt", "-sn never written, a load since: that one kept (" c[1] " / " c[2] ")")

    ; the chat guard: only with the game not in front (else skipped: a key could go out)
    if WinActive(WarcraftIII) {
        TwcCheck(true, "chat guard: skipped (a Warcraft III window is in front)")
        return TwcCheckDone()
    }
    threw := ""
    try wc3Chat("-twc check: never sent")
    catch WC3FocusLost
        threw := "WC3FocusLost"
    catch as e
        threw := Type(e) ": " e.Message
    macroErr := ""
    try macros.sendLines(["-twc check: never sent"])
    catch as e
        macroErr := e.Message
    TwcCheck(threw = "WC3FocusLost" && macroErr = "", "chat guard: a line with the game not in front threw " threw "; a macro stopped on it" (macroErr != "" ? " (it threw: " macroErr ")" : ""))
    TwcCheckDone()
}
SetTimer(TwcSaveNextRun, -6000)
