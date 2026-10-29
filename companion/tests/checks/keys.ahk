; Key binding (KeyWaitCombo): with none of the companion's windows in front, a bind ends by itself
; at once with no key, and the slot keeps its key (a bind left open took keys pressed in a fight).
; No keys are sent and nothing is activated: it only runs while another program is in front.
TwcKeysRun() {
    global remap
    HideMainWindow(), Sleep(500)                 ; its own window away: the focus goes back where it was
    hw := WinExist("A")
    if hw && WinGetPID(hw) = DllCall("GetCurrentProcessId") {
        TwcCheck(true, "skipped: a companion window is in front (the check never takes the focus)")
        return TwcCheckDone()
    }
    t0 := A_TickCount, k := KeyWaitCombo(), ms := A_TickCount - t0
    TwcCheck(k = "" && keyCaptureCancelled && ms < 1000, "another program in front: the bind ends by itself with no key (" ms " ms)")
    before := remap.yourKey("card", 1)
    r := remap.capture()
    TwcCheck(r.key = "" && remap.yourKey("card", 1) = before, "the Remap page's capture: no key, the slot as it was ('" before "')")
    TwcCheck(macros.capture().hotkey = "", "a macro's: no key")
    TwcCheckDone()
}
SetTimer(TwcKeysRun, -7000)
