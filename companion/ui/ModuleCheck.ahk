#Requires AutoHotkey v2.0
; ============================================================================
;  Module check - what the 1.28f game module has seen of each feature in the
;  running (or last) game, from this session's twc-game.log and the module's
;  live state: ✓ worked, ✗ refused or faulted (the log says why), · not seen
;  yet (off, or not tried in this game). "Copy report" puts all of it and the
;  session's log on the clipboard, to paste when something needs a look.
;  Opened from the WC3 page's game module row (Check).
; ============================================================================

; [name, ok pattern, refused pattern] per feature, matched against log lines
ModuleCheckFeatures() => [
    ["Quickcast through the game", "quickcast: clicked", ""],
    ["Cooldown and buff timers", "timers: game getter at .* checks out", "timers: refused"],
    ["Clear messages / chat", "clear (messages|chat): frame", "not a message frame|clear .* faulted"],
    ["Health bar size", "health bars: pass resized", "health bars: refused|reads faulted"],
    ["Health bar colours", "health bar colours: on", "health bar colours: refused|colouring a bar faulted"],
    ["Widescreen", "widescreen: on, the window is", "widescreen: refused|isn't the game's call to its projection|widescreen: writing the call"],
    ["FPS unlock", "FPS: limiter patched", "FPS: refused|FPS: the game's option functions faulted|C9 already"],
    ["Multiboard", "multiboard: [0-9A-F]{8}, vtable", "multiboard: refused|not a multiboard|multiboard: the game's call faulted"],
    ["Self-cast", "self-cast: clicked the portrait", "self-cast: refused|not the portrait|self-cast: the game's click faulted"],
    ["Autocast toggle", "autocast: button", "autocast: refused|not a command button|autocast: the game's click faulted"],
    ["Lobby latency", "latency: \d+ ms", "latency: refused|writing the patch failed|latency: a getter was changed"],
    ["Timers in the game", "timers in the game: drawing", "frames: refused|no more frames in this session"],
    ["Health numbers", "health numbers: the first one", "frames: refused|no more frames in this session|health numbers / mana bars: refused"],
    ["Mana bars", "mana bars: the first one .* checks out", "mana bars: the new bar|mana bars: destroying one faulted|health numbers / mana bars: refused"],
    ["Portrait regen", "portrait: the first update wrapped", "portrait: refused|portrait: writing a line faulted|portrait: the update entry was changed|portrait: the call at .* was changed|portrait: writing the call at"],
    ["Storm.dll (for new frames)", "SMemAlloc \(401\) at .* check out", "Storm.dll isn't loaded in the game|ordinals 401 / 403 aren't"],
    ["Hide the UI", "hide UI: console .* textures|hide UI: .* RTTI", "hide UI: .* refused|hide UI: .* faulted|  not the (time of day|minimap|upper menu bar|resource bar|idle workers)"],
]

; this session's log lines (from the last "loaded" line), or [] if none
ModuleCheckLog() {
    path := A_ScriptDir "\native\twc-game.log"
    if !FileExist(path)
        return []
    try text := FileRead(path)
    catch
        return []
    lines := StrSplit(StrReplace(text, "`r"), "`n")
    start := 1
    for i, l in lines
        if InStr(l, "---- twc-game.dll loaded")
            start := i
    out := []
    loop lines.Length - start + 1
        if (l := lines[start + A_Index - 1]) != ""
            out.Push(l)
    return out
}

; -> [{ mark, name, detail }] for the probe, the game UI and each feature
ModuleCheckRows(log) {
    global gameModule
    s := gameModule.state(), rows := []
    find(re) {
        for l in log
            if re != "" && RegExMatch(l, re)
                return SubStr(l, 26)            ; without the time stamp
        return ""
    }
    rows.Push(!s.loaded ? { mark: "·", name: "Module", detail: !gameModule.enabled ? "off (top of the WC3 page)" : "not in a game yet: start a 1.28f game" }
        : s.status = 2 ? { mark: "✗", name: "Module", detail: "the game isn't 1.28f (build " s.build "): idle" }
        : { mark: "✓", name: "Module", detail: "loaded, layout " s.layout (s.live ? ", running" : ", not responding") })
    if s.loaded && s.status != 2
        rows.Push(s.probe = 1 ? { mark: "✓", name: "Address check", detail: "passed" }
            : s.probe = 2 ? { mark: "✗", name: "Address check", detail: s.probeText }
            : { mark: "·", name: "Address check", detail: "not run yet" })
    ui := find("game UI at .*vtable checks out")
    rows.Push(ui != "" ? { mark: "✓", name: "Game UI", detail: ui } : { mark: "·", name: "Game UI", detail: "not seen yet: start a game (not just the lobby)" })
    for f in ModuleCheckFeatures() {
        bad := find(f[3]), ok := find(f[2])
        rows.Push(bad != "" ? { mark: "✗", name: f[1], detail: bad }
            : ok != "" ? { mark: "✓", name: f[1], detail: ok }
            : { mark: "·", name: f[1], detail: "not seen yet (off, or not tried in this game)" })
    }
    tips := []
    for l in log
        if InStr(l, "tooltips: ")
            tips.Push(Trim(SubStr(l, 26)))
    rows.Push({ mark: "·", name: "Tooltips (probe)", detail: tips.Length ? Join(" | ", tips*) : "not logged yet" })
    return rows
}

ModuleCheckReport(rows, log) {
    global version, gameModule
    s := gameModule.state()
    r := "TW Companion " version " · module layout " s.layout " · game build " s.build " · " FormatTime(, "yyyy-MM-dd HH:mm") "`n`n"
    for row in rows
        r .= row.mark " " row.name ": " row.detail "`n"
    r .= "`nLog (this session, " log.Length " lines):`n"
    n := 0
    for l in log
        if ++n <= 400
            r .= l "`n"
    if log.Length > 400
        r .= "... (" (log.Length - 400) " more lines in native\twc-game.log)`n"
    return r
}

ModuleCheckDialog() {
    global C, mainGui, UI_FONT
    static g := 0
    if g
        try g.Destroy()
    log := ModuleCheckLog(), rows := ModuleCheckRows(log)
    w := 640, x := 26, tw := w - 52
    g := Gui("-Caption +ToolWindow +AlwaysOnTop +Owner" mainGui.Hwnd)
    g.BackColor := C.frame                           ; = the 1px border
    g.MarginX := 0, g.MarginY := 0
    card := g.AddText("x1 y1 w" (w - 2) " h10 +Background" C.card)
    t := g.AddText("x" x " y22 w" tw " h28 +Background" C.card " c" C.text, "Module check")
    t.SetFont("s13 w700 q4", "Cinzel")
    intro := "What the game module saw in this game: ✓ worked, ✗ refused (it says why), · not seen yet. Try each feature once, then Copy report."
    it := g.AddText("x" x " y56 w" tw " +Background" C.card " c" C.dim, intro)
    UISetFont(it, "s9")
    y := 56 + TextHeight(it, intro, tw) + 14
    it.Move(, , , y - 70)
    for row in rows {
        m := g.AddText("x" x " y" y " w18 h20 +Background" C.card " c" (row.mark = "✓" ? C.accent : row.mark = "✗" ? "E5534B" : C.dim), row.mark)
        UISetFont(m, "s10 w700")
        n := g.AddText("x" (x + 22) " y" (y + 1) " w170 h20 +Background" C.card " c" C.text, row.name)
        UISetFont(n, "s9 w600")
        d := g.AddText("x" (x + 196) " y" (y + 2) " w" (tw - 196) " h18 +Background" C.card " c" C.muted, row.detail)
        UISetFont(d, "s8")
        y += 24
    }
    y += 16
    copy := g.AddText("x" (w - x - 104 - 8 - 150) " y" y " w150 h34 Center 0x200 +Background" C.accent " c" C.onAccent, "Copy report")
    close := g.AddText("x" (w - x - 104) " y" y " w104 h34 Center 0x200 +Background" C.chip " c" C.text, "Close")
    for b in [copy, close]
        UISetFont(b, "s9 w600"), b.GetPos(, , &bw, &bh), Box.Round(b, bw, bh, 4)
    copy.OnEvent("Click", (*) => (A_Clipboard := ModuleCheckReport(rows, log), Toast("Report copied: paste it in your message", "", 2500)))
    close.OnEvent("Click", (*) => g.Destroy())
    h := y + 34 + 24
    card.Move(, , , h - 2)
    g.OnEvent("Escape", (*) => g.Destroy())
    WinGetPos(&ox, &oy, &ow, &oh, mainGui)
    g.Show("x" Round(ox + (ow - w * DPI_K) / 2) " y" Round(Max(0, oy + (oh - h * DPI_K) / 2)) " w" w " h" h)
}
