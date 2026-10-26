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
    ; every feature's Options window opens (and closes)
    n := 0
    for f in Wc3Features()
        if f.HasProp("opts") || f.HasProp("window") {
            og := Wc3Options(f), n++
            if IsObject(og)
                try og.Destroy()
        }
    TwcCheck(n >= 12, "every Options window opens (" n ")")
    ; the Remap page's quickcast switches and their windows
    ShowPage("remap")
    for v in ["hook", "screen"] {
        was := v = "hook" ? gameModule.quickcast : QuickcastScreenOn()
        RemapQcSwitch(v), RemapQcSwitch(v)
        qg := QuickcastSettings(v)
        try qg.Destroy()
        TwcCheck((v = "hook" ? gameModule.quickcast : QuickcastScreenOn()) = was && remapQcCtrls[v].sw.Text = (was ? "On" : "Off"), "Remap: quickcast " v " switch and Options")
    }
    ; one page a tab on 1.28f (two columns): no pager
    global wc3PagerCtls
    for t in Wc3Tabs() {
        Wc3ShowVersion("128"), Wc3ShowTab(t[1])
        TwcCheck(!wc3PagerCtls[1].Visible, "1.28f > " t[2] ": one page")
    }
    ; the size and colour windows: typed, slid, player colour
    global healthBars
    sg := BarSizeDialog(), eds := [], sls := []
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
    TypeIn(eds[3], "0.5")
    TwcCheck(Abs(healthBars.manaHeight - 0.5) < 0.001 && eds.Length = 4, "mana bar height typed in the same window: " healthBars.manaHeight)
    sg.Destroy()
    cg := BarColoursDialog()
    cbs := []
    for ctl in cg
        if ctl.Type = "Checkbox"
            cbs.Push(ctl)
    TwcCheck(cbs.Length = 5, "colours: a player colour box per owner")
    BarPlayerColour("allies", "0080FF", 1)
    TwcCheck(healthBars.colour("allies") = "player", "allies: player colour")
    BarPlayerColour("allies", "0080FF", 0)
    TwcCheck(healthBars.colour("allies") = "0080FF", "back to their own colour: " healthBars.colour("allies"))
    cg.Destroy()
    ; the mouse slots are gone: an old [Remap] mouse key is neither a slot nor a macro conflict, and can be bound again
    IniWrite("$XButton2", iniFile, "Remap", "mouse1")
    noMouse := true
    for s in remap.get().slots
        noMouse := noMouse && s.group != "mouse"
    TwcCheck(noMouse && MacroKeyConflict("XButton2") = "", "an old [Remap] mouse1 key: no slot, no macro conflict")
    r := remap.setKey(Map("group", "card", "index", 9, "key", "XButton2"))
    TwcCheck(r.ok && r.msg = "" && remap.yourKey("card", 9) = "$XButton2", "and it binds to a slot without 'moved from' (" r.msg ")")
    remap.setKey(Map("group", "card", "index", 9, "key", "-")), IniDelete(iniFile, "Remap", "mouse1")
    ; the List view keeps the quickcast panel
    SetIni("list", "Remap", "view"), ShowPage("remap"), RefreshRemap()
    TwcCheck(remapQcCtrls["hook"].sw.Visible && remapQcCtrls["screen"].ob.Visible, "Remap List view: the quickcast switches are there")
    SetIni("hud", "Remap", "view"), RefreshRemap()
    ; a window closed over another page (the Quickcast window on Remap) doesn't draw the WC3 cards there
    RefreshWc3()
    stray := 0
    for card in wc3Cards
        stray += card.ctrls[1].Visible
    TwcCheck(!stray, "RefreshWc3 from the Remap page draws no WC3 cards over it (" stray ")")
    TwcCheckDone()
}
; as typing does it: the edit's own change notice (setting .Value raises no event)
TypeIn(ed, text) => (SendMessage(0xC, 0, StrPtr(text), ed), Sleep(100))      ; WM_SETTEXT; the event runs in the sleep
SetTimer(TwcPagesRun, -7000)
