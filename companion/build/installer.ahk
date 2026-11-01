#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-SetName TW Companion Setup
;@Ahk2Exe-SetDescription TW Companion Setup
;@Ahk2Exe-SetCopyright By Ruzai
; ============================================================================
;  TW Companion installer (and uninstaller). build.ps1 copies this next to the
;  staged "TW Companion" folder, fills in the version and compiles it, so the
;  FileInstall paths below are relative to dist\.
;  Per user, no admin: %LOCALAPPDATA%\Programs\TW Companion, Start Menu (and
;  optionally desktop) shortcut, an Apps & features entry. Installing over an
;  older version keeps tw-companion.ini and HiddenFiles.txt.
;    Setup.exe              install (window)
;    Setup.exe /S           install silently (for updates), then start it (/nostart: not)
;    Uninstall.exe /uninstall       (/S: no questions)
;  The uninstaller can't delete the folder it runs from (the user, 2026-10-31: "the uninstaller didn't work":
;  it ran rmdir 2 s later from Uninstall.exe inside the folder, which its own "was removed" box kept open),
;  so it runs a copy of itself from %TEMP% (/uninstall-temp), which removes the folder and then itself.
; ============================================================================
global VERSION := "{VERSION}"
global APP := "TW Companion"
global DIR := EnvGet("LOCALAPPDATA") "\Programs\" APP
global UNINST_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\TWCompanion"
global silent := false, noStart := false, uninstallArg := ""

for a in A_Args {
    if a = "/uninstall" || a = "/uninstall-temp"
        uninstallArg := a
    if a = "/S"
        silent := true
    if a = "/nostart"
        noStart := true
}
if uninstallArg != "" {
    Uninstall(uninstallArg = "/uninstall-temp")
    ExitApp
}
if silent {
    Install(Ini("desktop", 0), !noStart)
    ExitApp
}
ShowWindow()

; ---- the window, in the companion's colours ---------------------------------
ShowWindow() {
    global g, deskCb, runCb
    card := "14161B", text := "E6E4DF", muted := "9A9EAA", accent := "F5A623"
    g := Gui("-MinimizeBox", APP " " VERSION " setup")
    g.BackColor := card
    g.MarginX := 26, g.MarginY := 22
    ; each font is set before its control, so the control is sized for it
    g.SetFont("s16 w700", "Segoe UI")
    g.AddText("w440 c" text, APP)
    g.SetFont("s9 w600", "Segoe UI")
    g.AddText("w440 y+2 c" accent, "Version " VERSION)
    upgrading := FileExist(DIR "\" APP ".exe")
    info := (upgrading ? "Updates the installed copy in" : "Installs to") ":`n" DIR
        . (upgrading ? "`nYour settings, saves list and Quickcast Setup are kept." : "")
    g.SetFont("s9 w400", "Segoe UI")
    g.AddText("w440 y+14 c" muted, info)
    g.SetFont("s10 w400", "Segoe UI")
    deskCb := g.AddCheckbox("w440 y+16 c" text " Checked" Ini("desktop", 1), " Desktop shortcut")
    runCb := g.AddCheckbox("w440 y+8 c" text " Checked", " Start TW Companion when done")
    g.SetFont("s8 w400", "Segoe UI")
    g.AddText("w440 y+16 c" muted, "Warcraft III should run in Windowed Fullscreen (or windowed). "
        . "Windows asks for admin rights each time the companion starts: it needs them to send keys to Warcraft III.")
    g.SetFont("s9 w400", "Segoe UI")
    ok := g.AddButton("y+18 w130 h32 Default", upgrading ? "Update" : "Install")
    no := g.AddButton("x+10 w100 h32", "Cancel")
    ok.OnEvent("Click", (*) => (Install(deskCb.Value, runCb.Value), ExitApp()))
    no.OnEvent("Click", (*) => ExitApp())
    g.OnEvent("Close", (*) => ExitApp())
    g.Show()
}

; ---- install -------------------------------------------------------------------
Install(desktop, start) {
    if !CloseCompanion()
        return
    try FileDelete(A_Temp "\TWC-Uninstall.exe")          ; (an uninstaller's copy that couldn't delete itself)
    try {
        DirCreate(DIR "\assets")
        DirCreate(DIR "\lib\WebView2\64bit")
        DirCreate(DIR "\native")
        FileInstall("TW Companion\TW Companion.exe", DIR "\TW Companion.exe", 1)
        FileInstall("TW Companion\README.txt", DIR "\README.txt", 1)
        FileInstall("TW Companion\assets\bg.png", DIR "\assets\bg.png", 1)
        FileInstall("TW Companion\assets\bg@125.png", DIR "\assets\bg@125.png", 1)
        FileInstall("TW Companion\assets\bg@150.png", DIR "\assets\bg@150.png", 1)
        FileInstall("TW Companion\assets\bg@175.png", DIR "\assets\bg@175.png", 1)
        FileInstall("TW Companion\assets\bg@200.png", DIR "\assets\bg@200.png", 1)
        FileInstall("TW Companion\assets\Cinzel.ttf", DIR "\assets\Cinzel.ttf", 1)
        FileInstall("TW Companion\assets\Cinzel-OFL.txt", DIR "\assets\Cinzel-OFL.txt", 1)
        FileInstall("TW Companion\lib\WebView2\64bit\WebView2Loader.dll", DIR "\lib\WebView2\64bit\WebView2Loader.dll", 1)
        FileInstall("TW Companion\native\twc-game.dll", DIR "\native\twc-game.dll", 1)
        FileInstall("TW Companion\native\twc-inject.exe", DIR "\native\twc-inject.exe", 1)
        FileInstall("TW Companion\lib\WebView2\LICENSE-Microsoft.txt", DIR "\lib\WebView2\LICENSE-Microsoft.txt", 1)
        FileInstall("TW Companion\lib\WebView2\LICENSE-thqby.txt", DIR "\lib\WebView2\LICENSE-thqby.txt", 1)
        ; the uninstaller is this program, run with /uninstall
        if A_IsCompiled && A_ScriptFullPath != DIR "\Uninstall.exe"
            FileCopy(A_ScriptFullPath, DIR "\Uninstall.exe", 1)
    } catch as e {
        if !silent
            MsgBox("Couldn't install: " e.Message, APP " setup", "Icon!")
        return
    }
    exe := DIR "\" APP ".exe"
    FileCreateShortcut(exe, A_Programs "\" APP ".lnk", DIR, , APP)
    lnk := A_Desktop "\" APP ".lnk"
    if desktop
        FileCreateShortcut(exe, lnk, DIR, , APP)
    else if FileExist(lnk)
        FileDelete(lnk)
    SetIni("desktop", desktop)
    ; Apps & features
    RegWrite(APP, "REG_SZ", UNINST_KEY, "DisplayName")
    RegWrite(VERSION, "REG_SZ", UNINST_KEY, "DisplayVersion")
    RegWrite("Ruzai", "REG_SZ", UNINST_KEY, "Publisher")
    RegWrite(exe, "REG_SZ", UNINST_KEY, "DisplayIcon")
    RegWrite(DIR, "REG_SZ", UNINST_KEY, "InstallLocation")
    RegWrite('"' DIR '\Uninstall.exe" /uninstall', "REG_SZ", UNINST_KEY, "UninstallString")
    RegWrite(1, "REG_DWORD", UNINST_KEY, "NoModify")
    RegWrite(1, "REG_DWORD", UNINST_KEY, "NoRepair")
    if start
        Run('"' exe '"', DIR)
    else if !silent
        MsgBox(APP " " VERSION " is installed. Start it from the Start Menu" (desktop ? " or the desktop" : "") ".", APP " setup")
}

; ---- uninstall -------------------------------------------------------------------
; fromTemp: this is the copy in %TEMP% (the one in DIR handed over to it); it removes everything, then itself
Uninstall(fromTemp := false) {
    if !fromTemp && A_IsCompiled && InStr(A_ScriptFullPath, DIR "\") = 1 {
        tmp := A_Temp "\TWC-Uninstall.exe"
        try {
            FileCopy(A_ScriptFullPath, tmp, 1)
            Run('"' tmp '" /uninstall-temp' (silent ? " /S" : ""), A_Temp)
            return
        }
        ; (no copy: carry on from here; the folder goes after this exits)
    }
    if !silent && MsgBox("Remove " APP " from this computer?`n`nYour settings and saves list in " DIR " go too. "
            . "Your Warcraft III save files are not touched.", APP, "YesNo Icon?") != "Yes"
        return
    if !CloseCompanion() || !CloseGame()
        return
    for lnk in [A_Programs "\" APP ".lnk", A_Desktop "\" APP ".lnk"]
        try FileDelete(lnk)
    try RegDeleteKey(UNINST_KEY)
    ; the folder (and the overlay's browser cache): a few tries, the overlay's browser processes let go of their
    ; files a moment after the companion's gone
    left := []
    for d in [DIR, EnvGet("APPDATA") "\tw-companion"] {
        if InStr(A_ScriptFullPath, d "\") = 1          ; (no copy in %TEMP%: this exe is still in it)
            continue
        loop 10 {
            try DirDelete(d, true)
            if !DirExist(d)
                break
            Sleep(500)
        }
        if DirExist(d)
            left.Push(d)
    }
    ; what's left of this exe once it has exited: through cmd, which may not be allowed to start (an antivirus or
    ; app control: "Access is denied", the old uninstaller's whole removal hung on it); a copy left in %TEMP% is
    ; harmless, and the next Setup deletes it
    if InStr(A_ScriptFullPath, DIR "\") = 1 {          ; not from %TEMP%: the folder too
        try Run(A_ComSpec ' /c ping 127.0.0.1 -n 3 >nul & rmdir /s /q "' DIR '"', A_Temp, "Hide")
        catch
            left.Push(DIR)
    } else if fromTemp
        try Run(A_ComSpec ' /c ping 127.0.0.1 -n 3 >nul & del /f /q "' A_ScriptFullPath '"', A_Temp, "Hide")
    if !silent
        MsgBox(left.Length ? APP " was removed, but some files are still in use and stayed:`n`n" Join(left, "`n")
            . "`n`nDelete them by hand after restarting Windows." : APP " was removed.", APP, left.Length ? "Icon!" : "")
}
Join(list, sep) {
    t := ""
    for v in list
        t .= (A_Index > 1 ? sep : "") v
    return t
}
; Warcraft III with the game module loaded keeps its copy (native\twc-game.*.dll) open: then ask to quit it
CloseGame() {
    loop {
        running := false
        for exe in ["Warcraft III.exe", "war3.exe"]
            running := running || ProcessExist(exe)
        if !running || silent
            return true
        r := MsgBox("Warcraft III is running and may keep a file of " APP " open (its game module). Quit Warcraft III, then press Retry.`n`n"
            . "Or press Ignore to remove the rest now.", APP, "AbortRetryIgnore Icon!")
        if r = "Abort"
            return false
        if r = "Ignore"
            return true
    }
}

; A running companion keeps its exe locked. It runs as admin, so this (normal
; rights) program may not be allowed to close it: then ask.
CloseCompanion() {
    loop {
        loop 10 {
            if !ProcessExist(APP ".exe")
                return true
            try ProcessClose(APP ".exe")
            Sleep(300)
        }
        if silent || MsgBox(APP " is still running. Quit it (Alt+Esc, or right-click its tray icon > Exit), then press Retry.",
                APP " setup", "RetryCancel Icon!") != "Retry"
            return false
    }
}

; installer choices, kept in the registry next to the Apps & features entry
Ini(name, default) {
    try return RegRead(UNINST_KEY, "Setup_" name)
    return default
}
SetIni(name, value) => RegWrite(value, "REG_SZ", UNINST_KEY, "Setup_" name)
