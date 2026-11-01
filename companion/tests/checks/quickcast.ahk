; The screen quickcast's setup and colour tuning (screen-quickcast fixes,
; 9299b8d): old setups read, tuning can't drift past DRIFT, a small drift is
; followed, 6 near misses in a row reset to the setup's colours.
TwcQuickcastRun() {
    old := "0.70000,0.80000,0.90000,0.95000|101010,101010,101010,101010,101010,101010,101010,101010,101010,101010,101010"
    c := quickcast.parse(old)
    TwcCheck(c && c.orig.Length = 11 && c.orig[1] = 0x101010, "an old setup (2 parts) reads, its colours become the setup's")
    s := quickcast.serialize(c), c2 := quickcast.parse(s)
    TwcCheck(StrSplit(s, "|").Length = 3 && c2.empty[5] = 0x101010 && c2.orig[5] = 0x101010, "saved with 3 parts and read back")
    bright := []
    loop 11
        bright.Push(0x3A3A3A)
    loop 40
        quickcast.tune(c, bright)
    worst := 0
    loop 11
        worst := Max(worst, ColorDiff(c.empty[A_Index], c.orig[A_Index]))
    TwcCheck(worst <= QuickcastEngine.DRIFT && worst > 0, "tuning stops at the drift limit (worst " worst ", limit " QuickcastEngine.DRIFT ")")
    c3 := quickcast.parse(old), near := []
    loop 11
        near.Push(0x141414)
    loop 10
        quickcast.tune(c3, near)
    TwcCheck(c3.empty[1] = 0x131313 || c3.empty[1] = 0x141414, "a small drift is followed (" Format("{:06X}", c3.empty[1]) ")")
    loop 5
        quickcast.noteMiss(c, 6)
    TwcCheck(c.empty[1] != c.orig[1], "5 near misses: not reset yet")
    quickcast.noteMiss(c, 2)
    loop 5
        quickcast.noteMiss(c, 7)
    TwcCheck(c.empty[1] != c.orig[1], "a far miss in between restarts the count")
    quickcast.noteMiss(c, 5)
    TwcCheck(c.empty[1] = c.orig[1], "the 6th near miss in a row resets to the setup")
    TwcCheck(WC3WindowName("classicwide_1920x1080") = "1.28 widescreen 1920x1080" && WC3WindowName("reforged_2560x1440") = "Reforged 2560x1440", "window names")
    ; repeat while held: why it ends, and the tag on each repeat's log line (F24: never down here)
    remap.holding["f24"] := false
    w1 := remap.heldWhy("f24", A_TickCount)
    remap.holding["f24"] := true
    w2 := remap.heldWhy("f24", A_TickCount)
    remap.qcTry := 1, remap.qcStart := A_TickCount - 2500, remap.qcBase := "f24"
    t1 := remap.tryTag()
    remap.qcTry := 4, t2 := remap.tryTag()
    remap.holding["f24"] := false, t3 := remap.tryTag(), remap.qcTry := 0
    TwcCheck(w1 = "the key was let go" && InStr(w2, "isn't down"), "heldWhy: let go / no key-up (" w1 " / " w2 ")")
    TwcCheck(t1 = "" && InStr(t2, "[repeat 3, 2.5 s after the press, key up]") && InStr(t3, "key up, key-up seen]"), "tryTag: none on the press, then the repeat's number and the key (" t2 t3 ")")
    ; the key's own repeat stopping ends a repeat whose key-up went missing (the user's report, 2026-11-01)
    now := A_TickCount, g := []
    for t in [[0, 0], [2000, 2000], [3000, 100], [3000, 1500]]
        remap.pressAt["f24"] := now - t[1], remap.downAt["f24"] := now - t[2], g.Push(remap.repeatGone("f24", t[2] + 5))
    TwcCheck(!g[1] && g[2] && !g[3] && g[4], "repeatGone: just pressed / no repeat 2 s after the press / repeating / repeats stopped 1.5 s ago (" g[1] g[2] g[3] g[4] ")")
    ; not when it can't tell: another key after its last repeat (Windows repeats the last key only), a mouse button
    other := remap.repeatGone("f24", 200)
    remap.pressAt["xbutton1"] := now - 3000, remap.downAt["xbutton1"] := now - 3000
    mouse := remap.repeatGone("xbutton1", 3005)
    for k in ["f24", "xbutton1"]
        remap.pressAt.Delete(k), remap.downAt.Delete(k)
    TwcCheck(!other && !mouse, "repeatGone: not after another key (Shift, a second key) / never for a mouse button")
    ; a hold ended with the key up (a tap let go before its press was done): not spent, the next tap is a press
    remap.spend("f24", "repeat while held is off")
    TwcCheck(!remap.spent.Get("f24", false), "spend: a key that's up isn't marked")
    ; a repeat that throws still lets go of the key (left 'held', it never quickcast again)
    sendWas := remap.sendFn, remap.sendFn := (*) => 0
    try remap.keyCastHeld("Q", "$f24", "f24", {}, QpcMs())   ; no .repeat: throws in the repeat
    remap.sendFn := sendWas
    TwcCheck(!remap.holding.Get("f24", false), "keyCastHeld: the key let go after an error")
    ; one method at a time (the user, 2026-10-31): both on from before -> the hook; each switch on turns the other off
    global gameModule
    for k in ["quickcast"]
        try IniDelete(iniFile, gameModule.section, k)
    for k in ["screen", "reforged", "hookInterval", "hookCastGap", "interval", "castGap"]
        try IniDelete(iniFile, "Quickcast", k)
    both := gameModule.quickcast && !QuickcastScreenOn()
    RemapQcSwitch("screen"), toScreen := !gameModule.quickcast && QuickcastScreenOn()
    RemapQcSwitch("hook"), toHook := gameModule.quickcast && !QuickcastScreenOn()
    RemapQcSwitch("hook"), none := !gameModule.quickcast && !QuickcastScreenOn()
    RemapQcSwitch("hook")
    TwcCheck(both && toScreen && toHook && none && gameModule.quickcast, "one quickcast at a time: the defaults (both on) are the hook; Screen on turns the hook off and back; both can be off")
    h := quickcast.get("hook"), sc := quickcast.get("screen")
    TwcCheck(h.interval = 80 && h.castGap = 400 && sc.interval = 80 && sc.castGap = 400, "timings: 80 ms repeats, 400 ms after a cast, both methods (" h.interval "/" h.castGap ", " sc.interval "/" sc.castGap ")")
    quickcast.set("hookCastGap", 300)
    TwcCheck(quickcast.get("hook").castGap = 300 && quickcast.get("screen").castGap = 400, "each its own: the hook's wait set, the screen's kept")
    IniDelete(iniFile, "Quickcast", "hookCastGap")
    TwcCheckDone()
}
SetTimer(TwcQuickcastRun, -4000)
