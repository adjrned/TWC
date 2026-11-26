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
    ; the channel: stable unless opted in (a new key: the old [SelfUpdate] branch=beta isn't read); its release and Setup
    IniWrite("beta", iniFile, "SelfUpdate", "branch"), IniDelete(iniFile, "SelfUpdate", "channel")
    ch0 := su.channel, rel0 := su.release, set0 := su.setupName, br0 := su.branch
    IniWrite("ca960f92", iniFile, "SelfUpdate", "staged")
    changed := su.setChannel("beta"), same := su.setChannel("beta")
    TwcCheck(ch0 = "stable" && rel0 = "stable-latest" && set0 = "TWC-Companion-Setup-stable.exe" && br0 = "stable" && changed && !same
        && su.channel = "beta" && su.release = "beta-latest" && su.branch = "beta" && su.staged = "",
        "the channel: stable by default (stable-latest, its Setup, the stable branch), the old 'branch' key ignored; beta when opted in, the staged update dropped")
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
    ; the stable channel reads its own release's Setup, never the beta one
    su.setChannel("stable"), asked := ""
    su.DefineProp("api", { call: (self, path) => (asked := path, StrReplace(StrReplace(json, "beta-latest", "stable-latest"), "Setup-beta.exe", "Setup-stable.exe")) })
    r2 := su.checkRelease()
    su.DefineProp("api", { call: (self, path) => (asked := path, json) })
    betaOnly := false
    try su.checkRelease()
    catch
        betaOnly := true
    TwcCheck(InStr(r2.url, "TWC-Companion-Setup-stable.exe") && r2.sha = good && betaOnly && asked = "releases/tags/stable-latest",
        "stable: the stable-latest release and its own Setup; a release with only the beta Setup isn't taken")
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
