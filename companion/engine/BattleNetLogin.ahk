#Requires AutoHotkey v2.0
; ============================================================================
;  BattleNetLoginEngine - log in to Battle.net (eurobattle.net) by itself when
;  Warcraft III 1.28f starts: the game module clicks the main menu's
;  Battle.net (the gateway chosen in the game), then on the login screen asks
;  for the account; this types it in through the game's own edit boxes and
;  clicks Logon (layout 24, LoginPass in native\twc-game.cpp). Once per game
;  start; holding Shift at the main menu skips it; a failed logon isn't tried
;  again. Off by default (ini [Battle.net] autoLogin; account = the name).
;  Then (layout 25, on by default: [Battle.net] customGames) the custom games:
;  Custom Game clicked once logged in, and the game named in [Battle.net] game
;  joined by its name (typed into the panel's box, Join clicked); with no name
;  set, or a game selected in the list, the list is left open to pick from.
;  The password is kept in Windows' Credential Manager (generic credential
;  "TW Companion/Battle.net", encrypted for your Windows account), never in
;  the ini. It goes to the module only when the module is at the login
;  screen, and the module wipes its copy once it's typed in.
; ============================================================================
class BattleNetLoginEngine {
    section := "Battle.net"
    static TARGET := "TW Companion/Battle.net"
    answered := 0                   ; the module's blDone we've answered (0 = none)

    __New(gameModule) {
        this.gm := gameModule
        this.tickFn := ObjBindMethod(this, "tick")
        SetTimer(this.tickFn, 100)          ; the module waits on it at the login screen
    }
    enabled => Integer(Ini(this.section, "autoLogin", 0))
    setEnabled(on) {
        SetIni(on ? 1 : 0, this.section, "autoLogin")
        this.tick()
    }
    account => Ini(this.section, "account", "")
    customGames => Integer(Ini(this.section, "customGames", 1))
    setCustomGames(on) => (SetIni(on ? 1 : 0, this.section, "customGames"), this.tick())
    game => Ini(this.section, "game", "")
    setGame(name) {
        global sideGame
        SetIni(Trim(StrReplace(StrReplace(name, "`n"), "`r")), this.section, "game"), this.tick()
        if sideGame && Trim(sideGame.Value) != this.game       ; the sidebar's box shows the same name (not while typing in it: a space at the end stays)
            sideGame.Value := this.game
    }

    ; -- W3L (eurobattle.net's launcher, w3l.exe), from the sidebar --------------
    ; Its place is remembered ([Battle.net] w3l); the first time it's looked for in the game's
    ; folders (the loader's install folders, and their parents), else you pick it once.
    ; pick: choose it again (Shift + click). -> true if it was started
    w3lPath => Ini(this.section, "w3l", "")
    findW3l() {
        global loader
        for dir in loader.installDirs() {
            SplitPath(dir, , &parent)
            for d in [dir, parent]
                if d && FileExist(d "\w3l.exe")
                    return d "\w3l.exe"
        }
        return ""
    }
    launchW3l(pick := false) {
        exe := pick ? "" : this.w3lPath
        if exe = "" || !FileExist(exe)
            exe := pick ? "" : this.findW3l()
        if exe = "" || !FileExist(exe) {
            exe := FileSelect(3, A_ProgramFiles, "Where's w3l.exe (eurobattle.net's launcher)?", "W3L (w3l.exe)")
            if exe = ""
                return false
        }
        SetIni(exe, this.section, "w3l")
        if WinExist(WarcraftIII)
            Toast("Warcraft III is already running: W3L started anyway", "", 4000)
        SplitPath(exe, , &dir)
        try Run('"' exe '"', dir)
        catch as e {
            Toast("W3L couldn't be started: " e.Message, "error")
            return false
        }
        DebugLog("w3l: started " exe)
        return true
    }
    setAccount(name) => SetIni(Trim(StrReplace(StrReplace(name, "`n"), "`r")), this.section, "account")

    ; -- the password in Credential Manager (CREDENTIALW, generic) -------------
    static CredOffsets() {
        p := A_PtrSize, blob := (20 + 2 * p + p - 1) // p * p
        return { target: 8, blobSize: 16 + 2 * p, blob: blob, persist: blob + p, user: blob + p + 8 + 2 * p, size: blob + p + 8 + 3 * p }
    }
    hasPassword() {
        if !DllCall("advapi32\CredReadW", "str", BattleNetLoginEngine.TARGET, "uint", 1, "uint", 0, "ptr*", &pc := 0)
            return false
        DllCall("advapi32\CredFree", "ptr", pc)
        return true
    }
    ; save it ("" removes it): -> true if done
    setPassword(pw) {
        if pw = ""
            return DllCall("advapi32\CredDeleteW", "str", BattleNetLoginEngine.TARGET, "uint", 1, "uint", 0) || !this.hasPassword()
        o := BattleNetLoginEngine.CredOffsets()
        n := StrPut(pw, "UTF-8") - 1
        blob := Buffer(Max(n, 1), 0), StrPut(pw, blob, n, "UTF-8")
        cred := Buffer(o.size, 0)
        NumPut("uint", 1, cred, 4)                                          ; CRED_TYPE_GENERIC
        NumPut("ptr", StrPtr(BattleNetLoginEngine.TARGET), cred, o.target)
        NumPut("uint", n, cred, o.blobSize), NumPut("ptr", blob.Ptr, cred, o.blob)
        NumPut("uint", 2, cred, o.persist)                                  ; CRED_PERSIST_LOCAL_MACHINE
        user := this.account
        NumPut("ptr", StrPtr(user), cred, o.user)
        ok := DllCall("advapi32\CredWriteW", "ptr", cred, "uint", 0)
        DllCall("RtlZeroMemory", "ptr", blob, "uptr", blob.Size)
        DebugLog("battle.net login: password " (ok ? "saved in Credential Manager" : "not saved (CredWrite failed, " A_LastError ")"))
        return ok
    }
    ; the password as UTF-8 into buf (at most max bytes, ending in 0): -> its length, -1 if none saved
    readPassword(buf, max) {
        if !DllCall("advapi32\CredReadW", "str", BattleNetLoginEngine.TARGET, "uint", 1, "uint", 0, "ptr*", &pc := 0)
            return -1
        o := BattleNetLoginEngine.CredOffsets()
        n := Min(NumGet(pc, o.blobSize, "uint"), max - 1)
        DllCall("RtlMoveMemory", "ptr", buf, "ptr", NumGet(pc, o.blob, "ptr"), "uptr", n)
        NumPut("uchar", 0, buf, n)
        DllCall("RtlZeroMemory", "ptr", NumGet(pc, o.blob, "ptr"), "uptr", NumGet(pc, o.blobSize, "uint"))
        DllCall("advapi32\CredFree", "ptr", pc)
        return n
    }

    ; -- with the module (layout 24) -------------------------------------------
    ; the switch pushed; at the login screen (blState 2) the account and password written, once
    tick() {
        if !(v := this.gm.live()) || NumGet(v, Shm.layout, "uint") < 24
            return
        NumPut("uint", this.enabled && this.gm.enabled ? 1 : 0, v, Shm.blOn)
        if NumGet(v, Shm.layout, "uint") >= 25
            NumPut("uint", this.customGames ? 1 : 0, v, Shm.blAfter), StrPut(SubStr(this.game, 1, 31), v + Shm.blGame, 32, "UTF-8")
        if NumGet(v, Shm.blState, "uint") != 2 || !this.enabled
            return this.answered := 0               ; not asking now: the next ask (a new game start too) is answered again
        seq := NumGet(v, Shm.blSeq, "int")
        if seq != NumGet(v, Shm.blDone, "int")
            return                                  ; written, the module hasn't used it yet
        if this.answered && this.answered = seq + 1
            return
        StrPut(SubStr(this.account, 1, 31), v + Shm.blAccount, 32, "UTF-8")
        if this.readPassword(v + Shm.blPassword, 64) < 0
            NumPut("uchar", 0, v, Shm.blPassword)   ; none saved: the module leaves the login to you
        NumPut("int", seq + 1, v, Shm.blSeq)        ; last: the module acts on it
        this.answered := seq + 1
        DebugLog("battle.net login: the module is at the login screen: account '" this.account "' handed over")
    }

    statusText() {
        if !this.enabled
            return "Off"
        if this.account = "" || !this.hasPassword()
            return "On · set your account and password (Options)"
        if !this.gm.enabled
            return "On · needs the game module (top of this page)"
        s := this.gm.state(), v := this.gm.live()
        if !v || s.layout < 24
            return "On · " this.account " · when a 1.28f game starts"
        st := NumGet(v, Shm.blState, "uint")
        return "On · " this.account " · " (st = 1 ? "connecting to Battle.net" : st = 2 ? "at the login screen" : st = 3 ? "logged in (Logon clicked)"
            : st = 6 ? "logged in, the custom games open" : st = 7 ? "joining " this.game : st = 8 ? "logged in, the custom games left to you"
            : st = 4 ? "left to you this time (see the module log)" : st = 5 ? "refused (see the module log)" : "waiting for the main menu")
    }
}
