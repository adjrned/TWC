; The loader's Ignore (the save rows' right-click menu and eye, 2026-11-01): an ignored save leaves the list
; (Show ignored brings it back) and -l's guesses, but its exact name still loads it. Saves in a scratch
; folder; the ignored list is a scratch file too (the real HiddenFiles.txt is never touched).
TwcLoaderRun() {
    global loader, showHidden, saveFiles, hiddenChip
    dir := A_Temp "\twc-check-loader", hid := A_Temp "\twc-check-loader-hidden.txt"
    try DirDelete(dir, true)
    DirCreate(dir)
    try FileDelete(hid)
    body := "----------Hero Inventory----------`n-load abc`n"
    for n in ["sniper.txt", "snipe2.txt", "knight#91.txt", "knight#92.txt"]
        FileAppend(body, dir "\" n, "UTF-8")
    keepFolder := Ini(loader.section, "folder", "")
    SetIni(dir, loader.section, "folder")
    loader.DefineProp("hiddenPath", { get: (*) => hid })
    loader.loadHidden()
    err := ""
    try {
        r0 := loader.resolve("snip")
        loader.hideToggle(Map("name", "sniper.txt"))
        r1 := loader.resolve("snip"), r2 := loader.resolve("sniper")
        loader.hideToggle(Map("name", "knight#*"))
        r3 := loader.resolve("knight"), r4 := loader.resolve("kni")
        ShowPage("loader"), showHidden := false, RefreshFiles()
        listed := "", chip := hiddenChip.Text
        for f in saveFiles
            listed .= f.label ","
        showHidden := true, RefreshFiles(), n2 := saveFiles.Length
        showHidden := false
        loader.hideToggle(Map("name", "sniper.txt")), loader.hideToggle(Map("name", "knight#*"))
        r5 := loader.resolve("snip")
    } catch as e
        err := e.Message
    if keepFolder != ""
        SetIni(keepFolder, loader.section, "folder")
    else
        try IniDelete(iniFile, loader.section, "folder")
    loader.DeleteProp("hiddenPath"), loader.loadHidden()
    try DirDelete(dir, true)
    try FileDelete(hid)
    TwcCheck(err = "" && r1 = "snipe2.txt" && r2 = "sniper.txt" && r3 = "knight#92.txt" && r4 = "" && r5 != "",
        "-l with ignored saves: 'snip' -> " r1 " (sniper ignored), 'sniper' -> " r2 " (exact), 'knight' -> " r3 " (the series' exact name), 'kni' -> '" r4 "'; back: " r5 (err != "" ? " (error: " err ")" : ""))
    TwcCheck(err = "" && listed = "snipe," && InStr(chip, "Show ignored") && InStr(chip, "(2)") && n2 = 3,
        "the list: only '" listed "' (chip '" chip "'), with Show ignored: " n2 " rows")
    TwcCheckDone()
}
SetTimer(TwcLoaderRun, -6000)
