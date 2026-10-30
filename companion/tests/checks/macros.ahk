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
    ; from the mouse: the steps read, labelled, checked
    TwcCheck(MacrosEngine.RelStep("rclick@-85,80", &k, &dx, &dy) && k = "rclick" && dx = -85 && dy = 80 && MacrosEngine.KeyLabel("move@-28,27") = "Move mouse -28, 27"
        && MacrosEngine.ValidStep("^1") && MacrosEngine.ValidStep("Numpad7") && MacrosEngine.ValidStep("wait:3") && !MacrosEngine.ValidStep("bogus") && !MacrosEngine.ValidStep("click@x,1"),
        "from the mouse: 'rclick@-85,80' read, 'Move mouse -28, 27'; ^1, Numpad7, wait:3 are steps, 'bogus' and 'click@x,1' aren't")
    steps := MacroTextSteps("e wait:75`n move@-28,27  rclick@-85,80`nbogus", &bad)
    TwcCheck(steps.Length = 4 && steps[3] = "move@-28,27" && bad.Length = 1 && bad[1] = "bogus", "text: 4 steps (lines or spaces), 'bogus' named as not a step")
    ; the sequence from the mouse (moves and clicks swapped): measured from where it is, no gap before mouse steps, a cancel
    log := [], keepSend := macros.sendFn
    macros.sendFn := (t) => log.Push([A_TickCount, "key " t])
    macros.mouseFn := (kind, mx, my) => log.Push([A_TickCount, kind " " mx "," my])
    try macros.sendKeys(["e", "wait:30", "move@-28,27", "rclick@-85,80", "rclick@-83,80", "wait:40", "q"])
    got := ""
    for e in log
        got .= (got = "" ? "" : " | ") e[2]
    ax := 0, ay := 0                ; where the mouse was as it started (the first move is 28 left, 27 down of it)
    if log.Length >= 2 && RegExMatch(log[2][2], "(-?\d+),(-?\d+)", &mm)
        ax := mm[1] + 28, ay := mm[2] - 27
    want := "key {e} | move " (ax - 28) "," (ay + 27) " | rclick " (ax - 85) "," (ay + 80) " | rclick " (ax - 83) "," (ay + 80) " | key {q}"
    tight := log.Length = 5 ? log[4][1] - log[3][1] : 999
    TwcCheck(got = want && tight < 10 && !macros.running, "from the mouse: " got " (the two clicks " tight " ms apart: no gap)")
    log := []
    macros.mouseFn := (kind, mx, my) => (log.Push([A_TickCount, kind]), log.Length = 2 ? macros.cancel() : 0)
    try macros.sendKeys(["move@1,1", "move@2,2", "wait:500", "move@3,3", "q"])
    TwcCheck(log.Length = 2 && !macros.running && macros.cancelled, "a right click mid-way (cancel): the steps after it don't run (" log.Length " done)")
    ; the speed (the user: far slower than the same steps alone): a 50-step combo while a timer that takes
    ; 40 ms runs every 30 ms (as the companion's): critical, it isn't stretched (its waits' own time only)
    combo := StrSplit("e wait:75 move@-29,26 wait:3 move@-57,53 wait:3 move@-85,80 wait:3 rclick@-85,80 rclick@-83,80 wait:85 move@-17,36 wait:3 move@51,-7 wait:3 move@120,-50 wait:3 rclick@120,-50 rclick@122,-50 wait:155 move@38,-38 wait:3 move@-44,-26 wait:3 move@-126,-14 wait:3 rclick@-126,-14 rclick@-124,-14 wait:155 move@-54,24 wait:3 move@18,62 wait:3 move@90,100 wait:3 rclick@90,100 rclick@92,100 wait:155 move@60,25 wait:3 move@30,-50 wait:3 move@0,-125 wait:3 rclick@0,-125 rclick@2,-125 wait:135 move@0,0 wait:100 rclick@0,0", " ")
    budget := 0, n3 := 0
    for t in combo
        if (ms := MacrosEngine.WaitStep(t)) >= 0
            budget += ms, n3 += ms <= 20
    macros.mouseFn := (kind, mx, my) => 0
    busy := { n: 0 }
    hog() {
        busy.n++
        hogFrom := A_TickCount              ; (its own name: a nested function shares the outer's variables)
        while A_TickCount - hogFrom < 40
            continue
    }
    SetTimer(hog, 30), Sleep(100), before := busy.n
    t0 := A_TickCount
    macros.sendKeys(combo)
    took := A_TickCount - t0, during := busy.n - before
    SetTimer(hog, 0)
    TwcCheck(took <= budget + n3 * 16 + 80 && during <= 1, "the combo took " took " ms with a busy timer every 30 ms (its waits " budget " ms, " n3 " short ones; the timer ran " during " times meanwhile)")
    macros.sendFn := keepSend, macros.mouseFn := 0
    ; Edit as text's Save: valid text becomes the macro's steps; a bad one is named and nothing changes
    macroSel := 0, macroKind := "keys", macroKeys := []
    gone := { n: 0 }
    fakeG := { Destroy: (*) => gone.n++ }, ed := { Value: "e wait:75 move@-28,27 rclick@-85,80" }, errBox := { Text: "" }
    MacroTextSave(fakeG, ed, errBox)
    okSave := macroKeys.Length = 4 && macroKeys[4] = "rclick@-85,80" && gone.n = 1 && errBox.Text = ""
    ed.Value := "e nope", MacroTextSave(fakeG, ed, errBox)
    TwcCheck(okSave && InStr(errBox.Text, "nope") && macroKeys.Length = 4 && gone.n = 1, "Edit as text: saved as 4 steps; 'nope' refused ('" errBox.Text "')")
    list := macros.list()
    if list.Length && list[list.Length].text = "e wait:75 move@-28,27 rclick@-85,80"
        macros.delete(Map("index", list.Length))
    macroSel := keepSel, macroKind := keepKind, macroKeys := keepKeys
    TwcCheckDone()
}
SetTimer(TwcMacrosRun, -7000)
