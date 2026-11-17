#Requires AutoHotkey v2.0
; ============================================================================
;  LoaderEngine - TWRPG save file browsing + loading. No GUI; returns data.
; ============================================================================
class LoaderEngine {
    section := "Loader"
    detected := ""          ; cached detect() result
    sessionLast := ""       ; save loaded / saved through the companion since it started (-sn follows it)
    adopted := Map()        ; "lm.txt" -> "lm#*": unnumbered saves that head a series (see files)
    heads := Map()          ; the other way: "lm#*" -> "lm.txt"
    saves := Map()          ; per-save settings: key -> Map(field -> value) (see readSaves)
    scan := Map()           ; folder scan cache: lowercase path -> { t, size, ok } (see files)
    watch := 0              ; folder change notification: { path, h } (see folderChanged)
    static DEFAULT_MSG := "% time!"

    __New() {
        this.readSaves()
        this.migrate()
    }

    hiddenPath => A_ScriptDir "\HiddenFiles.txt"          ; the ignored list until 2026-11-16 (see migrate)
    ownHidden => iniFile = A_ScriptDir "\tw-companion.ini"
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
    ; star / hide / message key for a save: its series, or the file itself (lowercase)
    static KeyOf(name) => (s := LoaderEngine.Series(name)) ? s.key : StrLower(name)
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

    ; -- per-save settings ------------------------------------------------------
    ; One ini section per save or series (the user's pick, 2026-11-16: they were in four places, see
    ; migrate):  [Save knight#*]  star=2  ignored=1  msg=% time!  profile=Hero
    ; star = the favourites' order (lower first); msg absent = the default, "" = nothing sent.
    ; Keys are lowercase: a save's file name ("sniper.txt") or its series' ("knight#*").
    static FIELDS := ["star", "ignored", "msg", "profile"]
    static SecOf(key) => "Save " StrReplace(StrReplace(key, "%", "%25"), "]", "%5D")
    static KeyOfSec(sec) => StrLower(StrReplace(StrReplace(SubStr(sec, 6), "%5D", "]"), "%25", "%"))
    readSaves() {
        global iniFile
        this.saves := Map()
        try names := IniRead(iniFile)
        catch
            return
        for sec in StrSplit(names, "`n") {
            if SubStr(sec, 1, 5) != "Save "
                continue
            rec := Map()
            for f in LoaderEngine.FIELDS
                if (v := IniRead(iniFile, sec, f, Chr(1))) != Chr(1)
                    rec[f] := v
            if rec.Count
                this.saves[LoaderEngine.KeyOfSec(sec)] := rec
        }
    }
    ; a field of a save's settings ("" if unset). A series headed by an unnumbered save ("lm" with
    ; lm#2) also takes what was set on that save before the series began: read here, never moved
    get(key, field, default := "") {
        key := StrLower(key)
        if this.saves.Has(key) && this.saves[key].Has(field)
            return this.saves[key][field]
        if (head := this.heads.Get(key, "")) && this.saves.Has(head) && this.saves[head].Has(field)
            return this.saves[head][field]
        return default
    }
    ; set a field (Chr(1) = remove it); the series' own value from now on, so its head save's goes
    put(key, field, value := Chr(1)) {
        global iniFile
        key := StrLower(key), sec := LoaderEngine.SecOf(key)
        if !this.saves.Has(key)
            this.saves[key] := Map()
        rec := this.saves[key]
        if value == Chr(1) {
            if rec.Has(field)
                rec.Delete(field)
            try IniDelete(iniFile, sec, field)
        } else {
            rec[field] := value
            IniWrite(value, iniFile, sec, field)
        }
        if (head := this.heads.Get(key, "")) && this.saves.Has(head) && this.saves[head].Has(field)
            this.put(head, field)
        if !rec.Count {
            this.saves.Delete(key)
            try IniDelete(iniFile, sec)
        }
    }

    ; Settings from before [Save ...] (until 2026-11-16), moved once at start-up, then removed:
    ; [Loader] pinned (a|b|c, in order), HiddenFiles.txt (one per line, next to the companion),
    ; [LoaderMsg] key=msg, [LoadProfiles] key=profile. Per-file entries of numbered saves
    ; (knight#91.txt) go to their series; a series' own entry wins over them.
    migrate() {
        global iniFile
        raw := Ini(this.section, "pinned", Chr(1))
        if raw != Chr(1) {
            for n in StrSplit(raw, "|")
                if n != "" && this.get(k := LoaderEngine.KeyOf(n), "star") = ""
                    this.put(k, "star", this.nextStar())
            IniDelete(iniFile, this.section, "pinned")
        }
        ; only into the ini next to it (a check's scratch ini never takes, nor deletes, the real one's)
        if FileExist(this.hiddenPath) && this.ownHidden {
            for line in StrSplit(FileRead(this.hiddenPath, "UTF-8"), "`n", "`r")
                if Trim(line) != ""
                    this.put(LoaderEngine.KeyOf(Trim(line)), "ignored", 1)
            FileDelete(this.hiddenPath)
        }
        for sec, field in Map(this.section "Msg", "msg", "LoadProfiles", "profile") {
            try body := IniRead(iniFile, sec)
            catch
                continue
            lines := StrSplit(body, "`n")
            for pass in [1, 2]                      ; series / plain saves first, then numbered files
                for line in lines {
                    if !(p := InStr(line, "="))
                        continue
                    n := SubStr(line, 1, p - 1), k := LoaderEngine.KeyOf(n)
                    if (pass = 1) != (k = StrLower(n))
                        continue
                    if this.get(k, field, Chr(1)) == Chr(1)
                        this.put(k, field, SubStr(line, p + 1))
                }
            IniDelete(iniFile, sec)
        }
    }

    ; -- the save list ------------------------------------------------------------
    config(args := 0) {
        return { folder: this.folder, found: this.folderFound, auto: this.folderAuto,
            convert: Integer(Ini(this.section, "convert", 1)) }
    }

    ; Every save in the folder: { name, key, series, date, sortKey, hidden, msg }. Lists the folder and
    ; reads only files that are new or changed since the last time (time and size): reading all of them
    ; took ~1 ms each, before every -l / -sn and after each star (300 saves: 0.3 s). Has no side effects
    ; (it used to write settings while listing); keeps adopted / heads up to date.
    files(args := 0) {
        filter := args && args.Has("filter") ? args["filter"] : ""
        showHidden := args && args.Has("showHidden") ? args["showHidden"] : 0
        out := [], seen := Map()
        Loop Files, this.folder "\*.txt" {
            p := StrLower(A_LoopFileFullPath), t := A_LoopFileTimeModified, size := A_LoopFileSize
            c := this.scan.Get(p, 0)
            if !c || c.t != t || c.size != size
                c := { t: t, size: size, ok: LoaderEngine.IsSave(FileRead(A_LoopFileFullPath, "UTF-8")) ? 1 : 0 }
            seen[p] := c
            if !c.ok || filter && !InStr(A_LoopFileName, filter)
                continue
            out.Push({ name: A_LoopFileName, key: LoaderEngine.KeyOf(A_LoopFileName), series: LoaderEngine.Series(A_LoopFileName),
                date: FormatTime(t, "MM/dd/yy  hh:mm tt"), sortKey: t, hidden: 0, msg: "" })
        }
        this.scan := seen
        ; an unnumbered save is #1 of the series -sn starts from it: "lm" joins lm#2, lm#3
        ; (one row, one star / hide / message)
        keys := Map()
        for f in out
            if f.series
                keys[f.series.key] := 1
        this.adopted := Map(), this.heads := Map()
        for f in out {
            base := RegExReplace(f.name, "i)\.txt$")
            if !f.series && keys.Has(k := StrLower(base) "#*") {
                this.adopted[StrLower(f.name)] := k, this.heads[k] := StrLower(f.name)
                f.series := { stem: base, sep: "#", num: 1, width: 1, key: k }
                f.key := k
            }
        }
        for f in out
            f.hidden := this.get(f.key, "ignored") != "" ? 1 : 0, f.msg := this.messageFor(f.name)
        if !showHidden {
            kept := []
            for f in out
                if !f.hidden
                    kept.Push(f)
            out := kept
        }
        return out
    }

    ; The list's rows (the page only filters and draws them): a save of its own, or a series
    ; (knight#91, #92...) as one row named after it (its unnumbered save, "Sniper", if there is one,
    ; else "knight"), loading its newest number, with its saves newest first in .files.
    ; Favourites first in the order starred, then the most recent. q: only saves whose name has it.
    ;   { kind: "file" / "series", id, name, key, label, pinned (its place, 0 = no), hidden, msg,
    ;     date, sortKey, files: 0 / [{ name, label, date, sortKey }] }
    rows(q := "") {
        pins := Map()
        for i, k in this.pinned()
            pins[k] := i
        groups := Map(), tops := []
        for f in this.files(Map("showHidden", 1)) {
            if q != "" && !InStr(f.name, q)
                continue
            if f.series {
                if !groups.Has(f.key)
                    groups[f.key] := []
                groups[f.key].Push(f)
            } else
                tops.Push({ kind: "file", id: f.name, name: f.name, key: f.key, label: RegExReplace(f.name, "i)\.txt$"),
                    pinned: pins.Get(f.key, 0), hidden: f.hidden, msg: f.msg, date: f.date, sortKey: f.sortKey, files: 0 })
        }
        for key, fs in groups {
            SortBy(fs, (a, b) => b.series.num - a.series.num)              ; newest number first
            top := fs[1], label := top.series.stem, newest := "", kids := []
            for f in fs {
                if newest = "" || f.sortKey > newest
                    newest := f.sortKey
                if RegExReplace(f.name, "i)\.txt$") = f.series.stem
                    label := RegExReplace(f.name, "i)\.txt$")
                kids.Push({ name: f.name, label: RegExReplace(f.name, "i)\.txt$"), date: f.date, sortKey: f.sortKey })
            }
            tops.Push({ kind: "series", id: "S|" key, name: top.name, key: key, label: label,
                pinned: pins.Get(key, 0), hidden: top.hidden, msg: top.msg, date: top.date, sortKey: newest, files: kids })
        }
        SortBy(tops, (a, b) => (a.pinned && b.pinned) ? a.pinned - b.pinned
            : a.pinned ? -1 : b.pinned ? 1 : (a.sortKey < b.sortKey) - (a.sortKey > b.sortKey))
        return tops
    }

    ; favourites: keys in the order starred (a head save's star counts for its series)
    pinned(args := 0) {
        list := []
        for key, rec in this.saves
            if rec.Has("star")
                list.Push({ key: this.adopted.Get(key, key), star: Integer(rec["star"]) })
        SortBy(list, (a, b) => a.star - b.star)
        out := [], seen := Map()
        for e in list
            if !seen.Has(e.key)
                seen[e.key] := 1, out.Push(e.key)
        return out
    }
    nextStar() {
        top := 0
        for key, rec in this.saves
            if rec.Has("star")
                top := Max(top, Integer(rec["star"]))
        return top + 1
    }
    pinToggle(args) {
        key := args["name"]
        this.put(key, "star", this.get(key, "star") != "" ? Chr(1) : this.nextStar())
        return { pinned: this.pinned() }
    }
    hideToggle(args) {
        key := args["name"]
        this.put(key, "ignored", this.get(key, "ignored") != "" ? Chr(1) : 1)
        return { ok: 1 }
    }

    ; load message for a save: its series' (or its own), else "% time!" ("" = cleared on purpose: nothing)
    messageFor(name) {
        m := this.get(this.keyOf(name), "msg", Chr(1))
        return m == Chr(1) ? LoaderEngine.DEFAULT_MSG : m
    }
    setMessage(args) {
        this.put(args["name"], "msg", args["msg"])
        return { ok: 1 }
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

    ; a save's Remap profile (the user, 2026-11-01): loading it switches the remap to that profile;
    ; none: the profile in use stays
    profileFor(name) => this.get(this.keyOf(name), "profile")
    setProfileFor(name, profile) => this.put(this.keyOf(name), "profile", profile = "" ? Chr(1) : profile)
    ; a profile renamed ("" deleted): every save linked to it follows (deleted: unlinked)
    renameProfileLinks(old, name) {
        linked := []
        for key, rec in this.saves
            if rec.Get("profile", "") = old
                linked.Push(key)
        for key in linked
            this.put(key, "profile", name = "" ? Chr(1) : name)
    }
    ; after a load: its profile in use (true if one was switched to)
    applyProfile(name) {
        global remap
        p := this.profileFor(name)
        if p = "" || !IsSet(remap) || !remap || !remap.hasProfile(p) || p = remap.profile
            return false
        remap.useProfile(p)
        Push("toast", { kind: "ok", msg: "Remap profile: " p })
        return true
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

    ; -- archive (the user's ask, 2026-11-16) ------------------------------------------
    ; a series' older saves moved to <folder>\Archive, keeping its newest `keep` numbers: out of the
    ; list and -l, still on disk. Never overwrites: a name already in Archive gets " (2)", " (3)"...
    static ARCHIVE := "Archive"
    archiveCount(key, keep) {
        n := 0
        for f in this.files(Map("showHidden", 1))
            if f.key = key && f.series
                n++
        return Max(0, n - keep)
    }
    archiveSeries(key, keep) {
        fs := []
        for f in this.files(Map("showHidden", 1))
            if f.key = key && f.series
                fs.Push(f)
        SortBy(fs, (a, b) => b.series.num - a.series.num)
        dir := this.folder "\" LoaderEngine.ARCHIVE, moved := 0
        if fs.Length > keep
            DirCreate(dir)
        loop fs.Length - keep {
            f := fs[keep + A_Index], base := RegExReplace(f.name, "i)\.txt$"), to := dir "\" f.name, n := 1
            while FileExist(to) {
                n++
                to := dir "\" base " (" n ").txt"
            }
            try {
                FileMove(this.folder "\" f.name, to)
                moved++
            } catch as e
                try DebugLog("archive: " f.name " not moved: " e.Message)
        }
        try DebugLog("archive " key ": " moved " moved to " dir ", newest " keep " kept")
        return { moved: moved, folder: dir }
    }

    ; -- folder watch (the user's ask, 2026-11-16) -------------------------------------
    ; true when a save was added, removed, renamed or written in the folder since the last call (a
    ; Windows change notification: nothing is listed or read to find out). The first call starts it.
    folderChanged() {
        path := this.folder
        if this.watch && this.watch.path != path
            this.stopWatch()
        if !this.watch {
            if !DirExist(path)
                return false
            ; FILE_NOTIFY_CHANGE_FILE_NAME | LAST_WRITE, this folder only
            h := DllCall("FindFirstChangeNotificationW", "str", path, "int", 0, "uint", 0x11, "ptr")
            if h = -1 || !h
                return false
            this.watch := { path: path, h: h }
            return false
        }
        if DllCall("WaitForSingleObject", "ptr", this.watch.h, "uint", 0, "uint") != 0
            return false
        ; a burst (a save written, files moved) signals more than once: taken as one
        loop 20 {
            if !DllCall("FindNextChangeNotification", "ptr", this.watch.h) {
                this.stopWatch()                    ; the folder went away: started again next time
                break
            }
            if DllCall("WaitForSingleObject", "ptr", this.watch.h, "uint", 0, "uint") != 0
                break
        }
        return true
    }
    stopWatch() {
        if this.watch
            DllCall("FindCloseChangeNotification", "ptr", this.watch.h)
        this.watch := 0
    }
    __Delete() => this.stopWatch()

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
                return Push("toast", { kind: "error", msg: FocusWarcraftError() })
            try wc3Chat("-save " name)
            catch ChatStopped as e
                return Push("toast", { kind: "error", msg: "Not saved: " e.Message })
            ; that's now the save to continue from: -ll loads it, the next -sn
            ; counts up from it even before TWRPG has written the file
            prevSel := Ini(this.section, "selectedFile", ""), prevLast := this.sessionLast
            SetIni(name ".txt", this.section, "selectedFile")
            this.sessionLast := name ".txt"
            SetClipboardAfterChat(name)         ; the save's name, to paste where you keep track of them
            Push("toast", { msg: "Saving as " name "… · copied to the clipboard" })
            this.watchSave(name ".txt", prevSel, prevLast)
            return
        }
        if arg = "" {
            last := Ini(this.section, "selectedFile", "")
            if !last && (fav := this.pinned()).Length
                last := this.latestOf(fav[1])
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

    ; -sn: whether TWRPG wrote the save (the user's ask, 2026-11-16: -sn took it as saved, and -ll
    ; then pointed at a file that never came). Looked for every 250 ms for SAVE_WAIT ms: a new
    ; file, or one there before with a newer time. Seen: "Saved". Not: said so, and -ll / -sn
    ; go back to the save before (unless another load or -sn came since).
    static SAVE_WAIT := 10000
    watchSave(file, prevSel, prevLast) {
        path := this.folder "\" file, start := A_TickCount
        before := FileExist(path) ? FileGetTime(path, "M") : ""
        Tick() {
            if FileExist(path) && FileGetTime(path, "M") != before && FileGetSize(path) {
                SetTimer(Tick, 0)
                try DebugLog("-sn: " file " written after " (A_TickCount - start) " ms")
                return Push("toast", { kind: "ok", msg: "Saved " StrReplace(file, ".txt", "") })
            }
            if A_TickCount - start < LoaderEngine.SAVE_WAIT
                return
            SetTimer(Tick, 0)
            try DebugLog("-sn: no " file " in " this.folder " after " LoaderEngine.SAVE_WAIT " ms")
            if this.sessionLast = file {
                this.sessionLast := prevLast
                if Ini(this.section, "selectedFile", "") = file
                    SetIni(prevSel, this.section, "selectedFile")
            }
            Push("toast", { kind: "error", msg: "TWRPG didn't save " StrReplace(file, ".txt", "") ": no file after " LoaderEngine.SAVE_WAIT // 1000 " s" })
        }
        SetTimer(Tick, 250)
    }

    ; the file to load for a key: a series' newest number, or the save itself ("" = none)
    latestOf(key, files := 0) {
        best := "", top := -1
        for f in (files ? files : this.files(Map("showHidden", 1)))
            if f.key = key && (f.series ? f.series.num : 0) > top
                best := f.name, top := f.series ? f.series.num : 0
        return best
    }

    ; save file name for what was typed after -l, or ""
    resolve(arg) {
        ; compare without spaces: TWRPG never writes them ("-l sorc 3" -> sorc3)
        q := LoaderEngine.TwrpgName(StrReplace(arg, ".txt", ""))
        files := this.files(Map("showHidden", 1))       ; first: favourites of a series' head need it
        pins := Map()
        for i, n in this.pinned()
            pins[n] := i
        ; a number is a favourite slot (when you have that many favourites and no
        ; save is literally called that); otherwise it's matched as a name, so
        ; "-l 92" finds knight#92
        if IsInteger(q) && Integer(q) >= 1 && Integer(q) <= pins.Count {
            for f in files
                if LoaderEngine.TwrpgName(StrReplace(f.name, ".txt", "")) == q
                    return f.name
            for n, i in pins
                if i = Integer(q)
                    return this.latestOf(n, files)
        }
        ; ties: favourite, not ignored, then the highest number in a series, then newest (an ignored
        ; save is only ever its exact name: the user's Ignore, 2026-11-01)
        best := "", bestScore := 0, bestNum := -1, bestKey := ""
        for f in files {
            n := LoaderEngine.TwrpgName(StrReplace(f.name, ".txt", ""))
            score := n == q ? 3 : SubStr(n, 1, StrLen(q)) == q ? 2 : InStr(n, q) ? 1 : 0
            if f.series && LoaderEngine.TwrpgName(f.series.stem) == q
                score := 3                                  ; "-l knight" = the series
            if !score || (f.hidden && score < 3)        ; ignored: only by its exact name
                continue
            score := score * 10 + (pins.Has(f.key) ? 5 : 0) + (f.hidden ? 0 : 1)
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
            Push("toast", { kind: "error", msg: FocusWarcraftError() })
            return { error: "no wc3" }
        }

        HideMainWindow()
        delay := Integer(Ini("Settings", "loadDelay", 200))
        try DebugLog("load " name ": " codes.Length " codes, " (InStr(WC3WindowKey(), "reforged") ? "Reforged way (wait for the chat box, {Text})" : "1.28 way"))
        ; keyboard/mouse are held for the 1-2 s this takes: a key or Enter
        ; pressed mid-load would land inside the codes (needs admin, which the
        ; companion has; Ctrl+Alt+Del always releases it)
        ; Every line stops if the game isn't in front any more, or (1.28f, the module) its chat box
        ; stays open (wc3Chat: ChatGuard, ChatWaitClosed): typed on, the codes went to the other
        ; window and its Enter sent them, or into the game as hotkeys
        BlockInput("On")
        sent := 0, stopped := ""
        try {
            wc3Chat("-convert " userName)       ; always (the user, 2026-10-31: no longer a setting)
            for code in codes {
                Sleep(delay)
                wc3Chat(code)
                sent++
            }
            wc3Chat("-refresh")
            ; the load message once the save is in (the user's pick, 2026-10-29: after the codes, not before)
            if msg := this.pickMessage(this.messageFor(name)) {
                Sleep(delay)
                wc3Chat(LoaderEngine.FillMessage(msg, name))
            }
            Sleep(Integer(Ini("Settings", "postLoadDelay", 1000)))
            ControlSend("{f1}{Ctrl Down}{1}{Ctrl Up}", , WarcraftIII)
            ControlSend("{Esc}", , WarcraftIII)          ; the bag summoned back: always (the user, 2026-10-31)
        } catch ChatStopped as e {
            stopped := e.Message
        } finally {
            BlockInput("Off")
        }
        if stopped != "" {
            try DebugLog("load " name ": stopped (" stopped "; in front: " WinGetTitle("A") "), " sent " of " codes.Length " codes sent")
            Push("toast", { kind: "error", msg: "Load stopped: " stopped " (" sent " of " codes.Length " codes sent)" })
            return { error: "stopped" }
        }
        ; only a load that went through counts as "last" (-ll, -sn)
        SetIni(name, this.section, "selectedFile")
        this.sessionLast := name
        Push("toast", { kind: "ok", msg: "Loaded " StrReplace(name, ".txt", "") " (" codes.Length " codes)" })
        this.applyProfile(name)
        return { ok: 1 }
    }
}
