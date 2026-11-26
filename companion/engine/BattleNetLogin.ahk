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
;  "TW Companion/Battle.net/<account>", encrypted for your Windows account),
;  never in the ini. It goes to the module only when the module is at the
;  login screen, and the module wipes its copy once it's typed in.
;  Several accounts (the user, 2026-11-01): [Battle.net] accounts (a|b), each
;  with its own password; the one picked ([Battle.net] account) is the one the
;  next login uses. The old single entry "TW Companion/Battle.net" moves over
;  to the account's own the first time (migrate).
; ============================================================================
class BattleNetLoginEngine {
    section := "Battle.net"
    static TARGET := "TW Companion/Battle.net"
    answered := 0                   ; the module's blDone we've answered (0 = none)

    __New(gameModule) {
        this.gm := gameModule
        this.migrate()
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
    ; Its place is set in Settings ([Battle.net] w3l: Change picks it, Auto-detect looks in the
    ; game's folders, the loader's install folders and their parents). The sidebar's button
    ; starts it; with none set it looks once by itself, else it asks you to set it in Settings.
    w3lPath => Ini(this.section, "w3l", "")
    w3lAuto => Integer(Ini(this.section, "w3lAuto", 0))         ; 1: found by Auto-detect, 0: chosen by you
    ; Settings' Change: pick it -> true if one was picked
    pickW3l() {
        start := this.w3lPath != "" ? this.w3lPath : A_ProgramFiles
        exe := FileSelect(3, start, "Where's w3l.exe (eurobattle.net's launcher)?", "W3L (w3l.exe)")
        if exe = ""
            return false
        SetIni(exe, this.section, "w3l"), SetIni(0, this.section, "w3lAuto")
        return true
    }
    ; Settings' Auto-detect -> true if found (then saved)
    autoW3l() {
        if (exe := this.findW3l()) = ""
            return false
        SetIni(exe, this.section, "w3l"), SetIni(1, this.section, "w3lAuto")
        return true
    }
    ; the arguments it's started with (WFE's Launcher > Launch Arguments: -window, -nativefullscr, -opengl...;
    ; W3L hands them on to the game), [Battle.net] w3lArgs, one line
    w3lArgs => Ini(this.section, "w3lArgs", "")
    setW3lArgs(t) => SetIni(Trim(StrReplace(StrReplace(t, "`n", " "), "`r")), this.section, "w3lArgs")
    ; Settings' line about it
    w3lStatus() => this.w3lPath = "" ? "not set: Change or Auto-detect" : !FileExist(this.w3lPath) ? "not there any more: Change or Auto-detect"
        : this.w3lAuto ? "found automatically" : "chosen by you"
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
    ; the sidebar's button -> true if it was started
    launchW3l() {
        exe := this.w3lPath
        if (exe = "" || !FileExist(exe)) && this.autoW3l()
            exe := this.w3lPath
        if exe = "" || !FileExist(exe) {
            Toast("W3L isn't set: Settings > W3L (Change or Auto-detect)", "", 5000)
            return false
        }
        if WinExist(WarcraftIII)
            Toast("Warcraft III is already running: W3L started anyway", "", 4000)
        SplitPath(exe, , &dir)
        args := this.w3lArgs
        try Run('"' exe '"' (args != "" ? " " args : ""), dir)
        catch as e {
            Toast("W3L couldn't be started: " e.Message, "error")
            return false
        }
        DebugLog("w3l: started " exe (args != "" ? " " args : ""))
        return true
    }
    ; -- accounts ---------------------------------------------------------------
    accounts() {
        out := []
        for n in StrSplit(Ini(this.section, "accounts", ""), "|")
            if Trim(n) != ""
                out.Push(Trim(n))
        if !out.Length && this.account != ""
            out.Push(this.account)                  ; (before the list: the one account)
        return out
    }
    hasAccount(name) {
        for n in this.accounts()
            if n = name
                return true
        return false
    }
    static AccountName(name) => Trim(RegExReplace(name, "[|\r\n]"))
    ; pick one for the next login, added to the list if it's new: -> its name, "" if empty
    setAccount(name) {
        name := BattleNetLoginEngine.AccountName(name)
        if name = ""
            return ""
        list := this.accounts()
        if !this.hasAccount(name)
            list.Push(name)
        SetIni(Join("|", list*), this.section, "accounts")
        SetIni(name, this.section, "account")
        this.answered := 0
        DebugLog("battle.net login: account '" name "' picked")
        return name
    }
    ; its password gone too; the one picked: the first other takes over (none: no account)
    removeAccount(name) {
        global iniFile
        if !this.hasAccount(name)
            return false
        this.setPassword("", name)
        rest := []
        for n in this.accounts()
            if n != name
                rest.Push(n)
        SetIni(Join("|", rest*), this.section, "accounts")
        if this.account = name {
            if rest.Length
                SetIni(rest[1], this.section, "account")
            else
                try IniDelete(iniFile, this.section, "account")
        }
        return true
    }
    ; the old single password ("TW Companion/Battle.net") into the account's own entry, once
    migrate() {
        if A_ScriptName = "_preview.ahk" && BattleNetLoginEngine.TARGET = "TW Companion/Battle.net"   ; (checks, previews: never the real entry)
            return
        acc := this.account
        if acc = "" || BattleNetLoginEngine.CredHas(this.target(acc)) || !BattleNetLoginEngine.CredHas(BattleNetLoginEngine.TARGET)
            return
        buf := Buffer(64, 0), n := BattleNetLoginEngine.CredRead(BattleNetLoginEngine.TARGET, buf, 64)
        if n >= 0 && BattleNetLoginEngine.CredWrite(this.target(acc), StrGet(buf, n, "UTF-8"), acc)
            DllCall("advapi32\CredDeleteW", "str", BattleNetLoginEngine.TARGET, "uint", 1, "uint", 0)
        DllCall("RtlZeroMemory", "ptr", buf, "uptr", buf.Size)
        list := this.accounts()
        if !this.hasAccount(acc)
            list.Push(acc)
        SetIni(Join("|", list*), this.section, "accounts")
        DebugLog("battle.net login: the saved password moved to account '" acc "'s own entry")
    }
    target(acc) => BattleNetLoginEngine.TARGET "/" acc

    ; -- the password in Credential Manager (CREDENTIALW, generic) -------------
    static CredOffsets() {
        p := A_PtrSize, blob := (20 + 2 * p + p - 1) // p * p
        return { target: 8, blobSize: 16 + 2 * p, blob: blob, persist: blob + p, user: blob + p + 8 + 2 * p, size: blob + p + 8 + 3 * p }
    }
    ; an account's password (the one picked by default)
    hasPassword(acc := "") => (acc := acc != "" ? acc : this.account) != "" && BattleNetLoginEngine.CredHas(this.target(acc))
    ; save it ("" removes it): -> true if done
    setPassword(pw, acc := "") {
        acc := acc != "" ? acc : this.account
        if acc = ""
            return false
        if pw = ""
            return DllCall("advapi32\CredDeleteW", "str", this.target(acc), "uint", 1, "uint", 0) || !this.hasPassword(acc)
        ok := BattleNetLoginEngine.CredWrite(this.target(acc), pw, acc)
        DebugLog("battle.net login: password for '" acc "' " (ok ? "saved in Credential Manager" : "not saved (CredWrite failed, " A_LastError ")"))
        return ok
    }
    static CredHas(target) {
        if !DllCall("advapi32\CredReadW", "str", target, "uint", 1, "uint", 0, "ptr*", &pc := 0)
            return false
        DllCall("advapi32\CredFree", "ptr", pc)
        return true
    }
    static CredWrite(target, pw, user) {
        o := BattleNetLoginEngine.CredOffsets()
        n := StrPut(pw, "UTF-8") - 1
        blob := Buffer(Max(n, 1), 0), StrPut(pw, blob, n, "UTF-8")
        cred := Buffer(o.size, 0)
        NumPut("uint", 1, cred, 4)                                          ; CRED_TYPE_GENERIC
        NumPut("ptr", StrPtr(target), cred, o.target)
        NumPut("uint", n, cred, o.blobSize), NumPut("ptr", blob.Ptr, cred, o.blob)
        NumPut("uint", 2, cred, o.persist)                                  ; CRED_PERSIST_LOCAL_MACHINE
        NumPut("ptr", StrPtr(user), cred, o.user)
        ok := DllCall("advapi32\CredWriteW", "ptr", cred, "uint", 0)
        DllCall("RtlZeroMemory", "ptr", blob, "uptr", blob.Size)
        return ok
    }
    ; the picked account's password as UTF-8 into buf (at most max bytes, ending in 0): -> its length, -1 if none saved
    readPassword(buf, max) => this.account = "" ? -1 : BattleNetLoginEngine.CredRead(this.target(this.account), buf, max)
    static CredRead(target, buf, max) {
        if !DllCall("advapi32\CredReadW", "str", target, "uint", 1, "uint", 0, "ptr*", &pc := 0)
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
