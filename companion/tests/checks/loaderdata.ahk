; The loader's data (2026-11-16): per-save settings in [Save <key>] sections, moved once from the four old
; places (migrate); listing writes nothing; the list's rows built in the engine (rows); the folder scan
; reads only new / changed files; a series' older saves archived; the folder watch; and a line waiting
; for the game's chat box to close (ChatWaitClosed, a stand-in chat state). Scratch folders and the
; checks' own ini; the ignored-list file is a scratch one. No key is sent.
TwcLoaderDataRun() {
    global loader, iniFile, gameModule
    dir := A_Temp "\twc-check-loaderdata", hid := A_Temp "\twc-check-loaderdata-hidden.txt"
    try DirDelete(dir, true)
    DirCreate(dir)
    body := "----------Hero Inventory----------`n-load abc`n"
    for n in ["knight#90.txt", "knight#91.txt", "knight#92.txt", "lm.txt", "lm#2.txt", "Sniper.txt", "notes.txt"]
        FileAppend(n = "notes.txt" ? "not a save`n" : body, dir "\" n, "UTF-8")
    keepFolder := Ini(loader.section, "folder", "")
    SetIni(dir, loader.section, "folder")
    err := ""
    try {
        ; -- the old places, moved once
        IniWrite("knight#91.txt|Sniper.txt|lm.txt", iniFile, loader.section, "pinned")
        IniWrite("own", iniFile, "LoaderMsg", "knight#91.txt")
        IniWrite("series", iniFile, "LoaderMsg", "knight#*")
        IniWrite("", iniFile, "LoaderMsg", "Sniper.txt")
        IniWrite("Hero", iniFile, "LoadProfiles", "knight#92.txt")
        try FileDelete(hid)
        FileAppend("lm.txt`nknight#90.txt`n", hid, "UTF-8")
        loader.DefineProp("hiddenPath", { get: (*) => hid }), loader.DefineProp("ownHidden", { get: (*) => true })
        loader.readSaves(), loader.migrate()
        loader.DeleteProp("hiddenPath"), loader.DeleteProp("ownHidden")
        loader.files()
        pins := Join(",", loader.pinned()*)
        m1 := loader.messageFor("knight#93.txt"), m2 := loader.messageFor("Sniper.txt"), m3 := loader.messageFor("other.txt")
        p1 := loader.profileFor("knight#1.txt")
        h1 := loader.get("knight#*", "ignored"), h2 := loader.get("lm#*", "ignored")
        gone := Ini(loader.section, "pinned", "-") = "-" && !FileExist(hid)
        try gone := gone && (IniRead(iniFile, "LoaderMsg") = "x")
        try gone := gone && (IniRead(iniFile, "LoadProfiles") = "x")
        TwcCheck(pins = "knight#*,sniper.txt,lm#*" && m1 = "series" && m2 = "" && m3 = LoaderEngine.DEFAULT_MSG && p1 = "Hero"
            && h1 = "1" && h2 = "1" && gone,
            "moved once: favourites " pins "; messages series '" m1 "' (over a numbered save's), cleared '" m2 "', default '" m3
            "'; profile " p1 "; ignored knight " h1 " / lm (its head save's) " h2 "; the old places gone: " gone)

        ; -- listing writes nothing
        before := FileRead(iniFile), loader.files(Map("showHidden", 1)), loader.rows(), after := FileRead(iniFile)
        TwcCheck(before == after, "listing writes nothing to the ini")

        ; -- the rows: one per series (named after its unnumbered save), favourites first
        rs := loader.rows(), desc := ""
        for r in rs
            desc .= (desc != "" ? " | " : "") r.label (r.kind = "series" ? " x" r.files.Length : "") (r.pinned ? " *" r.pinned : "") (r.hidden ? " (ignored)" : "")
        TwcCheck(desc = "knight x3 *1 (ignored) | Sniper *2 | lm x2 *3 (ignored)" && rs[1].name = "knight#92.txt" && rs[1].files[1].name = "knight#92.txt",
            "rows: " desc "; knight loads " rs[1].name)
        ; a head save's star is the series': un-starring the series takes it off
        loader.pinToggle(Map("name", "lm#*"))
        s1 := loader.get("lm.txt", "star") = "" && loader.get("lm#*", "star") = ""
        loader.hideToggle(Map("name", "lm#*")), s2 := loader.get("lm#*", "ignored") = "" && loader.get("lm.txt", "ignored") = ""
        TwcCheck(s1 && s2 && Join(",", loader.pinned()*) = "knight#*,sniper.txt", "lm's star / ignore lived on lm.txt: off for the series, from both")

        ; -- the scan cache: an unchanged file isn't read again; a changed one is
        n0 := loader.files(Map("showHidden", 1)).Length
        f := FileOpen(dir "\notes.txt", "w", "UTF-8"), f.Write(body body), f.Close()
        n1 := loader.files(Map("showHidden", 1)).Length
        FileDelete(dir "\notes.txt")
        n2 := loader.files(Map("showHidden", 1)).Length
        loop 300
            FileAppend(body, dir "\bulk" A_Index ".txt", "UTF-8")
        t := A_TickCount, loader.files(Map("showHidden", 1)), cold := A_TickCount - t
        t := A_TickCount, loader.files(Map("showHidden", 1)), warm := A_TickCount - t
        loop 300
            FileDelete(dir "\bulk" A_Index ".txt")
        TwcCheck(n0 = 6 && n1 = 7 && n2 = 6 && warm < cold, "scan: " n0 " saves, notes.txt rewritten as a save: " n1 ", deleted: " n2 "; 300 more: " cold " ms first, " warm " ms again")

        ; -- the right-click menu of a series row builds (with its Archive submenu); Show stubbed: nothing opens
        global saveFiles, saveOffset, showHidden
        ShowPage("loader"), showHidden := true, RefreshFiles(), idx := 0
        for i, row in saveFiles
            if row.kind = "series" && row.key = "knight#*"
                idx := i
        shown := 0
        Menu.Prototype.DefineProp("Show", { call: (*) => shown++ })
        try SaveContext(idx - saveOffset)
        finally Menu.Prototype.DeleteProp("Show"), showHidden := false
        TwcCheck(idx && shown = 1, "a series row's right-click menu builds (row " idx ")")

        ; -- archive: knight keeps its newest 1; a name already in Archive isn't overwritten
        DirCreate(dir "\Archive"), FileAppend("old", dir "\Archive\knight#90.txt", "UTF-8")
        c := loader.archiveCount("knight#*", 1), r := loader.archiveSeries("knight#*", 1)
        left := ""
        for f2 in loader.files(Map("showHidden", 1))
            if f2.key = "knight#*"
                left .= f2.name
        TwcCheck(c = 2 && r.moved = 2 && left = "knight#92.txt" && FileExist(dir "\Archive\knight#91.txt")
            && FileExist(dir "\Archive\knight#90 (2).txt") && FileRead(dir "\Archive\knight#90.txt") = "old",
            "archive: " r.moved " of " c " moved, left " left ", the one already there kept (knight#90 (2).txt)")

        ; -- the folder watch (the page's own 1 s watch paused: it takes the same signal)
        SetTimer(LoaderWatch, 0), loader.stopWatch()
        w0 := loader.folderChanged(), w1 := loader.folderChanged()
        FileAppend(body, dir "\fresh.txt", "UTF-8"), Sleep(150)
        w2 := loader.folderChanged(), w3 := loader.folderChanged()
        TwcCheck(!w0 && !w1 && w2 && !w3, "folder watch: quiet " w0 w1 ", a new save " w2 ", then quiet " w3)
        loader.stopWatch()

        ; -- a chat line waits for the game's chat box (1.28f, the module): open too long = stopped
        gameModule.DefineProp("chatState", { call: (*) => 2 })
        t := A_TickCount, threw := ""
        try ChatWaitClosed(200)
        catch ChatStopped as e2
            threw := e2.Message
        waited := A_TickCount - t
        gameModule.DefineProp("chatState", { call: (*) => 1 })
        t := A_TickCount, ChatWaitClosed(200), quick := A_TickCount - t
        gameModule.DeleteProp("chatState")
        TwcCheck(InStr(threw, "stayed open") && waited >= 200 && quick < 50, "chat box: open throws after " waited " ms (" threw "), closed: " quick " ms")
    } catch as e
        err := e.Message " (line " e.Line ")"
    try gameModule.DeleteProp("chatState")
    SetTimer(LoaderWatch, 1000)
    try loader.DeleteProp("hiddenPath")
    try loader.DeleteProp("ownHidden")
    if keepFolder != ""
        SetIni(keepFolder, loader.section, "folder")
    else
        try IniDelete(iniFile, loader.section, "folder")
    try DirDelete(dir, true)
    try FileDelete(hid)
    if err != ""
        TwcCheck(false, "error: " err)
    TwcCheckDone()
}
SetTimer(TwcLoaderDataRun, -6000)
