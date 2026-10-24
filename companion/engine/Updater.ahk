#Requires AutoHotkey v2.0
; ============================================================================
;  UpdaterEngine - keeps the overlay's offline copy of the TWRPG site current.
;  The site publishes overlay-manifest.txt (sha256, size, path, url per file);
;  we compare it with the local copy's manifest, download only changed files
;  into web\_staging (unchanged ones are copied over), verify each by hash,
;  then swap the staging folder in for web\TWC in one move.
; ============================================================================
class UpdaterEngine {
    section := "Overlay"
    static MANIFEST := "overlay-manifest.txt"
    remote := 0              ; manifest text from the last check()

    webDir => A_ScriptDir "\web"
    appDir => this.webDir "\TWC"
    baseUrl {
        get {
            url := Ini(this.section, "updateUrl", "https://adjrned.github.io/TWC/")
            return SubStr(url, -1) = "/" ? url : url "/"
        }
    }

    localVersion() {
        m := this.parse(this.readLocal())
        return m.version
    }

    ; -> { state: "current" | "available" | "error", version, changed, message }
    check() {
        tmp := A_Temp "\twc-" UpdaterEngine.MANIFEST
        try {
            Download(this.baseUrl UpdaterEngine.MANIFEST "?t=" A_NowUTC A_TickCount, tmp)
            text := FileRead(tmp, "UTF-8")
            FileDelete(tmp)
        } catch as e {
            return { state: "error", message: "Couldn't reach the update server (offline?)" }
        }
        remote := this.parse(text)
        if !remote.version || !remote.files.Count
            return { state: "error", message: "The update server sent an unexpected reply" }
        this.remote := text
        changed := this.diff(this.parse(this.readLocal()), remote).Length
        return { state: changed ? "available" : "current", version: remote.version, changed: changed }
    }

    ; Downloads and installs the manifest from the last check().
    ; onProgress(done, total) is called per downloaded file; beforeSwap() runs
    ; right before the folder swap so the caller can release open files.
    ; -> { ok, version, message }
    apply(onProgress := 0, beforeSwap := 0) {
        if !this.remote {
            r := this.check()
            if r.state = "error"
                return { ok: 0, message: r.message }
        }
        loc := this.parse(this.readLocal())
        remote := this.parse(this.remote)
        changed := Map()
        for p in this.diff(loc, remote)
            changed[p] := true

        staging := this.webDir "\_staging", old := this.webDir "\_old"
        try {
            if DirExist(staging)
                DirDelete(staging, true)
            DirCreate(staging)
            done := 0, total := changed.Count
            for path, f in remote.files {
                rel := StrReplace(path, "/", "\")
                dest := staging "\" rel
                SplitPath(dest, , &dir)
                DirCreate(dir)
                if !changed.Has(path) {
                    FileCopy(this.appDir "\" rel, dest)
                    continue
                }
                ; ?v= busts browser/CDN caches for files that keep their name (data/*.json, icons)
                Download(this.baseUrl f.url "?v=" SubStr(f.hash, 1, 12), dest)
                if FileGetSize(dest) != f.size || FileSha256(dest) != f.hash
                    throw Error("Download was corrupted: " path)
                done++
                if onProgress
                    onProgress(done, total)
                Sleep(-1)
            }
            FileAppend(this.remote, staging "\" UpdaterEngine.MANIFEST, "UTF-8-RAW")

            if beforeSwap
                beforeSwap()
            if DirExist(old)
                DirDelete(old, true)
            if DirExist(this.appDir)
                DirMove(this.appDir, old, "R")
            DirMove(staging, this.appDir, "R")
            try DirDelete(old, true)
        } catch as e {
            try DirDelete(staging, true)
            if !DirExist(this.appDir) && DirExist(old)
                try DirMove(old, this.appDir, "R")
            return { ok: 0, message: "Update failed: " e.Message }
        }
        this.remote := 0
        return { ok: 1, version: remote.version }
    }

    ; -- manifest ------------------------------------------------------------
    readLocal() {
        f := this.appDir "\" UpdaterEngine.MANIFEST
        return FileExist(f) ? FileRead(f, "UTF-8") : ""
    }

    ; "version<TAB>..." then "<sha256><TAB><size><TAB><path><TAB><url>" per line
    parse(text) {
        out := { version: "", files: Map() }
        loop parse text, "`n", "`r" {
            cols := StrSplit(A_LoopField, "`t")
            if cols.Length = 2 && cols[1] = "version"
                out.version := cols[2]
            else if cols.Length = 4
                out.files[cols[3]] := { hash: cols[1], size: Integer(cols[2]), url: cols[4] }
        }
        return out
    }

    ; paths in `remote` that are new, changed, or missing on disk locally
    diff(loc, remote) {
        out := []
        for path, f in remote.files {
            l := loc.files.Has(path) ? loc.files[path] : 0
            if !l || l.hash != f.hash || !FileExist(this.appDir "\" StrReplace(path, "/", "\"))
                out.Push(path)
        }
        return out
    }
}

; SHA-256 of a file as lowercase hex (Windows CNG).
FileSha256(path) {
    data := FileRead(path, "RAW")
    hash := Buffer(32)
    DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", &hAlg := 0, "wstr", "SHA256", "ptr", 0, "uint", 0)
    DllCall("bcrypt\BCryptHash", "ptr", hAlg, "ptr", 0, "uint", 0, "ptr", data, "uint", data.Size, "ptr", hash, "uint", 32)
    DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hAlg, "uint", 0)
    hex := ""
    loop 32
        hex .= Format("{:02x}", NumGet(hash, A_Index - 1, "uchar"))
    return hex
}
