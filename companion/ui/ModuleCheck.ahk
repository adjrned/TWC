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
    ["Quickcast keys (as WFE)", "quickcast keys: key .* pressed slot|quickcast keys: on \(", "quickcast keys: (pressing a button faulted|the game window couldn.t be subclassed|slot \d+.s button .* isn.t a game button)"],
    ["Quickcast keys: the game's queue (timing)", "quickcast keys: the last 25 presses waited", ""],
    ["Quickcast on the game thread (target mode)", "quickcast: clicked as the game opened the target mode|quickcast: the target mode.s Enter is ours", "quickcast: vtable \+AAA220 entry|quickcast: the target mode.s vtable .* isn.t where|quickcast: the target mode hook faulted"],
    ["Cooldown and buff timers", "timers: game getter at .* checks out|timers in the game: drawing", "timers: refused|frames: refused|no more frames in this session"],
    ["Cooldowns on the card", "timers in the game: the first cooldown drawn", "cooldowns: the command card .* isn't readable"],
    ["Clear messages / chat", "clear (messages|chat): frame", "not a message frame|clear .* faulted"],
    ["Health bar size", "health bars: the game's own size is|health bars: pass resized", "health bars: refused|reads faulted"],
    ["Health bar colours", "health bar colours: on", "health bar colours: refused|colouring a bar faulted"],
    ["FPS unlock", "FPS: limiter patched", "FPS: refused|FPS: the game's option functions faulted|C9 already"],
    ["Multiboard", "multiboard: [0-9A-F]{8}, vtable", "multiboard: refused|not a multiboard|multiboard: the game's call faulted"],
    ["Allies' abilities", "allies' abilities: on|allies' abilities: the first ability shown", "allies' abilities: refused|allies' abilities: writing the hooks failed|allies' abilities: .* faulted"],
    ["Enemies' abilities (bosses)", "allies' abilities: the first enemy's ability shown|allies' abilities: on .*enemies' too", "allies' abilities: refused|allies' abilities: .* faulted"],
    ["Cooldown ping", "ping: .+\| (Cooldown|Ready|Not enough mana)", "ping: reading the button faulted"],
    ["Lobby latency", "latency: \d+ ms", "latency: refused|writing the patch failed|latency: a getter was changed"],
    ["Start countdown", "start countdown: [0-9.]+ s in games you host", "start countdown: refused|start countdown: writing it failed|start countdown: .* changed by someone else"],
    ["Health numbers", "health numbers: the first one", "frames: refused|no more frames in this session|health numbers / mana bars: refused"],
    ["Mana bars", "mana bars: the first one .* checks out", "mana bars: the new bar|mana bars: destroying one faulted|health numbers / mana bars: refused"],
    ["Portrait regen", "portrait: the first update wrapped", "portrait: refused|portrait: writing a line faulted|portrait: the update entry was changed|portrait: the call at .* was changed|portrait: writing the call at"],
    ["Storm.dll (for new frames)", "SMemAlloc \(401\) at .* check out", "Storm.dll isn't loaded in the game|ordinals 401 / 403 aren't"],
    ["Hide hover names", "unit names: on|unit names: the first name tip kept hidden", "unit names: refused|unit names: vtable .* left as it is"],
    ["Fast menu", "fast menu: the first transition sped up", "fast menu: refused|fast menu: writing the detour failed|fast menu: .* faulted|fast menu: .* changed by someone else"],
    ["Widescreen", "widescreen: on, the window is|widescreen: .* already hooked by", "widescreen: refused|isn't the game's call to its projection|widescreen: writing the call"],
    ["Detailed tooltips", "tooltips: the first .* tooltip got its lines", "tooltips: refused|tooltips: adding the lines faulted|tooltips: vtable .* left as it is"],
    ["Widescreen UI", "UI layout: \d+ frames laid out", "UI layout: .*stopping|UI layout: putting a (frame|model) back faulted|UI layout: the .* faulted: left out"],
    ["Portrait text", "portrait text: on", "portrait text: (no frames|making its frames failed|the portrait update isn't wrapped|giving the lines back faulted)"],
    ["Hide the UI", "hide UI: console .* textures|hide UI: .* RTTI", "hide UI: .* refused|hide UI: .* faulted|  not the (time of day|minimap|upper menu bar|resource bar|idle workers|buff bar)"],
    ["Your hero's buffs (alerts)", "hero buffs: your hero is", ""],
    ["Cooldown sweep", "cooldown sweep: the first one made", "cooldown sweep: .*(no sweeps|faulted)"],
    ["Battle.net login", "battle.net login: account '.*' typed in, Logon clicked", "battle.net login: .*(faulted|not a glue)"],
    ["Bigger buff bar", "buff bar size: x[0-9.]+ \(\d+ frames resized", "buff bar size: .*(refused|faulted)"],
    ["Damage meter feed", "damage: player \d+.s unit|damage: on \(", "damage: refused|damage: vtable \+[0-9A-F]+ entry"],
    ["Hide the UI, again (1.5 s pass)", "hide UI: the .* (hidden again|anchored again)", ""],
    ["Buff durations (probe)", "buff timers: '[^']+' .* appeared", "buff timers: (the map.s timer start .* isn.t|writing the timer probe failed)"],
    ["Damage meter hits (taken, sources)", "damage: unit type '....' is named|damage: '....' \(a unit type or an ability\) is named", ""],
    ["Damage meter spells (ability per hit)", "damage: a spell hit's ability: '....' \(the (spell event|source's last cooldown)", ""],
    ["Map text lines (the map's damage total, probe)", "map text: on \(|map text: '", "map text: the call at .* isn.t|map text: writing the call"],
    ["Damage meter names", "damage: player names .*'", "damage: reading the player names faulted|damage: player names \([^)]*\):(?!.*')"],
]

; this session's log lines (from the last "loaded" line), or [] if none
ModuleCheckLog() => ModuleCheckLines(ModuleCheckLogText()).now
; the module before it, when it was swapped live for this one: its lines from
; "unloading: a newer module replaces this one" on ([] if there was no swap)
ModuleCheckSwap() => ModuleCheckLines(ModuleCheckLogText()).before
ModuleCheckLogText() {
    path := A_ScriptDir "\native\twc-game.log"
    if !FileExist(path)
        return ""
    try return FileRead(path, "UTF-8")      ; the players' names are UTF-8 (the rest is ASCII)
    return ""
}
; -> { now, before } from the log's text. A second copy that stays idle ("loaded
; again ... stays idle") doesn't start a session: the live module's lines go on
ModuleCheckLines(text) {
    lines := StrSplit(StrReplace(text, "`r"), "`n")
    start := 0, prev := 0
    for i, l in lines
        if InStr(l, "---- twc-game.dll loaded") && !InStr(l, "---- twc-game.dll loaded again")
            prev := start, start := i
    now := [], before := []
    if !start
        return { now: now, before: before }
    loop lines.Length - start + 1
        if (l := lines[start + A_Index - 1]) != ""
            now.Push(l)
    ; the old module's unloading, just above this one's start (after its own start)
    i := start - 1, from := 0
    while i > prev && !from {
        if InStr(lines[i], "unloading: a newer module replaces this one")
            from := i
        i--
    }
    if from
        loop start - from
            if (l := lines[from + A_Index - 1]) != ""
                before.Push(l)
    return { now: now, before: before }
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
    if s.loaded && s.status != 2 {
        why := gameModule.qcWhyNot()
        rows.Push(why != "" ? { mark: "✗", name: "Quickcast now", detail: why }
            : !s.qc ? { mark: "·", name: "Quickcast now", detail: "ready (an older module: no counts)" }
            : { mark: s.qc.state = 1 ? "✓" : "·", name: "Quickcast now", detail: GameModuleEngine.QcStateText(s.qc.state) " · " s.qc.asked " asked: "
                . s.qc.clicked " clicked, " s.qc.noTarget " no target in time, " s.qc.notFront " not in front, " s.qc.cancelled " called off"
                . (s.qk ? " · keys as WFE: " (s.qk.state = 1 ? "on" : s.qk.state = 3 ? "refused" : "off") ", " s.qk.pressed " pressed, " s.qk.clicked " clicked" : "") })
    }
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
    if (swap := ModuleCheckSwap()).Length {
        r .= "`nThe module before (swapped live for this one), its unloading:`n"
        for l in swap
            r .= l "`n"
    }
    r .= "`nLog (this session, " log.Length " lines):`n"
    ; a long session: its start and its latest lines (quickcast's state and counts are the latest)
    for i, l in log
        if log.Length <= 400 || i <= 100 || i > log.Length - 300
            r .= l "`n"
        else if i = 101
            r .= "... (" (log.Length - 400) " lines left out here; all of them are in native\twc-game.log)`n"
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
    MakeScalable(g, "popup")
    g.MarginX := 0, g.MarginY := 0
    card := DialogCard(g, w)
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
    DialogStyle(g)
    WinGetPos(&ox, &oy, &ow, &oh, mainGui)
    g.Show("x" Round(ox + (ow - w * UiK(g)) / 2) " y" Round(Max(0, oy + (oh - h * UiK(g)) / 2)) " w" w " h" h)
    DialogRepaint(g)
}
