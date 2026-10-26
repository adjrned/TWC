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
    ; the size and colour windows: typed, slid, player colour
    global healthBars
    sg := BarSizeDialog("health"), eds := [], sls := []
    for ctl in sg
        if ctl.Type = "Edit"
            eds.Push(ctl)
        else if ctl.Type = "Slider"
            sls.Push(ctl)
    TypeIn(eds[1], "2,35")
    TwcCheck(Abs(healthBars.height - 2.35) < 0.001 && sls[1].Value = 235, "health bar height typed (2,35): " healthBars.height ", slider " sls[1].Value)
    TypeIn(eds[2], "9")
    TwcCheck(healthBars.width = 4, "a width past the limit is x4: " healthBars.width)
    TypeIn(eds[2], "abc")
    TwcCheck(healthBars.width = 4, "not a number: left as it was")
    sg.Destroy()
    mg := BarSizeDialog("mana")
    for ctl in mg
        if ctl.Type = "Edit" {
            TypeIn(ctl, "0.5")
            break
        }
    TwcCheck(Abs(healthBars.manaHeight - 0.5) < 0.001, "mana bar height typed: " healthBars.manaHeight)
    mg.Destroy()
    cg := BarColoursDialog()
    cbs := []
    for ctl in cg
        if ctl.Type = "Checkbox"
            cbs.Push(ctl)
    TwcCheck(cbs.Length = 5, "colours: a player colour box per owner")
    BarPlayerColour("allies", "0080FF", cg["Static5"], 1)
    TwcCheck(healthBars.colour("allies") = "player", "allies: player colour")
    BarPlayerColour("allies", "0080FF", cg["Static5"], 0)
    TwcCheck(healthBars.colour("allies") = "0080FF", "back to their own colour: " healthBars.colour("allies"))
    cg.Destroy()
    HidePartsDialog()
    TwcCheck(true, "Hide UI parts window")
    TwcCheckDone()
}
; as typing does it: the edit's own change notice (setting .Value raises no event)
TypeIn(ed, text) => (SendMessage(0xC, 0, StrPtr(text), ed), Sleep(100))      ; WM_SETTEXT; the event runs in the sleep
SetTimer(TwcPagesRun, -7000)
