#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================================
;  TW Companion - light native TWRPG loader for Warcraft III.
;  Borderless window on a baked background in the site's theme; native controls on top.
;  Opens loader-first; other sections are nav pages.
;
;  Control hotkeys:  F10 toggle (WC3) · F8 show/hide · Pause pause (WC3)
;                    Esc hide window · Alt+Esc exit
;  Overlay (TWRPG site over the game): Shift+Space show/hide ·
;                    Ctrl+Shift+Space pin (configurable on the Overlay page)
; ============================================================================

#Include lib\Common.ahk
#Include engine\Loader.ahk
#Include engine\Macros.ahk
#Include engine\Remap.ahk
#Include engine\Host.ahk
#Include engine\Settings.ahk
#Include engine\Updater.ahk
#Include ui\OverlayPanel.ahk

; ---- palette: the site's theme (src/styles/base.css) -------------------------
global C := {
    win:     "0C0D10",   ; --bg: content area, status badge     } baked into
    side:    "121419",   ; --bg2: sidebar                       } assets/bg.png
    panel:   "0C0D10",   ; behind labels/checkboxes (= --bg)
    well:    "121419",   ; --bg2: inputs
    card:    "14161B",   ; --card: lists
    border:  "23262E",   ; --border: cards
    frame:   "30343E",   ; --border2: inputs, buttons
    chip:    "191C22",   ; --bg3: .btn
    accent:  "F5A623",   ; --accent
    onAccent:"1A1004",   ; text on .btn.primary
    navOn:   "29231A",   ; .nav-link.active: accent at 10% over the sidebar
    text:    "E6E4DF",   ; --text
    muted:   "9A9EAA",   ; --muted2
    dim:     "6F7380" }  ; --muted
; window, sidebar width, and where page content starts (see assets/generate_bg.py)
global W := 880, H := 510, SIDE_W := 150, CX := 174, CY := 76
global TB_Y := 20           ; toolbar row: page title + that page's main controls
global NAV_ORDER := ["loader", "macros", "remap", "host", "settings", "overlay"]
global ICON_FONT := "Segoe Fluent Icons"
; the site's system-ui font on Windows 11; classic Segoe UI on older systems
global UI_FONT := FileExist(A_WinDir "\Fonts\SegUIVar.ttf") ? "Segoe UI Variable Text" : "Segoe UI"

; Set ctl's font to UI_FONT at the weight in opts ("s9 w600"). GDI only gives a
; family its Regular and Bold; Semibold (the site's 600, used by .btn and the
; nav) is a separate family, "<font> Semibold". Asking the base family for 600
; snaps to Bold, which is what made buttons look heavier than on the site.
UISetFont(ctl, opts) {
    global UI_FONT
    w := RegExMatch(opts, "\bw(\d+)", &m) ? Integer(m[1]) : 400
    if w >= 550 && w < 700
        ctl.SetFont(RegExReplace(opts, "\bw\d+", "w400"), UI_FONT " Semibold")
    else
        ctl.SetFont(opts, UI_FONT)
}
global boxes := Map()       ; control hwnd -> the Box drawn behind it (StyleControl)
global buttons := Map()     ; MkButton hwnd -> its background colour (picks the style)
global navItems := Map()    ; page -> { box, icon, label } in the sidebar
global popovers := Map()    ; hover popovers by name (AddPopover)
global chatHook := InputHook("V")       ; records the WC3 chat line (ChatEnter)
global toastGui := 0, toastText := 0   ; the themed toast (Toast)

; ---- globals ---------------------------------------------------------------
global version := "1.0.0"
global toolEnabled := true, chatting := false, toolEnableHistory := true
global showMain := false
global loader, macros, remap, host, settings, updater, webOverlay
global mainGui, bgPic, titleText, navBar, toolOn, toolOff, searchIcon
global pages := Map(), currentPage := "loader"
global controlsToDrag := Map()

; loader controls
global searchEdit, hiddenChip, helpBtn, msgLabel, msgSummary, msgInfo, msgEdit, loadBtn
global emptyTitle, emptySub, emptyBtn
global saveRows := [], saveCard, saveBar, saveThumb      ; the custom save list (BuildSaveList)
global saveFiles := [], saveOffset := 0, saveSel := "", showHidden := false, expanded := Map(), saveCache := 0
global SAVE_ROWS := 10, SAVE_ROW_H := 34
; macros
global macroListBox, macroCapBtn, macroMsgEdit, macroPendingHK := "", macroPendingLabel := "", macroSel := -1
; remap
global remapListBox, remapMap := []
global enSpells, enInv, enMouse
; host
global hostEdits := Map()
; settings
global setChecks := Map(), loadDelayEdit, postDelayEdit, folderEdit, folderLabel, convertCb
; overlay
global ovHkBtn, ovPinBtn, ovSideBtns := Map(), ovOpacityEdit, ovPinOpacityEdit, ovUnloadEdit, ovChecks := Map(), ovVersionText

; ---- run elevated ----------------------------------------------------------
if !A_IsAdmin {
    try {
        if A_IsCompiled
            Run '*RunAs "' A_ScriptFullPath '" /restart'
        else
            Run '*RunAs "' A_AhkPath '" /restart "' A_ScriptFullPath '"'
    }
    ExitApp
}

ProcessSetPriority("High")
; Cinzel (the site's display font) for headings, loaded for this process only
DllCall("gdi32\AddFontResourceEx", "str", A_ScriptDir "\assets\Cinzel.ttf", "uint", 0x10, "ptr", 0)
SetKeyDelay(Integer(Ini("Settings", "keyDelay", 10)))

loader := LoaderEngine()
macros := MacrosEngine()
remap := RemapEngine()
host := HostEngine()
settings := SettingsEngine()
updater := UpdaterEngine()
webOverlay := OverlayPanel(updater)

BuildOverlay()
BuildWindow()

; startup behaviour
if !Ini("Settings", "enableToolOnStart", 0)
    ToggleTool()
if Ini("Settings", "hideOnStart", 0)
    mainGui.Hide()
else {
    ShowMainWindow()
}

A_TrayMenu.Insert("1&", "Open TWRPG overlay", (*) => webOverlay.show())
A_TrayMenu.Insert("2&", "Update overlay data", (*) => webOverlay.runUpdate(true))
A_TrayMenu.Insert("3&")
SetTimer(() => webOverlay.startupCheck(), -8000)
SetTimer(ChatWatch, 250)       ; record WC3 chat only while WC3 is focused

; ============================================================================
;  Window construction
; ============================================================================
BuildWindow() {
    global
    mainGui := Gui("-Caption +Border", "TW Companion")
    mainGui.BackColor := C.win
    mainGui.SetFont("s10", UI_FONT)
    mainGui.OnEvent("Close", (*) => HideMainWindow())
    mainGui.OnEvent("Escape", (*) => HideMainWindow())

    bgPic := mainGui.AddPicture("x0 y0 w" W " h" H, A_ScriptDir "\assets\bg.png")

    ; sidebar nav, like the site's .nav-link: icon + label, the active one tinted
    ; with an orange icon and an accent bar on the sidebar's edge
    for i, name in NAV_ORDER {
        y := 84 + (i - 1) * 38
        bx := Box("", 10, y, SIDE_W - 20, 34, C.side, C.side, 4)
        ic := mainGui.AddText("x22 y" y " w22 h34 0x200 +Background" C.side " c" C.muted, PageInfo(name).icon)
        ic.SetFont("s11", ICON_FONT)
        lb := mainGui.AddText("x52 y" y " w" (SIDE_W - 66) " h34 0x200 +Background" C.side " c" C.muted, PageInfo(name).nav)
        UISetFont(lb, "s10 w500")
        for t in [ic, lb]
            t.OnEvent("Click", NavClick.Bind(name))
        navItems[name] := { box: bx, icon: ic, label: lb }
    }
    navBar := mainGui.AddText("x0 y84 w3 h34 +Background" C.accent)

    ; sidebar footer: caption + version, then tool On | Off as a full-width
    ; segmented control (like the site's language switcher)
    local fy := H - 64, sw := SIDE_W - 28, half := (sw - 3) // 2
    toolCap := mainGui.AddText("x14 y" fy " w" (sw - 44) " h16 +Background" C.side " c" C.dim, "TOOL  ·  F10")
    UISetFont(toolCap, "s8 w600")
    verText := mainGui.AddText("x" (SIDE_W - 58) " y" fy " w44 h16 Right +Background" C.side " c" C.dim, "v" version)
    UISetFont(verText, "s8")
    Box("", 14, fy + 20, sw, 30, C.side, C.frame, 5)
    toolOn := mainGui.AddText("x16 y" (fy + 22) " w" half " h26 Center 0x200 +Background" C.side, "On")
    mainGui.AddText("x" (16 + half) " y" (fy + 26) " w1 h18 +Background" C.frame)    ; divider
    toolOff := mainGui.AddText("x" (17 + half) " y" (fy + 22) " w" (sw - 4 - half - 1) " h26 Center 0x200 +Background" C.side, "Off")
    for t in [toolOn, toolOff] {
        UISetFont(t, "s9 w600"), t.OnEvent("Click", (*) => ToggleTool())
        t.GetPos(, , &tw, &th), Box.Round(t, tw, th, 4)
    }

    MkButton("✕", W - 40, TB_Y + 1, 26, 26, C.panel, C.muted, (*) => HideMainWindow())

    ; toolbar: compact Cinzel page title (the divider under it is baked into
    ; bg.png); pages put their main controls on the same row
    titleText := mainGui.AddText("x" CX " y" TB_Y " w150 h28 0x200 +Background" C.panel " c" C.text, "")
    titleText.SetFont("s14 w700", "Cinzel")

    ; pages are laid out from (40, 160); shift them into the content area
    BuildLoaderPage()
    BuildMacrosPage()
    BuildRemapPage()
    BuildHostPage()
    BuildSettingsPage()
    BuildOverlayPage()
    for pg, arr in pages
        for ctl in arr {        ; not `c`: names are case-insensitive, that's the palette
            ctl.GetPos(&x, &y)
            ctl.Move(x + CX - 40, y + CY - 160)
        }
    LayoutLoader()
    for pg, arr in pages.Clone()
        for ctl in arr.Clone()
            StyleControl(pg, ctl)
    BuildSaveList()
    ; search icon inside the loader's search box, like the site's search inputs.
    ; The edit starts right of it: an edit repaints its whole rect, so any
    ; overlap would wipe the icon.
    sb := boxes[searchEdit.Hwnd]
    searchIcon := mainGui.AddText("x" (sb.x + 1) " y" (sb.y + 1) " w30 h" (sb.h - 2) " Center 0x200 +Background" C.well " c" C.dim, Chr(0xE721))
    searchIcon.SetFont("s9", ICON_FONT)
    AddToPage("loader", searchIcon)
    searchEdit.GetPos(, &sy, , &sh)
    searchEdit.Move(sb.x + 31, sy, sb.w - 32, sh)
    SendMessage(0xD3, 1, 0, searchEdit)     ; EM_SETMARGINS left: the icon is the padding

    OnMessage(0x201, WM_LBUTTONDOWN)
    UpdateToolPill()
}

; Loader: search, ? and Show hidden share the toolbar row with the title; the
; load-message row sits at the bottom, under the save list
LayoutLoader() {
    global
    local R := W - 52                      ; stop short of the close button
    hiddenChip.Move(R - 140, TB_Y, 140, 28)
    helpBtn.Move(R - 178, TB_Y, 30, 28)
    searchEdit.Move(CX + 160, TB_Y, R - 186 - (CX + 160), 28)
    msgLabel.Move(CX, H - 82), msgSummary.Move(CX + 250, H - 82), msgInfo.Move(CX + 522, H - 84)
    msgEdit.Move(CX, H - 62, 540, 32)
    loadBtn.Move(CX + 560, H - 64, 120, 36)
}

PageInfo(name) {
    static info := Map(
        "loader",   { nav: "Loader",   icon: Chr(0xE8E5), title: "Loader" },
        "macros",   { nav: "Macros",   icon: Chr(0xE765), title: "Macros" },
        "remap",    { nav: "Remap",    icon: Chr(0xE8AB), title: "Remap" },
        "host",     { nav: "Host",     icon: Chr(0xE716), title: "Host" },
        "settings", { nav: "Settings", icon: Chr(0xE713), title: "Settings" },
        "overlay",  { nav: "Overlay",  icon: Chr(0xE8A7), title: "Overlay" })
    return info[name]
}

; A filled, bordered, rounded rectangle drawn *behind* other controls: two Text
; controls slotted just after the background picture in the z-order, rounded
; with a window region. Gives native controls the site's input/card/button look.
class Box {
    __New(page, x, y, w, h, fill, border, radius := 4) {
        global mainGui, bgPic
        this.r := radius
        this.outer := mainGui.AddText("x0 y0 w1 h1 +Background" border)
        this.inner := mainGui.AddText("x0 y0 w1 h1 +Background" fill)
        ; siblings paint in z-order, so each insert after the picture goes
        ; under what's already there: inner first, then outer below it
        for t in [this.inner, this.outer]
            DllCall("SetWindowPos", "ptr", t.Hwnd, "ptr", bgPic.Hwnd, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x13)
        if page
            AddToPage(page, this.outer, this.inner)
        this.Move(x, y, w, h)
    }
    Move(x, y, w, h) {
        this.x := x, this.y := y, this.w := w, this.h := h
        this.outer.Move(x, y, w, h)
        this.inner.Move(x + 1, y + 1, w - 2, h - 2)
        Box.Round(this.outer, w, h, this.r)
        Box.Round(this.inner, w - 2, h - 2, Max(0, this.r - 1))
    }
    Visible {
        set => (this.outer.Visible := Value, this.inner.Visible := Value)
    }
    Fill {
        set => (this.inner.Opt("+Background" Value), this.inner.Redraw())
    }
    static Round(ctl, w, h, r) {
        if r <= 0
            return
        rgn := DllCall("CreateRoundRectRgn", "int", 0, "int", 0, "int", w + 1, "int", h + 1, "int", r * 2, "int", r * 2, "ptr")
        DllCall("SetWindowRgn", "ptr", ctl.Hwnd, "ptr", rgn, "int", 1)
    }
}

; Restyle a page control like its site counterpart (native borders are thick
; and white): inputs get a --bg2 box with a --border2 edge and centred text,
; lists sit in a --card box with padding, .btn-style buttons get a bordered box,
; primary (orange) buttons just get rounded corners.
StyleControl(page, ctrl) {
    global boxes, buttons, C
    if ctrl.Type = "Edit" || ctrl.Type = "ListBox" {
        ctrl.Opt("-E0x200 -Border")
        DllCall("SetWindowPos", "ptr", ctrl.Hwnd, "ptr", 0, "int", 0, "int", 0, "int", 0, "int", 0, "uint", 0x37)   ; FRAMECHANGED
        ctrl.GetPos(&x, &y, &w, &h)
        if ctrl.Type = "ListBox" {
            ctrl.Opt("+Background" C.card)
            boxes[ctrl.Hwnd] := Box(page, x, y, w, h, C.card, C.border, 6)
        } else {
            boxes[ctrl.Hwnd] := Box(page, x, y, w, h, C.well, C.frame, 4)
            SendMessage(0xD3, 3, 10 | (10 << 16), ctrl)    ; EM_SETMARGINS: 10px left/right
        }
        PlaceInBox(ctrl)
    } else if ctrl.Type = "Text" && buttons.Has(ctrl.Hwnd) {
        ctrl.GetPos(&x, &y, &w, &h)
        bg := buttons[ctrl.Hwnd]
        if bg = C.chip {
            boxes[ctrl.Hwnd] := Box(page, x, y, w, h, C.chip, C.frame, 4)
            ctrl.Move(x + 1, y + 1, w - 2, h - 2)
        } else if bg = C.accent {
            Box.Round(ctrl, w, h, 4)
        }
    }
}
; fit a control inside its box (after the box moves)
PlaceInBox(ctrl) {
    global boxes
    b := boxes[ctrl.Hwnd]
    if ctrl.Type = "ListBox"
        ctrl.Move(b.x + 8, b.y + 6, b.w - 10, b.h - 12)          ; padding; scrollbar keeps the right edge
    else if ControlGetStyle(ctrl) & 0x4                           ; ES_MULTILINE
        ctrl.Move(b.x + 2, b.y + 4, b.w - 4, b.h - 8)
    else
        ctrl.Move(b.x + 1, b.y + (b.h - 20) // 2, b.w - 2, 20)   ; text vertically centred
}
; show/hide a control together with its box
SetShown(ctrl, v) {
    global boxes
    ctrl.Visible := v
    if boxes.Has(ctrl.Hwnd)
        boxes[ctrl.Hwnd].Visible := v
}

; drag window by clicking the background
; drag the window from any empty spot. Clicks on the background picture and on
; plain labels fall through to the window itself (statics are transparent to
; the mouse), so both mean "empty space".
WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global bgPic, mainGui
    if IsSet(mainGui) && (hwnd = mainGui.Hwnd || hwnd = bgPic.Hwnd) {
        PostMessage(0xA1, 2, , , "ahk_id " mainGui.Hwnd)    ; WM_NCLBUTTONDOWN, HTCAPTION
        return 0
    }
}

StrTitle(s) => StrUpper(SubStr(s, 1, 1)) SubStr(s, 2)

; make a Text control that behaves like a flat button (styled by StyleControl)
MkButton(label, x, y, w, h, bg, fg, handler) {
    global mainGui, buttons
    b := mainGui.AddText("x" x " y" y " w" w " h" h " Center 0x200 +Background" bg " c" fg, label)
    UISetFont(b, "s9 w600")
    b.OnEvent("Click", handler)
    buttons[b.Hwnd] := bg
    return b
}

AddToPage(name, ctrls*) {
    global pages
    if !pages.Has(name)
        pages[name] := []
    for c in ctrls
        pages[name].Push(c)
}

; ============================================================================
;  Navigation
; ============================================================================
NavClick(name, *) => ShowPage(name)

ShowPage(name) {
    global pages, navItems, navBar, titleText, currentPage, C, mainGui
    currentPage := name
    for pg, arr in pages
        for c in arr
            c.Visible := (pg = name)
    titleText.Text := PageInfo(name).title
    for nm, it in navItems {
        on := nm = name
        bg := on ? C.navOn : C.side
        it.box.Fill := bg
        it.icon.Opt("+Background" bg " +c" (on ? C.accent : C.muted)), it.icon.Redraw()
        it.label.Opt("+Background" bg " +c" (on ? C.text : C.muted)), it.label.Redraw()
        if on {
            it.label.GetPos(, &y)
            navBar.Move(, y), navBar.Redraw()
        }
    }
    switch name {
        case "loader":   RefreshFiles()
        case "macros":   RefreshMacros()
        case "remap":    RefreshRemap()
        case "host":     RefreshHost()
        case "settings": RefreshSettings()
        case "overlay":  RefreshOverlay()
    }
    ; rounded (region) boxes on the page we left can leave corner pixels behind
    DllCall("RedrawWindow", "ptr", mainGui.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x485)   ; INVALIDATE|ERASE|ALLCHILDREN|UPDATENOW
}

; ============================================================================
;  Loader page
; ============================================================================
BuildLoaderPage() {
    global
    searchEdit := mainGui.AddEdit("x40 y162 w482 h28 +Background" C.well " c" C.text, "")
    UISetFont(searchEdit, "s10")
    searchEdit.OnEvent("Change", (*) => SearchChanged())
    SendMessage(0x1501, 1, StrPtr("Search saves…"), searchEdit)    ; EM_SETCUEBANNER
    hiddenChip := MkButton("", 570, 162, 150, 28, C.chip, C.muted, (*) => ToggleShowHidden())
    helpBtn := MkButton("?", 530, 162, 30, 28, C.chip, C.muted, (*) => ShowPopover("commands"))
    AddToPage("loader", searchEdit, hiddenChip, helpBtn)

    ; load message for the selected save (rows themselves: BuildSaveList)
    msgLabel := mainGui.AddText("x40 y486 w250 h18 +Background" C.panel " c" C.muted, "Load message")
    ; what will actually be sent, and an ⓘ explaining how it works
    msgSummary := mainGui.AddText("x290 y486 w266 h18 Right +Background" C.panel " c" C.dim, "")
    UISetFont(msgSummary, "s9")
    msgInfo := mainGui.AddText("x562 y484 w18 h20 Center 0x200 +Background" C.panel " c" C.muted, Chr(0xE946))
    msgInfo.SetFont("s9", ICON_FONT)
    msgInfo.OnEvent("Click", (*) => ShowPopover("message"))     ; also makes it report hovers
    AddToPage("loader", msgSummary, msgInfo)
    msgEdit := mainGui.AddEdit("x40 y506 w540 h32 +Background" C.well " c" C.text, "")
    UISetFont(msgEdit, "s10")
    msgEdit.OnEvent("Change", (*) => SaveMessageChanged())
    SendMessage(0x1501, 1, StrPtr("e.g.  gl hf | sniper time | brb   (optional)"), msgEdit)
    loadBtn := MkButton("LOAD", 600, 504, 120, 36, C.accent, C.onAccent, (*) => LoadSelected())
    AddToPage("loader", msgLabel, msgEdit, loadBtn)
}

; The save list, drawn like the site's item rows: ☆/★ favourite, name, message
; badge, date, and a hide toggle per row. A fixed pool of row controls is
; re-filled as you scroll (wheel / arrows); built after the page shift, so it
; uses window coordinates.
BuildSaveList() {
    global
    local x := CX, y := CY, w := 680, h := SAVE_ROWS * SAVE_ROW_H + 2
    saveCard := Box("loader", x, y, w, h, C.card, C.border, 6)
    saveBar := mainGui.AddText("x" (x + 1) " y0 w3 h" (SAVE_ROW_H - 1) " +Background" C.accent)
    saveThumb := mainGui.AddText("x" (x + w - 6) " y" (y + 4) " w3 h20 +Background" C.frame)
    AddToPage("loader", saveBar, saveThumb)
    ; columns: star | name | message badge | date | hide
    local cols := [["star", 4, 36], ["name", 40, 290], ["count", 330, 110], ["msg", 440, 30], ["date", 470, 160], ["eye", 630, 40]]
    loop SAVE_ROWS {
        local i := A_Index, ry := y + 1 + (i - 1) * SAVE_ROW_H, row := { idx: i }
        for col in cols {
            local opt := "x" (x + col[2]) " y" ry " w" col[3] " h" (SAVE_ROW_H - 1) " 0x200 +Background" C.card
            if col[1] = "date"
                opt .= " Right"
            else if col[1] != "name"
                opt .= " Center"
            local t := mainGui.AddText(opt, "")
            if col[1] = "name" || col[1] = "date" || col[1] = "count"
                UISetFont(t, col[1] = "name" ? "s10 w500" : "s9")
            else
                t.SetFont("s10", ICON_FONT)
            row.%col[1]% := t
            AddToPage("loader", t)
        }
        row.sep := mainGui.AddText("x" (x + 1) " y" (ry + SAVE_ROW_H - 1) " w" (w - 2) " h1 +Background" C.border)
        AddToPage("loader", row.sep)
        row.star.OnEvent("Click", SaveRowClick.Bind(i, "star"))
        row.count.OnEvent("Click", SaveRowClick.Bind(i, "expand"))
        row.eye.OnEvent("Click", SaveRowClick.Bind(i, "eye"))
        for k in ["name", "msg", "date"] {
            row.%k%.OnEvent("Click", SaveRowClick.Bind(i, "select"))
            row.%k%.OnEvent("DoubleClick", SaveRowClick.Bind(i, "load"))
        }
        saveRows.Push(row)
    }
    ; empty state sits in the card
    emptyTitle := mainGui.AddText("x" x " y0 w" w " h24 Center +Background" C.card " c" C.text, "")
    UISetFont(emptyTitle, "s11 w600")
    emptySub := mainGui.AddText("x" x " y0 w" w " h40 Center +Background" C.card " c" C.muted, "")
    emptyBtn := MkButton("Choose folder", 0, 0, 160, 32, C.accent, C.onAccent, (*) => (loader.setFolder(Map()), RefreshFiles()))
    Box.Round(emptyBtn, 160, 32, 4)
    AddToPage("loader", emptyTitle, emptySub, emptyBtn)
    OnMessage(0x20A, SaveListWheel)
    AddPopover("commands", helpBtn, [
        ["Load from Warcraft III chat", ""],
        ["-l sniper", "loads the closest match: exact name, then starts with, then contains"],
        ["-l 2", "loads your 2nd ★ favourite (other numbers match names: -l 92 finds knight#92)"],
        ["-l  /  -ll", "reloads the save you loaded last"],
        ["-sn", "saves the next number of the save you loaded with the companion: after knight#92 it types -save knight#93 (lowercase, no spaces, like TWRPG names its files)"],
        ["", "Also -load and -loadlast. Loader commands are never sent to chat. Keyboard and mouse are held for the second or two a load takes."]])
    AddPopover("message", msgInfo, [
        ["Load message", ""],
        ["What", "A chat line the companion types in Warcraft III each time this save loads, right before its -load codes."],
        ["When", "Every load: LOAD, double-click, Enter, -l, -ll and favourites."],
        ["Random", "Separate options with  |  and one of them is picked at random each load."],
        ["Example", "gl hf | sniper time | brb    →  sends one of these three"],
        ["Series", "Numbered saves (knight#91, #92…) share one message for the whole series."],
        ["Empty", "Leave it blank to send nothing."],
        ["", "It's sent like anything you type in chat, so other players can see it."]], "above-right")
    OnMessage(0x200, PopoverHover)         ; WM_MOUSEMOVE: open a popover when its anchor is hovered
}

; reload := false re-groups the saves already read (expand, search, show
; hidden) instead of reading every file from disk again
RefreshFiles(reload := true) {
    global
    if reload || !IsObject(saveCache)
        saveCache := loader.files(Map("showHidden", 1))
    local all := [], q := searchEdit.Value
    for f in saveCache
        if q = "" || InStr(f.name, q)
            all.Push(f)
    local pins := Map(), hiddenCount := 0, groups := Map(), tops := []
    for i, n in loader.pinned()
        pins[n] := i
    ; numbered saves (knight#91, #92...) collapse into one row per series
    for f in all {
        if f.series {
            if !groups.Has(f.key)
                groups[f.key] := []
            groups[f.key].Push(f)
        } else {
            tops.Push({ kind: "file", id: f.name, name: f.name, key: f.name, label: StrReplace(f.name, ".txt", ""),
                pinned: pins.Has(f.name) ? pins[f.name] : 0, hidden: f.hidden, msg: f.msg, date: f.date, sortKey: f.sortKey, files: 0 })
        }
    }
    for key, fs in groups {
        SortBy(fs, (a, b) => b.series.num - a.series.num)              ; newest number first
        local newest := ""
        for f in fs
            if !newest || f.sortKey > newest
                newest := f.sortKey
        local top := fs[1]
        tops.Push({ kind: "series", id: "S|" key, name: top.name, key: key, label: StrReplace(top.name, ".txt", ""),
            pinned: pins.Has(key) ? pins[key] : 0, hidden: top.hidden, msg: top.msg, date: top.date, sortKey: newest, files: fs })
    }
    for e in tops
        if e.hidden
            hiddenCount++
    ; favourites first (in the order you starred them), then most recent
    SortBy(tops, (a, b) => (a.pinned && b.pinned) ? a.pinned - b.pinned
        : a.pinned ? -1 : b.pinned ? 1 : (a.sortKey < b.sortKey) - (a.sortKey > b.sortKey))
    saveFiles := []
    for e in tops {
        if e.hidden && !showHidden
            continue
        saveFiles.Push(e)
        if e.kind = "series" && expanded.Has(e.key)
            loop e.files.Length - 1 {
                local f := e.files[A_Index + 1]
                saveFiles.Push({ kind: "child", id: f.name, name: f.name, key: e.key, label: StrReplace(f.name, ".txt", ""),
                    pinned: 0, hidden: e.hidden, msg: e.msg, date: f.date, sortKey: f.sortKey, files: 0 })
            }
    }
    hiddenChip.Text := (showHidden ? "Hide hidden" : "Show hidden") (hiddenCount ? "  (" hiddenCount ")" : "")
    if !SaveIndex(saveSel)
        saveSel := saveFiles.Length ? saveFiles[1].id : ""
    saveOffset := Max(0, Min(saveOffset, saveFiles.Length - SAVE_ROWS))
    RenderSaves()
    ShowEmptyState(saveFiles.Length ? "" : EmptyReason())
    ShowSelectedMessage()
}

SearchChanged() {
    global saveOffset := 0
    RefreshFiles(false)
}
ToggleShowHidden() {
    global showHidden := !showHidden
    RefreshFiles(false)
}

RenderSaves() {
    global
    ; paint once at the end instead of once per row control (~60 of them)
    SendMessage(0x0B, 0, 0, mainGui)                    ; WM_SETREDRAW off
    try RenderSaveRows()
    SendMessage(0x0B, 1, 0, mainGui)                    ; WM_SETREDRAW on
    local c := saveCard
    local rc := Buffer(16), _ := NumPut("int", c.x, "int", c.y, "int", c.x + c.w, "int", c.y + c.h, rc)
    DllCall("RedrawWindow", "ptr", mainGui.Hwnd, "ptr", rc, "ptr", 0, "uint", 0x485)   ; INVALIDATE|ERASE|ALLCHILDREN|UPDATENOW
}
RenderSaveRows() {
    global
    local sel := SaveIndex(saveSel)
    saveBar.Visible := false
    for row in saveRows {
        local idx := saveOffset + row.idx, has := idx <= saveFiles.Length
        for k in ["star", "name", "count", "msg", "date", "eye", "sep"]
            row.%k%.Visible := has
        if !has
            continue
        local f := saveFiles[idx], on := idx = sel, bg := on ? C.navOn : C.card, child := f.kind = "child"
        row.star.Text := child ? "" : Chr(f.pinned ? 0xE735 : 0xE734)
        row.star.Opt("+Background" bg " +c" (f.pinned ? C.accent : C.dim))
        row.name.Text := (child ? "      " : "") f.label
        row.name.Opt("+Background" bg " +c" (f.hidden || child ? C.dim : C.text))
        row.count.Text := f.kind = "series" && f.files.Length > 1
            ? f.files.Length " saves  " (expanded.Has(f.key) ? "▾" : "▸") : ""
        row.count.Opt("+Background" bg " +c" C.muted)
        row.msg.Text := f.msg ? Chr(0xE8BD) : ""
        row.msg.Opt("+Background" bg " +c" C.muted)
        row.date.Text := f.date "  "
        row.date.Opt("+Background" bg " +c" C.muted)
        row.msg.Text := f.msg && !child ? Chr(0xE8BD) : ""
        row.eye.Text := child ? "" : Chr(f.hidden ? 0xED1A : 0xE890)
        row.eye.Opt("+Background" bg " +c" (f.hidden ? C.accent : C.dim))
        if on {
            row.name.GetPos(, &ry)
            saveBar.Move(, ry), saveBar.Visible := true
        }
    }
    ; scroll position, like a thin overlay scrollbar
    local over := saveFiles.Length > SAVE_ROWS
    saveThumb.Visible := over
    if over {
        local trackH := saveCard.h - 8, th := Max(18, trackH * SAVE_ROWS // saveFiles.Length)
        saveThumb.Move(, saveCard.y + 4 + (trackH - th) * saveOffset // (saveFiles.Length - SAVE_ROWS), , th)
    }
}

SaveIndex(id) {
    global saveFiles
    for i, f in saveFiles
        if f.id == id
            return i
    return 0
}

SaveRowClick(i, what, *) {
    global saveFiles, saveOffset, saveSel, loader, expanded
    idx := saveOffset + i
    if idx > saveFiles.Length
        return
    f := saveFiles[idx]
    switch what {
        case "star":
            if f.kind != "child"
                loader.pinToggle(Map("name", f.key)), RefreshFiles()
        case "eye":
            if f.kind != "child"
                loader.hideToggle(Map("name", f.key)), RefreshFiles()
        case "expand":
            if f.kind = "series" && f.files.Length > 1 {
                if expanded.Has(f.key)
                    expanded.Delete(f.key)
                else
                    expanded[f.key] := 1
                saveSel := f.id, RefreshFiles(false)
            }
        case "load": saveSel := f.id, LoadSelected()
        default:     saveSel := f.id, RenderSaves(), ShowSelectedMessage()
    }
}

; move the selection by n rows, keeping it in view
SaveMove(n) {
    global saveFiles, saveOffset, saveSel, SAVE_ROWS
    if !saveFiles.Length
        return
    i := Max(1, Min(saveFiles.Length, SaveIndex(saveSel) + n))
    saveSel := saveFiles[i].id
    if i <= saveOffset
        saveOffset := i - 1
    else if i > saveOffset + SAVE_ROWS
        saveOffset := i - SAVE_ROWS
    RenderSaves(), ShowSelectedMessage()
}

SaveListWheel(wParam, lParam, msg, hwnd) {
    global mainGui, currentPage, saveCard, saveOffset, saveFiles, SAVE_ROWS
    if currentPage != "loader" || !WinActive("ahk_id " mainGui.Hwnd)
        return
    mx := lParam << 48 >> 48, my := lParam << 32 >> 48       ; signed screen coords
    WinGetClientPos(&wx, &wy, , , mainGui)
    mx -= wx, my -= wy
    if mx < saveCard.x || mx > saveCard.x + saveCard.w || my < saveCard.y || my > saveCard.y + saveCard.h
        return
    step := (wParam << 32 >> 48) > 0 ? -3 : 3
    saveOffset := Max(0, Min(saveOffset + step, saveFiles.Length - SAVE_ROWS))
    RenderSaves()
    return 0
}

ShowSelectedMessage() {
    global saveSel, msgEdit, msgLabel, msgSummary, loader, saveFiles
    i := SaveIndex(saveSel)
    msgEdit.Enabled := i > 0
    msgLabel.Text := !i ? "Load message"
        : "Load message  ·  " (saveFiles[i].kind = "file" ? saveFiles[i].label : "every " RegExReplace(saveFiles[i].key, "#\*$") " save")
    v := i ? saveFiles[i].msg : ""
    if msgEdit.Value != v
        msgEdit.Value := v
    msgSummary.Text := i ? MessageSummary(v) : ""
}

; what a load message will send: nothing / the line / one of N at random
MessageSummary(raw) {
    n := 0
    for o in StrSplit(raw, "|")
        if Trim(o) != ""
            n++
    return n = 0 ? "nothing is sent" : n = 1 ? "sent once per load" : n " options · one picked at random"
}

SaveMessageChanged() {
    global saveSel, msgEdit, msgSummary, loader, saveFiles, saveCache
    i := SaveIndex(saveSel)
    if !i
        return
    e := saveFiles[i]
    loader.setMessage(Map("name", e.key, "msg", Trim(msgEdit.Value)))
    msgSummary.Text := MessageSummary(msgEdit.Value)
    had := e.msg != ""
    for f in saveFiles                      ; a series shares one message
        if f.key = e.key
            f.msg := Trim(msgEdit.Value)
    for f in saveCache                      ; keep the cached read in step
        if f.key = e.key
            f.msg := Trim(msgEdit.Value)
    if had != (e.msg != "")
        RenderSaves()
}

; why the save list is empty -> [title, subtitle, show "Choose folder"]
EmptyReason() {
    global loader, searchEdit, showHidden
    cfg := loader.config(Map())
    if !cfg.found
        return ["No TWRPG save folder found",
            "Looked in Documents\Warcraft III\CustomMapData\TWRPG (including OneDrive)`nand Warcraft III's install folder. Pick the folder with your saves.", true]
    if searchEdit.Value != ""
        return ['No saves match "' searchEdit.Value '"', "", false]
    return ["No saves in this folder yet", cfg.folder "`nTWRPG writes your saves here. Wrong folder? Pick another one.", true]
}

ShowEmptyState(reason) {
    global emptyTitle, emptySub, emptyBtn, saveCard
    on := reason != ""
    for ctl in [emptyTitle, emptySub]
        ctl.Visible := on
    emptyBtn.Visible := on && reason[3]
    if !on
        return
    b := saveCard
    top := b.y + Max(16, (b.h - 120) // 2)
    emptyTitle.Move(b.x + 2, top, b.w - 4), emptyTitle.Text := reason[1]
    emptySub.Move(b.x + 2, top + 30, b.w - 4), emptySub.Text := reason[2]
    emptyBtn.Move(b.x + (b.w - 160) // 2, top + 80)
}

LoadSelected() {
    global saveSel, saveFiles, loader
    if i := SaveIndex(saveSel) {
        r := loader.load(Map("name", saveFiles[i].name))      ; a series row loads its newest number
        if r.HasProp("error") && r.error = "not found"         ; deleted outside the companion
            RefreshFiles()
    }
    else
        Toast("Select a save first", "error")
}

; ---- hover popovers (the "?" and ⓘ helps) ------------------------------------
; A popover is a small card that opens while the mouse is over its anchor (or
; after a click) and closes once the mouse leaves both. Lines:
;   ["Title", ""]      heading
;   ["key", "text"]    a row; text wraps
;   ["", "text"]       muted footnote
AddPopover(name, anchor, lines, place := "below-right") {
    global popovers
    popovers[name] := { anchor: anchor, lines: lines, place: place, gui: 0, w: 0, h: 0 }
}
ShowPopover(name, show := true) {
    global popovers, mainGui, C
    p := popovers[name]
    if !show {
        if p.gui
            p.gui.Hide()
        return
    }
    if !p.gui {
        g := Gui("-Caption +ToolWindow +Owner" mainGui.Hwnd)
        g.BackColor := C.frame                           ; = the 1px border
        g.MarginX := 0, g.MarginY := 0
        w := 470, card := g.AddText("x1 y1 w" (w - 2) " h10 +Background" C.card)
        y := 14
        for line in p.lines {
            if line[2] = "" {
                t := g.AddText("x18 y" y " w" (w - 36) " h20 +Background" C.card " c" C.text, line[1])
                UISetFont(t, "s10 w600")
                y += 26
            } else if line[1] = "" {
                t := g.AddText("x18 y" (y + 2) " w" (w - 36) " +Background" C.card " c" C.dim, line[2])
                UISetFont(t, "s9")
                th := TextHeight(t, line[2], w - 36), t.Move(, , , th)
                y += th + 10
            } else {
                k := g.AddText("x18 y" y " w80 h18 +Background" C.card " c" C.accent, line[1])
                UISetFont(k, "s9 w600")
                v := g.AddText("x100 y" y " w" (w - 118) " +Background" C.card " c" C.muted, line[2])
                UISetFont(v, "s9")
                th := Max(18, TextHeight(v, line[2], w - 118)), v.Move(, , , th)
                y += th + 8
            }
        }
        h := y + 6
        card.Move(, , , h - 2)
        g.Show("Hide w" w " h" h)
        p.gui := g, p.w := w, p.h := h
    }
    p.anchor.GetPos(&ax, &ay, &aw, &ah)
    WinGetClientPos(&wx, &wy, , , mainGui)
    x := InStr(p.place, "right") ? wx + ax + aw - p.w : wx + ax
    y := InStr(p.place, "above") ? wy + ay - p.h - 6 : wy + ay + ah + 6
    p.gui.Show("NA x" x " y" y)
    SetTimer(PopoverHoverCheck, 120)
}
PopoverHoverCheck() {
    global popovers
    MouseGetPos(, , &win, &ctl, 2)
    anyOpen := false
    for name, p in popovers {
        if !p.gui || !DllCall("IsWindowVisible", "ptr", p.gui.Hwnd)
            continue
        if ctl = p.anchor.Hwnd || win = p.gui.Hwnd
            anyOpen := true
        else
            p.gui.Hide()
    }
    if !anyOpen
        SetTimer(PopoverHoverCheck, 0)
}
PopoverHover(wParam, lParam, msg, hwnd) {
    global popovers
    for name, p in popovers
        if hwnd = p.anchor.Hwnd && !(p.gui && DllCall("IsWindowVisible", "ptr", p.gui.Hwnd))
            ShowPopover(name)
}

; insertion sort with a comparator (save lists are small)
SortBy(arr, cmp) {
    loop arr.Length - 1 {
        i := A_Index + 1, v := arr[i], j := i - 1
        while j >= 1 && cmp(arr[j], v) > 0
            arr[j + 1] := arr[j], j--
        arr[j + 1] := v
    }
}

; ============================================================================
;  Macros page
; ============================================================================
BuildMacrosPage() {
    global
    macroListBox := mainGui.AddListBox("x40 y162 w680 h214 +Background" C.well " c" C.text, [])
    UISetFont(macroListBox, "s10")
    macroListBox.OnEvent("DoubleClick", (*) => MacroEditSelected())
    ApplyDark(macroListBox.Hwnd)
    lbl := mainGui.AddText("x40 y384 w150 h18 +Background" C.panel " c" C.muted, "Hotkey")
    lbl2 := mainGui.AddText("x200 y384 w300 h18 +Background" C.panel " c" C.muted, "Message (line per row)")
    macroCapBtn := MkButton("click to set", 40, 404, 150, 28, C.chip, C.text, (*) => MacroCapture())
    macroMsgEdit := mainGui.AddEdit("x200 y404 w520 h52 Multi +Background" C.well " c" C.text, "")
    UISetFont(macroMsgEdit, "s10")
    addBtn := MkButton("Add / Update", 40, 470, 140, 30, C.accent, C.onAccent, (*) => MacroSave())
    delBtn := MkButton("Delete", 190, 470, 90, 30, C.chip, C.text, (*) => MacroDelete())
    newBtn := MkButton("New", 290, 470, 80, 30, C.chip, C.text, (*) => MacroNew())
    AddToPage("macros", macroListBox, lbl, lbl2, macroCapBtn, macroMsgEdit, addBtn, delBtn, newBtn)
}
RefreshMacros() {
    global macroListBox, macros
    list := macros.list()
    items := []
    for m in list {
        prev := StrReplace(StrReplace(m.text, "`r", ""), "`n", "  |  ")
        items.Push((m.label ? m.label : "-") "        " prev)
    }
    macroListBox.Delete()
    if items.Length
        macroListBox.Add(items)
}
MacroEditSelected() {
    global macros, macroSel, macroPendingHK, macroPendingLabel, macroCapBtn, macroMsgEdit
    idx := macroListBox.Value
    if !idx
        return
    m := macros.list()[idx]
    macroSel := idx
    macroPendingHK := m.hotkey, macroPendingLabel := m.label
    macroCapBtn.Text := m.label ? m.label : "click to set"
    macroMsgEdit.Value := m.text
}
MacroCapture() {
    global macros, macroCapBtn, macroPendingHK, macroPendingLabel
    macroCapBtn.Text := "press keys…"
    r := macros.capture(Map())
    if r.hotkey {
        macroPendingHK := r.hotkey, macroPendingLabel := r.label
    }
    macroCapBtn.Text := macroPendingLabel ? macroPendingLabel : "click to set"
}
MacroSave() {
    global macros, macroPendingHK, macroMsgEdit, macroSel
    if !macroPendingHK || !Trim(macroMsgEdit.Value) {
        Toast("Set a hotkey and a message", "error")
        return
    }
    args := Map("hotkey", macroPendingHK, "text", macroMsgEdit.Value)
    if macroSel >= 1
        args["index"] := macroSel
    macros.save(args)
    MacroNew()
    RefreshMacros()
}
MacroDelete() {
    global macros, macroSel
    if macroSel >= 1 {
        macros.delete(Map("index", macroSel))
        MacroNew()
        RefreshMacros()
    }
}
MacroNew() {
    global macroSel := -1, macroPendingHK := "", macroPendingLabel := "", macroCapBtn, macroMsgEdit
    macroCapBtn.Text := "click to set"
    macroMsgEdit.Value := ""
}

; ============================================================================
;  Remap page
; ============================================================================
BuildRemapPage() {
    global
    remapListBox := mainGui.AddListBox("x40 y162 w680 h276 +Background" C.well " c" C.text, [])
    remapListBox.SetFont("s10", "Consolas")
    ApplyDark(remapListBox.Hwnd)
    yourBtn := MkButton("Set Your Key", 40, 448, 130, 28, C.chip, C.text, (*) => RemapSet("new"))
    gameBtn := MkButton("Set Game Key", 178, 448, 130, 28, C.chip, C.text, (*) => RemapSet("orig"))
    qcBtn := MkButton("Toggle QC", 316, 448, 110, 28, C.chip, C.text, (*) => RemapToggleQc())
    enSpells := mainGui.AddCheckbox("x40 y488 h22 +Background" C.panel " c" C.text, " Remap spells")
    enInv := mainGui.AddCheckbox("x220 y488 h22 +Background" C.panel " c" C.text, " Remap inventory")
    enMouse := mainGui.AddCheckbox("x420 y488 h22 +Background" C.panel " c" C.text, " Remap mouse")
    enSpells.OnEvent("Click", (c, *) => (remap.setEnable(Map("group", "spell", "value", c.Value))))
    enInv.OnEvent("Click", (c, *) => (remap.setEnable(Map("group", "inv", "value", c.Value))))
    enMouse.OnEvent("Click", (c, *) => (remap.setEnable(Map("group", "mouse", "value", c.Value))))
    AddToPage("remap", remapListBox, yourBtn, gameBtn, qcBtn, enSpells, enInv, enMouse)
}
RefreshRemap() {
    global remap, remapListBox, remapMap, enSpells, enInv, enMouse
    d := remap.get()
    enSpells.Value := d.enableSpells, enInv.Value := d.enableInv, enMouse.Value := d.enableMouse
    remapMap := []
    items := []
    for i, s in d.spells {
        remapMap.Push({ group: "spell", index: i })
        items.Push(Fmt("Spell " i, 10) Fmt(s.newLabel ? s.newLabel : "-", 8) "→ " Fmt(s.origLabel ? s.origLabel : "-", 8) (s.qc ? " ·QC" : ""))
    }
    for i, s in d.inv {
        remapMap.Push({ group: "inv", index: i })
        items.Push(Fmt("Item " i, 10) Fmt(s.newLabel ? s.newLabel : "-", 8) "→ " s.target)
    }
    for i, s in d.mouse {
        remapMap.Push({ group: "mouse", index: i })
        items.Push(Fmt(s.side, 10) Fmt(s.newLabel ? s.newLabel : "-", 8))
    }
    remapListBox.Delete()
    remapListBox.Add(items)
}
Fmt(s, n) {
    s := "" s
    while StrLen(s) < n
        s .= " "
    return s
}
RemapSelected() {
    global remapListBox, remapMap
    idx := remapListBox.Value
    return (idx && idx <= remapMap.Length) ? remapMap[idx] : 0
}
RemapSet(field) {
    global remap
    sel := RemapSelected()
    if !sel
        return
    if field = "orig" && sel.group != "spell"
        return
    r := remap.capture(Map("plain", field = "orig" ? 1 : 0))
    if r.key
        remap.setKey(Map("group", sel.group, "index", sel.index, "field", field, "key", r.key))
    RefreshRemap()
}
RemapToggleQc() {
    global remap
    sel := RemapSelected()
    if !sel || sel.group != "spell"
        return
    d := remap.get()
    cur := d.spells[sel.index].qc
    remap.setQc(Map("index", sel.index, "value", cur ? 0 : 1))
    RefreshRemap()
}

; ============================================================================
;  Host page
; ============================================================================
BuildHostPage() {
    global
    mk(id, label, x, y, w) {
        lbl := mainGui.AddText("x" x " y" y " w" w " h16 +Background" C.panel " c" C.muted, label)
        e := mainGui.AddEdit("x" x " y" (y + 20) " w" w " h26 +Background" C.well " c" C.text, "")
        UISetFont(e, "s10")
        hostEdits[id] := e
        AddToPage("host", lbl, e)
    }
    mk("botName", "Bot name", 40, 160, 300)
    mk("trigger", "Trigger", 360, 160, 160)
    mk("gameName", "Game name", 40, 220, 260)
    incBtn := MkButton("+1", 312, 240, 40, 26, C.chip, C.accent, (*) => HostInc())
    mk("exBefore", "Extra command before host", 40, 288, 680)
    mk("exAfter", "Extra command after host", 40, 348, 680)
    privBtn := MkButton("HOST PRIVATE LOBBY", 40, 420, 330, 36, C.accent, C.onAccent, (*) => DoHost(1))
    pubBtn := MkButton("HOST PUBLIC LOBBY", 390, 420, 330, 36, C.chip, C.accent, (*) => DoHost(0))
    AddToPage("host", incBtn, privBtn, pubBtn)
}
RefreshHost() {
    global host, hostEdits
    d := host.get()
    for id, e in hostEdits
        e.Value := d.fields.HasProp(id) ? d.fields.%id% : ""
}
HostInc() {
    global host, hostEdits
    r := host.increment(Map("gameName", hostEdits["gameName"].Value))
    hostEdits["gameName"].Value := r.gameName
}
DoHost(private) {
    global host, hostEdits
    args := Map("private", private)
    for id, e in hostEdits
        args[id] := e.Value
    host.host(args)
}

; ============================================================================
;  Settings page
; ============================================================================
BuildSettingsPage() {
    global
    labels := Map("enableToolOnStart", "Enable tool on start",
        "enableToolAfterLoad", "Enable tool after loading a save",
        "summonBagAfterLoad", "Summon bag (Esc) after loading",
        "hideOnStart", "Hide window on start",
        "autoToggleTool", "Auto-disable tool while chatting (Enter)")
    y := 160
    for key, text in labels {
        cb := mainGui.AddCheckbox("x40 y" y " h22 +Background" C.panel " c" C.text, " " text)
        cb.OnEvent("Click", SettingToggle.Bind(key))
        setChecks[key] := cb
        AddToPage("settings", cb)
        y += 30
    }
    convertCb := mainGui.AddCheckbox("x40 y" y " h22 +Background" C.panel " c" C.text, " Send -convert before loading (Reforged name fix)")
    convertCb.OnEvent("Click", (c, *) => loader.setConvert(Map("value", c.Value)))
    AddToPage("settings", convertCb)
    y += 30
    l1 := mainGui.AddText("x40 y" (y + 8) " w220 h20 +Background" C.panel " c" C.muted, "Delay between codes (ms)")
    loadDelayEdit := mainGui.AddEdit("x270 y" (y + 4) " w80 h24 Number +Background" C.well " c" C.text, "200")
    l2 := mainGui.AddText("x40 y" (y + 40) " w220 h20 +Background" C.panel " c" C.muted, "Delay after load (ms)")
    postDelayEdit := mainGui.AddEdit("x270 y" (y + 36) " w80 h24 Number +Background" C.well " c" C.text, "1000")
    loadDelayEdit.OnEvent("Change", (*) => settings.set(Map("key", "loadDelay", "value", loadDelayEdit.Value + 0)))
    postDelayEdit.OnEvent("Change", (*) => settings.set(Map("key", "postLoadDelay", "value", postDelayEdit.Value + 0)))
    folderLabel := mainGui.AddText("x40 y" (y + 82) " w460 h20 +Background" C.panel " c" C.muted, "TWRPG folder")
    l3 := folderLabel
    folderEdit := mainGui.AddEdit("x40 y" (y + 102) " w440 h24 ReadOnly +Background" C.well " c" C.text, "")
    setBtn := MkButton("Change", 490, y + 100, 72, 26, C.chip, C.text, (*) => (loader.setFolder(Map()), RefreshSettings()))
    openBtn := MkButton("Open", 568, y + 100, 60, 26, C.chip, C.text, (*) => loader.openFolder(Map()))
    autoBtn := MkButton("Auto-detect", 634, y + 100, 86, 26, C.chip, C.text, (*) => (loader.autoFolder(Map()), RefreshSettings()))
    resetBtn := MkButton("Reset all settings", 40, y + 142, 180, 30, C.chip, C.text, (*) => ResetAll())
    AddToPage("settings", l1, loadDelayEdit, l2, postDelayEdit, l3, folderEdit, setBtn, openBtn, autoBtn, resetBtn)
}
RefreshSettings() {
    global settings, setChecks, loadDelayEdit, postDelayEdit, folderEdit, folderLabel, convertCb, loader
    s := settings.get()
    for key, cb in setChecks
        cb.Value := s.HasProp(key) ? s.%key% : 0
    loadDelayEdit.Value := s.loadDelay
    postDelayEdit.Value := s.postLoadDelay
    cfg := loader.config(Map())
    convertCb.Value := cfg.convert
    folderEdit.Value := cfg.folder
    folderLabel.Text := "TWRPG folder  ·  " (!cfg.found ? "not found, pick it with Change" : cfg.auto ? "found automatically" : "chosen by you")
}
SettingToggle(key, ctrl, *) => settings.set(Map("key", key, "value", ctrl.Value))
ResetAll() {
    if Dialog("This clears every setting, macro, remap and favourite, then restarts the companion.", "Reset settings", ["Reset", "Cancel"]) = "Reset"
        settings.reset(Map())
}

; ============================================================================
;  Overlay page - the TWRPG site over the game (ui\OverlayPanel.ahk)
; ============================================================================
BuildOverlayPage() {
    global
    lbl(text, x, y, w) {
        t := mainGui.AddText("x" x " y" y " w" w " h20 0x200 +Background" C.panel " c" C.muted, text)
        AddToPage("overlay", t)
        return t
    }
    num(key, x, y) {
        e := mainGui.AddEdit("x" x " y" y " w60 h24 Number +Background" C.well " c" C.text, "")
        UISetFont(e, "s10")
        e.OnEvent("Change", (c, *) => (c.Value != "" && webOverlay.set(key, c.Value + 0)))
        AddToPage("overlay", e)
        return e
    }
    lbl("Show / hide", 40, 164, 150)
    ovHkBtn := MkButton("", 200, 160, 160, 28, C.chip, C.text, (*) => OverlayCapture("hotkey", ovHkBtn))
    lbl("Pin (click-through)", 380, 164, 150)
    ovPinBtn := MkButton("", 540, 160, 160, 28, C.chip, C.text, (*) => OverlayCapture("pinHotkey", ovPinBtn))
    AddToPage("overlay", ovHkBtn, ovPinBtn)

    lbl("Dock", 40, 208, 150)
    for i, side in ["right", "left", "full"] {
        b := MkButton(StrTitle(side), 200 + (i - 1) * 76, 204, 70, 28, C.chip, C.muted, OverlaySide.Bind(side))
        ovSideBtns[side] := b
        AddToPage("overlay", b)
    }
    lbl("Drag the panel's inner edge to resize.", 440, 208, 280)

    lbl("Opacity %", 40, 252, 150)
    ovOpacityEdit := num("opacity", 200, 250)
    lbl("Pinned opacity %", 380, 252, 150)
    ovPinOpacityEdit := num("pinOpacity", 540, 250)
    lbl("Unload after (min)", 40, 296, 150)
    ovUnloadEdit := num("unloadMinutes", 200, 294)
    lbl("Frees memory while hidden. 0 = keep loaded.", 270, 296, 440)

    labels := [["outsideGame", "Hotkeys also work outside Warcraft III"],
        ["checkOnStart", "Check for TWRPG data updates on start"],
        ["autoInstall", "Install updates automatically"]]
    y := 336
    for pair in labels {
        cb := mainGui.AddCheckbox("x40 y" y " h22 +Background" C.panel " c" C.text, " " pair[2])
        cb.OnEvent("Click", OverlayCheck.Bind(pair[1]))
        ovChecks[pair[1]] := cb
        AddToPage("overlay", cb)
        y += 30
    }
    ovVersionText := lbl("", 40, 434, 680)
    openBtn := MkButton("Open overlay", 40, 466, 150, 32, C.accent, C.onAccent, (*) => (HideMainWindow(), webOverlay.show()))
    updBtn := MkButton("Update data now", 200, 466, 170, 32, C.chip, C.accent, (*) => (webOverlay.runUpdate(true), RefreshOverlay()))
    AddToPage("overlay", openBtn, updBtn)
}
RefreshOverlay() {
    global ovHkBtn, ovPinBtn, ovSideBtns, ovOpacityEdit, ovPinOpacityEdit, ovUnloadEdit, ovChecks, ovVersionText, webOverlay, C, boxes
    s := webOverlay.get()
    ovHkBtn.Text := s.hotkey ? ReadableHotkey(s.hotkey) : "none"
    ovPinBtn.Text := s.pinHotkey ? ReadableHotkey(s.pinHotkey) : "none"
    for side, b in ovSideBtns {          ; selected one tinted, like the site's locale switcher
        bg := side = s.side ? C.navOn : C.chip
        b.Opt("+Background" bg " +c" (side = s.side ? C.accent : C.muted)), b.Redraw()
        boxes[b.Hwnd].Fill := bg
    }
    ovOpacityEdit.Value := s.opacity
    ovPinOpacityEdit.Value := s.pinOpacity
    ovUnloadEdit.Value := s.unloadMinutes
    for key, cb in ovChecks
        cb.Value := s.%key%
    ovVersionText.Text := s.version ? "Offline data: " s.version : "Offline data: not installed (Update data now)"
}
OverlayCapture(key, btn) {
    btn.Text := "press keys… (Esc = none)"
    combo := KeyWaitCombo()
    combo := RegExReplace(combo, "[<>]")     ; either Shift/Ctrl/Alt
    webOverlay.set(key, combo = "Escape" ? "" : combo)
    RefreshOverlay()
}
OverlaySide(side, *) {
    webOverlay.set("side", side)
    RefreshOverlay()
}
OverlayCheck(key, ctrl, *) => webOverlay.set(key, ctrl.Value)

; ============================================================================
;  Shared: tool toggle, overlay, show/hide, toast
; ============================================================================
ToggleTool() {
    global toolEnabled := !toolEnabled
    UpdateOverlay()
    UpdateToolPill()
    macros.refresh()
    remap.refresh()
}

UpdateToolPill() {
    global toolOn, toolOff, C
    if !IsSet(toolOn)
        return
    toolOn.Opt("+Background" (toolEnabled ? C.navOn : C.side) " +c" (toolEnabled ? C.accent : C.dim)), toolOn.Redraw()
    toolOff.Opt("+Background" (!toolEnabled ? C.navOn : C.side) " +c" (!toolEnabled ? C.accent : C.dim)), toolOff.Redraw()
}

ShowMainWindow() {
    global showMain := true
    ShowPage(currentPage)               ; before Show, so other pages' controls never flash
    mainGui.Show("w" W " h" H)
    try WinSetRegion("0-0 w" W " h" H " R14-14", mainGui.Hwnd)
}
HideMainWindow() {
    global showMain := false
    try mainGui.Hide()
}
ShowHideMain() {
    global showMain
    if showMain
        HideMainWindow()
    else
        ShowMainWindow()
}
PauseGame() => SendInput("{F10}{m}{F10}")

; ---- WC3 chat ---------------------------------------------------------------
; Loader commands are spotted by what was typed, not by tracking whether chat is
; open (that can drift: menus, alt-tab, the lobby's always-open chat box).
; chatHook records keys typed in WC3 since the last Enter / Esc / click. On
; Enter, if that is exactly a loader command (-l, -ll, -sn...), the chat box is
; emptied and closed with an empty Enter (no message, nothing in the lobby)
; and the command runs; otherwise Enter goes through untouched.
; `chatting` is only kept for the tool's auto-disable while typing.
ChatEnter(hk) {
    global chatting, chatHook, loader
    key := InStr(hk, "+") ? "+{Enter}" : InStr(hk, "Numpad") ? "{NumpadEnter}" : "{Enter}"
    line := chatHook.Input
    ChatRestart()
    if loader.isCommand(line) {
        SendInput("{End}{BS " (StrLen(line) + 16) "}{Enter}")
        ChatClosed()
        ; then forget what the command itself typed (-load codes, -save ...)
        SetTimer(() => (loader.command(line), ChatRestart()), -80)
        return
    }
    SendInput(key)
    if chatting
        ChatClosed()
    else
        ChatOpened()
}
; start a fresh line (only while WC3 is the active window: never record what
; you type in other apps)
ChatRestart() {
    global chatHook
    chatHook.Stop()
    if WinActive(WarcraftIII)
        chatHook.Start()
}
ChatWatch() {
    global chatHook
    if !WinActive(WarcraftIII) {
        if chatHook.InProgress
            chatHook.Stop()
    } else if !chatHook.InProgress {
        chatHook.Start()
    }
}
ChatOpened() {
    global chatting := true, toolEnabled, toolEnableHistory
    if Ini("Settings", "autoToggleTool", 1) {
        toolEnableHistory := toolEnabled, toolEnabled := false
        UpdateOverlay(), UpdateToolPill(), macros.refresh(), remap.refresh()
    }
}
ChatClosed() {
    global chatting, toolEnabled, toolEnableHistory
    if !chatting
        return
    chatting := false
    if Ini("Settings", "autoToggleTool", 1) {
        toolEnabled := toolEnableHistory
        UpdateOverlay(), UpdateToolPill(), macros.refresh(), remap.refresh()
    }
}
MsgEditFocused() {
    global msgEdit
    try return ControlGetFocus("ahk_id " mainGui.Hwnd) = msgEdit.Hwnd
    return false
}

; ---- themed toast + dialog (instead of ToolTip / MsgBox) ---------------------
; Toast mirrors the site's #toast: dark card, 1px accent border, bold accent
; text (square corners: window regions can't keep a 1px border on a curve). Over the game it sits top-centre; otherwise at the bottom of the
; window (or screen). ms = 0 keeps it up until the next Toast / HideToast().
Toast(msg, kind := "", ms := 3500) {
    global toastGui, toastText, C, UI_FONT, mainGui, W, H
    ; tw/th, not w/h: names are case-insensitive and W/H are the window size
    if !toastGui {
        toastGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000")    ; never takes focus
        toastGui.BackColor := C.accent                                         ; = the 1px border
        toastGui.MarginX := 0, toastGui.MarginY := 0
        toastText := toastGui.AddText("x1 y1 w10 h10 Center 0x200 +Background13151A c" C.accent, "")
        UISetFont(toastText, "s10 w700")
    }
    tw := TextWidth(toastText, msg) + 54, th := 40
    toastText.Move(1, 1, tw - 2, th - 2), toastText.Text := msg
    if WinActive(WarcraftIII) {
        WinGetClientPos(&ax, &ay, &aw, , WarcraftIII)
        tx := ax + (aw - tw) // 2, ty := ay + 80
    } else if IsSet(mainGui) && DllCall("IsWindowVisible", "ptr", mainGui.Hwnd) {
        WinGetPos(&ax, &ay, , , mainGui)
        tx := ax + (W - tw) // 2, ty := ay + H - th - 30
    } else {
        MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
        tx := l + (r - l - tw) // 2, ty := b - th - 30
    }
    toastGui.Show("NA x" tx " y" ty " w" tw " h" th)
    SetTimer(HideToast, ms > 0 ? -ms : 0)
}
HideToast() {
    global toastGui
    if toastGui
        toastGui.Hide()
}
; pixel width of s in ctl's font
TextWidth(ctl, s) {
    hdc := DllCall("GetDC", "ptr", ctl.Hwnd, "ptr")
    old := DllCall("SelectObject", "ptr", hdc, "ptr", SendMessage(0x31, 0, 0, ctl), "ptr")   ; WM_GETFONT
    DllCall("GetTextExtentPoint32W", "ptr", hdc, "str", s, "int", StrLen(s), "int64*", &size := 0)
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    DllCall("ReleaseDC", "ptr", ctl.Hwnd, "ptr", hdc)
    return size & 0xFFFFFFFF
}

; pixel height of s word-wrapped to width in ctl's font
TextHeight(ctl, s, width) {
    hdc := DllCall("GetDC", "ptr", ctl.Hwnd, "ptr")
    old := DllCall("SelectObject", "ptr", hdc, "ptr", SendMessage(0x31, 0, 0, ctl), "ptr")
    rc := Buffer(16, 0), NumPut("int", width, rc, 8)
    DllCall("DrawTextW", "ptr", hdc, "str", s, "int", -1, "ptr", rc, "uint", 0x410)   ; DT_CALCRECT | DT_WORDBREAK
    DllCall("SelectObject", "ptr", hdc, "ptr", old)
    DllCall("ReleaseDC", "ptr", ctl.Hwnd, "ptr", hdc)
    return NumGet(rc, 12, "int")
}

; Modal dialog in the site's .modal style (card, Cinzel title, muted text,
; .btn buttons; the first button is the primary one). Returns the label
; clicked, or the last button's label on Esc / close.
Dialog(text, title := "TW Companion", buttons := ["OK"]) {
    global C, UI_FONT, mainGui
    owned := IsSet(mainGui) && DllCall("IsWindowVisible", "ptr", mainGui.Hwnd)
    g := Gui("-Caption +ToolWindow +AlwaysOnTop" (owned ? " +Owner" mainGui.Hwnd : ""))
    g.BackColor := C.frame                           ; = the 1px border
    g.MarginX := 0, g.MarginY := 0
    w := 440, res := { v: buttons[buttons.Length] }
    card := g.AddText("x1 y1 w" (w - 2) " h10 +Background" C.card)
    t := g.AddText("x26 y22 w" (w - 52) " h28 +Background" C.card " c" C.text, title)
    t.SetFont("s13 w700", "Cinzel")
    body := g.AddText("x26 y58 w" (w - 52) " +Background" C.card " c" C.muted, text)
    UISetFont(body, "s10")
    bh := TextHeight(body, text, w - 52)
    body.Move(, , , bh)
    by := 58 + bh + 24, bx := w - 26
    loop buttons.Length {
        i := buttons.Length - A_Index + 1, label := buttons[i]
        primary := i = 1
        b := g.AddText("x" (bx - 104) " y" by " w104 h34 Center 0x200 +Background" (primary ? C.accent : C.chip)
            " c" (primary ? C.onAccent : C.text), label)
        UISetFont(b, "s9 w600")
        b.OnEvent("Click", ((l, *) => (res.v := l, g.Destroy())).Bind(label))
        Box.Round(b, 104, 34, 4)
        bx -= 112
    }
    h := by + 34 + 24
    card.Move(, , , h - 2)
    g.OnEvent("Escape", (*) => g.Destroy())
    g.OnEvent("Close", (*) => g.Destroy())
    if owned {
        WinGetPos(&ox, &oy, &ow, &oh, mainGui)
        pos := "x" (ox + (ow - w) // 2) " y" (oy + (oh - h) // 2)
    } else {
        pos := "Center"
    }
    g.Show(pos " w" w " h" h)
    WinWaitClose("ahk_id " g.Hwnd)
    return res.v
}
Push(event, data) {
    if event = "toast"
        Toast(data.msg, data.HasProp("kind") ? data.kind : "")
}

; dark-mode a control (best effort)
ApplyDark(hwnd) {
    try DllCall("uxtheme\SetWindowTheme", "ptr", hwnd, "str", "DarkMode_Explorer", "ptr", 0)
}

; ============================================================================
;  Overlay
; ============================================================================
BuildOverlay() {
    global overlay, overlayText, C
    overlay := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20", "twc-overlay")
    overlay.BackColor := C.win
    UISetFont(overlay, "s10 w600")
    overlayText := overlay.AddText("+BackgroundTrans w140 h22", "")
    WinSetTransparent(210, overlay)
    UpdateOverlay()
    if !Ini("Settings", "hideOverlay", 0)
        overlay.Show("x0 y0 NoActivate")
}
UpdateOverlay() {
    global overlayText, C
    if !IsSet(overlayText)
        return
    overlayText.Opt("+c" (toolEnabled ? C.accent : C.dim))
    overlayText.Text := toolEnabled ? "◆ TW ON" : "◇ TW OFF"
}

; ============================================================================
;  Control hotkeys
; ============================================================================
#HotIf WinActive("TW Companion")
$~Esc:: HideMainWindow()
#HotIf WinActive("TW Companion") && currentPage = "loader" && !MsgEditFocused()
Up:: SaveMove(-1)
Down:: SaveMove(1)
PgUp:: SaveMove(-SAVE_ROWS)
PgDn:: SaveMove(SAVE_ROWS)
Enter:: LoadSelected()
#HotIf

$*F8:: ShowHideMain()
$!Esc:: ExitApp

#HotIf WinActive(WarcraftIII)
$~F10:: ToggleTool()
$~Pause:: PauseGame()
$Enter::
$NumpadEnter::
$+Enter:: ChatEnter(ThisHotkey)
$~LButton::
$~Esc:: (ChatClosed(), ChatRestart())
#HotIf
