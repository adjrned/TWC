#Requires AutoHotkey v2.0
; ============================================================================
;  LoaderEngine - TWRPG save file browsing + loading. No GUI; returns data.
; ============================================================================
class LoaderEngine {
    section := "Loader"
    hiddenMap := Map()

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
    folder => Ini(this.section, "folder", A_MyDocuments "\Warcraft III\CustomMapData\TWRPG")

    ; -- RPC endpoints -------------------------------------------------------
    config(args := 0) {
        return { folder: this.folder, convert: Integer(Ini(this.section, "convert", 1)) }
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
            text := FileRead(A_LoopFileFullPath, "UTF-8")
            if !RegExMatch(text, "----------(?:Hero Inventory|영웅 아이템)----------")
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
