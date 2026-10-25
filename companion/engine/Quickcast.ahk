#Requires AutoHotkey v2.0
; ============================================================================
;  QuickcastEngine - "is WC3 waiting for a target?" from the screen.
;  No injection or memory reading, so it works the same on 1.28 and Reforged:
;  while an ability waits for a target, the command card shows only Cancel
;  (bottom-right), every other slot is empty. A one-time calibration in game
;  records where the card is and what its empty slots look like; a quickcast
;  then sends the key, looks at the card for a frame or two and clicks only if
;  it went empty. Calibrations are kept per game version and window size.
; ============================================================================
class QuickcastEngine {
    section := "Quickcast"
    cache := Map()              ; calibration key -> parsed calibration (or 0)
    cal := 0                    ; calibration in progress: { step, p1, p2, normal }
    seen := { same: 0, diffs: "" }      ; the last look at the card (debug log)
    calHotkey := "$Space"         ; held back from the game during the setup
    static STEPS := ["Point at Move (the command card's top-left button) and press Space",
        "Point at the command card's bottom-right button and press Space",
        "Press A (Attack): the card shows only Cancel. Then press Space"]
    tuned := 0                  ; when the empty card was last saved after tuning
    fromWindow := Map()         ; window key -> true once reading the game window itself works
    misses := 0                 ; quickcasts in a row with no targeting seen (window reads)

    ; -- settings --------------------------------------------------------------
    get() {
        return { repeat: Integer(Ini(this.section, "repeat", 1)),
            interval: Integer(Ini(this.section, "interval", 40)),
            castGap: Integer(Ini(this.section, "castGap", 450)),
            window: this.windowKey(), calibrated: this.current() ? 1 : 0 }
    }
    set(key, value) => SetIni(value, this.section, key)

    windowKey() => WC3WindowKey()
    ; The calibration for the game as it is now (0 = none / not running). Kept
    ; in the ini, so updates never lose it. A window resized to the same shape
    ; (same version and aspect ratio) reuses it: positions are fractions.
    current() {
        if !(k := this.windowKey())
            return 0
        if !this.cache.Has(k) {
            v := Ini(this.section, "cal_" k, "")
            if v = "" && RegExMatch(k, "^(\w+)_(\d+)x(\d+)$", &m)
                try for key in StrSplit(IniRead(iniFile, this.section), "`n")
                    if RegExMatch(key, "^cal_" m[1] "_(\d+)x(\d+)=(.*)$", &o) && Abs(o[1] / o[2] - m[2] / m[3]) < 0.01 {
                        v := o[3]
                        break
                    }
            this.cache[k] := this.parse(v)
        }
        return this.cache[k]
    }

    ; -- detection -----------------------------------------------------------
    ; true when the card's slots 1-11 look like the calibrated empty card.
    ; Move, Stop, Hold, Attack and Patrol are always there on a normal card, so
    ; at most 6 slots can look empty then; 8 leaves room for the cursor, a
    ; tooltip, or a card that looks a little different from the setup (another
    ; race's HUD, brightness) until tuning catches up. this.seen keeps the last
    ; look, for the debug log.
    targeting(c, fromWindow := -1) {
        g := this.grabCard(c, fromWindow)
        if !g
            return false
        same := 0, diffs := "", cols := []
        loop 11 {
            cols.Push(col := this.slotColor(c, g, A_Index))
            d := ColorDiff(col, c.empty[A_Index])
            same += d <= 80
            diffs .= (A_Index > 1 ? "," : "") d
        }
        this.seen := { same: same, diffs: diffs }
        if same >= 8
            this.tune(c, cols)
        return same >= 8
    }
    ; Reading the screen waits for Windows to compose a frame (~16 ms a read);
    ; reading the game window directly can be ~1 ms, but only some games draw
    ; where it can be read, and a stale picture would look "never targeting".
    ; So it's proven live first: right after the screen showed targeting, the
    ; window must show it too. Five misses in a row on window reads go back to
    ; the screen (and it's proven again on the next hit).
    learnCapture(c, hit) {
        k := WC3WindowKey()
        if this.fromWindow.Get(k, false) {
            this.misses := hit ? 0 : this.misses + 1
            if this.misses >= 5
                this.fromWindow[k] := false, this.misses := 0, DebugLog("quickcast: back to reading the screen")
            return
        }
        if !hit || this.fromWindow.Has(k)
            return
        t := QpcMs(), live := this.targeting(c, true), ms := QpcMs() - t
        this.fromWindow[k] := live
        DebugLog("quickcast: reading the game window " (live ? "works (" Round(ms, 1) " ms a read), using it" : "doesn't work, reading the screen"))
    }
    ; A hit: move the saved empty card a quarter of the way to what was just
    ; seen, so drifts (lighting, another race's HUD, a slightly off setup) fix
    ; themselves in a few casts. A slot far off (the cursor, a tooltip) is left
    ; alone, and no slot moves further than DRIFT from what the setup saw
    ; (c.orig): a run of odd reads (a dimmed or paused game, a mostly empty
    ; card) can't walk it away for good. Saved at most every 30 s.
    static DRIFT := 90
    tune(c, cols) {
        loop 11 {
            a := c.empty[A_Index], b := cols[A_Index]
            if ColorDiff(a, b) > 160
                continue                    ; the odd slot out (cursor, tooltip): leave it
            r := ((a >> 16 & 0xFF) * 3 + (b >> 16 & 0xFF) + 2) // 4      ; rounded: a small drift either way is followed
            gr := ((a >> 8 & 0xFF) * 3 + (b >> 8 & 0xFF) + 2) // 4
            bl := ((a & 0xFF) * 3 + (b & 0xFF) + 2) // 4
            v := r << 16 | gr << 8 | bl
            if ColorDiff(v, c.orig[A_Index]) <= QuickcastEngine.DRIFT
                c.empty[A_Index] := v
        }
        if A_TickCount - this.tuned > 30000 && (k := this.windowKey()) {
            this.tuned := A_TickCount
            SetIni(this.serialize(c), this.section, "cal_" k)
        }
    }

    ; After a miss (Remap.quickSmart): a run of near misses (5-7 slots looked
    ; empty, 8 are needed) means the tuned colours may have drifted: back to
    ; what the setup saw. Harmless if it was only a unit with a small card.
    nearRun := 0
    noteMiss(c, bestSame) {
        this.nearRun := bestSame >= 5 && bestSame <= 7 ? this.nearRun + 1 : 0
        if this.nearRun < 6
            return
        this.nearRun := 0
        changed := false
        loop 11
            changed |= c.empty[A_Index] != c.orig[A_Index], c.empty[A_Index] := c.orig[A_Index]
        if changed && (k := this.windowKey()) {
            SetIni(this.serialize(c), this.section, "cal_" k)
            DebugLog("quickcast: 6 near misses in a row: the empty card's colours are back to the setup's")
        }
    }
    noteHit() => this.nearRun := 0

    ; -- calibration (in game, three presses of Space) --------------------------
    ; Remaps and macros pause meanwhile (qcCalibrating), so A is the game's Attack
    ; even if it's bound. Esc cancels.
    calibrateStart(onDone) {
        global qcCalibrating
        if !WinExist(WarcraftIII) {
            Toast("Start Warcraft III first, in a game with your hero selected", "error")
            return onDone(0, "")
        }
        this.cal := { step: 1, onDone: onDone }
        qcCalibrating := true, RefreshHotkeys()
        DebugLog("quickcast setup started (" this.windowKey() ")")
        HotIfWinActive(WarcraftIII)
        Hotkey(this.calHotkey, (*) => this.calibrateStep(), "On")
        HotIfWinActive()
        WinActivate(WarcraftIII)
        this.stepToast(1)
    }
    stepToast(n) => Toast("Quickcast Setup " n "/3  ·  " QuickcastEngine.STEPS[n] "  ·  Esc cancels", "", 0)
    calibrateStep() {
        c := this.cal
        if !c
            return
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        if c.step = 1 {
            c.p1 := [(mx - wx) / cw, (my - wy) / ch], c.step := 2
            this.stepToast(2)
        } else if c.step = 2 {
            c.p2 := [(mx - wx) / cw, (my - wy) / ch]
            if c.p2[1] - c.p1[1] < 0.03 || c.p2[2] - c.p1[2] < 0.03
                return this.calibrateEnd(0, "That button wasn't below and right of Move. Run the setup again.")
            g := this.grabCard(c)
            c.normal := []
            loop 11
                c.normal.Push(this.slotColor(c, g, A_Index))
            c.step := 3
            this.stepToast(3)
        } else {
            g := this.grabCard(c)
            c.empty := []
            loop 11
                c.empty.Push(this.slotColor(c, g, A_Index))
            c.orig := c.empty.Clone()
            ; it only works if the card visibly changed (and the screen isn't black)
            changed := 0, black := 0
            loop 11 {
                if ColorDiff(c.normal[A_Index], c.empty[A_Index]) > 60
                    changed++
                if c.empty[A_Index] = 0 && c.normal[A_Index] = 0
                    black++
            }
            if black >= 10
                return this.calibrateEnd(0, "The companion can't see the game. Use windowed or windowed fullscreen mode.")
            if changed < 4
                return this.calibrateEnd(0, "The command card didn't change: press A first, then Space while it shows only Cancel")
            k := this.windowKey()
            DebugLog("quickcast setup: card changed in " changed "/11 slots between normal and targeting")
            SetIni(this.serialize(c), this.section, "cal_" k)
            this.cache.Delete(k)
            this.calibrateEnd(1, "Quickcast set up for " StrReplace(k, "_", " "))
        }
    }
    calibrateEnd(ok, msg) {
        global qcCalibrating
        if !this.cal
            return
        HotIfWinActive(WarcraftIII)
        try Hotkey(this.calHotkey, "Off")
        HotIfWinActive()
        qcCalibrating := false, RefreshHotkeys()
        DebugLog("quickcast setup ended: " msg)
        done := this.cal.onDone
        this.cal := 0
        Toast(msg, ok ? "" : "error")
        done(ok, msg)
    }

    ; -- geometry & pixels ---------------------------------------------------
    ; slot i (1-12, row by row) centre as a fraction of the client area
    slotAt(c, i) {
        col := Mod(i - 1, 4), row := (i - 1) // 4
        return [c.p1[1] + (c.p2[1] - c.p1[1]) * col / 3, c.p1[2] + (c.p2[2] - c.p1[2]) * row / 2]
    }
    ; the card's bounding box, grabbed from the screen in one go
    ; fromWindow: -1 = the best way known for this window, true / false = force it
    grabCard(c, fromWindow := -1) {
        if !WinExist(WarcraftIII)
            return 0
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        pitch := (c.p2[1] - c.p1[1]) * cw / 3
        r := Max(4, Round(pitch * 0.25))
        x := Round(wx + c.p1[1] * cw) - r, y := Round(wy + c.p1[2] * ch) - r
        w := Round((c.p2[1] - c.p1[1]) * cw) + 2 * r + 1, h := Round((c.p2[2] - c.p1[2]) * ch) + 2 * r + 1
        win := fromWindow = -1 ? this.fromWindow.Get(WC3WindowKey(), false) : fromWindow
        g := win ? ScreenGrab(x - wx, y - wy, w, h, WinExist(WarcraftIII)) : ScreenGrab(x, y, w, h)
        g.ox := x, g.oy := y, g.wx := wx, g.wy := wy, g.cw := cw, g.ch := ch, g.r := r
        return g
    }
    ; a slot's average colour from its centre and four points around it
    slotColor(c, g, i) {
        p := this.slotAt(c, i)
        cx := Round(g.wx + p[1] * g.cw) - g.ox, cy := Round(g.wy + p[2] * g.ch) - g.oy
        d := g.r, r := 0, gr := 0, b := 0
        for o in [[0, 0], [-d, -d], [d, -d], [-d, d], [d, d]] {
            px := g.pixel(cx + o[1], cy + o[2])
            r += px >> 16 & 0xFF, gr += px >> 8 & 0xFF, b += px & 0xFF
        }
        return (r // 5) << 16 | (gr // 5) << 8 | (b // 5)
    }

    ; -- storage: "x1,y1,x2,y2|tuned c1,...,c11|setup c1,...,c11" ---------------
    ; (older ones have no third part: their colours count as the setup's)
    serialize(c) {
        hex(list) {
            out := ""
            for v in list
                out .= (A_Index > 1 ? "," : "") Format("{:06X}", v)
            return out
        }
        return Format("{:.5f},{:.5f},{:.5f},{:.5f}", c.p1[1], c.p1[2], c.p2[1], c.p2[2]) "|" hex(c.empty) "|" hex(c.orig)
    }
    parse(s) {
        parts := StrSplit(s, "|")
        if parts.Length < 2 || parts.Length > 3
            return 0
        p := StrSplit(parts[1], ",")
        if p.Length != 4
            return 0
        cols(part) {
            out := []
            for v in StrSplit(part, ",")
                out.Push(Integer("0x" v))
            return out.Length = 11 ? out : 0
        }
        if !(empty := cols(parts[2]))
            return 0
        orig := parts.Length = 3 ? cols(parts[3]) : 0
        return { p1: [p[1] + 0, p[2] + 0], p2: [p[3] + 0, p[4] + 0], empty: empty, orig: orig ? orig : empty.Clone() }
    }
}

; "reforged_1920x1080" / "classic_1920x1080" for the running game ("" if it
; isn't): screen layouts differ by version and size. Reforged runs from _retail_.
; 1.28 with the game module's widescreen applied is "classicwide_...": the HUD
; isn't stretched then, so it has its own setups.
WC3WindowKey() {
    global gameDisplay, gameModule
    static kind := Map()            ; WC3 window -> "reforged" / "classic"
    if !(hwnd := WinExist(WarcraftIII))
        return ""
    if !kind.Has(hwnd) {
        try path := WinGetProcessPath(hwnd)
        catch
            path := ""
        kind[hwnd] := InStr(path, "_retail_") ? "reforged" : "classic"
    }
    WinGetClientPos(, , &cw, &ch, hwnd)
    static wide := false, wideAt := 0               ; looked up at most twice a second (it reads the ini)
    if kind[hwnd] = "classic" && A_TickCount - wideAt > 500 {
        wideAt := A_TickCount
        wide := IsSet(gameDisplay) && gameDisplay.widescreen && gameModule.enabled
            && (v := gameModule.live()) && NumGet(v, 4, "uint") >= 7 && NumGet(v, 616, "uint") = 1
    }
    return kind[hwnd] (kind[hwnd] = "classic" && wide ? "wide" : "") "_" cw "x" ch
}
; a window key for people: "1.28 1920x1080", "1.28 widescreen 1920x1080", "Reforged 1920x1080"
WC3WindowName(k) => StrReplace(StrReplace(StrReplace(StrReplace(k, "classicwide", "1.28 widescreen"), "classic", "1.28"), "reforged", "Reforged"), "_", " ")

; milliseconds from the performance counter (A_TickCount moves in ~16 ms steps)
QpcMs() {
    static f := (DllCall("QueryPerformanceFrequency", "int64*", &v := 0), v)
    DllCall("QueryPerformanceCounter", "int64*", &t := 0)
    return t * 1000 / f
}

; how far apart two 0xRRGGBB colours are (sum of channel differences, 0-765)
ColorDiff(a, b) => Abs((a >> 16 & 0xFF) - (b >> 16 & 0xFF)) + Abs((a >> 8 & 0xFF) - (b >> 8 & 0xFF)) + Abs((a & 0xFF) - (b & 0xFF))

; A screen rectangle copied into memory with one BitBlt (reading pixels one by
; one with PixelGetColor is far too slow for a per-cast check).
; hwnd: copy from that window's client area (x, y relative to it) instead of
; the screen
class ScreenGrab {
    __New(x, y, w, h, hwnd := 0) {
        this.w := w, this.h := h, this.buf := Buffer(w * h * 4, 0)
        sdc := DllCall("GetDC", "ptr", hwnd, "ptr")
        mdc := DllCall("CreateCompatibleDC", "ptr", sdc, "ptr")
        bi := Buffer(40, 0)
        NumPut("uint", 40, "int", w, "int", -h, "ushort", 1, "ushort", 32, bi)     ; top-down 32-bit
        hbm := DllCall("CreateDIBSection", "ptr", mdc, "ptr", bi, "uint", 0, "ptr*", &bits := 0, "ptr", 0, "uint", 0, "ptr")
        old := DllCall("SelectObject", "ptr", mdc, "ptr", hbm, "ptr")
        DllCall("BitBlt", "ptr", mdc, "int", 0, "int", 0, "int", w, "int", h, "ptr", sdc, "int", x, "int", y, "uint", 0x00CC0020)
        DllCall("RtlMoveMemory", "ptr", this.buf, "ptr", bits, "uptr", w * h * 4)
        DllCall("SelectObject", "ptr", mdc, "ptr", old)
        DllCall("DeleteObject", "ptr", hbm)
        DllCall("DeleteDC", "ptr", mdc)
        DllCall("ReleaseDC", "ptr", hwnd, "ptr", sdc)
    }
    ; 0xRRGGBB at (x, y); 0 outside the grab
    pixel(x, y) {
        if x < 0 || y < 0 || x >= this.w || y >= this.h
            return 0
        return NumGet(this.buf, (y * this.w + x) * 4, "uint") & 0xFFFFFF
    }
}
