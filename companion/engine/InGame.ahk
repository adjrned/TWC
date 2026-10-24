#Requires AutoHotkey v2.0
; ============================================================================
;  WC3InGame - is Warcraft III in a game (not a menu, lobby or score screen)?
;  In a game, 1.28 and Reforged both draw the menu bar at the top left: four
;  buttons (Help F9, Menu F10, Allies F11, Chat F12) with a bright top edge
;  and dark faces, sized by the window height. Menus have none of it, so
;  remaps and macros stay out of menu text fields (game names, chat lobbies).
; ============================================================================
class InGameEngine {
    ; button edges at 1080p (x), sampled just inside each end of each button
    static XS := [258, 375, 413, 530, 566, 684, 720, 838]
    trusted := Map()            ; window key -> false once the bar was missing in a game

    ; the bar seen = in a game. A window whose bar can't be seen (a HUD mod, an
    ; odd size) is marked untrusted the first time chat proves it's in a game.
    inGame() {
        if !WinExist(WarcraftIII)
            return false
        k := WC3WindowKey()
        if this.trusted.Has(k) && !this.trusted[k]
            return true
        return this.barSeen()
    }
    distrust() => this.trusted[WC3WindowKey()] := false

    barSeen() {
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        f := ch / 1080
        s := ScreenGrab(wx, wy, Round(860 * f), Round(30 * f))
        hits := 0
        for x in InGameEngine.XS {
            px := Round(x * f)
            top := false
            loop 4                                   ; the top edge, rows 3-6 at 1080p (thin:
                if Bright(s.pixel(px, Round((2 + A_Index) * f)))   ; blurred at other sizes)
                    top := true
            face := 0
            for y in [10, 14, 22, 26]                ; the face, around the label
                face += Dark(s.pixel(px, Round(y * f)))
            hits += top && face >= 3
        }
        return hits >= 6
    }
}
Bright(px) => Max(px >> 16 & 0xFF, px >> 8 & 0xFF, px & 0xFF) >= 0x80
Dark(px) => (px >> 16 & 0xFF) + (px >> 8 & 0xFF) + (px & 0xFF) < 0x90
