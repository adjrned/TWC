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
    TwcCheckDone()
}
SetTimer(TwcQuickcastRun, -4000)
