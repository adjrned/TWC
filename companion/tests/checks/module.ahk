; The companion's side of the game module, against a stand-in: a buffer in the
; module's layout (engine\GameLayout.ahk) with every feature on and working,
; behind a "Warcraft III" window of our own (shown off screen, never
; activated, no keys sent; the injector is never run). Every status line must
; read its own field, and every push must land where the module reads it.
TwcModuleIni() {
    for sect, keys in Map("HealthBars", ["numbers", "mana", "portrait", "on", "colours"], "Display", ["widescreen", "fps", "hideUi", "wideUi", "tooltips", "fastMenu", "buffBar"], "Hosting", ["latency", "countdown"], "Timers", ["cooldowns", "buffs", "allies"])
        for key in keys
            IniWrite(1, iniFile, sect, key)
}
TwcModuleIni()
global twcShmBuf := Buffer(Shm.size, 0)

TwcModuleFill() {
    v := twcShmBuf.Ptr
    NumPut("uint", 0x54574331, v, Shm.magic), NumPut("uint", 23, v, Shm.layout), NumPut("uint", 7680, v, Shm.build)
    NumPut("uint", 1, v, Shm.status), NumPut("uint", 1, v, Shm.probe), NumPut("uint", 1, v, Shm.ui)
    for f in ["hbState", "hcState", "wsState", "fpsState", "latState", "stState", "itState", "hnState", "mbState", "prState", "ulState", "ttState", "fmState", "csState", "alState", "bbState"]
        NumPut("uint", 1, v, Shm.%f%)
    NumPut("uint", 3, v, Shm.uiState), NumPut("float", 0.004, v, Shm.hbDefHeight), NumPut("uint", 60, v, Shm.fpsGameLimit)
    NumPut("int", 100, v, Shm.latGame), NumPut("int", 250, v, Shm.latGame + 8)
    NumPut("uint", 12, v, Shm.hnCount), NumPut("uint", 5, v, Shm.mbCount), NumPut("float", 6, v, Shm.csGame)
    NumPut("float", 4.5, v, Shm.cdLeft), NumPut("uint", 1, v, Shm.buffCount), NumPut("uint", 1, v, Shm.buffFlags), NumPut("float", 9, v, Shm.buffLeft)
    ; your hero's buffs (layout 22): Inner Fire 4 s of 12 (positive, the game's name), an aura without a name
    NumPut("uint", 0x4870616C, v, Shm.hrHero), NumPut("uint", 1, v, Shm.hrAlive), NumPut("uint", 2, v, Shm.hrCount)
    NumPut("uint", 0x42696E66, v, Shm.hrId), NumPut("float", 4, v, Shm.hrLeft), NumPut("float", 12, v, Shm.hrTotal), NumPut("uint", 1 | 4 | 8, v, Shm.hrFlags)
    StrPut("Inner Fire", v + Shm.hrName, 48, "UTF-8")
    NumPut("uint", 0x42484164, v, Shm.hrId + 4), NumPut("uint", 1 | 2 | 4, v, Shm.hrFlags + 4)
}

TwcModuleRun() {
    fake := Gui("+ToolWindow", "Warcraft III")
    fake.Show("NA x-3000 y-3000 w200 h100")
    gameModule.DefineProp("check", { call: (*) => 0 })                  ; never inject
    gameModule.DefineProp("live", { call: (*) => (NumPut("uint", A_TickCount, twcShmBuf, Shm.heartbeat), twcShmBuf.Ptr) })
    TwcModuleFill()
    s := gameModule.state()
    TwcCheck(s.loaded && s.layout = 23 && s.live && s.probe = 1 && s.build = 7680, "state: loaded, layout 23, live, probe passed")
    TwcCheck(InStr(gameModule.statusText(), "check passed"), "module: " gameModule.statusText())
    t := gameModule.timers()
    hb := gameModule.heroBuffs()
    TwcCheck(hb && hb.hero = "Hpal" && hb.alive && hb.buffs.Length = 2 && hb.buffs[1].id = "Binf" && hb.buffs[1].name = "Inner Fire" && hb.buffs[1].left = 4
        && hb.buffs[1].positive && !hb.buffs[1].aura && hb.buffs[2].id = "BHad" && hb.buffs[2].aura && hb.buffs[2].name = "", "hero buffs: 'Hpal', Inner Fire 4 s, an aura")
    gameModule.heroWanted(true), hw1 := NumGet(twcShmBuf, Shm.hrWant, "uint"), gameModule.heroWanted(false)
    TwcCheck(hw1 = 1 && NumGet(twcShmBuf, Shm.hrWant, "uint") = 0, "heroWanted pushes hrWant")
    ; buff alerts by rawcode: watched from the hero's list, the label / the game's name, missing / running out
    TwcCheck(buffWatch.moduleReady() && buffWatch.addId("Binf", "Inner Fire") && buffWatch.addId("Bslo") && !buffWatch.addId("Binf") && !buffWatch.addId("Bi|f") && !buffWatch.addId("abc"),
        "addId: two rawcodes watched; again, a '|' or not 4 letters: refused")
    bl := buffWatch.buffs()
    TwcCheck(bl.Length = 2 && bl[1].id = "Binf" && bl[1].name = "" && bl[1].gname = "Inner Fire" && bl[2].gname = "", "saved as label|id|Binf|Inner Fire")
    hbw := buffWatch.heroBuffs(true), hw2 := NumGet(twcShmBuf, Shm.hrWant, "uint")
    missing := [], ending := []
    BuffWatchEngine.IdAlerts(bl, hbw, 5, missing, ending)
    TwcCheck(hw2 = 1 && missing.Length = 1 && missing[1] = "Bslo" && ending.Length = 1 && ending[1] = "Inner Fire 4 s", "alerts: 'Bslo missing', 'Inner Fire 4 s' (" Join(", ", missing*) " / " Join(", ", ending*) ")")
    buffWatch.rename(1, "IF"), buffWatch.rename(2, "Slow")
    missing := [], ending := [], BuffWatchEngine.IdAlerts(buffWatch.buffs(), hbw, 5, missing, ending)
    m2 := missing.Length ? missing[1] : "", e2 := ending.Length ? ending[1] : ""
    NumPut("uint", 0, twcShmBuf, Shm.hrAlive)
    missing := [], ending := [], BuffWatchEngine.IdAlerts(buffWatch.buffs(), gameModule.heroBuffs(), 5, missing, ending)
    TwcCheck(m2 = "Slow" && e2 = "IF 4 s" && !missing.Length && !ending.Length, "your labels win; the hero dead: no alerts")
    NumPut("uint", 1, twcShmBuf, Shm.hrAlive)
    TwcCheck(InStr(buffWatch.statusText(), "watching IF, Slow"), "buff alerts: " buffWatch.statusText())
    buffWatch.rename(1, ""), TwcCheck(buffWatch.buffs()[1].name = "" && InStr(buffWatch.statusText(), "watching Inner Fire"), "an empty label: the game's name again")
    buffWatch.heroBuffs(false)
    TwcCheck(NumGet(twcShmBuf, Shm.hrWant, "uint") = 0, "heroBuffs(false) stops the module's read")
    TwcCheck(t.cd[1].left = 4.5 && t.buffs.Length = 1 && t.buffs[1].left = 9, "timers: the first cooldown and buff")
    want := Map(
        "bars", [(*) => healthBars.statusText(), "0.0040 high"],
        "colours", [(*) => healthBars.colourStatus(), "by owner"],
        "numbers", [(*) => healthBars.numberStatus(), "(12 now)"],
        "mana", [(*) => healthBars.manaStatus(), "(5 now)"],
        "portrait", [(*) => healthBars.portraitStatus(), "regen next to"],
        "cooldowns", [(*) => timersHud.cooldownStatus(), "drawn on the command card and items · allies' too · Alt + click pings"],
        "buffs", [(*) => timersHud.buffStatus(), "drawn under the buff icons"],
        "fps", [(*) => gameDisplay.fpsStatus(), "the game's own setting: 60"],
        "hide", [(*) => gameDisplay.hideStatus(), "time of day, minimap"],
        "latency", [(*) => gameDisplay.latencyStatus(), "LAN 100, Battle.net 250"],
        "wideUi", [(*) => gameDisplay.wideUiStatus(), "laid out for the wide window"],
        "widescreen", [(*) => gameDisplay.wsStatus(), "the world fits the window"],
        "tooltips", [(*) => gameDisplay.tooltipsStatus(), "hover the damage or armor icon"],
        "fastMenu", [(*) => gameDisplay.fastMenuStatus(), "the menus switch at once"],
        "countdown", [(*) => gameDisplay.countdownStatus(), "start 0 s after Start Game (the game's own: 6 s)"],
        "buffBar", [(*) => gameDisplay.buffBarStatus(), "On · x1.5 (in the widescreen UI's layout)"])
    for name, w in want {
        st := w[1]()
        TwcCheck(InStr(st, w[2]), name ": " st)
    }
    healthBars.push(), gameDisplay.push(), timersHud.pushGame()
    v := twcShmBuf.Ptr
    TwcCheck(NumGet(v, Shm.itOn, "uint") = 3, "pushed itOn: cooldowns (1) and buffs (2)")
    for f in ["hnOn", "mbOn", "prOn", "hbOn", "hcOn", "wsOn", "fpsOn", "latOn", "ulOn", "ttOn", "fmOn", "csOn", "alOn", "pingOn"]
        TwcCheck(NumGet(v, Shm.%f%, "uint") = 1, "pushed " f)
    TwcCheck(NumGet(v, Shm.uiHide, "uint") = 0x7D && NumGet(v, Shm.fpsLimit, "uint") = 200 && NumGet(v, Shm.latMs, "uint") = 50
        && Abs(NumGet(v, Shm.mbHeight, "float") - 0.75) < 0.001 && Abs(NumGet(v, Shm.hbHeight, "float") - 1.5) < 0.001, "pushed values: what the UI hides, FPS limit, latency, mana and bar height")
    gameDisplay.toggleHideMenu()
    TwcCheck(NumGet(v, Shm.uiHide, "uint") = 0x79, "menu buttons shown: the upper menu bar isn't hidden (" Format("{:X}", NumGet(v, Shm.uiHide, "uint")) ")")
    gameDisplay.toggleHideMenu()
    TwcCheck(gameDisplay.setCountdownSecs("2,5") = false && gameDisplay.setCountdownSecs("2.54") && NumGet(v, Shm.csSecs, "float") = 2.5
        && gameDisplay.setCountdownSecs(9) && gameDisplay.countdownSecs = 6 && gameDisplay.countdownLabel = "Countdown: 6 s", "countdown seconds: typed, tenths, at most 6 (" gameDisplay.countdownLabel ")")
    gameDisplay.setCountdownSecs(0)
    gameDisplay.toggleBuffBarUp()
    TwcCheck(NumGet(v, Shm.ulOn, "uint") = 3 && gameDisplay.buffBarLabel = "Buff bar: raised", "the buff bar raised: ulOn bit 2 (" NumGet(v, Shm.ulOn, "uint") ")")
    gameDisplay.toggleBuffBarUp()
    TwcCheck(NumGet(v, Shm.ulOn, "uint") = 1, "and back in place")
    ; WFE's DISPLAYMINUTES: off by default, a bit each
    TwcCheck(NumGet(v, Shm.tmMinutes, "uint") = 0, "minutes off by default: whole seconds (WFE's)")
    timersHud.setMinutes("cdMinutes", 1), m1 := NumGet(v, Shm.tmMinutes, "uint")
    timersHud.setMinutes("buffMinutes", 1), m2 := NumGet(v, Shm.tmMinutes, "uint")
    timersHud.setMinutes("cdMinutes", 0), timersHud.setMinutes("buffMinutes", 0)
    TwcCheck(m1 = 1 && m2 = 3 && NumGet(v, Shm.tmMinutes, "uint") = 0, "minutes pushed: cooldowns 1, buffs 2 (" m1 ", " m2 ")")
    ; the cooldowns' look (layout 20): defaults x1, gold from 5 s, Ready on; typed values clamped
    TwcCheck(NumGet(v, Shm.cdSize, "float") = 1 && NumGet(v, Shm.cdGold, "float") = 5 && NumGet(v, Shm.cdReady, "uint") = 1 && NumGet(v, Shm.cdNoBadge, "uint") = 1, "pushed the cooldowns' look: x1, gold from 5 s, Ready, the game's badge hidden, its clock shown, no ring")
    ok := timersHud.setCdSize("1.25") && timersHud.setCdGold(99) && !timersHud.setCdSize("abc")
    TwcCheck(ok && NumGet(v, Shm.cdSize, "float") = 1.25 && NumGet(v, Shm.cdGold, "float") = 30, "size typed 1.25, gold 99 -> 30, not a number refused")
    timersHud.setCdSize(1), timersHud.setCdGold(5)
    ; the buffs' look (layout 22): x1, gold from 5 s, no aura seconds, no ring by default; their own values
    TwcCheck(NumGet(v, Shm.bfSize, "float") = 1 && NumGet(v, Shm.bfGold, "float") = 5 && NumGet(v, Shm.bfOpts, "uint") = 0, "pushed the buffs' look: x1, gold from 5 s, auras / ring off")
    ok := timersHud.setBfSize("0.8") && timersHud.setBfGold(2) && !timersHud.setBfGold("x")
    timersHud.setBfAuras(1), timersHud.setBfRing(1)
    TwcCheck(ok && Abs(NumGet(v, Shm.bfSize, "float") - 0.8) < 1e-6 && NumGet(v, Shm.bfGold, "float") = 2 && NumGet(v, Shm.bfOpts, "uint") = 3 && NumGet(v, Shm.cdSize, "float") = 1,
        "buffs x0.8, gold from 2 s, auras (1) and ring (2): bfOpts " NumGet(v, Shm.bfOpts, "uint") "; the cooldowns' untouched")
    timersHud.setBfSize(1), timersHud.setBfGold(5), timersHud.setBfAuras(0), timersHud.setBfRing(0)
    ; the bigger buff bar (layout 23): x1.5 by default, typed values clamped to 1-2, 0 when off
    k1 := NumGet(v, Shm.bbScale, "float"), ok := gameDisplay.setBuffBarScale("2.5") && !gameDisplay.setBuffBarScale("big")
    k2 := NumGet(v, Shm.bbScale, "float"), gameDisplay.setBuffBar(0), k3 := NumGet(v, Shm.bbScale, "float")
    gameDisplay.setBuffBar(1), gameDisplay.setBuffBarScale(1.5)
    TwcCheck(k1 = 1.5 && ok && k2 = 2 && k3 = 0 && NumGet(v, Shm.bbScale, "float") = 1.5, "buff bar: pushed x1.5, 2.5 -> 2, off 0 (" k1 " " k2 " " k3 ")")
    ; the ping key: only on a button the module says is under the cursor
    TwcCheck(!timersHud.pingActive(), "ping key: not in the game window, so the click is the game's")
    rows := ModuleCheckRows(ModuleCheckLog())
    TwcCheck(rows.Length >= 20, "Module check rows: " rows.Length)
    ; the lines 1.28f's portrait fallback logs (call sites instead of the vtable): not a refusal, then working
    row(rows, name) {
        for r in rows
            if r.name = name
                return r
        return { mark: "?", detail: "no row" }
    }
    pr := ["2026-10-25 22:30:22.504  portrait: the update +40D0E0 isn't in the first 128 entries of vtable +AB05B4"
        , "2026-10-25 22:30:22.590    called directly at +40C2A1 (call)"
        , "2026-10-25 22:30:22.591  portrait: the update will be wrapped at its 1 call sites (on the game thread)"]
    r := row(ModuleCheckRows(pr), "Portrait regen")
    TwcCheck(r.mark = "·", "portrait, call sites found, not wrapped yet: " r.mark " " r.detail)
    pr.Push("2026-10-25 22:30:22.700  portrait: on (its update +40D0E0 is wrapped at 1 call sites)"
        , "2026-10-25 22:30:22.800  portrait: the first update wrapped (portrait 2EA90088, unit 1E000000, lines +240 3BFA0088 / +244 3BFA0188)")
    r := row(ModuleCheckRows(pr), "Portrait regen")
    TwcCheck(r.mark = "✓", "portrait through its call sites: " r.mark " " r.detail)
    pr.Push("2026-10-25 22:31:00.000  portrait: the call at +40C2A1 was changed by someone else: stopping")
    r := row(ModuleCheckRows(pr), "Portrait regen")
    TwcCheck(r.mark = "✗", "portrait, a call site changed: " r.mark " " r.detail)
    ; bar size: sized in the bar's update, so a pass may never log "pass resized": the first size line is the sign
    r := row(ModuleCheckRows(["2026-10-26 10:00:00.000  health bars: the game's own size is 0.00400 high, 0.03000 wide (UI units; the width is the first unit's)"]), "Health bar size")
    TwcCheck(r.mark = "✓", "bar size from its first size line: " r.mark " " r.detail)
    ; the widescreen UI's portrait text and its handlers' faults have rows of their own
    r := row(ModuleCheckRows(["2026-10-26 10:00:00.000  portrait text: no frames (no Storm.dll in the game): the portrait's own lines stay"]), "Portrait text")
    r2 := row(ModuleCheckRows(["2026-10-26 10:00:00.000  UI layout: 102 frames laid out for a 1920x1080 window", "2026-10-26 10:00:01.000  UI layout: the chat box faulted: left out"]), "Widescreen UI")
    TwcCheck(r.mark = "✗" && r2.mark = "✗", "portrait text refused: " r.mark ", a layout group faulted: " r2.mark)
    r := row(ModuleCheckRows(["2026-10-26 10:00:00.000    not the buff bar (+AAD510): refusing it"]), "Hide the UI")
    TwcCheck(r.mark = "✗", "Hide the UI's buff bar refused: " r.mark " " r.detail)
    ; Widescreen next to another widescreen mod (state 4): its own status line
    NumPut("uint", 4, v, Shm.wsState)
    TwcCheck(InStr(gameDisplay.wsStatus(), "another widescreen mod"), "widescreen, state 4: " gameDisplay.wsStatus())
    NumPut("uint", 1, v, Shm.wsState)
    ShowPage("wc3"), Wc3ShowVersion("128")
    for tab in Wc3Tabs()
        Wc3ShowTab(tab[1])
    TwcCheck(true, "WC3 page with the module running")
    ; every switch and button on the page, as a click does it (off -> on -> off)
    for f in Wc3Features() {
        if !Wc3OnVersion(f, "128")
            continue
        Wc3ShowTab(f.tab)
        if f.HasProp("on") {
            Wc3Switch(f), Wc3Switch(f)
            TwcCheck(true, "switch: " f.title)
        }
    }
    gameModule.setEnabled(false), RefreshWc3(), gameModule.setEnabled(true), RefreshWc3()
    TwcCheck(true, "the game module's own switch")
    TwcModuleSwap()
    fake.Destroy()
    TwcCheckDone()
}
; swapping the module live: the copy the game loads, and the hand-over (no game, no injector)
TwcModuleSwap() {
    tmp := A_Temp "\twc-swapcheck"
    try DirDelete(tmp, 1)
    DirCreate(tmp)
    FileCopy(A_ScriptDir "\native\twc-game.dll", tmp "\twc-game.dll")
    FileAppend("old", tmp "\twc-game.deadbeef.dll")
    gm2 := GameModuleEngine()
    gm2.DefineProp("dir", { get: (*) => tmp })
    st := GameModuleEngine.FileStamp(tmp "\twc-game.dll")
    copy := gm2.loadCopy()
    TwcCheck(st && copy = tmp "\twc-game." Format("{:08x}", st) ".dll" && FileExist(copy) && !FileExist(tmp "\twc-game.deadbeef.dll"),
        "the game loads a stamped copy (" SubStr(copy, StrLen(tmp) + 2) "), an old copy not in use goes")
    ; the old module unloads (status 3): its view goes, then it's loaded again
    pid := DllCall("GetCurrentProcessId")
    h := DllCall("CreateFileMapping", "ptr", -1, "ptr", 0, "uint", 4, "uint", 0, "uint", Shm.size, "str", "Local\TWC_Game_" pid, "ptr")
    v := gm2.view(pid)
    NumPut("uint", 0x54574331, v, Shm.magic), NumPut("uint", 13, v, Shm.layout), NumPut("uint", 4, v, Shm.status)
    calls := { n: 0 }
    gm2.DefineProp("check", { call: (*) => calls.n++ })
    gm2.swapping := pid, gm2.swapAt := A_TickCount
    TwcCheck(!gm2.live(), "while swapping nothing is pushed (live() is 0)")
    gm2.swapStep(pid)
    TwcCheck(gm2.swapping = pid && gm2.views.Has(pid) && !calls.n, "still unloading (status 4): waits")
    NumPut("uint", 3, v, Shm.status)
    gm2.swapStep(pid)
    TwcCheck(!gm2.swapping && !gm2.views.Has(pid) && calls.n = 1, "unloaded (status 3): the view is let go and the new one is loaded")
    ; the old module still had its name open: the view opened again is the old one's (status 3) -> let go, loaded again
    v := gm2.view(pid), gm2.tried[pid] := true
    TwcCheck(v && gm2.dropUnloaded(pid, v) && !gm2.views.Has(pid) && !gm2.tried.Has(pid), "a view of an unloaded module (the old one's, in the race): let go, to be loaded again")
    v := gm2.view(pid), NumPut("uint", 1, v, Shm.status)
    TwcCheck(!gm2.dropUnloaded(pid, v) && gm2.views.Has(pid), "a running module's view: kept")
    gm2.drop(pid)
    DllCall("CloseHandle", "ptr", h)
    ; loading again after a failure, and past a retired module of the same build ("already in", no memory)
    FileAppend("", tmp "\twc-inject.exe")
    codes := [1, 2, 0], seen := []
    gm3 := GameModuleEngine()
    gm3.DefineProp("dir", { get: (*) => tmp })
    gm3.DefineProp("runInjector", { call: (self, exe, p, dll) => (seen.Push(dll), codes.RemoveAt(1)) })
    t := { n: 1, at: A_TickCount, done: false, fresh: 0 }
    gm3.injectOnce(999999, t), d1 := t.done
    gm3.injectOnce(999999, t), f1 := t.fresh
    gm3.injectOnce(999999, t)
    TwcCheck(!d1 && f1 = 1 && t.done && seen.Length = 3 && !InStr(seen[2], "-1") && InStr(seen[3], "-1.dll"),
        "a failed load isn't the end; 'already in' with no module memory: a fresh copy (" SubStr(seen[3], StrLen(tmp) + 2) ")")
    try DirDelete(tmp, 1)
}
SetTimer(TwcModuleRun, -7000)
