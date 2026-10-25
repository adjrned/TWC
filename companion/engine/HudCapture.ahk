#Requires AutoHotkey v2.0
; ============================================================================
;  HUD pictures - for building Reforged's cooldown and buff timers from the
;  screen: tray > "Debug: save HUD pictures" saves the command card and the
;  buff bar twice a second for 15 s as BMP files in captures\<date-time>\,
;  then opens the folder. Only while Warcraft III is the active window, so
;  nothing else on the screen is saved. Use a cooldown or two and let a buff
;  run out meanwhile, then send the folder.
;  The parts come from the quickcast setup (command card) and the buff bar
;  setup; without them, the bottom right of the game.
; ============================================================================
class HudCaptureEngine {
    shots := 0, dir := "", fn := 0
    static COUNT := 30, EVERY := 500

    __New(quickcast, timersHud) {
        this.qc := quickcast, this.hud := timersHud
        this.fn := ObjBindMethod(this, "tick")
    }
    start(*) {
        if this.shots
            return Toast("Already saving HUD pictures", "", 2000)
        if !WinExist(WarcraftIII)
            return Toast("Start Warcraft III first, in a game", "error")
        this.dir := A_ScriptDir "\captures\" FormatTime(, "yyyyMMdd-HHmmss")
        DirCreate(this.dir)
        this.shots := HudCaptureEngine.COUNT, this.saved := 0
        WinActivate(WarcraftIII)
        Toast("Saving HUD pictures for 15 s: use a cooldown, let a buff run out", "", 3000)
        SetTimer(this.fn, HudCaptureEngine.EVERY)
    }
    ; the areas to save, in screen pixels: [{ name, x, y, w, h }]
    areas() {
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        out := []
        if (c := this.qc.current()) {
            pitch := (c.p2[1] - c.p1[1]) * cw / 3, m := Round(pitch * 0.7)
            out.Push({ name: "card", x: Round(wx + c.p1[1] * cw) - m, y: Round(wy + c.p1[2] * ch) - m,
                w: Round((c.p2[1] - c.p1[1]) * cw) + 2 * m, h: Round((c.p2[2] - c.p1[2]) * ch) + 2 * m })
        }
        if (b := this.hud.buffBar()) {
            p := b.dx * cw
            out.Push({ name: "buffs", x: Round(wx + b.x * cw - p), y: Round(wy + b.y * ch - p), w: Round(p * 10), h: Round(p * 2) })
        }
        if !out.Length                                  ; no setups: the bottom right of the game
            out.Push({ name: "hud", x: wx + Round(cw * 0.6), y: wy + Round(ch * 0.7), w: Round(cw * 0.4), h: Round(ch * 0.3) })
        return out
    }
    tick() {
        if this.shots <= 0
            return this.finish()
        this.shots--
        if !WinActive(WarcraftIII)
            return
        n := HudCaptureEngine.COUNT - this.shots
        for a in this.areas()
            if a.w > 0 && a.h > 0 && a.w * a.h <= 4000000
                HudCaptureEngine.SaveBmp(ScreenGrab(a.x, a.y, a.w, a.h), this.dir "\" Format("{:02}", n) "-" a.name ".bmp"), this.saved++
        if this.shots <= 0
            this.finish()
    }
    finish() {
        SetTimer(this.fn, 0)
        this.shots := 0
        DebugLog("HUD pictures: " this.saved " saved in " this.dir)
        if !this.saved {
            try DirDelete(this.dir)
            return Toast("No HUD pictures saved: Warcraft III wasn't the active window", "error")
        }
        Toast(this.saved " HUD pictures saved", "", 2500)
        Run('explorer.exe "' this.dir '"')
    }
    ; a ScreenGrab as a 32-bit top-down BMP
    static SaveBmp(g, path) {
        size := g.w * g.h * 4
        h := Buffer(54, 0)
        NumPut("ushort", 0x4D42, h, 0), NumPut("uint", 54 + size, h, 2), NumPut("uint", 54, h, 10)
        NumPut("uint", 40, "int", g.w, "int", -g.h, "ushort", 1, "ushort", 32, h, 14)
        NumPut("uint", size, h, 34)
        f := FileOpen(path, "w")
        f.RawWrite(h, 54), f.RawWrite(g.buf, size)
        f.Close()
    }
}
