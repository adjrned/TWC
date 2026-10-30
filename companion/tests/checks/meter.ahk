; The damage meter (ui\DamageMeter.ahk): fights, standings, number format, and its window
; with the sample (shown without the focus, its rows, rebuilt for another row count).
TwcMeterRun() {
    global dmgMeter
    m := dmgMeter
    TwcCheck(DamageMeter.Short(812) = "812" && DamageMeter.Short(45600) = "45.6K" && DamageMeter.Short(1234567) = "1.23M" && DamageMeter.Short(250000000) = "250M"
        && DamageMeter.Clock(83) = "1:23", "numbers: 812, 45.6K, 1.23M, 250M; 1:23 (" DamageMeter.Short(45600) ", " DamageMeter.Short(1234567) ")")
    m.reset(), t := 1000000
    m.hit(0, 3000, t), m.hit(1, 9000, t + 500), m.hit(0, 3000, t + 4000), m.hit(2, 0, t + 4000)
    s := m.standings(t + 4000)
    TwcCheck(s.Length = 2 && s[1].player = 1 && s[1].dmg = 9000 && s[2].dmg = 6000 && Abs(s[1].share - 0.6) < 0.001 && Abs(s[1].dps - 2250) < 1,
        "standings: most first, shares, DPS over the fight's 4 s (" s[1].dmg " / " s[2].dmg ", " Round(s[1].dps) "/s)")
    TwcCheck(Abs(m.fightSecs(t + 60000) - 4) < 0.01, "a fight over (no damage for its idle time): its length stays 4 s")
    m.hit(3, 100, t + 4000 + m.idleSecs * 1000 + 1)
    s := m.standings(t + 20000)
    TwcCheck(s.Length = 1 && s[1].player = 3 && s[1].name = "Player 4", "a hit after the idle time starts a new fight (" s.Length " rows, '" s[1].name "')")
    ; layout 33's hits: dealt and taken, the breakdown, the history, the whole game, the pin, the chat line
    m.reset(), m.names := Map(0, "Ruzai", 1, "Kaelith"), m.typeNames := Map("Hpal", "Paladin", "nogl", "Ogre Lord", "ngh1", "Ghoul")
    t := 2000000
    H(from, to, amt, src, tgt, attack, dt, at) => m.addHit({ amount: amt, from: from, to: to, src: src, tgt: tgt, attack: attack, dmgType: dt }, at)
    H(0, 12, 1000, "Hpal", "nogl", 1, 4, t), H(0, 12, 3000, "Hpal", "nogl", 0, 14, t + 1000), H(1, 12, 500, "Hblm", "ngh1", 0, 8, t + 1000)
    H(12, 0, 700, "nogl", "Hpal", 1, 4, t + 2000)
    s := m.standings(t + 2000)
    b := m.breakdown(0, "src", t + 2000), bt := m.breakdown(0, "tgt", t + 2000)
    TwcCheck(s.Length = 2 && s[1].dmg = 4000 && s[1].hits = 2 && s[1].max = 3000 && b.Length = 2 && b[1].name = "Magic spell · Paladin" && b[1].dmg = 3000
        && b[2].name = "Attack · Paladin" && Abs(b[1].share - 0.75) < 0.001 && bt.Length = 1 && bt[1].name = "Ogre Lord",
        "dealt: Ruzai 4000 in 2 hits (top 3000); sources '" (b.Length ? b[1].name : "") "' 75%, 'Attack · Paladin'; targets: Ogre Lord")
    m.mode := "taken"
    s := m.standings(t + 2000)
    TwcCheck(s.Length = 1 && s[1].player = 0 && s[1].dmg = 700 && m.breakdown(0, "src", t + 2000)[1].name = "Attack · Ogre Lord",
        "taken: Ruzai took 700, from 'Attack · Ogre Lord' (the creeps' hits on players)")
    m.mode := "dealt", m.filter := "ngh1", m.filterName := "Ghoul"
    s := m.standings(t + 2000)
    TwcCheck(s.Length = 1 && s[1].player = 1 && s[1].dmg = 500, "the pin on Ghoul: only Kaelith's 500 on it")
    m.filter := "nogl", m.filterName := "Ogre Lord"
    rt := m.reportText(t + 2000)
    TwcCheck(rt = "Damage on Ogre Lord (fight 0:02): 1. Ruzai 4K 100%", "the chat line: '" rt "'")
    m.filter := "", m.filterName := ""
    H(1, 12, 9000, "Hblm", "nogl", 0, 8, t + 2000 + m.idleSecs * 1000 + 1)          ; a new fight
    s := m.standings(t + 30000)
    old := (m.page := 1, m.standings(t + 30000)), whole := (m.page := -1, m.standings(t + 30000))
    m.page := 0
    TwcCheck(m.fights.Length = 1 && s.Length = 1 && s[1].dmg = 9000 && old.Length = 2 && old[1].dmg = 4000 && whole[1].player = 1 && whole[1].dmg = 9500
        && whole[2].dmg = 4000 && m.pages().Length = 3 && InStr(m.pageLabel(t + 30000), "Last fight"),
        "a second fight: this one 9000, the one before kept (4000), the whole game adds them (" (whole.Length ? whole[1].dmg : "") "), pages game / before / now")
    m.stepPage(-1), p1 := m.page, m.stepPage(-1), p2 := m.page, m.stepPage(-1), p3 := m.page, m.stepPage(1), m.stepPage(1), m.stepPage(1)
    TwcCheck(p1 = 1 && p2 = -1 && p3 = -1 && m.page = 0, "‹ goes to the fight before, then the whole game (and stops); › back to now")
    ; the feed end to end: the real GameModuleEngine readers over a stand-in layout-33 memory (the ring's
    ; reader once threw on every read, swallowed by tick's try: the meter showed nothing)
    mem := Buffer(Shm.size, 0)
    NumPut("uint", 0x54574331, mem, Shm.magic), NumPut("uint", 33, mem, Shm.layout), NumPut("uint", 1, mem, Shm.dmState)
    StrPut("Ruzai", mem.Ptr + Shm.dmName, 32, "UTF-8"), NumPut("int", 0, mem, Shm.dmColour)
    PutHit(i, amt, from, to, src, tgt, flags, dt) {
        p := mem.Ptr + Shm.dmRing + 24 * i
        NumPut("float", amt, p, 0), NumPut("uint", src, p, 4), NumPut("uint", tgt, p, 8), NumPut("uint", 0x1234, p, 12)
        NumPut("uchar", from, p, 16), NumPut("uchar", to, p, 17), NumPut("uchar", flags, p, 18), NumPut("uchar", dt, p, 19)
    }
    fake := { base: GameModuleEngine.Prototype }
    fake.DefineProp("live", { call: (*) => mem.Ptr })
    m.reset(), m.names := Map(), m.typeNames := Map(), m.typeN := 0, m.ringSeq := -1, m.lost := 0
    keepGm := m.gm, keepOn := Ini("DamageMeter", "on", 0), m.gm := fake
    IniWrite(1, iniFile, "DamageMeter", "on")
    err := ""
    try {
        m.feed()                                        ; the first read: from where the ring is
        PutHit(0, 1500, 0, 12, 0x4870616C, 0x6E6F676C, 1 | 4, 4)            ; 'Hpal' attacks 'nogl'
        PutHit(1, 700, 12, 0, 0x6E6F676C, 0x4870616C, 1 | 8, 4)             ; and takes a hit back
        NumPut("int", 2, mem, Shm.dmRingSeq)
        NumPut("uint", 0x4870616C, mem, Shm.dmTypeId), StrPut("Paladin", mem.Ptr + Shm.dmTypeName, 32, "UTF-8"), NumPut("int", 1, mem, Shm.dmTypeN)
        m.feed()
    } catch as e
        err := e.Message
    s := m.standings(), m.mode := "taken", tk := m.standings(), m.mode := "dealt"
    b := s.Length ? m.breakdown(0, "src") : []
    TwcCheck(err = "" && s.Length = 1 && s[1].name = "Ruzai" && s[1].dmg = 1500 && tk.Length = 1 && tk[1].dmg = 700 && b.Length && b[1].name = "Attack · Paladin",
        "the feed through the real readers: dealt 1500 by 'Ruzai', taken 700, 'Attack · Paladin'" (err != "" ? " (error: " err ")" : ""))
    m.gm := keepGm, IniWrite(keepOn, iniFile, "DamageMeter", "on")
    m.reset(), m.ringSeq := -1
    m.setSample(true)
    Sleep(1200)
    m.tick()
    hw := m.gui ? m.gui.Hwnd : 0
    vis := hw && DllCall("IsWindowVisible", "ptr", hw)
    shown := 0
    for r in m.rows
        shown += r.name.Visible
    TwcCheck(vis && shown >= 5 && WinGetExStyle(hw) & 0x08000000 && winScale.Has(hw) && winScale[hw].kind = "meter",
        "the sample: the window shows (never takes the focus, scalable as 'meter'), " shown " rows")
    WinGetPos(, , , &h1, m.gui)
    m.setRows(10), m.tick()
    WinGetPos(, , , &h2, m.gui)
    TwcCheck(m.rows.Length = 10 && h2 > h1, "10 rows: rebuilt taller (" h1 " -> " h2 " px)")
    IniWrite(1, iniFile, "DamageMeter", "on"), m.setSample(false), m.setHidden(true), m.hit(0, 500)
    TwcCheck(!m.wanted() && InStr(m.statusText(), "Hidden") && m.standings().Length, "hidden: not shown, still counting (" m.statusText() ")")
    m.setHidden(false), IniWrite(0, iniFile, "DamageMeter", "on")
    m.setRows(6), m.setSample(false), m.tick()
    TwcCheck(!m.gui || !DllCall("IsWindowVisible", "ptr", m.gui.Hwnd), "the sample off, the meter off: hidden")
    TwcCheckDone()
}
SetTimer(TwcMeterRun, -7000)
