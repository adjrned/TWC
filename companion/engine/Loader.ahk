#Requires AutoHotkey v2.0
; ============================================================================
;  LoaderEngine - TWRPG save file browsing + loading. No GUI; returns data.
; ============================================================================
class LoaderEngine {
    section := "Loader"
    hiddenMap := Map()
    detected := ""          ; cached detect() result

    __New() {
        this.loadHidden()
        HotIfWinActive(WarcraftIII)
        Hotstring(":*XB0:-l",       (*) => this.hotstrLoad())
        Hotstring(":*XB0:-load",    (*) => this.hotstrLoad())
        Hotstring(":XB0:-ll",       (*) => this.load(Map("useLast", 1)))
        Hotstring(":XB0:-loadlast", (*) => this.load(Map("useLast", 1)))
        HotIfWinActive()
    }

    hiddenPath => A_ScriptDir "\HiddenFiles.txt"
    static SUB := "CustomMapData\TWRPG"

    ; The folder you picked, if it still exists; otherwise wherever TWRPG saves
    ; are found (see candidates); otherwise the usual Reforged location.
    folder {
        get {
            f := Ini(this.section, "folder", "")
            if f && DirExist(f)
                return f
            if !this.detected || !DirExist(this.detected)
                this.detected := this.detect()
            return this.detected ? this.detected : A_MyDocuments "\Warcraft III\" LoaderEngine.SUB
        }
    }
    folderFound => DirExist(this.folder) ? 1 : 0
    folderAuto => !(Ini(this.section, "folder", "") && DirExist(Ini(this.section, "folder", "")))

    ; Where WC3 keeps TWRPG saves, most likely first:
    ;  Reforged / 1.28+: <Documents>\Warcraft III\CustomMapData\TWRPG (Documents
    ;    may be redirected to OneDrive), PTR uses "Warcraft III Public Test";
    ;  1.26/1.27 (classic): <install folder>\CustomMapData\TWRPG.
    candidates() {
        docs := [A_MyDocuments, EnvGet("USERPROFILE") "\Documents"]
        for od in [EnvGet("OneDrive"), EnvGet("OneDriveConsumer"), EnvGet("OneDriveCommercial")]
            if od
                docs.Push(od "\Documents")
        Loop Files, EnvGet("USERPROFILE") "\OneDrive*", "D"
            docs.Push(A_LoopFileFullPath "\Documents")
        out := []
        for d in docs
            for game in ["Warcraft III", "Warcraft III Public Test"]
                out.Push(d "\" game "\" LoaderEngine.SUB)
        for dir in this.installDirs()
            out.Push(dir "\" LoaderEngine.SUB)
        seen := Map(), uniq := []
        for p in out
            if !seen.Has(StrLower(p))
                seen[StrLower(p)] := 1, uniq.Push(p)
        return uniq
    }

    ; classic WC3 install folders: Blizzard's registry keys, plus a running game
    installDirs() {
        dirs := []
        for key in ["HKCU\Software\Blizzard Entertainment\Warcraft III",
                    "HKLM\SOFTWARE\WOW6432Node\Blizzard Entertainment\Warcraft III",
                    "HKLM\SOFTWARE\Blizzard Entertainment\Warcraft III"]
            for val in ["InstallPath", "InstallPathX"]
                try if (p := RegRead(key, val))
                    dirs.Push(RTrim(p, "\"))
        for exe in ["war3.exe", "Warcraft III.exe", "Frozen Throne.exe"]
            if pid := ProcessExist(exe) {
                try {
                    SplitPath(ProcessGetPath(pid), , &dir)
                    dirs.Push(dir)
                    SplitPath(dir, , &parent)       ; Reforged: <install>\_retail_\x86_64\
                    dirs.Push(parent)
                }
            }
        return dirs
    }

    ; first candidate holding a TWRPG save, else the first that exists
    detect() {
        existing := ""
        for p in this.candidates() {
            if !DirExist(p)
                continue
            if !existing
                existing := p
            Loop Files, p "\*.txt"
                if LoaderEngine.IsSave(FileRead(A_LoopFileFullPath, "UTF-8"))
                    return p
        }
        return existing
    }

    static IsSave(text) => RegExMatch(text, "----------(?:Hero Inventory|영웅 아이템)----------")

    ; -- RPC endpoints -------------------------------------------------------
    config(args := 0) {
        return { folder: this.folder, found: this.folderFound, auto: this.folderAuto,
            convert: Integer(Ini(this.section, "convert", 1)) }
    }

    files(args := 0) {
        filter := args && args.Has("filter") ? args["filter"] : ""
        showHidden := args && args.Has("showHidden") ? args["showHidden"] : 0
        out := []
        Loop Files, this.folder "\*.txt" {
            if filter && !InStr(A_LoopFileName, filter)
                continue
            isHidden := this.hiddenMap.Has(A_LoopFileName) ? 1 : 0
            if isHidden && !showHidden
                continue
            if !LoaderEngine.IsSave(FileRead(A_LoopFileFullPath, "UTF-8"))
                continue
            out.Push({
                name: A_LoopFileName,
                date: FormatTime(A_LoopFileTimeModified, "MM/dd/yy  hh:mm tt"),
                sortKey: A_LoopFileTimeModified,
                hidden: isHidden,
                msg: Ini(this.section "Msg", A_LoopFileName, "")
            })
        }
        return out
    }

    pinned(args := 0) {
        raw := Ini(this.section, "pinned", "")
        return raw ? StrSplit(raw, "|") : []
    }

    pinToggle(args) {
        name := args["name"]
        list := this.pinned()
        idx := 0
        for i, f in list
            if f == name {
                idx := i
                break
            }
        if idx
            list.RemoveAt(idx)
        else if list.Length >= 10
            return { error: "Quick Load is full (10 max)", pinned: list }
        else
            list.Push(name)
        SetIni(list.Length ? Join("|", list*) : "", this.section, "pinned")
        return { pinned: list }
    }

    hideToggle(args) {
        name := args["name"]
        if this.hiddenMap.Has(name)
            this.hiddenMap.Delete(name)
        else
            this.hiddenMap.Set(name, true)
        this.writeHidden()
        return { ok: 1 }
    }

    setMessage(args) {
        SetIni(args["msg"], this.section "Msg", args["name"])
        return { ok: 1 }
    }

    setConvert(args) {
        SetIni(args["value"], this.section, "convert")
        return { ok: 1 }
    }

    openFolder(args := 0) {
        try Run(this.folder)
        return { ok: 1 }
    }

    setFolder(args := 0) {
        folder := SelectFolder()
        if folder
            SetIni(folder, this.section, "folder")
        return { folder: this.folder }
    }

    ; forget the picked folder and go back to auto-detection
    autoFolder(args := 0) {
        try IniDelete(iniFile, this.section, "folder")
        this.detected := ""
        return { folder: this.folder }
    }

    hotstrLoad() {
        input := this.getTypedInput()
        if !input
            input := Ini(this.section, "selectedFile", "")
        else if SubStr(input, 1, 1) == " "
            input := SubStr(input, 2)
        else
            return
        if !InStr(input, ".txt")
            input .= ".txt"
        this.load(Map("name", input))
    }

    getTypedInput() {
        hook := InputHook("V", "{Enter}")
        hook.VisibleNonText := false
        hook.Start()
        hook.Wait()
        return hook.Input
    }

    load(args) {
        global toolEnabled
        useLast := args.Has("useLast") ? args["useLast"] : 0
        name := useLast ? Ini(this.section, "selectedFile", "") : (args.Has("name") ? args["name"] : "")
        if !name {
            Push("toast", { kind: "error", msg: "No save file specified" })
            return { error: "no file" }
        }
        path := this.folder "\" name
        if !FileExist(path) {
            Push("toast", { kind: "error", msg: "File not found: " name })
            return { error: "not found" }
        }
        SetIni(name, this.section, "selectedFile")
        text := FileRead(path, "UTF-8")

        if !RegExMatch(text, "(?:User Name|아이디):\s*([^\r\n]+)", &m) {
            Push("toast", { kind: "error", msg: "No user name in " name })
            return { error: "no name" }
        }
        userName := Trim(m[1])

        codes := []
        pos := 1
        while pos := InStr(text, "-load", , pos) {
            if RegExMatch(text, "-load [A-Za-z\d\?@#$%&\-]*", &lm, pos)
                codes.Push(lm[0])
            pos += 5
        }
        if !codes.Length {
            Push("toast", { kind: "error", msg: "No -load codes in " name })
            return { error: "no codes" }
        }

        if !FocusWarcraft() {
            Push("toast", { kind: "error", msg: "Warcraft III not found" })
            return { error: "no wc3" }
        }

        HideMainWindow()
        delay := Integer(Ini("Settings", "loadDelay", 200))
        if msg := Ini(this.section "Msg", name, "")
            wc3Chat(msg)
        if Integer(Ini(this.section, "convert", 1))
            wc3Chat("-convert " userName)
        for code in codes {
            Sleep(delay)
            wc3Chat(code)
        }
        wc3Chat("-refresh")
        Sleep(Integer(Ini("Settings", "postLoadDelay", 1000)))
        ControlSend("{f1}{Ctrl Down}{1}{Ctrl Up}", , WarcraftIII)
        if Integer(Ini("Settings", "summonBagAfterLoad", 0))
            ControlSend("{Esc}", , WarcraftIII)
        if Integer(Ini("Settings", "enableToolAfterLoad", 0)) && !toolEnabled
            ToggleTool()
        Push("toast", { kind: "ok", msg: "Loaded " StrReplace(name, ".txt", "") " (" codes.Length " codes)" })
        return { ok: 1 }
    }

    ; -- hidden files persistence -------------------------------------------
    loadHidden() {
        this.hiddenMap := Map()
        try {
            for f in StrSplit(FileRead(this.hiddenPath, "UTF-8"), "`n")
                if Trim(f)
                    this.hiddenMap.Set(Trim(f), true)
        }
    }

    writeHidden() {
        arr := []
        for k in this.hiddenMap
            arr.Push(k)
        try FileDelete(this.hiddenPath)
        if arr.Length
            FileAppend(Join("`n", arr*), this.hiddenPath, "UTF-8")
    }
}
