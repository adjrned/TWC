; Keys macros' clicks and delays (engine\Macros.ahk, the hidden keys editor): the steps read and
; labelled, a click kept relative to the game window (a stand-in window here), the sequence sent in
; order with a delay's own wait (the send and the click swapped: no real input), the editor's
; + Delay. Nothing is clicked or pressed for real.
TwcMacrosRun() {
    global macros, macroKind, macroKeys, macroSel, macroDelayEdit
    TwcCheck(MacrosEngine.ClickStep("rclick:0.5000,0.2500", &r, &x, &y, &sc) && r && x = 0.5 && y = 0.25 && !sc
        && MacrosEngine.ClickStep("sclick:1024,768", &r2, &x2, &y2, &sc2) && !r2 && x2 = 1024 && sc2 && !MacrosEngine.ClickStep("q")
        && MacrosEngine.WaitStep("wait:250") = 250 && MacrosEngine.WaitStep("wait:999999") = 60000 && MacrosEngine.WaitStep("Numpad7") = -1,
        "steps read: a right click at 50%, 25% of the game window, a click at screen 1024, 768; a wait of 250 ms (a minute at most); keys aren't steps")
    TwcCheck(MacrosEngine.KeyLabel("click:0.5120,0.7330") = "Click 51%, 73%" && MacrosEngine.KeyLabel("srclick:10,20") = "Right-click 10, 20"
        && MacrosEngine.KeyLabel("wait:250") = "Wait 250 ms" && MacrosEngine.HasSteps(["q", "wait:5"]) && !MacrosEngine.HasSteps(["q", "w"]),
        "labels: '" MacrosEngine.KeyLabel("click:0.5120,0.7330") "', '" MacrosEngine.KeyLabel("srclick:10,20") "', '" MacrosEngine.KeyLabel("wait:250") "'")
    ; a stand-in game window at a known place (never activated; its pixels as the display scales them)
    g := Gui("+ToolWindow -Caption +E0x08000000", "TWC macro check window")
    g.Show("NA x200 y150 w400 h300")
    win := "ahk_id " g.Hwnd
    WinGetClientPos(&gx, &gy, &gw, &gh, win)
    inside := ClickStepFor(1, gx + gw // 4, gy + gh // 4, win), outside := ClickStepFor(0, gx - 50, gy + 10, win)
    TwcCheck(inside = "rclick:" Format("{:.4f}", (gw // 4) / gw) "," Format("{:.4f}", (gh // 4) / gh) && outside = "sclick:" (gx - 50) "," (gy + 10),
        "a click in the game window: kept as its spot in it ('" inside "'); outside it: a screen position ('" outside "')")
    ; the sequence: q, a click, a 200 ms wait, w (keyGap between the others)
    log := []
    keepSend := macros.sendFn, keepClick := macros.clickFn, keepWin := macros.win
    macros.sendFn := (t) => log.Push([A_TickCount, "key " t])
    macros.clickFn := (right, cx, cy) => log.Push([A_TickCount, (right ? "rclick " : "click ") cx "," cy])
    macros.win := win
    try macros.sendKeys(["q", "click:0.5000,0.5000", "wait:200", "w"])
    macros.sendFn := keepSend, macros.clickFn := keepClick, macros.win := keepWin
    got := ""
    for e in log
        got .= (got = "" ? "" : " | ") e[2]
    wantClick := "click " (gx + Round(gw / 2)) "," (gy + Round(gh / 2))
    waitedMs := log.Length = 3 ? log[3][1] - log[2][1] : 0
    TwcCheck(got = "key {q} | " wantClick " | key {w}" && waitedMs >= 180,
        "sent in order: " got " (the click at the window's middle; w " waitedMs " ms after the click: the delay's own wait)")
    g.Destroy()
    ; the editor's + Delay: on a keys macro being made, the box's ms as a step (kept for next time)
    keepKind := macroKind, keepKeys := macroKeys.Clone(), keepSel := macroSel
    macroSel := 0, macroKind := "keys", macroKeys := ["q"]
    macroDelayEdit.Value := 300
    err := ""
    try MacroAddDelay()
    catch as e
        err := e.Message
    lastStep := macroKeys.Length ? macroKeys[macroKeys.Length] : ""
    list := macros.list(), saved := list.Length ? list[list.Length] : 0
    TwcCheck(err = "" && lastStep = "wait:300" && Ini("MacroEditor", "delay", "") = 300 && saved && saved.text = "q wait:300" && saved.kind = "keys"
        && InStr(MacroStatus(), "steps, in order"), "+ Delay: 'wait:300' added and saved ('" (saved ? saved.text : "") "'), status '" MacroStatus() "'" (err != "" ? " (error: " err ")" : ""))
    if saved
        macros.delete(Map("index", list.Length))
    macroSel := keepSel, macroKind := keepKind, macroKeys := keepKeys
    TwcCheckDone()
}
SetTimer(TwcMacrosRun, -7000)
