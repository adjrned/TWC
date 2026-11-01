; The boss timers (ui\BossTimers.ahk): an attempt from the first hit, what it learns per boss type
; (first time, HP, gaps; kept in the store file), the bars it predicts (after a cast: the median gap;
; before: the median first time, or an HP mark), a kill and a reset; the feed end to end through the
; real GameModuleEngine readers over a stand-in layout-36 memory; the sample's window.
TwcBossRun() {
    global bossBars
    b := bossBars
    keepGm := b.gm, keepOn := Ini("BossTimers", "on", 0)
    b.gm := 0, b.forget()
    TwcCheck(!FileExist(BossTimers.StorePath()) && b.learnedCount() = 0 && InStr(BossTimers.StorePath(), "tw-companion-bosses.ini"),
        "the store: next to the settings, empty after Forget (" BossTimers.StorePath() ")")
    TwcCheck(BossTimers.Median([3, 1, 2]) = 2 && BossTimers.Median([4, 1, 2, 3]) = 2.5 && BossTimers.Spread([5, 2, 9]) = 7, "median 2 / 2.5, spread 7")
    ; attempt 1: hit at T, Frost Nova at 10 s and 30 s, Army at 15 s (50% HP); a reset
    T := 10000000, boss := 0x5000, b.typeNames := Map("Nlk1", "Lich King", "A0FN", "Frost Nova", "A0AR", "Army of the Dead")
    b.hitsOn := Map(boss, { first: T, last: T })
    C1(ab, secs, hp, at0) => b.cast({ unit: boss, type: "Nlk1", ability: ab, hp: hp, hpMax: 100000 }, at0 + secs * 1000)
    C1("A0FN", 10, 90000, T), C1("A0AR", 15, 50000, T), C1("A0FN", 30, 40000, T)
    f1 := b.fight
    b.endFight("reset")
    st := b.storeOf("Nlk1")
    fn := st.abilities.Has("A0FN") ? st.abilities["A0FN"] : 0, ar := st.abilities.Has("A0AR") ? st.abilities["A0AR"] : 0
    TwcCheck(f1 && f1.engaged && f1.start = T && fn && fn.first.Length = 1 && fn.first[1] = 10 && fn.gap.Length = 1 && fn.gap[1] = 20 && ar && ar.hp[1] = 0.5
        && st.attempts = 1 && !b.fight, "attempt 1 (from the first hit): Frost Nova first at 10 s, then every 20 s; Army at 50% HP; 1 attempt")
    ; read back from the file, as after a restart
    b.learned := Map(), st := b.storeOf("Nlk1")
    TwcCheck(st.attempts = 1 && st.name = "Lich King" && st.abilities.Count = 2 && st.abilities["A0FN"].gap[1] = 20 && b.learnedCount() = 1,
        "kept in the store and read back (" st.abilities.Count " abilities, name '" st.name "')")
    ; attempt 2: Army at a very different time but the same HP: an HP mark now; Frost Nova predicted
    T2 := T + 600000
    b.hitsOn := Map(boss, { first: T2, last: T2 })
    C1("A0FN", 11, 95000, T2)
    p := b.predict(T2 + 20000)
    fnRow := 0
    for r in p
        if r.ability = "A0FN"
            fnRow := r
    TwcCheck(fnRow && fnRow.kind = "time" && Abs(fnRow.left - 11) < 0.01 && BossTimers.LeftText(fnRow) = "11s",
        "after its cast at 11 s: Frost Nova in 11 s at 0:20 (11 + the 20 s gap) ('" (fnRow ? BossTimers.LeftText(fnRow) : "") "')")
    C1("A0AR", 45, 50500, T2)
    b.fight.last := T2 + 60000
    b.endFight("kill")
    st := b.storeOf("Nlk1")
    T3 := T2 + 600000
    b.hitsOn := Map(boss, { first: T3, last: T3 })
    C1("A0XX", 1, 99000, T3)                ; (a third spell: the attempt starts)
    b.fight.hp := 80000
    p := b.predict(T3 + 5000)
    kinds := ""
    for r in p
        kinds .= (kinds = "" ? "" : ", ") r.name " " BossTimers.LeftText(r)
    TwcCheck(st.attempts = 2 && st.kills = 1 && p.Length = 3 && p[1].ability = "A0FN" && Abs(p[1].left - 5.5) < 0.01 && p[1].rough = false
        && p[2].kind = "hp" && BossTimers.LeftText(p[2]) = "at 50%" && p[3].kind = "seen",
        "attempt 3 at 0:05: " kinds " (Frost Nova by its first times 10 / 11 s; Army by HP: it came at 15 and 45 s, both times at 50%)")
    b.fight.hp := 30000, p := b.predict(T3 + 5000)
    gone := true
    for r in p
        gone := gone && r.ability != "A0AR"
    TwcCheck(gone, "the boss below the mark: that bar's gone")
    b.endFight("reset")
    ; the feed end to end: the readers over a stand-in memory (layout 36): a player's hit on the boss, then its cast
    mem := Buffer(Shm.size, 0)
    NumPut("uint", 0x54574331, mem, Shm.magic), NumPut("uint", 36, mem, Shm.layout), NumPut("uint", 1, mem, Shm.bcState)
    fake := { base: GameModuleEngine.Prototype }
    fake.DefineProp("live", { call: (*) => mem.Ptr })
    b.gm := fake, b.castSeq := -1, b.hitSeq := -1, b.hitsOn := Map()
    IniWrite(1, iniFile, "BossTimers", "on")
    err := ""
    try {
        b.feed()                                        ; the first read: from where the rings are
        hp := mem.Ptr + Shm.dmRing
        NumPut("float", 500, hp, 0), NumPut("uint", 0x4870616C, hp, 4), NumPut("uint", 0x4E6C6B31, hp, 8), NumPut("uint", 0x7000, hp, 12)
        NumPut("uchar", 0, hp, 16), NumPut("uchar", 12, hp, 17), NumPut("int", 1, mem, Shm.dmRingSeq)
        b.feed()
        cp := mem.Ptr + Shm.bcRing
        NumPut("uint", A_TickCount & 0xFFFFFFFF, cp, 0), NumPut("uint", 0x7000, cp, 4), NumPut("uint", 0x4E6C6B31, cp, 8), NumPut("uint", 0x41304D54, cp, 12)
        NumPut("float", 70000, cp, 16), NumPut("float", 100000, cp, 20), NumPut("uchar", 12, cp, 24), NumPut("int", 1, mem, Shm.bcSeq)
        NumPut("uint", 1, mem, Shm.bcWatchAlive), NumPut("float", 70000, mem, Shm.bcWatchHp), NumPut("float", 100000, mem, Shm.bcWatchMax)
        b.feed()
    } catch as e
        err := e.Message
    f := b.fight
    TwcCheck(err = "" && NumGet(mem, Shm.bcOn, "uint") = 1 && NumGet(mem, Shm.dmOn, "uint") = 1 && f && f.unit = 0x7000 && f.type = "Nlk1" && f.engaged
        && f.casts.Has("A0MT") && NumGet(mem, Shm.bcWatch, "uint") = 0x7000,
        "the feed through the real readers: casts and hits on, the boss engaged from the hit on it, 'A0MT' noted, the boss followed" (err != "" ? " (error: " err ")" : ""))
    NumPut("uint", 0, mem, Shm.bcWatchAlive), b.feed()
    TwcCheck(!b.fight && b.storeOf("Nlk1").kills = 2 && NumGet(mem, Shm.bcWatch, "uint") = 0, "the boss followed dies: a kill, learned, no longer followed")
    ; hitting enemies that haven't cast: the one hit last followed for its HP; a small one ruled out, a boss's
    ; attempt starts from the hits (the window comes up by itself); the ✕ hides it for that attempt only
    b.hitsOn := Map(), b.notBoss := Map(), b.candidate := 0
    Hit(k, unit, type) {
        p := mem.Ptr + Shm.dmRing + GameModuleEngine.HIT * k
        NumPut("float", 300, p, 0), NumPut("uint", 0x4870616C, p, 4), NumPut("uint", type, p, 8), NumPut("uint", unit, p, 12)
        NumPut("uchar", 0, p, 16), NumPut("uchar", 12, p, 17), NumPut("int", k + 1, mem, Shm.dmRingSeq)
    }
    Watch(hp, mx, alive) => (NumPut("float", hp, mem, Shm.bcWatchHp), NumPut("float", mx, mem, Shm.bcWatchMax), NumPut("uint", alive, mem, Shm.bcWatchAlive))
    err := ""
    try {
        Hit(1, 0x9000, 0x6E303031), Watch(800, 1000, 1), b.feed()           ; a small enemy ('n001', 1000 HP)
        small := b.candidate && b.candidate.unit = 0x9000 && NumGet(mem, Shm.bcWatch, "uint") = 0x9000
        b.candidate.at -= 500, b.feed()
        ruled := !b.fight && b.notBoss.Has(0x9000)
        Hit(2, 0x8000, 0x4E626F73), b.feed()                                ; the boss ('Nbos'), no cast yet
        early := !b.fight && b.candidate && b.candidate.unit = 0x8000       ; (the watch's HP still the last unit's: not trusted yet)
        Watch(90000, 120000, 1), b.candidate.at -= 500, b.feed()
    } catch as e
        err := e.Message
    f := b.fight
    TwcCheck(err = "" && small && ruled && early && f && f.unit = 0x8000 && f.type = "Nbos" && f.engaged && f.hpMax = 120000 && f.casts.Count = 0,
        "hits, no cast: the small enemy (1000 HP) ruled out; the boss (120000 HP) engaged from the hits on it, before any cast" (err != "" ? " (error: " err ")" : ""))
    b.setHidden(true)
    hid := b.dismissed = 0x8000 && InStr(b.statusText(), "hidden for this attempt")
    b.endFight("reset"), b.startFight({ unit: 0x8000, type: "Nbos", hp: 120000, hpMax: 120000 }, A_TickCount)
    TwcCheck(hid && !b.dismissed, "the ✕: hidden for that attempt ('" b.statusText() "'), shown again at the next")
    b.endFight("reset")
    IniWrite(0, iniFile, "BossTimers", "on"), b.feed()
    TwcCheck(NumGet(mem, Shm.bcOn, "uint") = 0, "off: the module's casts off")
    b.gm := keepGm, IniWrite(keepOn, iniFile, "BossTimers", "on")
    ; the sample's window
    b.setSample(true)
    Sleep(600)
    b.tick()
    hw := b.gui ? b.gui.Hwnd : 0
    shown := 0
    for r in b.rows
        shown += r.name.Visible
    TwcCheck(hw && DllCall("IsWindowVisible", "ptr", hw) && shown >= 3 && WinGetExStyle(hw) & 0x08000000 && winScale.Has(hw) && winScale[hw].kind = "bosstimers"
        && b.rows[1].name.Text != "", "the sample: the window shows (never takes the focus, scalable as 'bosstimers'), " shown " bars, the first '" (shown ? b.rows[1].name.Text " " b.rows[1].left.Text : "") "'")
    b.setSample(false), b.tick()
    TwcCheck(!b.gui || !DllCall("IsWindowVisible", "ptr", b.gui.Hwnd), "the sample off: hidden")
    TwcCheck(!b.learned.Has("SMPL") && !InStr(IniRead(BossTimers.StorePath()), "SMPL"), "the sample learned nothing")
    b.forget()
    TwcCheckDone()
}
SetTimer(TwcBossRun, -7000)
