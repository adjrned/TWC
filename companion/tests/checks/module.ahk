; The companion's side of the game module, against a stand-in: a buffer in the
; module's layout (engine\GameLayout.ahk) with every feature on and working,
; behind a "Warcraft III" window of our own (shown off screen, never
; activated, no keys sent; the injector is never run). Every status line must
; read its own field, and every push must land where the module reads it.
TwcModuleIni() {
    for sect, keys in Map("HealthBars", ["numbers", "mana", "portrait", "on", "colours"], "Display", ["widescreen", "fps", "hideUi", "wideUi", "tooltips", "fastMenu"], "Hosting", ["latency"], "Timers", ["show"])
        for key in keys
            IniWrite(1, iniFile, sect, key)
    IniWrite("game", iniFile, "Timers", "where")
}
TwcModuleIni()
global twcShmBuf := Buffer(Shm.size, 0)

TwcModuleFill() {
    v := twcShmBuf.Ptr
    NumPut("uint", 0x54574331, v, Shm.magic), NumPut("uint", 16, v, Shm.layout), NumPut("uint", 7680, v, Shm.build)
    NumPut("uint", 1, v, Shm.status), NumPut("uint", 1, v, Shm.probe), NumPut("uint", 1, v, Shm.ui)
    for f in ["hbState", "hcState", "wsState", "fpsState", "latState", "stState", "itState", "hnState", "mbState", "prState", "ulState", "ttState", "fmState"]
        NumPut("uint", 1, v, Shm.%f%)
    NumPut("uint", 3, v, Shm.uiState), NumPut("float", 0.004, v, Shm.hbDefHeight), NumPut("uint", 60, v, Shm.fpsGameLimit)
    NumPut("int", 100, v, Shm.latGame), NumPut("int", 250, v, Shm.latGame + 8)
    NumPut("uint", 12, v, Shm.hnCount), NumPut("uint", 5, v, Shm.mbCount)
    NumPut("float", 4.5, v, Shm.cdLeft), NumPut("uint", 1, v, Shm.buffCount), NumPut("uint", 1, v, Shm.buffFlags), NumPut("float", 9, v, Shm.buffLeft)
}

TwcModuleRun() {
    fake := Gui("+ToolWindow", "Warcraft III")
    fake.Show("NA x-3000 y-3000 w200 h100")
    gameModule.DefineProp("check", { call: (*) => 0 })                  ; never inject
    gameModule.DefineProp("live", { call: (*) => (NumPut("uint", A_TickCount, twcShmBuf, Shm.heartbeat), twcShmBuf.Ptr) })
    TwcModuleFill()
    s := gameModule.state()
    TwcCheck(s.loaded && s.layout = 16 && s.live && s.probe = 1 && s.build = 7680, "state: loaded, layout 16, live, probe passed")
    TwcCheck(InStr(gameModule.statusText(), "check passed"), "module: " gameModule.statusText())
    t := gameModule.timers()
    TwcCheck(t.cd[1].left = 4.5 && t.buffs.Length = 1 && t.buffs[1].left = 9, "timers: the first cooldown and buff")
    want := Map(
        "bars", [(*) => healthBars.statusText(), "0.0040 high"],
        "colours", [(*) => healthBars.colourStatus(), "by owner"],
        "numbers", [(*) => healthBars.numberStatus(), "(12 now)"],
        "mana", [(*) => healthBars.manaStatus(), "(5 now)"],
        "portrait", [(*) => healthBars.portraitStatus(), "regen next to"],
        "fps", [(*) => gameDisplay.fpsStatus(), "the game's own setting: 60"],
        "hide", [(*) => gameDisplay.hideStatus(), "time of day, minimap"],
        "latency", [(*) => gameDisplay.latencyStatus(), "LAN 100, Battle.net 250"],
        "timers", [(*) => timersHud.statusText(), "drawn in the game"],
        "wideUi", [(*) => gameDisplay.wideUiStatus(), "laid out for the wide window"],
        "widescreen", [(*) => gameDisplay.wsStatus(), "the world fits the window"],
        "tooltips", [(*) => gameDisplay.tooltipsStatus(), "hover the damage or armor icon"],
        "fastMenu", [(*) => gameDisplay.fastMenuStatus(), "the menus switch at once"])
    for name, w in want {
        st := w[1]()
        TwcCheck(InStr(st, w[2]), name ": " st)
    }
    healthBars.push(), gameDisplay.push(), timersHud.pushGame()
    v := twcShmBuf.Ptr
    for f in ["hnOn", "mbOn", "prOn", "itOn", "hbOn", "hcOn", "wsOn", "fpsOn", "latOn", "ulOn", "ttOn", "fmOn"]
        TwcCheck(NumGet(v, Shm.%f%, "uint") = 1, "pushed " f)
    TwcCheck(NumGet(v, Shm.uiHide, "uint") = 0x7D && NumGet(v, Shm.fpsLimit, "uint") = 200 && NumGet(v, Shm.latMs, "uint") = 50
        && Abs(NumGet(v, Shm.mbHeight, "float") - 0.75) < 0.001 && Abs(NumGet(v, Shm.hbHeight, "float") - 1.5) < 0.001, "pushed values: what the UI hides, FPS limit, latency, mana and bar height")
    gameDisplay.toggleHideMenu()
    TwcCheck(NumGet(v, Shm.uiHide, "uint") = 0x79, "menu buttons shown: the upper menu bar isn't hidden (" Format("{:X}", NumGet(v, Shm.uiHide, "uint")) ")")
    gameDisplay.toggleHideMenu()
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
    try DirDelete(tmp, 1)
}
SetTimer(TwcModuleRun, -7000)
