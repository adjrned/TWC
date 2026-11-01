; The companion starts and runs its timers for 8 s without an error (/validate
; only catches load-time errors; a local shadowing a global only shows here).
TwcStartupDone() {
    try a := WinGetTitle("A")
    catch
        a := "(none)"
    TwcCheck(IsSet(mainGui) && mainGui.Hwnd, "started, ran 8 s (active window: " a ")")
    TwcCheckDone()
}
SetTimer(TwcStartupDone, -8000)
