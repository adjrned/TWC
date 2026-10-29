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
