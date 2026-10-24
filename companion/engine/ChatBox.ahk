#Requires AutoHotkey v2.0
; ============================================================================
;  ChatBoxEngine - "is the WC3 chat box open?" from the screen.
;  In a game the chat input is a dark bar with a thin gold border, centred
;  above the HUD. Its place is known for 1.28 at 1920x1080 (measured), and is
;  found by itself elsewhere: the first time chat opens, the gold border is
;  searched for and its position kept per game version and window size.
;  A look at a few border pixels then says open / closed.
; ============================================================================
class ChatBoxEngine {
    section := "Chat"
    geo := Map()                ; window key -> { t, b, l, r } as fractions of the client, or 0
    ; measured: 1.28, 1920x1080 (border at y 697 / 742, x 605 / 1314)
    static DEFAULTS := Map("classic_1920x1080", "0.6454,0.6870,0.3151,0.6844")

    current() {
        if !(k := WC3WindowKey())
            return 0
        if !this.geo.Has(k)
            this.geo[k] := this.parse(Ini(this.section, "geo_" k, ChatBoxEngine.DEFAULTS.Get(k, "")))
        return this.geo[k]
    }

    ; true when the gold border is there along most of its top and bottom edges
    ; and the bar between them is dark
    isOpen(g) {
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        x0 := Round(wx + g.l * cw) - 4, y0 := Round(wy + g.t * ch) - 4
        w := Round((g.r - g.l) * cw) + 9, h := Round((g.b - g.t) * ch) + 9
        s := ScreenGrab(x0, y0, w, h)
        top := 0, bottom := 0, dark := 0
        loop 10 {
            x := 4 + Round((w - 9) * (A_Index - 0.5) / 10)
            if this.goldNear(s, x, 4)
                top++
            if this.goldNear(s, x, h - 5)
                bottom++
            px := s.pixel(x, h // 2)
            r := px >> 16 & 0xFF, gr := px >> 8 & 0xFF, b := px & 0xFF
            if r + gr + b < 0xC0 && b >= r
                dark++
        }
        return top >= 7 && bottom >= 7 && dark >= 5
    }
    ; gold within 4 rows of y (the border is 1-2 px, sizes round differently)
    goldNear(s, x, y) {
        loop 9
            if IsChatGold(s.pixel(x, y - 5 + A_Index))
                return true
        return false
    }

    ; Find the box on screen (chat must be open) and keep its place for this
    ; game window. -> true if found.
    locate() {
        if !(k := WC3WindowKey())
            return false
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        rx := Round(cw * 0.1), ry := Round(ch * 0.45), rw := Round(cw * 0.8), rh := Round(ch * 0.45)
        s := ScreenGrab(wx + rx, wy + ry, rw, rh)
        cx := rw // 2
        ; gold rows down the middle: the border's top and bottom
        rows := [], y := 0
        while y < rh {
            if IsChatGold(s.pixel(cx, y)) {
                rows.Push(y)
                y += 3                      ; one entry per border line
            }
            y++
        }
        for i, y1 in rows
            for y2 in rows {
                gap := y2 - y1
                if gap < ch * 0.025 || gap > ch * 0.07
                    continue
                ; follow the top border both ways from the middle
                l := this.edge(s, cx, y1, -1), r := this.edge(s, cx, y1, 1)
                if r - l < cw * 0.2
                    continue
                g := { t: (ry + y1) / ch, b: (ry + y2) / ch, l: (rx + l) / cw, r: (rx + r) / cw }
                SetIni(Format("{:.4f},{:.4f},{:.4f},{:.4f}", g.t, g.b, g.l, g.r), this.section, "geo_" k)
                this.geo[k] := g
                return true
            }
        return false
    }
    ; walk along a border line until it stops being gold (3 px in a row)
    edge(s, x, y, dir) {
        miss := 0, last := x
        while x > 0 && x < s.w - 1 && miss < 3 {
            x += dir
            if IsChatGold(s.pixel(x, y)) || IsChatGold(s.pixel(x, y - 1)) || IsChatGold(s.pixel(x, y + 1))
                miss := 0, last := x
            else
                miss++
        }
        return last
    }

    parse(v) {
        p := StrSplit(v, ",")
        return p.Length = 4 ? { t: p[1] + 0, b: p[2] + 0, l: p[3] + 0, r: p[4] + 0 } : 0
    }
}

; the border's gold (F6BA10 / FBC319 / EFAD03), not its darker anti-aliased edge
IsChatGold(px) {
    r := px >> 16 & 0xFF, g := px >> 8 & 0xFF, b := px & 0xFF
    return r >= 0xC0 && g >= 0x90 && g <= 0xD8 && b <= 0x48 && r > g
}
