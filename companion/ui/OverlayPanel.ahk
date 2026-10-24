#Requires AutoHotkey v2.0
; ============================================================================
;  OverlayPanel - the TWRPG site (builds, items, bosses...) in a WebView2 panel
;  docked over Warcraft III, PoE-overlay style:
;    Shift+Space       show + focus / hide (configurable)
;    Ctrl+Shift+Space  pin: stays on screen, see-through and click-through,
;                      so the game keeps focus (configurable)
;    Esc               hide (when Esc didn't close something in the page)
;  Hides when you click back into the game or switch to another app.
;  Served offline from web\TWC as https://twc.local/TWC/ (see UpdaterEngine).
;  The WebView is created on first use and closed after sitting hidden for a
;  while, so it costs nothing until you open it.
; ============================================================================
#Include ..\lib\WebView2\WebView2.ahk

class OverlayPanel {
    section := "Overlay"
    static HOST := "twc.local"
    static HOME := "https://twc.local/TWC/index.html"
    static GRIP := 6         ; resize strip on the panel's inner edge, px
    static MIN_W := 380

    gui := 0, wvc := 0, wv := 0, grip := 0
    shown := false, pinned := false, ready := false
    pending := []            ; messages to post once the page says "ready"
    updating := false
    hkShow := "", hkPin := ""

    __New(updater) {
        this.updater := updater
        this.hotIfFn := (*) => this.hotkeyActive()
        this.watchFn := ObjBindMethod(this, "watchFocus")
        this.unloadFn := ObjBindMethod(this, "unload")
        this.bindHotkeys()
        OnMessage(0x201, ObjBindMethod(this, "onLButtonDown"))
        OnMessage(0x20, ObjBindMethod(this, "onSetCursor"))
    }

    ; -- settings ------------------------------------------------------------
    get() {
        return {
            hotkey: Ini(this.section, "hotkey", "+Space"),
            pinHotkey: Ini(this.section, "pinHotkey", "^+Space"),
            side: Ini(this.section, "side", "right"),
            width: Integer(Ini(this.section, "width", 0)),
            opacity: Integer(Ini(this.section, "opacity", 100)),
            pinOpacity: Integer(Ini(this.section, "pinOpacity", 70)),
            unloadMinutes: Integer(Ini(this.section, "unloadMinutes", 10)),
            outsideGame: Integer(Ini(this.section, "outsideGame", 0)),
            checkOnStart: Integer(Ini(this.section, "checkOnStart", 1)),
            autoInstall: Integer(Ini(this.section, "autoInstall", 0)),
            version: this.updater.localVersion()
        }
    }

    set(key, value) {
        SetIni(value, this.section, key)
        if key = "hotkey" || key = "pinHotkey" || key = "outsideGame"
            this.bindHotkeys()
        else if this.shown
            this.applyLayout()
    }

    ; -- hotkeys -------------------------------------------------------------
    ; Active in Warcraft III (or anywhere with outsideGame) and in the overlay
    ; itself, but never while typing in WC3 chat so Shift+Space stays a space.
    hotkeyActive() {
        global chatting
        if this.gui && WinActive("ahk_id " this.gui.Hwnd)
            return true
        if chatting
            return false
        return WinActive(WarcraftIII) || Ini(this.section, "outsideGame", 0)
    }

    bindHotkeys() {
        s := this.get()
        HotIf(this.hotIfFn)
        for old in [this.hkShow, this.hkPin]
            if old
                try Hotkey(old, "Off")
        this.hkShow := s.hotkey ? "$" s.hotkey : ""
        this.hkPin := s.pinHotkey ? "$" s.pinHotkey : ""
        if this.hkShow
            try Hotkey(this.hkShow, (*) => this.toggle(), "On")
        if this.hkPin
            try Hotkey(this.hkPin, (*) => this.togglePin(), "On")
        HotIf()
    }

    ; -- show / hide / pin ---------------------------------------------------
    toggle() {
        if this.shown && !this.pinned
            this.hide()
        else
            this.show()
    }

    show() {
        if !this.ensure()
            return
        SetTimer(this.unloadFn, 0)
        this.setPinned(false)
        this.applyLayout()
        this.gui.Show("NA")
        this.wvc.IsVisible := true
        this.shown := true
        WinActivate("ahk_id " this.gui.Hwnd)
        try this.wvc.MoveFocus(0)
        SetTimer(this.watchFn, 200)
    }

    hide(refocusGame := true) {
        if !this.shown
            return
        SetTimer(this.watchFn, 0)
        this.setPinned(false)
        this.gui.Hide()
        try this.wvc.IsVisible := false    ; lets WebView2 throttle while hidden
        this.shown := false
        this.saveUrl()
        if refocusGame
            FocusWarcraft()
        mins := Ini(this.section, "unloadMinutes", 10)
        if mins > 0
            SetTimer(this.unloadFn, -mins * 60000)
    }

    togglePin() {
        if this.pinned {
            this.show()          ; unpin -> back to interactive
            return
        }
        if !this.shown
            this.show()
        this.setPinned(true)
        SetTimer(this.watchFn, 0)
        FocusWarcraft()
    }

    setPinned(on) {
        if !this.gui || this.pinned = on
            return
        this.pinned := on
        s := this.get()
        WinSetExStyle((on ? "+" : "-") "0x20", this.gui)    ; WS_EX_TRANSPARENT: clicks go to the game
        this.applyOpacity(on ? s.pinOpacity : s.opacity)
    }

    applyOpacity(pct) {
        pct := Max(20, Min(100, pct))
        WinSetTransparent(pct >= 100 && !this.pinned ? "Off" : Round(pct * 2.55), this.gui)
    }

    ; hide when focus moves to the game or another app (not to our own
    ; dialogs, e.g. the tracker's file picker, or WebView2 popups)
    watchFocus() {
        if !this.shown || this.pinned
            return
        a := WinExist("A")
        if !a || a = this.gui.Hwnd
            return
        try {
            if WinGetPID("ahk_id " a) = ProcessExist()
                return
            if WinGetProcessName("ahk_id " a) = "msedgewebview2.exe"
                return
            if DllCall("GetWindow", "ptr", a, "uint", 4, "ptr") = this.gui.Hwnd    ; GW_OWNER
                return
        }
        this.hide(false)
    }

    ; -- layout --------------------------------------------------------------
    ; Docks to the WC3 client area (or the work area of the screen under the
    ; mouse when the game isn't running).
    target() {
        if WinExist(WarcraftIII) && WinGetMinMax(WarcraftIII) != -1 {
            WinGetClientPos(&x, &y, &w, &h, WarcraftIII)
            if w > 200
                return { x: x, y: y, w: w, h: h }
        }
        CoordMode("Mouse", "Screen")
        MouseGetPos(&mx, &my)
        loop MonitorGetCount() {
            MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
            if mx >= l && mx < r && my >= t && my < b
                return { x: l, y: t, w: r - l, h: b - t }
        }
        MonitorGetWorkArea(MonitorGetPrimary(), &l, &t, &r, &b)
        return { x: l, y: t, w: r - l, h: b - t }
    }

    applyLayout() {
        s := this.get(), t := this.target()
        if s.side = "full" {
            x := t.x, w := t.w
        } else {
            w := s.width ? s.width : Round(t.w * 0.45)
            w := Max(Min(w, t.w), Min(OverlayPanel.MIN_W, t.w))
            x := s.side = "left" ? t.x : t.x + t.w - w
        }
        this.gui.Move(x, t.y, w, t.h)
        this.layoutChildren(w, t.h)
        this.applyOpacity(this.pinned ? s.pinOpacity : s.opacity)
    }

    layoutChildren(w, h) {
        g := OverlayPanel.GRIP, side := Ini(this.section, "side", "right")
        full := side = "full"
        gx := side = "left" ? w - g : 0
        this.grip.Move(gx, 0, g, h)
        this.grip.Visible := !full
        left := full || side = "left" ? 0 : g
        right := full || side != "left" ? w : w - g
        rc := Buffer(16)
        NumPut("int", left, "int", 0, "int", right, "int", h, rc)
        try this.wvc.Bounds := rc
    }

    ; drag the grip to resize; width is saved when you let go
    onLButtonDown(wParam, lParam, msg, hwnd) {
        if !this.grip || hwnd != this.grip.Hwnd
            return
        CoordMode("Mouse", "Screen")
        this.gui.GetPos(&x, &y, &w, &h)
        left := Ini(this.section, "side", "right") = "left"
        t := this.target()
        while GetKeyState("LButton", "P") {
            MouseGetPos(&mx)
            nw := left ? mx - x : x + w - mx
            nw := Max(OverlayPanel.MIN_W, Min(t.w, nw))
            this.gui.Move(left ? x : x + w - nw, , nw)
            this.layoutChildren(nw, h)
            Sleep(15)
        }
        this.gui.GetPos(, , &w)
        SetIni(w, this.section, "width")
        return 0
    }

    onSetCursor(wParam, lParam, msg, hwnd) {
        if this.grip && wParam = this.grip.Hwnd {
            DllCall("SetCursor", "ptr", DllCall("LoadCursor", "ptr", 0, "ptr", 32644, "ptr"))   ; IDC_SIZEWE
            return true
        }
    }

    ; -- WebView lifetime ----------------------------------------------------
    ensure() {
        if this.wv
            return true
        if !FileExist(this.updater.appDir "\index.html") {
            if Dialog("The overlay's offline copy of the TWRPG site isn't installed yet. Download it now? (about 10 MB)", "Overlay data", ["Download", "Not now"]) = "Download"
                this.runUpdate(true)
            if !FileExist(this.updater.appDir "\index.html")
                return false
        }
        try {
            this.build()
            return true
        } catch as e {
            this.unload()
            Dialog("WebView2 said: " e.Message "`n`nIs the Microsoft Edge WebView2 Runtime installed?", "Overlay couldn't start")
            return false
        }
    }

    build() {
        g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale", "TW Overlay")
        g.BackColor := "0C0D10"
        g.OnEvent("Close", (*) => this.hide())
        this.grip := g.AddText("x0 y0 w" OverlayPanel.GRIP " h100 Background30343E")
        this.gui := g
        g.Show("Hide w800 h600")

        dataDir := A_AppData "\tw-companion\webview"
        DirCreate(dataDir)
        this.wvc := WebView2.create(g.Hwnd, , 0, dataDir)
        try this.wvc.DefaultBackgroundColor := 0x100D0CFF    ; site --bg #0C0D10 (bytes A,R,G,B): no white flash
        z := Ini(this.section, "zoom", "")
        if z
            this.wvc.ZoomFactor := z + 0
        this.wvc.add_ZoomFactorChanged((c, *) => SetIni(Round(c.ZoomFactor, 2), this.section, "zoom"))

        wv := this.wv := this.wvc.CoreWebView2
        st := wv.Settings
        st.IsStatusBarEnabled := false
        wv.SetVirtualHostNameToFolderMapping(OverlayPanel.HOST, this.updater.webDir, WebView2.HOST_RESOURCE_ACCESS_KIND.ALLOW)
        wv.add_WebMessageReceived((s, args) => this.onMessage(args.TryGetWebMessageAsString()))
        wv.add_NewWindowRequested(ObjBindMethod(this, "onNewWindow"))
        wv.add_ProcessFailed((*) => SetTimer(() => (this.hide(false), this.unload()), -10))
        wv.Navigate(this.startUrl())
    }

    unload() {
        SetTimer(this.watchFn, 0)
        if this.shown
            return
        this.saveUrl()
        try this.wvc.Close()
        try this.gui.Destroy()
        this.gui := 0, this.wvc := 0, this.wv := 0, this.grip := 0
        this.ready := false, this.pinned := false
    }

    startUrl() {
        u := Ini(this.section, "lastUrl", "")
        return InStr(u, "https://" OverlayPanel.HOST "/TWC/") = 1 ? u : OverlayPanel.HOME
    }

    saveUrl() {
        try {
            u := this.wv.Source
            if InStr(u, "https://" OverlayPanel.HOST "/TWC/") = 1
                SetIni(u, this.section, "lastUrl")
        }
    }

    onNewWindow(sender, args) {
        args.Handled := true
        this.openExternal(args.Uri)
    }

    openExternal(url) {
        if RegExMatch(url, "i)^https?://") {
            if this.shown && !this.pinned
                this.hide(false)
            Run(url)
        }
    }

    ; -- page <-> AHK messages -----------------------------------------------
    onMessage(msg) {
        if msg = "ready" {
            this.ready := true
            this.post({ type: "version", version: this.updater.localVersion() })
            for m in this.pending
                this.post(m)
            this.pending := []
        } else if msg = "hide" {
            this.hide()
        } else if msg = "update" {
            SetTimer(() => this.runUpdate(true), -10)
        } else if InStr(msg, "open|") = 1 {
            this.openExternal(SubStr(msg, 6))
        }
    }

    post(obj) {
        if !this.wv || !this.ready {
            this.pending.Push(obj)
            return
        }
        try this.wv.PostWebMessageAsJson(JsonObj(obj))
    }

    ; -- updates -------------------------------------------------------------
    ; manual: started by a button (report "up to date"/errors); otherwise a
    ; background check on startup that only speaks up when there's news.
    runUpdate(manual := false, install := true) {
        if this.updating
            return
        this.updating := true
        try {
            this.postUpdate("checking", manual)
            r := this.updater.check()
            if r.state = "error" {
                this.postUpdate("error", manual, { message: r.message })
                if manual
                    Toast(r.message, "error")
                return
            }
            if r.state = "current" {
                this.postUpdate("current", manual)
                if manual
                    Toast("Overlay data is up to date")
                return
            }
            if !install {
                this.postUpdate("available", manual, { version: r.version })
                Toast("TWRPG overlay data update available - open the overlay or Settings to install")
                return
            }
            this.postUpdate("downloading", manual, { done: 0, total: r.changed })
            onProgress(done, total) {
                this.postUpdate("downloading", manual, { done: done, total: total })
                Toast("Updating overlay data  " done " / " total, "", 0)
            }
            res := this.updater.apply(onProgress, () => this.releaseFiles())
            HideToast()
            if !res.ok {
                this.postUpdate("error", manual, { message: res.message })
                Toast(res.message, "error")
                this.reloadPage()
                return
            }
            this.reloadPage()
            this.post({ type: "version", version: res.version })
            this.postUpdate("current", true)
            Toast("Overlay data updated (" res.version ")")
        } finally {
            this.updating := false
        }
    }

    postUpdate(state, manual, extra := 0) {
        m := { type: "update", state: state, manual: manual ? 1 : 0 }
        if extra
            for k, v in extra.OwnProps()
                m.%k% := v
        if this.wv
            this.post(m)
    }

    ; leave the page so nothing in web\TWC is in use during the folder swap
    releaseFiles() {
        if !this.wv
            return
        this.saveUrl()
        this.ready := false
        try this.wv.Navigate("about:blank")
        Sleep(400)
    }

    reloadPage() {
        if this.wv && this.wv.Source = "about:blank"
            this.wv.Navigate(this.startUrl())
    }

    startupCheck() {
        s := this.get()
        if s.checkOnStart
            this.runUpdate(false, s.autoInstall && !this.shown)
    }
}

; flat object -> JSON (strings and numbers only, which is all we post)
JsonObj(obj) {
    out := ""
    for k, v in obj.OwnProps()
        out .= (out = "" ? "" : ",") JsonStr(k) ":" (IsNumber(v) ? v : JsonStr(v))
    return "{" out "}"
}
JsonStr(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, '"', '\"')
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`t", "\t")
    return '"' s '"'
}
