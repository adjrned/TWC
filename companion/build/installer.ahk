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
;    Setup.exe /S           install silently (for updates), then start it
;    Uninstall.exe /uninstall
; ============================================================================
global VERSION := "{VERSION}"
global APP := "TW Companion"
global DIR := EnvGet("LOCALAPPDATA") "\Programs\" APP
global UNINST_KEY := "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\TWCompanion"
global silent := false

for a in A_Args {
    if a = "/uninstall"
        Uninstall(), ExitApp()
    if a = "/S"
        silent := true
}
if silent {
    Install(Ini("desktop", 0), true)
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
    try {
        DirCreate(DIR "\assets")
        DirCreate(DIR "\lib\WebView2\64bit")
        FileInstall("TW Companion\TW Companion.exe", DIR "\TW Companion.exe", 1)
        FileInstall("TW Companion\README.txt", DIR "\README.txt", 1)
        FileInstall("TW Companion\assets\bg.png", DIR "\assets\bg.png", 1)
        FileInstall("TW Companion\assets\Cinzel.ttf", DIR "\assets\Cinzel.ttf", 1)
        FileInstall("TW Companion\assets\Cinzel-OFL.txt", DIR "\assets\Cinzel-OFL.txt", 1)
        FileInstall("TW Companion\lib\WebView2\64bit\WebView2Loader.dll", DIR "\lib\WebView2\64bit\WebView2Loader.dll", 1)
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
Uninstall() {
    if MsgBox("Remove " APP " from this computer?`n`nYour settings and saves list in " DIR " go too. "
            . "Your Warcraft III save files are not touched.", APP, "YesNo Icon?") != "Yes"
        return
    if !CloseCompanion()
        return
    for lnk in [A_Programs "\" APP ".lnk", A_Desktop "\" APP ".lnk"]
        try FileDelete(lnk)
    try RegDeleteKey(UNINST_KEY)
    try DirDelete(EnvGet("APPDATA") "\tw-companion", true)       ; the overlay's browser cache
    ; this exe is in DIR: delete the folder once it has exited
    Run(A_ComSpec ' /c ping 127.0.0.1 -n 3 >nul & rmdir /s /q "' DIR '"', A_Temp, "Hide")   ; not from inside DIR
    MsgBox(APP " was removed.", APP)
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
