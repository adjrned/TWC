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
    calHotkey := "$Insert"
    static STEPS := ["Point at Move (the command card's top-left button) and press Insert",
        "Point at the command card's bottom-right button and press Insert",
        "Press A (Attack): the card shows only Cancel. Then press Insert"]

    ; -- settings --------------------------------------------------------------
    get() {
        return { repeat: Integer(Ini(this.section, "repeat", 1)),
            interval: Integer(Ini(this.section, "interval", 40)),
            window: this.windowKey(), calibrated: this.current() ? 1 : 0 }
    }
    set(key, value) => SetIni(value, this.section, key)

    windowKey() => WC3WindowKey()
    ; the calibration for the game as it is now (0 = none / not running)
    current() {
        if !(k := this.windowKey())
            return 0
        if !this.cache.Has(k)
            this.cache[k] := this.parse(Ini(this.section, "cal_" k, ""))
        return this.cache[k]
    }

    ; -- detection -----------------------------------------------------------
    ; true when the card's slots 1-11 look like the calibrated empty card
    targeting(c) {
        g := this.grabCard(c)
        if !g
            return false
        same := 0
        loop 11
            if ColorDiff(this.slotColor(c, g, A_Index), c.empty[A_Index]) <= 48
                same++
        return same >= 10           ; one slot may be off (cursor over the card, a tooltip)
    }

    ; -- calibration (in game, three presses of Insert) -------------------------
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
    stepToast(n) => Toast("Quickcast setup " n "/3  ·  " QuickcastEngine.STEPS[n] "  ·  Esc cancels", "", 0)
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
                return this.calibrateEnd(0, "The command card didn't change: press A first, then Insert while it shows only Cancel")
            k := this.windowKey()
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
    grabCard(c) {
        if !WinExist(WarcraftIII)
            return 0
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        pitch := (c.p2[1] - c.p1[1]) * cw / 3
        r := Max(4, Round(pitch * 0.25))
        x := Round(wx + c.p1[1] * cw) - r, y := Round(wy + c.p1[2] * ch) - r
        w := Round((c.p2[1] - c.p1[1]) * cw) + 2 * r + 1, h := Round((c.p2[2] - c.p1[2]) * ch) + 2 * r + 1
        g := ScreenGrab(x, y, w, h)
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

    ; -- storage: "x1,y1,x2,y2|c1,...,c11" -----------------------------------
    serialize(c) {
        cols := ""
        for v in c.empty
            cols .= (A_Index > 1 ? "," : "") Format("{:06X}", v)
        return Format("{:.5f},{:.5f},{:.5f},{:.5f}", c.p1[1], c.p1[2], c.p2[1], c.p2[2]) "|" cols
    }
    parse(s) {
        parts := StrSplit(s, "|")
        if parts.Length != 2
            return 0
        p := StrSplit(parts[1], ","), cols := StrSplit(parts[2], ",")
        if p.Length != 4 || cols.Length != 11
            return 0
        empty := []
        for v in cols
            empty.Push(Integer("0x" v))
        return { p1: [p[1] + 0, p[2] + 0], p2: [p[3] + 0, p[4] + 0], empty: empty }
    }
}

; "reforged_1920x1080" / "classic_1920x1080" for the running game ("" if it
; isn't): screen layouts differ by version and size. Reforged runs from _retail_.
WC3WindowKey() {
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
    return kind[hwnd] "_" cw "x" ch
}

; how far apart two 0xRRGGBB colours are (sum of channel differences, 0-765)
ColorDiff(a, b) => Abs((a >> 16 & 0xFF) - (b >> 16 & 0xFF)) + Abs((a >> 8 & 0xFF) - (b >> 8 & 0xFF)) + Abs((a & 0xFF) - (b & 0xFF))

; A screen rectangle copied into memory with one BitBlt (reading pixels one by
; one with PixelGetColor is far too slow for a per-cast check).
class ScreenGrab {
    __New(x, y, w, h) {
        this.w := w, this.h := h, this.buf := Buffer(w * h * 4, 0)
        sdc := DllCall("GetDC", "ptr", 0, "ptr")
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
        DllCall("ReleaseDC", "ptr", 0, "ptr", sdc)
    }
    ; 0xRRGGBB at (x, y); 0 outside the grab
    pixel(x, y) {
        if x < 0 || y < 0 || x >= this.w || y >= this.h
            return 0
        return NumGet(this.buf, (y * this.w + x) * 4, "uint") & 0xFFFFFF
    }
}
