#Requires AutoHotkey v2.0
; ============================================================================
;  SelfUpdateEngine - keeps a source copy of the companion on the latest commit
;  of a GitHub branch (beta by default), without git.
;  The branch's file list (GitHub's tree API) gives every file's git blob id,
;  a SHA-1 of its content. Local files are hashed the same way, so only the
;  files that differ are downloaded (pinned to the commit, so they all match)
;  and put in when the companion next starts or exits. Settings, saves lists and web\ are never in
;  the repo, so they are never touched. Only for the .ahk (source) version:
;  the compiled exe is updated by downloading a new release.
; ============================================================================
class SelfUpdateEngine {
    section := "SelfUpdate"
    dir := A_ScriptDir                  ; the copy kept up to date (a check: a scratch folder)
    static REPO := "adjrned/TWC"
    static PREFIX := "companion/"       ; the companion's folder in the repo
    static TEXT := "i)\.(ahk|md|txt|py|ps1|json|csv)$"   ; stored with LF in git

    enabled => !A_IsCompiled && Integer(Ini(this.section, "auto", 1))
    branch => Ini(this.section, "branch", "beta")
    commit => Ini(this.section, "commit", "")

    ; -> { commit, files: [{ path, sha }] } changed against this folder; throws on network errors
    check() {
        head := RegExMatch(this.api("commits/" this.branch), '"sha"\s*:\s*"([0-9a-f]{40})"', &m) ? m[1] : ""
        if !head
            throw Error("No commit found for branch " this.branch)
        changed := []
        if head != this.commit || !this.commit {
            tree := this.api("git/trees/" head "?recursive=1")
            pos := 1
            while pos := RegExMatch(tree, '"path"\s*:\s*"([^"]+)"\s*,\s*"mode"\s*:\s*"\d+"\s*,\s*"type"\s*:\s*"blob"\s*,\s*"sha"\s*:\s*"([0-9a-f]{40})"', &e, pos) {
                pos += StrLen(e[0])
                if SubStr(e[1], 1, StrLen(SelfUpdateEngine.PREFIX)) != SelfUpdateEngine.PREFIX
                    continue
                rel := SubStr(e[1], StrLen(SelfUpdateEngine.PREFIX) + 1)
                lp := this.dir "\" StrReplace(rel, "/", "\")
                if !FileExist(lp) || GitBlobSha(lp, rel ~= SelfUpdateEngine.TEXT) != e[2]
                    changed.Push({ path: rel, sha: e[2] })
            }
        }
        return { commit: head, files: changed }
    }

    ; -- staged: downloaded when found, put in when the companion next starts or exits (the user, 2026-11-01:
    ; it restarted by itself for every update), or at once with Update now
    stageDir => A_Temp "\tw-companion-staged"
    staged => Ini(this.section, "staged", "")          ; the commit downloaded and waiting ("" none)
    ; download every changed file to the staging folder (each checked against its git id), with the list
    stage(res) {
        dir := this.stageDir
        try DirDelete(dir, true)
        SetIni("", this.section, "staged")
        DirCreate(dir)
        list := ""
        for f in res.files {
            dest := dir "\" StrReplace(f.path, "/", "\")
            SplitPath(dest, , &sub)
            DirCreate(sub)
            Download("https://raw.githubusercontent.com/" SelfUpdateEngine.REPO "/" res.commit "/" SelfUpdateEngine.PREFIX f.path, dest)
            if GitBlobSha(dest, false) != f.sha
                throw Error("Download didn't match: " f.path)
            list .= f.path "`n"
        }
        FileAppend(list, dir "\.staged-files", "UTF-8")
        SetIni(res.commit, this.section, "staged")
    }
    ; move the staged files in -> how many (0: none waiting; files gone from the staging folder: forgotten,
    ; the next check downloads them again)
    applyStaged() {
        c := this.staged, dir := this.stageDir
        if c = ""
            return 0
        SetIni("", this.section, "staged")
        if !FileExist(dir "\.staged-files")
            return 0
        paths := StrSplit(Trim(FileRead(dir "\.staged-files", "UTF-8"), "`r`n"), "`n", "`r")
        for p in paths
            if !FileExist(dir "\" StrReplace(p, "/", "\")) {
                try DirDelete(dir, true)
                return 0
            }
        for p in paths {
            target := this.dir "\" StrReplace(p, "/", "\")
            SplitPath(target, , &sub)
            DirCreate(sub)
            FileMove(dir "\" StrReplace(p, "/", "\"), target, true)
        }
        try DirDelete(dir, true)
        SetIni(c, this.section, "commit")
        return paths.Length
    }
    dropStaged() {
        SetIni("", this.section, "staged")
        try DirDelete(this.stageDir, true)
    }
    ; the exe's Setup downloaded and waiting (run when the companion next starts): { path, sha, commit }, commit "" none
    pendingSetup => { path: Ini(this.section, "setupPath", ""), sha: Ini(this.section, "setupSha", ""), commit: Ini(this.section, "setupCommit", "") }
    setPendingSetup(path := "", sha := "", commit := "") {
        SetIni(path, this.section, "setupPath"), SetIni(sha, this.section, "setupSha"), SetIni(commit, this.section, "setupCommit")
    }

    ; -- the installed exe: the rolling beta-latest release ------------------
    ; GitHub Actions rebuilds it on every push to beta (.github/workflows/
    ; companion-beta.yml). -> { commit, url } of its build and its Setup.
    static RELEASE := "beta-latest", SETUP := "TWC-Companion-Setup-beta.exe"
    checkRelease() {
        j := this.api("releases/tags/" SelfUpdateEngine.RELEASE)
        commit := RegExMatch(j, '"target_commitish"\s*:\s*"([0-9a-f]{40})"', &m) ? m[1] : ""
        url := RegExMatch(j, '"browser_download_url"\s*:\s*"([^"]*' SelfUpdateEngine.SETUP ')"', &u) ? u[1] : ""
        ; the Setup's SHA-256, as GitHub keeps it for each release file ("digest"), in its own entry (from its name
        ; to its download link): the download is run as admin, so it's checked against it first
        sha := ""
        if (at := RegExMatch(j, '"name"\s*:\s*"' SelfUpdateEngine.SETUP '"')) && (end := InStr(j, '"browser_download_url"', , at))
            sha := RegExMatch(SubStr(j, at, end - at), '"digest"\s*:\s*"sha256:([0-9a-f]{64})"', &d) ? d[1] : ""
        if !commit || !url || !sha
            throw Error("The beta release isn't ready (it's rebuilt after each change; try again in a few minutes)")
        return { commit: commit, url: url, sha: sha }
    }
    static SetupMatches(path, sha) => sha != "" && FileExist(path) && FileSha256(path) = sha
    ; -> the downloaded Setup's path, once its SHA-256 is the release's (a security check found the Setup ran with
    ; only its size checked, 2026-10-31)
    downloadSetup(r) {
        path := A_Temp "\" SelfUpdateEngine.SETUP
        try FileDelete(path)
        Download(r.url, path)
        if FileGetSize(path) < 1000000
            throw Error("The download looks incomplete")
        if !r.HasProp("sha") || !SelfUpdateEngine.SetupMatches(path, r.sha) {
            try FileDelete(path)
            throw Error("The download didn't match the release (its SHA-256): not installed")
        }
        return path
    }

    api(path) {
        req := ComObject("WinHttp.WinHttpRequest.5.1")
        req.Open("GET", "https://api.github.com/repos/" SelfUpdateEngine.REPO "/" path, false)
        req.SetRequestHeader("User-Agent", "TW-Companion")
        req.SetRequestHeader("Accept", "application/vnd.github+json")
        req.Send()
        if req.Status != 200
            throw Error("GitHub said " req.Status (req.Status = 403 ? " (rate limit, try again later)" : ""))
        return req.ResponseText
    }
}

; git's id for a file: SHA-1 of "blob <size>\0<content>". Text files are
; hashed with CRLF turned into LF, as git stores them.
GitBlobSha(path, text) {
    data := FileRead(path, "RAW")
    if text {
        ; Latin-1 maps every byte to one character, so this round-trips any bytes
        s := StrGet(data, data.Size, "CP28591")
        s := StrReplace(s, "`r`n", "`n")
        data := Buffer(StrPut(s, "CP28591") - 1)
        StrPut(s, data, StrLen(s), "CP28591")
    }
    head := "blob " data.Size Chr(0)
    hn := StrPut(head, "CP28591") - 1
    all := Buffer(hn + data.Size)
    StrPut(head, all, hn, "CP28591")
    DllCall("RtlMoveMemory", "ptr", all.Ptr + hn, "ptr", data, "uptr", data.Size)
    hash := Buffer(20)
    DllCall("bcrypt\BCryptOpenAlgorithmProvider", "ptr*", &hAlg := 0, "wstr", "SHA1", "ptr", 0, "uint", 0)
    DllCall("bcrypt\BCryptHash", "ptr", hAlg, "ptr", 0, "uint", 0, "ptr", all, "uint", all.Size, "ptr", hash, "uint", 20)
    DllCall("bcrypt\BCryptCloseAlgorithmProvider", "ptr", hAlg, "uint", 0)
    hex := ""
    loop 20
        hex .= Format("{:02x}", NumGet(hash, A_Index - 1, "uchar"))
    return hex
}
