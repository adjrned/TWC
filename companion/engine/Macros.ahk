#Requires AutoHotkey v2.0
; ============================================================================
;  MacrosEngine - configurable hotkey macros, of two kinds:
;    chat  types chat lines in Warcraft III (one per row of its text)
;    keys  presses game keys in a row, e.g. items 1-5 at once (its text is the
;          keys, space separated: "Numpad7 Numpad8 q ^1"); also clicks and delays:
;          "click:0.5120,0.7330" / "rclick:..." a left / right click at that spot of
;          the Warcraft III window (its client area, as fractions: the window may
;          move or change size), "sclick:1024,768" / "srclick:..." at a screen
;          position, "wait:250" a delay in ms (instead of the usual gap); and from
;          where the mouse was when the macro started: "move@-28,27" moves it there,
;          "click@-85,80" / "rclick@..." clicks there (and leaves it there). Mouse
;          steps have no gap before them; a macro with these steps runs in SendEvent
;          mode as a critical thread (the companion's timers can't stretch its waits),
;          and your own right click stops it (the button's physical state: its own
;          clicks don't)
; ============================================================================
class MacrosEngine {
    section := "Macros"
    macros := []             ; [{hotkey, text, kind}]
    registered := Map()
    sendFn := SendInput             ; how keys are sent, clickFn(right, x, y) how clicks are (0: Click); win the game
    clickFn := 0                    ;   window clicks are relative to (checks swap them: never real input)
    win := WarcraftIII
    mouseFn := 0                    ; mouseFn(kind, x, y) how mouse-relative steps are done (0: MouseMove / Click)
    running := false, cancelled := false, rbDown := false, at := [0, 0]

    __New() {
        this.reload()
    }

    ; -- RPC endpoints -------------------------------------------------------
    list(args := 0) {
        out := []
        for m in this.macros
            out.Push({
                hotkey: m.hotkey,
                label: ReadableHotkey(m.hotkey),
                text: m.text,
                kind: m.kind,
                summary: MacrosEngine.Summary(m)
            })
        return out
    }

    capture(args := 0) {
        combo := KeyWaitCombo()
        if combo == "Escape" || combo = ""                  ; "": cancelled (the key stays as it was)
            return { hotkey: "", label: "" }
        hk := "$" combo
        return { hotkey: hk, label: ReadableHotkey(hk) }
    }

    save(args) {
        index := args.Has("index") ? Integer(args["index"]) : -1
        entry := { hotkey: args["hotkey"], text: args["text"], kind: args.Has("kind") ? args["kind"] : "chat" }
        if index >= 1 && index <= this.macros.Length
            this.macros[index] := entry
        else
            this.macros.Push(entry)
        this.persist()
        this.reload()
        return { ok: 1 }
    }

    ; drag to reorder: the macro at from ends up at to
    move(args) {
        from := Integer(args["from"]), to := Integer(args["to"])
        if from < 1 || from > this.macros.Length || to < 1 || to > this.macros.Length || from = to
            return { ok: 0 }
        m := this.macros.RemoveAt(from)
        this.macros.InsertAt(to, m)
        this.persist()
        this.reload()
        return { ok: 1 }
    }

    delete(args) {
        index := Integer(args["index"])
        if index >= 1 && index <= this.macros.Length
            this.macros.RemoveAt(index)
        this.persist()
        this.reload()
        return { ok: 1 }
    }

    ; -- keys macros -----------------------------------------------------------
    static Keys(text) {
        out := []
        for t in StrSplit(Trim(text), " ")
            if t != ""
                out.Push(t)
        return out
    }
    ; a click step -> true, with right (0 / 1), x, y and screen (0: fractions of the game window, 1: screen pixels)
    static ClickStep(t, &right := 0, &x := 0, &y := 0, &screen := 0) {
        if !RegExMatch(t, "i)^(s?)(r?)click:(-?[\d.]+),(-?[\d.]+)$", &m)
            return false
        screen := m[1] != "", right := m[2] != "", x := m[3] + 0, y := m[4] + 0
        return true
    }
    ; a step from where the mouse was when the macro started -> true, with kind ("move" | "click" | "rclick") and the offset
    static RelStep(t, &kind := "", &dx := 0, &dy := 0) {
        if !RegExMatch(t, "i)^(move|click|rclick)@(-?\d+),(-?\d+)$", &m)
            return false
        kind := StrLower(m[1]), dx := Integer(m[2]), dy := Integer(m[3])
        return true
    }
    static HasRelative(keys) {
        for t in keys
            if MacrosEngine.RelStep(t)
                return true
        return false
    }
    ; a step the editor takes: a key (with ^ ! + # in front), a click, a mouse step or a delay
    static ValidStep(t) {
        if MacrosEngine.ClickStep(t) || MacrosEngine.RelStep(t) || MacrosEngine.WaitStep(t) >= 0
            return true
        return RegExMatch(t, "^[\^!+#]*(.+)$", &m) && GetKeyVK(m[1]) != 0
    }
    ; a delay step -> its ms (at most a minute), else -1
    static WaitStep(t) => RegExMatch(t, "i)^wait:(\d+)$", &m) ? Min(60000, Integer(m[1])) : -1
    ; a sequence with clicks or delays (not only keys)
    static HasSteps(keys) {
        for t in keys
            if MacrosEngine.ClickStep(t) || MacrosEngine.RelStep(t) || MacrosEngine.WaitStep(t) >= 0
                return true
        return false
    }
    ; "Numpad7" -> "Item 1", "q" -> "Skill Q", "^1" -> "Ctrl+1", "Click 51%, 73%", "Wait 250 ms"
    static KeyLabel(t) {
        if (ms := MacrosEngine.WaitStep(t)) >= 0
            return "Wait " ms " ms"
        if MacrosEngine.RelStep(t, &kind, &dx, &dy)
            return (kind = "move" ? "Move" : kind = "rclick" ? "Right-click" : "Click") " mouse " dx ", " dy
        if MacrosEngine.ClickStep(t, &right, &x, &y, &screen)
            return (right ? "Right-click " : "Click ") (screen ? Round(x) ", " Round(y) : Round(x * 100) "%, " Round(y * 100) "%")
        for i, k in RemapEngine.INV_TARGETS
            if t = k
                return "Item " i
        for c in RemapEngine.CARD
            if t = c.game
                return c.name
        return ReadableHotkey(t)
    }
    ; one line for lists and messages: the first chat line, or the keys
    static Summary(m) {
        if m.kind = "keys" {
            labels := []
            for t in MacrosEngine.Keys(m.text)
                labels.Push(MacrosEngine.KeyLabel(t))
            return Join(" " Chr(0xB7) " ", labels*)
        }
        for l in StrSplit(StrReplace(m.text, "`r"), "`n")
            if Trim(l) != ""
                return l
        return ""
    }
    ; a key as SendInput text: modifiers, then "{q}" (never "{Q}", which is Shift+q)
    static KeyInput(t) {
        RegExMatch(t, "^([\^!+#]*)(.+)$", &m)
        return m[1] "{" (StrLen(m[2]) = 1 ? StrLower(m[2]) : m[2]) "}"
    }

    ; -- persistence ---------------------------------------------------------
    encode(text) => StrReplace(StrReplace(text, "`r`n", "`n"), "`n", "\n")
    decode(text) => StrReplace(text, "\n", "`n")

    persist() {
        gap := Ini(this.section, "keyGap", "")
        IniDelete(iniFile, this.section)
        if gap != ""
            SetIni(gap, this.section, "keyGap")
        SetIni(this.macros.Length, this.section, "count")
        for i, m in this.macros {
            SetIni(m.hotkey, this.section, "hk" i)
            SetIni(this.encode(m.text), this.section, "tx" i)
            if m.kind != "chat"
                SetIni(m.kind, this.section, "kd" i)
        }
    }

    reload() {
        this.macros := []
        count := Integer(Ini(this.section, "count", -1))
        if count == -1 {
            this.seedDefaults()
            count := Integer(Ini(this.section, "count", 0))
        }
        loop count {
            hk := Ini(this.section, "hk" A_Index, "")
            tx := this.decode(Ini(this.section, "tx" A_Index, ""))
            kd := Ini(this.section, "kd" A_Index, "chat")
            if tx                       ; a macro whose key was cleared stays, off
                this.macros.Push({ hotkey: hk, text: tx, kind: kd })
        }
        this.registerAll()
    }

    seedDefaults() {
        defaults := [
            { hotkey: "$F5", text: "-recall" },
            { hotkey: "$F6", text: "-rf" },
            { hotkey: "$F7", text: "-chest play MA and you will forever be goated but be hated by people because u outdps them by right clicking" }
        ]
        SetIni(defaults.Length, this.section, "count")
        for i, d in defaults {
            SetIni(d.hotkey, this.section, "hk" i)
            SetIni(this.encode(d.text), this.section, "tx" i)
        }
    }

    ; -- hotkey registration -------------------------------------------------
    registerAll() {
        for _, reg in this.registered {
            reg.enable := false
            reg.refresh()
        }
        this.registered := Map()
        for m in this.macros {
            if !m.hotkey
                continue
            fn := m.kind = "keys" ? this.sendKeys.Bind(this, MacrosEngine.Keys(m.text))
                : this.sendLines.Bind(this, StrSplit(StrReplace(m.text, "`r", ""), "`n"))
            this.registered.Set(m.hotkey, RegisterHotkey(m.hotkey, fn, WarcraftIII, true))
        }
    }

    sendLines(lines) {
        for line in lines
            if line != ""
                wc3Chat(line)
    }

    ; the keys one after another, a few ms apart so the game sees each one
    ; (keyGap in [Macros], default 15). Sent keys never trigger the companion's
    ; own hotkeys, so these are game keys. A delay step waits its own time
    ; instead of the gap; a click step clicks there and puts the mouse back.
    sendKeys(keys) {
        gap := Integer(Ini(this.section, "keyGap", 15)), waited := true
        rel := MacrosEngine.HasRelative(keys), send := this.sendFn
        if rel {
            if this.running
                return                              ; one at a time (its own key again while it runs)
            SendMode("Event"), CoordMode("Mouse", "Screen")
            if send = SendInput
                send := SendEvent
            MouseGetPos(&ax, &ay)
            this.running := true, this.cancelled := false
            ; the user (2026-10-30): far slower than the same steps as a script of its own. Its waits let the
            ; companion's timers run (the chat box's screen check, the meter, the module's reads), each a wait
            ; stretched by theirs: critical, they wait until it's done. A hotkey can't run then either, so
            ; your right click is the button's physical state (the mouse hook's: sent clicks don't count)
            Critical("On")
            if !this.mouseFn
                InstallMouseHook()
            this.rbDown := !this.mouseFn && GetKeyState("RButton", "P")
            this.at := [ax, ay]
        }
        try {
            for t in keys {
                if rel && this.stopped() {
                    DebugLog("macros: stopped by your right click")
                    break
                }
                if (ms := MacrosEngine.WaitStep(t)) >= 0 {
                    this.wait(ms, rel), waited := true
                    continue
                }
                if MacrosEngine.RelStep(t, &kind, &dx, &dy) {   ; mouse steps: no gap before them
                    this.mouse(kind, ax + dx, ay + dy), waited := false
                    continue
                }
                if MacrosEngine.ClickStep(t, &right, &x, &y, &screen) {
                    MacrosEngine.ClickAt(right, x, y, screen, this.clickFn, this.win), waited := false
                    continue
                }
                if !waited && gap > 0
                    Sleep(gap)
                waited := false
                send(MacrosEngine.KeyInput(t))
            }
        } finally {
            if rel
                this.running := false, Critical("Off")
        }
    }
    ; your right click since the last look (pressed down again: one held from before doesn't count)
    stopped() {
        if !this.cancelled && !this.mouseFn {
            down := GetKeyState("RButton", "P")
            if down && !this.rbDown
                this.cancelled := true
            this.rbDown := down
        }
        return this.cancelled
    }
    ; a delay; in a macro that can be stopped, in short sleeps so a right click stops it at once
    wait(ms, rel) {
        if !rel || ms <= 20
            return Sleep(ms)
        endAt := A_TickCount + ms
        while !this.stopped() && A_TickCount < endAt
            Sleep(Min(15, endAt - A_TickCount))
    }
    ; a mouse step; a click where the mouse already is doesn't move it first (Event mode's mouse delay each move)
    mouse(kind, x, y) {
        if this.mouseFn
            return (this.mouseFn)(kind, x, y)
        if kind = "move" || x != this.at[1] || y != this.at[2]
            MouseMove(x, y, 0)
        this.at := [x, y]
        if kind != "move"
            Click(kind = "rclick" ? "Right" : "Left")
    }
    cancel(*) {
        if this.running
            this.cancelled := true
    }
    ; a click at a spot of the game window (fractions of its client area) or of the screen; false: no game window
    static ClickAt(right, x, y, screen, clickFn := 0, win := "") {
        CoordMode("Mouse", "Screen")
        if !screen {
            if !WinExist(win != "" ? win : WarcraftIII)
                return false
            WinGetClientPos(&gx, &gy, &gw, &gh)
            x := gx + Round(x * gw), y := gy + Round(y * gh)
        }
        MouseGetPos(&ox, &oy)
        if clickFn
            clickFn(right, Round(x), Round(y))
        else {
            Click(Round(x) " " Round(y) (right ? " Right" : ""))
            MouseMove(ox, oy, 0)
        }
        return true
    }

    refresh() {
        for _, reg in this.registered
            reg.refresh()
    }
}
