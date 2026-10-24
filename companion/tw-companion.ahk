#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================================
;  TW Companion - light native TWRPG loader for Warcraft III.
;  Borderless window on a baked glossy background; native controls on top.
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

; ---- palette ---------------------------------------------------------------
global C := {
    win:    "080B26",
    panel:  "131A46",
    well:   "0C1030",
    gold:   "ECD08A",
    goldbtn:"C9A24B",
    chip:   "1E2658",
    text:   "E6E8F5",
    muted:  "9AA0C8" }
global W := 760, H := 600

; ---- globals ---------------------------------------------------------------
global version := "1.0.0"
global toolEnabled := true, chatting := false, toolEnableHistory := true
global showMain := false
global loader, macros, remap, host, settings, updater, webOverlay
global mainGui, bgPic, titleText, toolPill
global pages := Map(), navText := Map(), currentPage := "loader"
global controlsToDrag := Map()

; loader controls
global searchEdit, fileListBox, convertCb, quickBtns := [], quickNames := []
global fileNames := []
; macros
global macroListBox, macroCapBtn, macroMsgEdit, macroPendingHK := "", macroPendingLabel := "", macroSel := -1
; remap
global remapListBox, remapMap := []
global enSpells, enInv, enMouse
; host
global hostEdits := Map()
; settings
global setChecks := Map(), loadDelayEdit, postDelayEdit, folderEdit
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

; ============================================================================
;  Window construction
; ============================================================================
BuildWindow() {
    global
    mainGui := Gui("-Caption +Border", "TW Companion")
    mainGui.BackColor := C.win
    mainGui.SetFont("s10", "Segoe UI")
    mainGui.OnEvent("Close", (*) => HideMainWindow())
    mainGui.OnEvent("Escape", (*) => HideMainWindow())

    bgPic := mainGui.AddPicture("x0 y0 w" W " h" H, A_ScriptDir "\assets\bg.png")

    ; nav
    navX := Map("loader", 40, "macros", 108, "remap", 180, "host", 246, "settings", 296, "overlay", 372)
    navW := Map("loader", 62, "macros", 66, "remap", 60, "host", 44, "settings", 70, "overlay", 66)
    for name, x in navX {
        t := mainGui.AddText("x" x " y98 w" navW[name] " h22 Center 0x200 +Background" C.panel, StrTitle(name))
        t.SetFont("s10 Bold", "Segoe UI")
        t.OnEvent("Click", NavClick.Bind(name))
        navText[name] := t
    }

    ; tool pill + close
    toolPill := MkButton("", 548, 96, 132, 26, C.chip, C.muted, (*) => ToggleTool())
    MkButton("✕", 712, 96, 26, 26, C.panel, C.muted, (*) => HideMainWindow())

    ; section title
    titleText := mainGui.AddText("x40 y128 w400 h26 +Background" C.panel, "")
    titleText.SetFont("s15", "Segoe UI Semibold")

    BuildLoaderPage()
    BuildMacrosPage()
    BuildRemapPage()
    BuildHostPage()
    BuildSettingsPage()
    BuildOverlayPage()

    OnMessage(0x201, WM_LBUTTONDOWN)
    UpdateToolPill()
}

; drag window by clicking the background
WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
    global bgPic, mainGui
    if (hwnd = bgPic.Hwnd)
        PostMessage(0xA1, 2, , , "ahk_id " mainGui.Hwnd)
}

StrTitle(s) => StrUpper(SubStr(s, 1, 1)) SubStr(s, 2)

; make a Text control that behaves like a flat button
MkButton(label, x, y, w, h, bg, fg, handler) {
    global mainGui
    b := mainGui.AddText("x" x " y" y " w" w " h" h " Center 0x200 +Background" bg " c" fg, label)
    b.SetFont("s10", "Segoe UI Semibold")
    b.OnEvent("Click", handler)
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
    global pages, navText, titleText, currentPage, C
    currentPage := name
    for pg, arr in pages
        for c in arr
            c.Visible := (pg = name)
    titleText.Text := SectionTitle(name)
    for nm, t in navText
        t.Opt("+c" (nm = name ? C.gold : C.muted))
    switch name {
        case "loader":   RefreshFiles(), RefreshQuick()
        case "macros":   RefreshMacros()
        case "remap":    RefreshRemap()
        case "host":     RefreshHost()
        case "settings": RefreshSettings()
        case "overlay":  RefreshOverlay()
    }
}

SectionTitle(name) {
    m := Map("loader","Loader","macros","Macros","remap","Remap","host","Host","settings","Settings","overlay","TWRPG Overlay")
    return m[name]
}

; ============================================================================
;  Loader page
; ============================================================================
BuildLoaderPage() {
    global
    searchEdit := mainGui.AddEdit("x40 y162 w680 h28 +Background" C.well " c" C.text, "")
    searchEdit.SetFont("s10", "Segoe UI")
    searchEdit.OnEvent("Change", (*) => RefreshFiles())
    AddToPage("loader", searchEdit)

    ; quick-load chips (up to 8)
    quickBtns := []
    loop 8 {
        i := A_Index
        x := 40 + Mod(i - 1, 8) * 86
        b := MkButton("", x, 200, 80, 32, C.chip, C.gold, QuickClick.Bind(i))
        b.Visible := false
        quickBtns.Push(b)
        AddToPage("loader", b)
    }

    fileListBox := mainGui.AddListBox("x40 y244 w680 h250 +Background" C.well " c" C.text, [])
    fileListBox.SetFont("s10", "Segoe UI")
    fileListBox.OnEvent("DoubleClick", (*) => LoadSelected())
    ApplyDark(fileListBox.Hwnd)
    AddToPage("loader", fileListBox)

    convertCb := mainGui.AddCheckbox("x40 y508 h24 +Background" C.panel " c" C.text, " Use -convert (Reforged name fix)")
    convertCb.Value := Integer(Ini("Loader", "convert", 1))
    convertCb.OnEvent("Click", (c, *) => loader.setConvert(Map("value", c.Value)))
    AddToPage("loader", convertCb)

    pinBtn := MkButton("Pin",  360, 506, 56, 28, C.chip, C.text, (*) => PinSelected())
    hideBtn := MkButton("Hide", 422, 506, 60, 28, C.chip, C.text, (*) => HideSelected())
    msgBtn := MkButton("Msg",  488, 506, 56, 28, C.chip, C.text, (*) => MsgSelected())
    loadBtn := MkButton("LOAD", 600, 504, 120, 32, C.goldbtn, "1A1508", (*) => LoadSelected())
    AddToPage("loader", pinBtn, hideBtn, msgBtn, loadBtn)
}

RefreshFiles() {
    global fileListBox, fileNames, searchEdit, loader
    files := loader.files(Map("filter", searchEdit.Value, "showHidden", 1))
    fileNames := []
    items := []
    for f in files {
        fileNames.Push(f.name)
        tag := (f.hidden ? "  [hidden]" : "") (f.msg ? "  [msg]" : "")
        items.Push(StrReplace(f.name, ".txt", "") "        " f.date tag)
    }
    fileListBox.Delete()
    if items.Length
        fileListBox.Add(items)
}

RefreshQuick() {
    global quickBtns, quickNames, loader
    quickNames := loader.pinned()
    for i, b in quickBtns {
        if i <= quickNames.Length {
            b.Text := StrReplace(quickNames[i], ".txt", "")
            b.Visible := true
        } else {
            b.Visible := false
        }
    }
}

SelectedFileName() {
    global fileListBox, fileNames
    idx := fileListBox.Value
    return (idx && idx <= fileNames.Length) ? fileNames[idx] : ""
}

LoadSelected() {
    n := SelectedFileName()
    if n
        loader.load(Map("name", n))
    else
        Toast("Select a save first", "error")
}
QuickClick(i, *) {
    global quickNames, loader
    if i <= quickNames.Length
        loader.load(Map("name", quickNames[i]))
}
PinSelected() {
    n := SelectedFileName()
    if n {
        loader.pinToggle(Map("name", n))
        RefreshQuick()
    }
}
HideSelected() {
    n := SelectedFileName()
    if n {
        loader.hideToggle(Map("name", n))
        RefreshFiles()
    }
}
MsgSelected() {
    n := SelectedFileName()
    if !n
        return
    ib := InputBox("Message shown in chat when this save loads:", "Loading Message", "w360 h130")
    if ib.Result != "Cancel" {
        loader.setMessage(Map("name", n, "msg", ib.Value))
        RefreshFiles()
    }
}

; ============================================================================
;  Macros page
; ============================================================================
BuildMacrosPage() {
    global
    macroListBox := mainGui.AddListBox("x40 y162 w680 h214 +Background" C.well " c" C.text, [])
    macroListBox.SetFont("s10", "Segoe UI")
    macroListBox.OnEvent("DoubleClick", (*) => MacroEditSelected())
    ApplyDark(macroListBox.Hwnd)
    lbl := mainGui.AddText("x40 y384 w150 h18 +Background" C.panel " c" C.muted, "Hotkey")
    lbl2 := mainGui.AddText("x200 y384 w300 h18 +Background" C.panel " c" C.muted, "Message (line per row)")
    macroCapBtn := MkButton("click to set", 40, 404, 150, 28, C.chip, C.text, (*) => MacroCapture())
    macroMsgEdit := mainGui.AddEdit("x200 y404 w520 h52 Multi +Background" C.well " c" C.text, "")
    macroMsgEdit.SetFont("s10", "Segoe UI")
    addBtn := MkButton("Add / Update", 40, 470, 140, 30, C.goldbtn, "1A1508", (*) => MacroSave())
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
        e.SetFont("s10", "Segoe UI")
        hostEdits[id] := e
        AddToPage("host", lbl, e)
    }
    mk("botName", "Bot name", 40, 160, 300)
    mk("trigger", "Trigger", 360, 160, 160)
    mk("gameName", "Game name", 40, 220, 260)
    incBtn := MkButton("+1", 312, 240, 40, 26, C.chip, C.gold, (*) => HostInc())
    mk("exBefore", "Extra command before host", 40, 288, 680)
    mk("exAfter", "Extra command after host", 40, 348, 680)
    privBtn := MkButton("HOST PRIVATE LOBBY", 40, 420, 330, 36, C.goldbtn, "1A1508", (*) => DoHost(1))
    pubBtn := MkButton("HOST PUBLIC LOBBY", 390, 420, 330, 36, C.chip, C.gold, (*) => DoHost(0))
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
    l1 := mainGui.AddText("x40 y" (y + 8) " w220 h20 +Background" C.panel " c" C.muted, "Delay between codes (ms)")
    loadDelayEdit := mainGui.AddEdit("x270 y" (y + 4) " w80 h24 Number +Background" C.well " c" C.text, "200")
    l2 := mainGui.AddText("x40 y" (y + 40) " w220 h20 +Background" C.panel " c" C.muted, "Delay after load (ms)")
    postDelayEdit := mainGui.AddEdit("x270 y" (y + 36) " w80 h24 Number +Background" C.well " c" C.text, "1000")
    loadDelayEdit.OnEvent("Change", (*) => settings.set(Map("key", "loadDelay", "value", loadDelayEdit.Value + 0)))
    postDelayEdit.OnEvent("Change", (*) => settings.set(Map("key", "postLoadDelay", "value", postDelayEdit.Value + 0)))
    l3 := mainGui.AddText("x40 y" (y + 82) " w120 h20 +Background" C.panel " c" C.muted, "TWRPG folder")
    folderEdit := mainGui.AddEdit("x40 y" (y + 102) " w520 h24 ReadOnly +Background" C.well " c" C.text, "")
    setBtn := MkButton("Set", 570, y + 100, 60, 26, C.chip, C.text, (*) => (loader.setFolder(Map()), RefreshSettings()))
    openBtn := MkButton("Open", 636, y + 100, 60, 26, C.chip, C.text, (*) => loader.openFolder(Map()))
    resetBtn := MkButton("Reset all settings", 40, y + 142, 180, 30, C.chip, C.text, (*) => ResetAll())
    AddToPage("settings", l1, loadDelayEdit, l2, postDelayEdit, l3, folderEdit, setBtn, openBtn, resetBtn)
}
RefreshSettings() {
    global settings, setChecks, loadDelayEdit, postDelayEdit, folderEdit, loader
    s := settings.get()
    for key, cb in setChecks
        cb.Value := s.HasProp(key) ? s.%key% : 0
    loadDelayEdit.Value := s.loadDelay
    postDelayEdit.Value := s.postLoadDelay
    folderEdit.Value := loader.config(Map()).folder
}
SettingToggle(key, ctrl, *) => settings.set(Map("key", key, "value", ctrl.Value))
ResetAll() {
    if MsgBox("Reset all settings and restart?", "Reset", "YesNo") = "Yes"
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
        e.SetFont("s10", "Segoe UI")
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
    openBtn := MkButton("Open overlay", 40, 466, 150, 32, C.goldbtn, "1A1508", (*) => (HideMainWindow(), webOverlay.show()))
    updBtn := MkButton("Update data now", 200, 466, 170, 32, C.chip, C.gold, (*) => (webOverlay.runUpdate(true), RefreshOverlay()))
    AddToPage("overlay", openBtn, updBtn)
}
RefreshOverlay() {
    global ovHkBtn, ovPinBtn, ovSideBtns, ovOpacityEdit, ovPinOpacityEdit, ovUnloadEdit, ovChecks, ovVersionText, webOverlay, C
    s := webOverlay.get()
    ovHkBtn.Text := s.hotkey ? ReadableHotkey(s.hotkey) : "none"
    ovPinBtn.Text := s.pinHotkey ? ReadableHotkey(s.pinHotkey) : "none"
    for side, b in ovSideBtns
        b.Opt("+c" (side = s.side ? C.gold : C.muted)), b.Redraw()
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
    global toolPill, C
    if !IsSet(toolPill)
        return
    toolPill.Text := toolEnabled ? "● TOOL ON" : "○ TOOL OFF"
    toolPill.Opt("+c" (toolEnabled ? C.gold : C.muted))
}

ShowMainWindow() {
    global showMain := true
    mainGui.Show("w" W " h" H)
    try WinSetRegion("0-0 w" W " h" H " R18-18", mainGui.Hwnd)
    ShowPage(currentPage)
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

Toast(msg, kind := "") {
    ToolTip(msg)
    SetTimer(() => ToolTip(), -3500)
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
    overlay.SetFont("s10 bold", "Segoe UI")
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
    overlayText.Opt("+c" (toolEnabled ? C.gold : "66708F"))
    overlayText.Text := toolEnabled ? "◆ TW ON" : "◇ TW OFF"
}

; ============================================================================
;  Control hotkeys
; ============================================================================
#HotIf WinActive("TW Companion")
$~Esc:: HideMainWindow()
#HotIf

$*F8:: ShowHideMain()
$!Esc:: ExitApp

#HotIf WinActive(WarcraftIII)
$~F10:: ToggleTool()
$~Pause:: PauseGame()
$~+Enter::
$~NumpadEnter::
$~Enter::
{
    global chatting, toolEnabled, toolEnableHistory
    if !Ini("Settings", "autoToggleTool", 1)
        return
    if !chatting {
        chatting := true, toolEnableHistory := toolEnabled, toolEnabled := false
    } else {
        chatting := false, toolEnabled := toolEnableHistory
    }
    UpdateOverlay(), UpdateToolPill(), macros.refresh(), remap.refresh()
}
$~LButton::
$~Esc::
{
    global chatting, toolEnabled, toolEnableHistory
    if chatting {
        chatting := false, toolEnabled := toolEnableHistory
        UpdateOverlay(), UpdateToolPill(), macros.refresh(), remap.refresh()
    }
}
#HotIf
