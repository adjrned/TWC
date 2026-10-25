#Requires AutoHotkey v2.0
; ============================================================================
;  LoaderEngine - TWRPG save file browsing + loading. No GUI; returns data.
; ============================================================================
class LoaderEngine {
    section := "Loader"
    hiddenMap := Map()
    detected := ""          ; cached detect() result
    sessionLast := ""       ; save loaded / saved through the companion since it started (-sn follows it)
    adopted := Map()        ; "lm.txt" -> "lm#*": unnumbered saves that head a series (see files)
    static DEFAULT_MSG := "% time!"

    __New() {
        this.loadHidden()
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

    ; -- numbered saves --------------------------------------------------------
    ; People save as knight#91, knight#92... ("-save knight#92" in TWRPG). Those
    ; files form a series: one row in the list, one star / hide / load message
    ; (stored under the series key "knight#*"), and -sn saves the next number.
    ; "knight#91" -> { stem: "knight", sep: "#", num: 91, width: 2, key: "knight#*" }
    static Series(name) {
        n := RegExReplace(name, "i)\.txt$")
        if !RegExMatch(n, "^(.*?[^\d\s#_.\-])(\s*[#_.\-]?\s*)(\d+)$", &m)
            return 0
        return { stem: m[1], sep: m[2], num: Integer(m[3]), width: StrLen(m[3]), key: StrLower(m[1]) "#*" }
    }
    ; star / hide / message key for a save: its series, or the file itself
    static KeyOf(name) => (s := LoaderEngine.Series(name)) ? s.key : name
    ; the same, counting an unnumbered save that heads a series ("lm" with lm#2)
    keyOf(name) => this.adopted.Get(StrLower(name), LoaderEngine.KeyOf(name))

    ; the file name TWRPG writes for "-save <name>": it drops spaces and saves
    ; lowercase ("-save Sorc 3" -> sorc3.txt)
    static TwrpgName(name) => StrLower(RegExReplace(name, "\s+"))

    ; name for the next save in a series: the highest number on disk + 1 (so
    ; going back to an older save never overwrites a newer one). ref is a save
    ; or series name; default = the save loaded through the companion this
    ; session (not one remembered from an earlier day: you may be on another
    ; hero now). Unnumbered names start a series at #2 (they count as #1).
    nextSave(ref := "") {
        ref := RegExReplace(ref != "" ? ref : this.sessionLast, "i)\.txt$")
        if ref = ""
            return ""
        s := LoaderEngine.Series(ref)
        if !s
            s := { stem: ref, sep: "#", num: 1, width: 1, key: StrLower(ref) "#*" }
        top := s.num
        for f in this.files(Map("showHidden", 1))
            if (fs := LoaderEngine.Series(f.name)) && fs.key = s.key && fs.num > top
                top := fs.num, s.sep := fs.sep, s.width := fs.width
        return LoaderEngine.TwrpgName(s.stem s.sep Format("{:0" s.width "}", top + 1))
    }

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
            key := LoaderEngine.KeyOf(A_LoopFileName)
            isHidden := this.hiddenMap.Has(key) || this.hiddenMap.Has(A_LoopFileName) ? 1 : 0
            if !LoaderEngine.IsSave(FileRead(A_LoopFileFullPath, "UTF-8"))
                continue
            s := LoaderEngine.Series(A_LoopFileName)
            out.Push({
                name: A_LoopFileName,
                key: key,
                series: s,
                date: FormatTime(A_LoopFileTimeModified, "MM/dd/yy  hh:mm tt"),
                sortKey: A_LoopFileTimeModified,
                hidden: isHidden,
                msg: ""
            })
        }
        ; an unnumbered save is #1 of the series -sn starts from it: "lm" joins
        ; lm#2, lm#3 (one row, one star / hide / message, moved over once)
        keys := Map()
        for f in out
            if f.series
                keys[f.series.key] := 1
        this.adopted := Map()
        for f in out {
            base := RegExReplace(f.name, "i)\.txt$")
            if !f.series && keys.Has(k := StrLower(base) "#*") {
                this.adopt(f.name, k)
                f.series := { stem: base, sep: "#", num: 1, width: 1, key: k }
                f.key := k
                f.hidden := this.hiddenMap.Has(k) ? 1 : 0
            }
        }
        for f in out
            f.msg := this.messageFor(f.name)
        if !showHidden {
            kept := []
            for f in out
                if !f.hidden
                    kept.Push(f)
            out := kept
        }
        return out
    }

    ; move a save's own star / hide / message to its series key
    adopt(name, key) {
        this.adopted[StrLower(name)] := key
        raw := Ini(this.section, "pinned", "")
        if raw {
            list := [], seen := Map()
            for n in StrSplit(raw, "|")
                if !seen.Has(n := (n = name ? key : n))
                    seen[n] := 1, list.Push(n)
            if (fixed := Join("|", list*)) != raw
                SetIni(fixed, this.section, "pinned")
        }
        if this.hiddenMap.Has(name) {
            this.hiddenMap.Delete(name), this.hiddenMap[key] := true
            this.writeHidden()
        }
        own := Ini(this.section "Msg", name, Chr(1))
        if own != Chr(1) {
            if Ini(this.section "Msg", key, Chr(1)) = Chr(1)
                SetIni(own, this.section "Msg", key)
            try IniDelete(iniFile, this.section "Msg", name)
        }
    }

    ; favourites, by key; entries saved per file before series existed
    ; (knight#91.txt) are folded into their series key (knight#*) once
    pinned(args := 0) {
        raw := Ini(this.section, "pinned", "")
        out := [], seen := Map()
        for n in (raw ? StrSplit(raw, "|") : [])
            if !seen.Has(k := LoaderEngine.KeyOf(n))
                seen[k] := 1, out.Push(k)
        if (fixed := Join("|", out*)) != raw
            SetIni(fixed, this.section, "pinned")
        return out
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

    ; load message for a save: its series' one, else its own, else "% time!"
    ; (one cleared on purpose is kept as "" and sends nothing)
    messageFor(name) {
        m := Ini(this.section "Msg", this.keyOf(name), Chr(1))
        if m = Chr(1)
            m := Ini(this.section "Msg", name, Chr(1))
        return m = Chr(1) ? LoaderEngine.DEFAULT_MSG : m
    }

    ; % in a load message is the save's name ("knight" for knight#92)
    static FillMessage(msg, name) {
        s := LoaderEngine.Series(name)
        return StrReplace(msg, "%", s ? s.stem : RegExReplace(name, "i)\.txt$"))
    }

    ; "a | b | c" -> one of the options at random (flavour text)
    pickMessage(raw) {
        opts := []
        for o in StrSplit(raw, "|")
            if Trim(o) != ""
                opts.Push(Trim(o))
        return opts.Length ? opts[Random(1, opts.Length)] : ""
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

    ; -- chat commands -------------------------------------------------------
    ; The main script hands every finished WC3 chat line to isCommand(); loader
    ; commands are kept out of chat and run here instead:
    ;   -l <name> / -load <name>   best match: exact, then starts with, then
    ;                              contains (favourites, then newest, win ties)
    ;   -l <n>                     favourite number n
    ;   -l / -ll / -loadlast       the last save you loaded
    ;   -sn / -savenext [name]     "-save <next number>" for that series
    static CMD := "i)^\s*-(l|load|ll|loadlast|sn|savenext)(?:\s+(.*?))?\s*$"

    isCommand(line) {
        if !RegExMatch(line, LoaderEngine.CMD, &m)
            return false
        return !(m[2] != "" && (m[1] = "ll" || m[1] = "loadlast"))
    }

    command(line) {
        RegExMatch(line, LoaderEngine.CMD, &m)
        arg := Trim(m[2])
        if m[1] = "sn" || m[1] = "savenext" {
            name := this.nextSave(arg)
            if name = ""
                return Push("toast", { kind: "error", msg: "Load a save with the companion first, or type -sn <name>" })
            if !FocusWarcraft()
                return Push("toast", { kind: "error", msg: "Warcraft III not found" })
            wc3Chat("-save " name)
            ; that's now the save to continue from: -ll loads it, the next -sn
            ; counts up from it even before TWRPG has written the file
            SetIni(name ".txt", this.section, "selectedFile")
            this.sessionLast := name ".txt"
            SetClipboardAfterChat(name)         ; the save's name, to paste where you keep track of them
            return Push("toast", { msg: "Saved as " name " · copied to the clipboard" })
        }
        if arg = "" {
            last := Ini(this.section, "selectedFile", "")
            if !last && (fav := this.pinned()).Length
                last := InStr(fav[1], "#*") ? this.latestOf(fav[1]) : fav[1]
            if !last
                return Push("toast", { kind: "error", msg: "No save loaded yet. Try -l <name>" })
            return this.load(Map("name", last))
        }
        name := this.resolve(arg)
        if !name
            return Push("toast", { kind: "error", msg: 'No save matches "' arg '"' })
        Push("toast", { msg: "Loading " StrReplace(name, ".txt", "") "…" })
        return this.load(Map("name", name))
    }

    ; newest-numbered file of a series key
    latestOf(key, files := 0) {
        best := "", top := -1
        for f in (files ? files : this.files(Map("showHidden", 1)))
            if f.key = key && f.series && f.series.num > top
                best := f.name, top := f.series.num
        return best
    }

    ; save file name for what was typed after -l, or ""
    resolve(arg) {
        ; compare without spaces: TWRPG never writes them ("-l sorc 3" -> sorc3)
        q := LoaderEngine.TwrpgName(StrReplace(arg, ".txt", ""))
        pins := Map()
        for i, n in this.pinned()
            pins[n] := i
        files := this.files(Map("showHidden", 1))
        ; a number is a favourite slot (when you have that many favourites and no
        ; save is literally called that); otherwise it's matched as a name, so
        ; "-l 92" finds knight#92
        if IsInteger(q) && Integer(q) >= 1 && Integer(q) <= pins.Count {
            for f in files
                if LoaderEngine.TwrpgName(StrReplace(f.name, ".txt", "")) == q
                    return f.name
            for n, i in pins
                if i = Integer(q)
                    return InStr(n, "#*") ? this.latestOf(n, files) : n
        }
        ; ties: favourite, not hidden, then the highest number in a series, then newest
        best := "", bestScore := 0, bestNum := -1, bestKey := ""
        for f in files {
            n := LoaderEngine.TwrpgName(StrReplace(f.name, ".txt", ""))
            score := n == q ? 3 : SubStr(n, 1, StrLen(q)) == q ? 2 : InStr(n, q) ? 1 : 0
            if f.series && LoaderEngine.TwrpgName(f.series.stem) == q
                score := 3                                  ; "-l knight" = the series
            if !score
                continue
            score := score * 10 + (pins.Has(f.key) || pins.Has(f.name) ? 5 : 0) + (f.hidden ? 0 : 1)
            num := f.series ? f.series.num : -1
            if score > bestScore || (score = bestScore && (num > bestNum || (num = bestNum && f.sortKey > bestKey)))
                best := f.name, bestScore := score, bestNum := num, bestKey := f.sortKey
        }
        return best
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
        text := FileRead(path, "UTF-8")

        ; saves are WC3 preload files - call Preload( "User Name: X" ) - so stop at the quote
        if !RegExMatch(text, '(?:User Name|아이디):\s*([^"\r\n]+)', &m) {
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
        try DebugLog("load " name ": " codes.Length " codes, " (InStr(WC3WindowKey(), "reforged") ? "Reforged way (wait for the chat box, {Text})" : "1.28 way"))
        ; keyboard/mouse are held for the 1-2 s this takes: a key or Enter
        ; pressed mid-load would land inside the codes (needs admin, which the
        ; companion has; Ctrl+Alt+Del always releases it)
        BlockInput("On")
        try {
            if msg := this.pickMessage(this.messageFor(name))
                wc3Chat(LoaderEngine.FillMessage(msg, name))
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
        } finally {
            BlockInput("Off")
        }
        ; only a load that went through counts as "last" (-ll, -sn)
        SetIni(name, this.section, "selectedFile")
        this.sessionLast := name
        Push("toast", { kind: "ok", msg: "Loaded " StrReplace(name, ".txt", "") " (" codes.Length " codes)" })
        return { ok: 1 }
    }

    ; -- hidden files persistence -------------------------------------------
    loadHidden() {
        this.hiddenMap := Map()
        try {
            for f in StrSplit(FileRead(this.hiddenPath, "UTF-8"), "`n")
                if Trim(f)
                    this.hiddenMap.Set(LoaderEngine.KeyOf(Trim(f)), true)   ; per-file -> series key
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
