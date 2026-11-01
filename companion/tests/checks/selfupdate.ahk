; Updates only on a restart (the user, 2026-11-01): staged files go in with applyStaged, into a scratch folder
; here (never the companion's own), a staging folder missing a file is forgotten, and the sidebar's arrow and
; the Settings button follow what's waiting. No network.
TwcSelfUpdateRun() {
    global selfUpdate, updPill, updBtn
    root := A_Temp "\twc-selfupdate-check", stage := root "\stage", copy := root "\copy"
    try DirDelete(root, 1)
    DirCreate(stage "\sub"), DirCreate(copy)
    Put(path, text) {
        try FileDelete(path)
        FileAppend(text, path, "UTF-8")
    }
    was := { staged: Ini(selfUpdate.section, "staged", ""), commit: Ini(selfUpdate.section, "commit", "") }
    su := SelfUpdateEngine()
    su.dir := copy
    su.DefineProp("stageDir", { get: (*) => stage })
    err := ""
    try {
        Put(stage "\a.txt", "new a"), Put(stage "\sub\b.ahk", "new b"), Put(copy "\a.txt", "old a")
        Put(stage "\.staged-files", "a.txt`nsub/b.ahk`n")
        SetIni("abc1234", su.section, "staged")
        ready := UpdateReady(), UpdateFlag()
        flagged := updPill.Visible && updBtn.Text = "Update now"
        n := su.applyStaged()
        moved := n = 2 && FileRead(copy "\a.txt") = "new a" && FileRead(copy "\sub\b.ahk") = "new b" && !DirExist(stage)
        after := su.staged = "" && Ini(su.section, "commit", "") = "abc1234"
        UpdateFlag()
        cleared := !updPill.Visible && updBtn.Text = "Check for updates"
        ; a staging folder that lost a file (a temp clean-up): nothing moved, forgotten
        DirCreate(stage), Put(stage "\.staged-files", "gone.txt`n"), SetIni("def5678", su.section, "staged")
        lost := su.applyStaged() = 0 && su.staged = "" && !FileExist(copy "\gone.txt")
        none := su.applyStaged() = 0
    } catch as e
        err := e.Message
    SetIni(was.staged, selfUpdate.section, "staged"), SetIni(was.commit, selfUpdate.section, "commit")
    UpdateFlag()
    TwcCheck(err = "" && ready && flagged, "staged: an update waiting, the sidebar's arrow shown and Settings says Update now" (err != "" ? " (error: " err ")" : ""))
    TwcCheck(err = "" && moved && after, "applyStaged: both files moved in (one in a new folder), the commit kept, nothing left waiting")
    TwcCheck(err = "" && cleared, "after it: the arrow hidden, Check for updates")
    TwcCheck(err = "" && lost && none, "a staging folder missing a file: nothing moved, forgotten; nothing staged: nothing done")
    try DirDelete(root, 1)
    TwcCheckDone()
}
SetTimer(TwcSelfUpdateRun, -4500)
