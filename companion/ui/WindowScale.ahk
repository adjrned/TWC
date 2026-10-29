#Requires AutoHotkey v2.0
; ============================================================================
;  WindowScale - the companion's windows resized as a whole: drag an edge or a
;  corner and the window and everything in it grow or shrink together (the
;  look kept, the shape too). Kept: ini [Window] scale (the main window),
;  popupScale (Options, Quickcast, Module check, messages: one size for all)
;  and <kind>Scale for a window of its own kind (meterScale: the damage meter).
;  Drag any empty spot to move a window.
;
;  The pages and dialogs still lay themselves out in base units (96-DPI GUI
;  units at 100%, as before): for a window made scalable (MakeScalable, right
;  after Gui()), AutoHotkey's Add*, Move, GetPos, SetFont and Show are wrapped,
;  so its code reads and writes base units and the window shows them x scale.
;  UiK(g): real pixels per base unit (DPI_K x the scale), where code turns
;  base units into pixels itself (regions, text measuring, the mouse).
; ============================================================================
global winScale := Map()        ; window hwnd -> { k, kind, w, h }: its scale, "main" / "popup", its base size (from Show)
global scBase := Map()          ; control hwnd -> [x, y, w, h] in base units
global scFont := Map()          ; control hwnd -> its font at 100% (the handle AutoHotkey made)
global scRgn := Map()           ; control hwnd -> [w, h, r]: its round corners (Box.Round)
global scPic := Map()           ; control hwnd -> its picture: a file, or a function (pixels per unit) -> a file
global scHooks := Map()         ; window hwnd -> [fn(g)]: run after a rescale (the window's own region)
global scFonts := Map()         ; font "|" scale -> the font made at that scale (kept: the scales snap to 5% steps)
global scOrigGetPos := 0       ; AutoHotkey's own GetPos (real units / DPI)
global SCALE_MIN := 0.7, SCALE_MAX := 2.5, SCALE_STEP := 0.05

UiK(g) => DPI_K * (IsObject(g) && winScale.Has(g.Hwnd) ? winScale[g.Hwnd].k : 1)

; g resized as a whole from now on (before its controls are added); kind: "main", "popup" or a
; window's own ("meter"); all but the main window move by any empty spot
ScaleKey(kind) => kind = "main" ? "scale" : kind "Scale"
MakeScalable(g, kind) {
    WindowScaleInit()
    k := Ini("Window", ScaleKey(kind), 1)
    k := IsNumber(k) ? Max(SCALE_MIN, Min(SCALE_MAX, k + 0)) : 1
    winScale[g.Hwnd] := { k: k, kind: kind, w: 0, h: 0 }
    scHooks[g.Hwnd] := []
}
; fn(g) after each rescale of g
OnRescale(g, fn) => scHooks[g.Hwnd].Push(fn)
; a picture redrawn for each scale: picker(pixels per unit) -> its file
ScaleImage(ctl, picker) {
    scPic[ctl.Hwnd] := picker
    ScPicLoad(ctl)
}

WindowScaleInit() {
    static done := false
    if done
        return
    done := true
    cp := Gui.Control.Prototype, gp := Gui.Prototype
    global scOrigGetPos
    origMove := cp.GetOwnPropDesc("Move").Call, origGetPos := scOrigGetPos := cp.GetOwnPropDesc("GetPos").Call
    origSetFont := cp.GetOwnPropDesc("SetFont").Call
    origShow := gp.GetOwnPropDesc("Show").Call, origDestroy := gp.GetOwnPropDesc("Destroy").Call
    cp.DefineProp("Move", { Call: ScMove.Bind(origMove, origGetPos) })
    cp.DefineProp("GetPos", { Call: ScGetPos.Bind(origGetPos) })
    cp.DefineProp("SetFont", { Call: ScSetFont.Bind(origSetFont) })
    gp.DefineProp("Show", { Call: ScShow.Bind(origShow) })
    gp.DefineProp("Destroy", { Call: ScDestroy.Bind(origDestroy) })
    for t in ["Text", "Edit", "Checkbox", "ListBox", "Picture", "Slider", "Button", "Radio", "DropDownList", "ComboBox",
        "ListView", "GroupBox", "Progress", "Hotkey", "UpDown", "Link", "DateTime", "TreeView"]
        gp.DefineProp("Add" t, { Call: ScAdd.Bind(gp.GetOwnPropDesc("Add" t).Call, origGetPos, t) })
    OnMessage(0x20, ScSetCursor)        ; WM_SETCURSOR: the resize arrows on a window's edges
}

; -- the wrapped functions ---------------------------------------------------------
ScAdd(orig, origGetPos, type, g, opts := "", text?) {
    if !winScale.Has(g.Hwnd)
        return IsSet(text) ? orig(g, opts, text) : orig(g, opts)
    k := winScale[g.Hwnd].k, given := Map()
    ; absolute x / y / w / h scaled (so x+N and the like follow the scaled ones), kept as given
    o := "", pos := 1
    while p := RegExMatch(opts, "i)(?<=^|\s)([xywh])(\d+(?:\.\d+)?)(?=\s|$)", &m, pos) {
        given[StrLower(m[1])] := m[2] + 0
        o .= SubStr(opts, pos, p - pos) m[1] Round(m[2] * k)
        pos := p + m.Len
    }
    o .= SubStr(opts, pos)
    ctl := IsSet(text) ? orig(g, o, text) : orig(g, o)
    hw := ctl.Hwnd
    for mp in [scRgn, scPic]                        ; a handle used again: nothing of the control before
        if mp.Has(hw)
            mp.Delete(hw)
    origGetPos(ctl, &x, &y, &w, &h)
    ; sizes left out are the control's own (made for the font at 100%): base units already
    scBase[hw] := [given.Has("x") ? given["x"] : x / k, given.Has("y") ? given["y"] : y / k,
        given.Has("w") ? given["w"] : w, given.Has("h") ? given["h"] : h]
    scFont[hw] := SendMessage(0x31, 0, 0, ctl)      ; WM_GETFONT
    if type = "Picture" && IsSet(text) && text != ""
        scPic[hw] := text
    if k != 1 {
        ScFontApply(ctl, k)
        if scPic.Has(hw)
            ScPicLoad(ctl)
        ScPlace(ctl, UiK(g))
    }
    return ctl
}
ScMove(origMove, origGetPos, ctl, x?, y?, w?, h?) {
    g := ctl.Gui
    if !winScale.Has(g.Hwnd)
        return origMove(ctl, x?, y?, w?, h?)
    b := ScBaseOf(ctl, origGetPos)
    IsSet(x) && b[1] := x, IsSet(y) && b[2] := y, IsSet(w) && b[3] := w, IsSet(h) && b[4] := h
    ScPlace(ctl, UiK(g))
}
ScGetPos(origGetPos, ctl, &x := 0, &y := 0, &w := 0, &h := 0) {
    if !winScale.Has(ctl.Gui.Hwnd)
        return origGetPos(ctl, &x, &y, &w, &h)
    b := ScBaseOf(ctl, origGetPos)
    x := b[1], y := b[2], w := b[3], h := b[4]
}
ScSetFont(origSetFont, ctl, opts := "", name?) {
    origSetFont(ctl, opts, name?)
    g := ctl.Gui
    if !winScale.Has(g.Hwnd)
        return
    scFont[ctl.Hwnd] := SendMessage(0x31, 0, 0, ctl)
    if winScale[g.Hwnd].k != 1
        ScFontApply(ctl, winScale[g.Hwnd].k)
}
; Show's w / h are base units: the window made that size x its scale (x / y are screen pixels, as ever)
ScShow(origShow, g, opts := "") {
    if !winScale.Has(g.Hwnd)
        return origShow(g, opts)
    s := winScale[g.Hwnd]
    if RegExMatch(opts, "i)(?<=^|\s)w(\d+)(?=\s|$)", &m)
        s.w := m[1] + 0
    if RegExMatch(opts, "i)(?<=^|\s)h(\d+)(?=\s|$)", &m)
        s.h := m[1] + 0
    kk := UiK(g), k := s.k
    ; AutoHotkey's units (x DPI); without a size it would fit the window to its controls
    opts := RegExReplace(opts, "i)(?<=^|\s)[wh]\d+(?=\s|$)")
    if s.w && s.h
        opts .= " w" Round(s.w * k) " h" Round(s.h * k)
    origShow(g, opts)
    if s.w && s.h                                    ; to the pixel
        DllCall("SetWindowPos", "ptr", g.Hwnd, "ptr", 0, "int", 0, "int", 0, "int", Round(s.w * kk), "int", Round(s.h * kk), "uint", 0x16)
    for fn in scHooks[g.Hwnd]
        fn(g)
}
ScDestroy(origDestroy, g) {
    hw := g.Hwnd
    for mp in [winScale, scHooks]
        if mp.Has(hw)
            mp.Delete(hw)
    origDestroy(g)
}

; -- helpers -----------------------------------------------------------------------
ScBaseOf(ctl, origGetPos) {
    hw := ctl.Hwnd
    if !scBase.Has(hw) {                             ; made before it was scalable: from where it is
        k := winScale[ctl.Gui.Hwnd].k
        origGetPos(ctl, &x, &y, &w, &h)
        scBase[hw] := [x / k, y / k, w / k, h / k]
    }
    return scBase[hw]
}
; the control where its base rect is, at kk pixels a unit (each number rounded, as AutoHotkey
; does: at 100% to the pixel where it always was)
ScPlace(ctl, kk) {
    b := scBase[ctl.Hwnd]
    DllCall("SetWindowPos", "ptr", ctl.Hwnd, "ptr", 0, "int", Round(b[1] * kk), "int", Round(b[2] * kk),
        "int", Round(b[3] * kk), "int", Round(b[4] * kk), "uint", 0x14)   ; NOZORDER | NOACTIVATE
}
ScFontApply(ctl, k) {
    hw := ctl.Hwnd
    if !scFont.Has(hw) || !scFont[hw]
        return
    base := scFont[hw]
    if Abs(k - 1) < 0.001 {
        SendMessage(0x30, base, 1, ctl)              ; WM_SETFONT
        return
    }
    key := base "|" Round(k, 3)
    if !scFonts.Has(key) {
        lf := Buffer(92, 0)                          ; LOGFONTW
        DllCall("GetObjectW", "ptr", base, "int", 92, "ptr", lf)
        NumPut("int", Round(NumGet(lf, 0, "int") * k), lf, 0)      ; lfHeight
        NumPut("int", Round(NumGet(lf, 4, "int") * k), lf, 4)      ; lfWidth (0: the font's own)
        scFonts[key] := DllCall("CreateFontIndirectW", "ptr", lf, "ptr")
    }
    SendMessage(0x30, scFonts[key], 1, ctl)
}
ScPicLoad(ctl) {
    p := scPic[ctl.Hwnd], kk := UiK(ctl.Gui), b := scBase[ctl.Hwnd]
    file := HasMethod(p) ? p(kk) : p
    try ctl.Value := "*w" Round(b[3] * kk) " *h" Round(b[4] * kk) " " file
    ScPlace(ctl, kk)
}

; g at scale k (its top left at x, y in screen pixels, if given): every control, its font,
; round corners and picture
ApplyScale(g, k, x?, y?) {
    s := winScale[g.Hwnd]
    if Abs(s.k - k) < 0.001
        return
    for hw, ctl in g                                 ; base rects first, at the old scale
        ScBaseOf(ctl, scOrigGetPos)
    s.k := k, kk := UiK(g)
    SendMessage(0x0B, 0, 0, g)                       ; WM_SETREDRAW off
    for hw, ctl in g {
        ScFontApply(ctl, k)
        if scPic.Has(hw)
            ScPicLoad(ctl)
        else
            ScPlace(ctl, kk)
        if scRgn.Has(hw)
            Box.Round(ctl, scRgn[hw]*)
    }
    flags := IsSet(x) ? 0x14 : 0x16                 ; NOZORDER | NOACTIVATE (| NOMOVE)
    DllCall("SetWindowPos", "ptr", g.Hwnd, "ptr", 0, "int", x ?? 0, "int", y ?? 0, "int", Round(s.w * kk), "int", Round(s.h * kk), "uint", flags)
    for fn in scHooks[g.Hwnd]
        fn(g)
    SendMessage(0x0B, 1, 0, g)
    DllCall("RedrawWindow", "ptr", g.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x485)   ; INVALIDATE | ERASE | ALLCHILDREN | UPDATENOW
}

; -- the edges: arrows, and the drag ------------------------------------------------
; the edge of window hw under the cursor: 0 none, else WMSZ's code (1 left, 2 right, 3 top,
; 4 top left, 5 top right, 6 bottom, 7 bottom left, 8 bottom right)
ScEdge(hw) {
    if !winScale.Has(hw) || !winScale[hw].w
        return 0
    pt := Buffer(8), DllCall("GetCursorPos", "ptr", pt)
    mx := NumGet(pt, 0, "int"), my := NumGet(pt, 4, "int")
    WinGetPos(&wx, &wy, &ww, &wh, "ahk_id " hw)
    z := Round(6 * DPI_K), cz := Round(18 * DPI_K)
    if mx < wx || my < wy || mx >= wx + ww || my >= wy + wh
        return 0
    l := mx - wx < z, r := wx + ww - mx <= z, t := my - wy < z, b := wy + wh - my <= z
    ; near a corner along an edge: the corner
    if l || r
        t := t || my - wy < cz, b := b || wy + wh - my <= cz
    else if t || b
        l := mx - wx < cz, r := wx + ww - mx <= cz
    return t ? (l ? 4 : r ? 5 : 3) : b ? (l ? 7 : r ? 8 : 6) : l ? 1 : r ? 2 : 0
}
ScSetCursor(wParam, lParam, msg, hwnd) {
    root := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")      ; GA_ROOT
    if !winScale.Has(root) || !(e := ScEdge(root))
        return
    id := [32644, 32644, 32645, 32642, 32643, 32645, 32643, 32642][e]   ; SIZEWE, SIZENS, SIZENWSE, SIZENESW
    DllCall("SetCursor", "ptr", DllCall("LoadCursor", "ptr", 0, "ptr", id, "ptr"))
    return 1
}
; a left click in a scalable window (WM_LBUTTONDOWN): true if it started a resize (an edge)
; or a move (an empty spot of a popup; the main window moves itself)
ScClick(hwnd) {
    root := DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr")
    if !winScale.Has(root)
        return false
    if e := ScEdge(root) {
        SetTimer(ScResize.Bind(root, e), -1)
        return true
    }
    if hwnd = root && winScale[root].kind != "main" {
        PostMessage(0xA1, 2, , , "ahk_id " root)     ; WM_NCLBUTTONDOWN, HTCAPTION
        return true
    }
    return false
}
; drag edge e of window hw while the button is down: one scale for both sides (the shape kept),
; in 5% steps, the far side staying put; then kept in the ini
ScResize(hw, e) {
    g := GuiFromHwnd(hw)
    if !g || !winScale.Has(hw)
        return
    s := winScale[hw], k0 := s.k
    pt := Buffer(8), DllCall("GetCursorPos", "ptr", pt)
    mx0 := NumGet(pt, 0, "int"), my0 := NumGet(pt, 4, "int")
    WinGetPos(&x0, &y0, &w0, &h0, g)
    ; no bigger than the screen it's on
    mon := DllCall("MonitorFromWindow", "ptr", hw, "uint", 2, "ptr"), mi := Buffer(40, 0)
    NumPut("uint", 40, mi), DllCall("GetMonitorInfoW", "ptr", mon, "ptr", mi)
    waW := NumGet(mi, 28, "int") - NumGet(mi, 20, "int"), waH := NumGet(mi, 32, "int") - NumGet(mi, 24, "int")
    kMax := Min(SCALE_MAX, waW / (s.w * DPI_K), waH / (s.h * DPI_K))
    sx := e = 1 || e = 4 || e = 7 ? -1 : e = 2 || e = 5 || e = 8 ? 1 : 0
    sy := e >= 3 && e <= 5 ? -1 : e >= 6 ? 1 : 0
    while GetKeyState("LButton", "P") {
        DllCall("GetCursorPos", "ptr", pt)
        dx := NumGet(pt, 0, "int") - mx0, dy := NumGet(pt, 4, "int") - my0
        kw := (w0 + sx * dx) / w0 * k0, kh := (h0 + sy * dy) / h0 * k0
        k := sx && sy ? Max(kw, kh) : sx ? kw : kh
        k := Max(SCALE_MIN, Min(kMax, Round(k / SCALE_STEP) * SCALE_STEP))
        if Abs(k - s.k) >= 0.001 {
            kk := DPI_K * k, pw := Round(s.w * kk), ph := Round(s.h * kk)
            ApplyScale(g, k, sx < 0 ? x0 + w0 - pw : x0, sy < 0 ? y0 + h0 - ph : y0)
        }
        Sleep(15)
    }
    if Abs(s.k - k0) >= 0.001
        SetIni(Round(s.k, 2), "Window", ScaleKey(s.kind))
}
