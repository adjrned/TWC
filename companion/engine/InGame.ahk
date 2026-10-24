#Requires AutoHotkey v2.0
; ============================================================================
;  WC3InGame - is Warcraft III in a game (not a menu, lobby or score screen)?
;  In a game, 1.28 and Reforged both draw the menu bar at the top: four
;  buttons (Help F9, Menu F10, Allies F11, Chat F12) with a bright top edge
;  and dark faces, as tall as the window height says. Menus have none of it, so
;  remaps and macros stay out of menu text fields (game names, chat lobbies).
; ============================================================================
class InGameEngine {
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

    ; Where the bar sits across the screen depends on the aspect ratio and the
    ; version (16:9, 16:10 or 4:3; centred, or stretched on 1.28 without a
    ; widescreen fix), but its height always follows the window height. So the
    ; whole top strip is scanned: a column "looks like the bar" with a bright top
    ; edge (rows 3-6 at 1080p; thin, so blurred at other sizes) over a dark face.
    ; The four buttons make that true across a good part of the width; menus
    ; don't come close.
    barSeen() {
        WinGetClientPos(&wx, &wy, &cw, &ch, WarcraftIII)
        f := ch / 1080
        s := ScreenGrab(wx, wy, cw, Round(30 * f))
        tops := [], faces := []
        loop 4
            tops.Push(Round((2 + A_Index) * f))
        for y in [10, 14, 22, 26]
            faces.Push(Round(y * f))
        hits := 0, x := 0
        while x < cw {
            top := false
            for y in tops
                if Bright(s.pixel(x, y)) {
                    top := true
                    break
                }
            if top {
                face := 0
                for y in faces
                    face += Dark(s.pixel(x, y))
                hits += face >= 3
            }
            x += 2
        }
        return hits * 2 >= cw * 0.12
    }
}
Bright(px) => Max(px >> 16 & 0xFF, px >> 8 & 0xFF, px & 0xFF) >= 0x80
Dark(px) => (px >> 16 & 0xFF) + (px >> 8 & 0xFF) + (px & 0xFF) < 0x90
