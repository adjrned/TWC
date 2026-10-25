#Requires AutoHotkey v2.0
; ============================================================================
;  SelfUpdateEngine - keeps a source copy of the companion on the latest commit
;  of a GitHub branch (beta by default), without git.
;  The branch's file list (GitHub's tree API) gives every file's git blob id,
;  a SHA-1 of its content. Local files are hashed the same way, so only the
;  files that differ are downloaded (pinned to the commit, so they all match),
;  then the companion restarts. Settings, saves lists and web\ are never in
;  the repo, so they are never touched. Only for the .ahk (source) version:
;  the compiled exe is updated by downloading a new release.
; ============================================================================
class SelfUpdateEngine {
    section := "SelfUpdate"
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
                lp := A_ScriptDir "\" StrReplace(rel, "/", "\")
                if !FileExist(lp) || GitBlobSha(lp, rel ~= SelfUpdateEngine.TEXT) != e[2]
                    changed.Push({ path: rel, sha: e[2] })
            }
        }
        return { commit: head, files: changed }
    }

    ; download every changed file to a temp folder first, then move them in
    apply(res) {
        tmp := A_Temp "\tw-companion-update"
        try DirDelete(tmp, true)
        DirCreate(tmp)
        for f in res.files {
            dest := tmp "\" StrReplace(f.path, "/", "\")
            SplitPath(dest, , &dir)
            DirCreate(dir)
            Download("https://raw.githubusercontent.com/" SelfUpdateEngine.REPO "/" res.commit "/" SelfUpdateEngine.PREFIX f.path, dest)
            if GitBlobSha(dest, false) != f.sha
                throw Error("Download didn't match: " f.path)
        }
        for f in res.files {
            target := A_ScriptDir "\" StrReplace(f.path, "/", "\")
            SplitPath(target, , &dir)
            DirCreate(dir)
            FileMove(tmp "\" StrReplace(f.path, "/", "\"), target, true)
        }
        try DirDelete(tmp, true)
        SetIni(res.commit, this.section, "commit")
    }

    ; -- the installed exe: the rolling beta-latest release ------------------
    ; GitHub Actions rebuilds it on every push to beta (.github/workflows/
    ; companion-beta.yml). -> { commit, url } of its build and its Setup.
    static RELEASE := "beta-latest", SETUP := "TWC-Companion-Setup-beta.exe"
    checkRelease() {
        j := this.api("releases/tags/" SelfUpdateEngine.RELEASE)
        commit := RegExMatch(j, '"target_commitish"\s*:\s*"([0-9a-f]{40})"', &m) ? m[1] : ""
        url := RegExMatch(j, '"browser_download_url"\s*:\s*"([^"]*' SelfUpdateEngine.SETUP ')"', &u) ? u[1] : ""
        if !commit || !url
            throw Error("The beta release isn't ready (it's rebuilt after each change; try again in a few minutes)")
        return { commit: commit, url: url }
    }
    ; -> the downloaded Setup's path
    downloadSetup(r) {
        path := A_Temp "\" SelfUpdateEngine.SETUP
        try FileDelete(path)
        Download(r.url, path)
        if FileGetSize(path) < 1000000
            throw Error("The download looks incomplete")
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
