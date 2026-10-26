; Every page opens, and on the WC3 page every version, tab and pager page (a
; local shadowing a built-in, like Mod, only fails when its page is built).
TwcPagesRun() {
    global pages
    names := []
    for name in pages
        names.Push(name)
    for name in names {
        ShowPageInner(name, "")             ; not ShowPage: it hides errors behind a try
        TwcCheck(true, "page " name)
    }
    ShowPage("wc3")
    for v in Wc3Versions()
        for t in Wc3Tabs() {
            Wc3ShowVersion(v[1]), Wc3ShowTab(t[1])
            loop 3
                Wc3Turn(1)
            loop 3
                Wc3Turn(-1)
            TwcCheck(true, "WC3 " v[2] " > " t[2])
        }
    ModuleCheckDialog()
    TwcCheck(true, "Module check window")
    TwcCheckDone()
}
SetTimer(TwcPagesRun, -7000)
