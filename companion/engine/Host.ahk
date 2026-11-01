#Requires AutoHotkey v2.0
; ============================================================================
;  HostEngine - whisper a host bot to open a lobby.
;  Bots are TWRPG's known ones plus any you add; each keeps its own trigger
;  and extra commands. In Warcraft III chat (handed over by the main script's
;  Enter tracking, like the loader's -l):
;    -h / -host [bot] [game name]       private lobby
;    -hp / -hostpub [bot] [game name]   public lobby
;  The bot is matched by name (exact, starts with, contains: "lee" = leebot);
;  left out, the selected bot and the last game name are used.
; ============================================================================
class HostEngine {
    section := "Host"
    static BOTS := ["awebo", "macibot", "geybot", "leebot", "yozorabot", "spookybot", "stonebot"]
    static CMD := "i)^\s*-(h|host|hp|hostpub)(?:\s+(.*?))?\s*$"

    ; -- bots ------------------------------------------------------------------
    ; the known bots, then the ones you added
    bots() {
        out := [], seen := Map(), raw := Ini(this.section, "botNameList", "")
        for list in [HostEngine.BOTS, raw ? StrSplit(raw, "|") : []]
            for b in list
                if b != "" && !seen.Has(StrLower(b))
                    seen[StrLower(b)] := 1, out.Push(b)
        return out
    }
    isKnown(bot) {
        for b in HostEngine.BOTS
            if b = bot
                return true
        return false
    }
    selected => Ini(this.section, "botName", "geybot")
    select(bot) => SetIni(bot, this.section, "botName")
    gameName => Ini(this.section, "gameName", "sey")

    addBot(name) {
        name := Trim(StrReplace(name, "|"))
        if name = ""
            return ""
        for b in this.bots()
            if b = name
                return b
        raw := Ini(this.section, "botNameList", "")
        SetIni(raw = "" ? name : raw "|" name, this.section, "botNameList")
        return name
    }
    removeBot(name) {
        list := []
        for b in StrSplit(Ini(this.section, "botNameList", ""), "|")
            if b != "" && b != name
                list.Push(b)
        SetIni(Join("|", list*), this.section, "botNameList")
        if this.selected = name
            this.select(HostEngine.BOTS[1])
    }

    ; a bot's own trigger and extra commands (trigger / exBefore / exAfter);
    ; until set, the page's old shared values
    field(bot, name) {
        static shared := Map("trigger", "!", "exBefore", "", "exAfter", "")
        return Ini(this.section, name "_" StrLower(bot), Ini(this.section, name, shared[name]))
    }
    setField(bot, name, value) => SetIni(value, this.section, name "_" StrLower(bot))

    ; "lee" -> "leebot": exact name, then starts with, then contains ("" = none)
    resolve(q) {
        q := StrLower(Trim(q))
        if q = ""
            return ""
        for rule in [1, 2, 3]
            for b in this.bots() {
                n := StrLower(b)
                if rule = 1 ? n == q : rule = 2 ? SubStr(n, 1, StrLen(q)) == q : InStr(n, q)
                    return b
            }
        return ""
    }

    increment(name) {
        if RegExMatch(name, "^(.*?)(\d+)$", &m)
            return m[1] Format("{:0" StrLen(m[2]) "}", Integer(m[2]) + 1)
        return name "1"
    }

    ; -- chat commands -----------------------------------------------------------
    isCommand(line) => RegExMatch(line, HostEngine.CMD)

    ; -h lee sey: leebot, game "sey". One word that isn't a bot is the game name.
    command(line) {
        RegExMatch(line, HostEngine.CMD, &m)
        private := m[1] = "h" || m[1] = "host"
        args := Trim(m[2]), bot := "", game := ""
        if args != "" {
            parts := StrSplit(args, " ", , 2)
            if bot := this.resolve(parts[1])
                game := parts.Length > 1 ? Trim(parts[2]) : ""
            else
                game := args
        }
        return this.doHost(private, bot, game)
    }

    ; -- hosting -----------------------------------------------------------------
    doHost(private, bot := "", game := "") {
        bot := bot != "" ? bot : this.selected
        game := game != "" ? game : this.gameName
        trig := this.field(bot, "trigger")
        if bot = "" || game = "" {
            Push("toast", { kind: "error", msg: "Pick a bot and a game name on the Host page" })
            return { error: "missing fields" }
        }
        if !FocusWarcraft() {
            Push("toast", { kind: "error", msg: "Warcraft III not found" })
            return { error: "no wc3" }
        }
        ; what -h alone uses next time
        this.select(bot), SetIni(game, this.section, "gameName")
        HideMainWindow()
        exBefore := this.field(bot, "exBefore"), exAfter := this.field(bot, "exAfter")
        if exBefore != ""
            wc3Chat("/w " bot " " trig exBefore)
        wc3Chat("/w " bot " " trig (private ? "priv" : "pub") " " game)
        if exAfter != ""
            wc3Chat("/w " bot " " trig exAfter)
        wc3Chat("Game Name: " game)
        Push("toast", { kind: "ok", msg: "Hosting " (private ? "private" : "public") " lobby on " bot ": " game })
        return { ok: 1 }
    }
}
