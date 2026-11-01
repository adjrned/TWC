; Windows resized as a whole (ui\WindowScale.ahk): the main window and a popup at other
; scales, every page built at one; code still reads base units; back at 100% every control
; is where it was, to the pixel. The mouse is never moved (the edges' drag isn't run).
TwcScaleRect(hw) {
    rc := Buffer(16)
    DllCall("GetWindowRect", "ptr", hw, "ptr", rc)
    DllCall("MapWindowPoints", "ptr", 0, "ptr", DllCall("GetParent", "ptr", hw, "ptr"), "ptr", rc, "uint", 2)
    return [NumGet(rc, 0, "int"), NumGet(rc, 4, "int"), NumGet(rc, 8, "int") - NumGet(rc, 0, "int"), NumGet(rc, 12, "int") - NumGet(rc, 4, "int")]
}
TwcScaleFontH(ctl) {
    lf := Buffer(92, 0)
    DllCall("GetObjectW", "ptr", SendMessage(0x31, 0, 0, ctl), "int", 92, "ptr", lf)
    return Abs(NumGet(lf, 0, "int"))
}
TwcScalePages() {
    global pages
    names := []
    for name in pages
        names.Push(name)
    for name in names
        ShowPageInner(name, "")
    ShowPage("wc3")
}
TwcScaleRun() {
    global mainGui, titleText, pages, W, H
    ShowMainWindow()
    TwcScalePages()                                  ; every page laid out once, at 100%
    ShowPage("loader")
    before := Map()
    for hw, ctl in mainGui
        before[hw] := TwcScaleRect(hw)
    titleText.GetPos(&bx, &by, &bw, &bh)
    f1 := TwcScaleFontH(titleText), tw1 := TextWidth(titleText, "TW Companion")

    ApplyScale(mainGui, 1.5)
    WinGetPos(, , &ww, &wh, mainGui)
    titleText.GetPos(&sx, &sy, &sw, &sh)
    r := TwcScaleRect(titleText.Hwnd), kk := UiK(mainGui)
    TwcCheck(Abs(ww - W * kk) <= 1 && Abs(wh - H * kk) <= 1, "x1.5: the window " ww " x " wh " (" Round(W * kk) " x " Round(H * kk) ")")
    TwcCheck(sx = bx && sy = by && sw = bw && sh = bh, "x1.5: GetPos still in base units (" sx ", " sy ", " sw ", " sh ")")
    TwcCheck(Abs(r[1] - bx * kk) <= 1 && Abs(r[3] - bw * kk) <= 1, "x1.5: the title at " r[1] ", " r[3] " wide on screen")
    f2 := TwcScaleFontH(titleText), tw2 := TextWidth(titleText, "TW Companion")
    TwcCheck(Abs(f2 / f1 - 1.5) < 0.1 && Abs(tw2 - tw1) <= 2, "x1.5: its font " f1 " -> " f2 " px, its text " tw1 " -> " tw2 " units wide")
    rgn := DllCall("CreateRectRgn", "int", 0, "int", 0, "int", 0, "int", 0, "ptr"), rb := Buffer(16)
    DllCall("GetWindowRgn", "ptr", mainGui.Hwnd, "ptr", rgn), DllCall("GetRgnBox", "ptr", rgn, "ptr", rb), DllCall("DeleteObject", "ptr", rgn)
    TwcCheck(Abs(NumGet(rb, 8, "int") - W * kk) <= 2, "x1.5: the round corners follow (region " NumGet(rb, 8, "int") " wide)")
    ; every page built and shown at x1.5; what's made now is in base units too
    TwcScalePages()
    bad := 0, n := 0
    for hw, ctl in mainGui {
        ctl.GetPos(&x, &y, &w, &h), n++
        rr := TwcScaleRect(hw)
        bad += Abs(rr[1] - Round(x * kk)) > 1 || Abs(rr[3] - Round(w * kk)) > 1
    }
    TwcCheck(n > 100 && !bad, "x1.5: every page shown; " n " controls where their base rects say (" bad " off)")
    ; a popup at the popups' own size
    IniWrite(1.25, iniFile, "Window", "popupScale")
    qg := QuickcastSettings("hook")
    WinGetPos(, , &qw, , qg)
    TwcCheck(Abs(qw - 460 * DPI_K * 1.25) <= 1 && winScale[qg.Hwnd].kind = "popup", "a popup at x1.25: " qw " px wide")
    qh := qg.Hwnd, qg.Destroy()
    TwcCheck(!winScale.Has(qh), "a closed popup is forgotten")
    IniDelete(iniFile, "Window", "popupScale")
    ; small, then back: every control where it was at first
    ShowPage("loader"), ApplyScale(mainGui, 0.7), ApplyScale(mainGui, 1)
    moved := 0
    for hw, rr in before {
        nr := TwcScaleRect(hw)
        moved += nr[1] != rr[1] || nr[2] != rr[2] || nr[3] != rr[3] || nr[4] != rr[4]
    }
    TwcCheck(!moved && TwcScaleFontH(titleText) = f1, "x0.7 then x1: all " before.Count " first controls back to the pixel (" moved " not), the font too")
    TwcCheckDone()
}
SetTimer(TwcScaleRun, -7000)
