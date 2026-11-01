; The installed exe's update (engine\SelfUpdate.ahk checkRelease / downloadSetup): the Setup's SHA-256 taken from
; its own entry in GitHub's release data (not another file's), and a download that doesn't match is refused and
; deleted. No network: api() and Download are stood in for.
TwcExeUpdateRun() {
    good := "ca960f9288ac423293282542ed9a41c373ba01451bfec32d80e329371b9afa3c"
    zipSha := "a75930798f507a3bb74dd321c847d312d5190812d22509c90c341ac8c93d17b5"
    json := '{"target_commitish":"e459e1b1abca1f574a2a84aaf6f338eb939e2e78","assets":['
        . '{"name":"TWC-Companion-beta.zip","uploader":{"login":"x"},"digest":"sha256:' zipSha '","browser_download_url":"https://github.com/adjrned/TWC/releases/download/beta-latest/TWC-Companion-beta.zip"},'
        . '{"name":"TWC-Companion-Setup-beta.exe","uploader":{"login":"x"},"size":3784704,"digest":"sha256:' good '","browser_download_url":"https://github.com/adjrned/TWC/releases/download/beta-latest/TWC-Companion-Setup-beta.exe"}]}'
    su := SelfUpdateEngine()
    su.DefineProp("api", { call: (*) => json })
    err := ""
    try r := su.checkRelease()
    catch as e
        err := e.Message
    TwcCheck(err = "" && r.sha = good && InStr(r.url, "TWC-Companion-Setup-beta.exe") && r.commit = "e459e1b1abca1f574a2a84aaf6f338eb939e2e78",
        "the release: the Setup's own SHA-256 (not the zip's), its link and commit" (err != "" ? " (error: " err ")" : ""))
    su.DefineProp("api", { call: (*) => StrReplace(json, ',"digest":"sha256:' good '"', "") })
    noSha := false
    try su.checkRelease()
    catch
        noSha := true
    TwcCheck(noSha, "no SHA-256 for the Setup: not taken (nothing to check the download against)")
    ; a downloaded file: taken only with the release's SHA-256 (a 1.1 MB file of our own as the 'download')
    src := A_Temp "\twc-exeupdate-src.bin"
    try FileDelete(src)
    f := FileOpen(src, "w"), f.RawWrite(Buffer(1100000, 0x41)), f.Close()
    TwcCheck(!SelfUpdateEngine.SetupMatches(src, good) && SelfUpdateEngine.SetupMatches(src, FileSha256(src)) && !SelfUpdateEngine.SetupMatches(src, ""),
        "a download with another SHA-256 (or none to check against): not run; the matching one is")
    try FileDelete(src)
    TwcCheckDone()
}
SetTimer(TwcExeUpdateRun, -4000)
