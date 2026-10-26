; The companion's side of the game module, against a stand-in: a buffer in the
; module's layout (engine\GameLayout.ahk) with every feature on and working,
; behind a "Warcraft III" window of our own (shown off screen, never
; activated, no keys sent; the injector is never run). Every status line must
; read its own field, and every push must land where the module reads it.
TwcModuleIni() {
    for sect, keys in Map("HealthBars", ["numbers", "mana", "portrait", "on", "colours"], "Display", ["widescreen", "fps", "hideUi"], "Hosting", ["latency"], "Timers", ["show"])
        for key in keys
            IniWrite(1, iniFile, sect, key)
    IniWrite(3, iniFile, "Display", "hideParts")
    IniWrite("game", iniFile, "Timers", "where")
}
TwcModuleIni()
global twcShmBuf := Buffer(Shm.size, 0)

TwcModuleFill() {
    v := twcShmBuf.Ptr
    NumPut("uint", 0x54574331, v, Shm.magic), NumPut("uint", 11, v, Shm.layout), NumPut("uint", 7680, v, Shm.build)
    NumPut("uint", 1, v, Shm.status), NumPut("uint", 1, v, Shm.probe), NumPut("uint", 1, v, Shm.ui)
    for f in ["hbState", "hcState", "wsState", "fpsState", "latState", "stState", "itState", "hnState", "mbState", "prState"]
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
    TwcCheck(s.loaded && s.layout = 11 && s.live && s.probe = 1 && s.build = 7680, "state: loaded, layout 11, live, probe passed")
    TwcCheck(InStr(gameModule.statusText(), "check passed"), "module: " gameModule.statusText())
    t := gameModule.timers()
    TwcCheck(t.cd[1].left = 4.5 && t.buffs.Length = 1 && t.buffs[1].left = 9, "timers: the first cooldown and buff")
    want := Map(
        "bars", [(*) => healthBars.statusText(), "0.0040 high"],
        "colours", [(*) => healthBars.colourStatus(), "yours green"],
        "numbers", [(*) => healthBars.numberStatus(), "(12 now)"],
        "mana", [(*) => healthBars.manaStatus(), "(5 now)"],
        "portrait", [(*) => healthBars.portraitStatus(), "regen next to"],
        "widescreen", [(*) => gameDisplay.wsStatus(), "16:9 in this game"],
        "fps", [(*) => gameDisplay.fpsStatus(), "the game's own setting: 60"],
        "hide", [(*) => gameDisplay.hideStatus(), "time of day, minimap"],
        "latency", [(*) => gameDisplay.latencyStatus(), "LAN 100, Battle.net 250"],
        "timers", [(*) => timersHud.statusText(), "drawn in the game"])
    for name, w in want {
        st := w[1]()
        TwcCheck(InStr(st, w[2]), name ": " st)
    }
    healthBars.push(), gameDisplay.push(), timersHud.pushGame()
    v := twcShmBuf.Ptr
    for f in ["hnOn", "mbOn", "prOn", "itOn", "hbOn", "hcOn", "wsOn", "fpsOn", "latOn"]
        TwcCheck(NumGet(v, Shm.%f%, "uint") = 1, "pushed " f)
    TwcCheck(NumGet(v, Shm.uiHide, "uint") = 3 && NumGet(v, Shm.fpsLimit, "uint") = 200 && NumGet(v, Shm.latMs, "uint") = 50
        && Abs(NumGet(v, Shm.mbHeight, "float") - 0.75) < 0.001 && Abs(NumGet(v, Shm.hbHeight, "float") - 1.5) < 0.001, "pushed values: parts, FPS limit, latency, mana and bar height")
    rows := ModuleCheckRows(ModuleCheckLog())
    TwcCheck(rows.Length >= 20, "Module check rows: " rows.Length)
    ShowPage("wc3"), Wc3ShowVersion("128")
    for tab in Wc3Tabs()
        Wc3ShowTab(tab[1])
    TwcCheck(true, "WC3 page with the module running")
    fake.Destroy()
    TwcCheckDone()
}
SetTimer(TwcModuleRun, -7000)
