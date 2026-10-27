// ============================================================================
//  twc-game.dll - the TW Companion's in-game module for Warcraft III 1.28f.
//  Loaded into the game by twc-inject.exe when Settings > Game module is on.
//  It does nothing unless the game is exactly 1.28f (build 7680): every
//  address it uses belongs to that build. Before it touches anything it
//  probes those addresses (Probe); if the probe fails it stays idle.
//
//  It talks to the companion through shared memory "Local\TWC_Game_<pid>"
//  (the layout is Shared below; engine/GameModule.ahk reads it): a heartbeat,
//  the game build, the probe result, whether the game waits for a target,
//  and quickcast requests (the companion sends the ability's key and asks
//  for a click, and sets the event "Local\TWC_GameQc_<pid>"; the module
//  clicks the moment the game wants a target).
//  It logs to twc-game.log next to this DLL.
//
//  Every feature is off until the companion turns it on. Quickcast only reads
//  the game UI (through the game's own getter) and clicks with SendInput, as
//  WFE does; game calls that change something run on the game's thread. The
//  writes into the game's code and data: five entries of the health bar's
//  vtable (update, set-unit, hide, show, dtor), the portrait update's entry
//  or its two call sites, the info panel icons' update entries (tooltips),
//  the camera's call to its projection (widescreen), the menu animation's
//  first 6 bytes (Fast menu, the one detour), the FPS unlock's one byte and
//  the latency getters' first 6 bytes; each is checked to still be the
//  game's (or ours) before it's changed, and put back when turned off and on
//  unload (RestoreAll). Frames it adds (timers in the game, health numbers,
//  mana bars, the portrait text) are made with the game's own Storm.dll and
//  constructors; frames it moves or hides are put back by their passes.
//
//  Build: native\build.bat (32-bit, MSVC). Tests: native\tests\run-tests.bat.
// ============================================================================
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <math.h>
#include <intrin.h>
#include <initializer_list>

#pragma comment(lib, "version.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "winmm.lib")

static const DWORD BUILD_128F = 7680;

#pragma pack(push, 4)
struct Shared {             // keep in step with engine/GameModule.ahk
    DWORD magic;            // 'TWC1'
    DWORD layout;           // 24
    DWORD build;            // the game's build number (7680 = 1.28f)
    DWORD status;           // 0 starting, 1 running, 2 not 1.28f (idle), 3 stopping / unloaded, 4 unloading (layout 13), 5 can't unload (see the log)
    DWORD heartbeat;        // GetTickCount() at the last update
    DWORD targeting;        // 1 while the game waits for a target
    // layout 2
    DWORD probe;            // 0 not run, 1 passed, 2 failed (probeText says why): nothing acts unless 1
    DWORD ui;               // 0 no game UI seen yet, 1 seen and it checked out
    volatile LONG qcSeq;    // companion: +1 per quickcast request (written last)
    DWORD qcUntil;          // companion: GetTickCount() deadline of the request (0 = cancelled)
    DWORD qcFlags;          // companion: 1 = keep Shift down (a queued order)
    volatile LONG qcDone;   // module: the request it answered
    DWORD qcResult;         // module: 1 clicked, 2 no target wanted in time, 3 the game wasn't in front
    DWORD qcMs;             // module: ms from the request to the click
    char probeText[112];    // "passed" or why it failed
    // layout 3: cooldown and buff timers of the selected unit (ReadTimers)
    DWORD tmWant;           // companion: 1 = keep them up to date (its timer display is on)
    volatile LONG tmSeq;    // module: +1 after each update
    DWORD tmFlags;          // module: 1 cooldowns read, 2 buffs read, 4 items read (layout 11), 0x100 a game getter was refused (see the log)
    float cdLeft[12];       // command card, row by row (4 a row): seconds of cooldown left, 0 = ready / none
    float cdTotal[12];      //   and the full cooldown (0 = unknown)
    DWORD buffCount;        // buff bar slots read (<= 16)
    float buffLeft[16];     // buff bar, left to right: seconds left (0 = none or no timer)
    float buffTotal[16];    //   and its full duration (0 = unknown)
    DWORD buffFlags[16];    //   1 a buff is shown, 2 it's an aura
    DWORD buffId[16];       //   its type id ('Bxxx', 0 = unknown)
    // layout 4: commands run on the game's thread (RunCommand)
    volatile LONG cmdSeq;   // companion: +1 per command (written last)
    DWORD cmd;              // companion: 1 clear messages, 2 clear chat, 3 multiboard minimise / maximise,
                            //   4 autocast toggle on the command card slot cmdArg (unused since 2026-10-26),
                            //   5 the cooldown ping of the button under the cursor (layout 18: pingText)
    volatile LONG cmdDone;  // module: the command it answered
    DWORD cmdResult;        // module: 1 done, 2 refused (see the log), 3 the game thread didn't run it in time
    // layout 5: health bar size (BarsPass)
    DWORD hbOn;             // companion: 1 = keep the bars at the sizes below (0 = put them back once)
    float hbHeight;         // companion: height, times the game's own (1 = unchanged)
    float hbWidth;          // companion: width, times the game's own (experimental)
    DWORD hbState;          // module: 0 not yet, 1 applied, 2 no health bars seen, 3 refused (see the log)
    float hbDefHeight;      // module: the game's own bar height / width, as first seen
    float hbDefWidth;
    DWORD hbCount;          // module: bars resized in the last pass
    // layout 6: health bar colours (BarUpdateHook)
    DWORD hcOn;             // companion: 1 = colour the bars
    DWORD hcMode;           // companion: 0 by owner, 1 by health
    DWORD hcColours[5];     // companion: 0xAARRGGBB for yours, allies, enemies, neutral hostile, neutral passive (alpha 0: the owner's player colour, layout 12)
    DWORD hcState;          // module: 0 off, 1 on (the bar update is ours), 2 refused (see the log)
    // layout 7: widescreen and FPS unlock (DisplayPass)
    DWORD wsOn;             // companion: 1 = widescreen in games
    DWORD wsState;          // module: 0 off, 1 on in this game, 2 on, waiting for a game, 3 refused (see the log)
    DWORD fpsOn;            // companion: 1 = FPS unlocked
    DWORD fpsLimit;         // companion: the frame rate ceiling (64 at least, as WFE)
    DWORD fpsState;         // module: 0 off, 1 unlocked, 3 refused (see the log)
    DWORD fpsGameLimit;     // module: the game's own frame limit setting, as first read (0 = not read)
    // layout 8: self-cast (WatchSelfCast) and the autocast toggle (command 4)
    DWORD scHeld;           // companion: 0 self-cast off, 1 on, 2 on and its key held (the companion keeps the key from the game)
    DWORD scState;          // module: 0 off, 1 watching, 3 refused (see the log)
    DWORD scCount;          // module: self-casts done
    DWORD cmdArg;           // companion: command 4's command card slot (0-11, row by row)
    // layout 9: lobby latency (LatencyPass)
    DWORD latOn;            // companion: 1 = games you host use latMs
    DWORD latMs;            // companion: the latency, ms (5-1000)
    DWORD latState;         // module: 0 the game's own, 1 set, 3 refused (see the log)
    DWORD latGame[3];       // module: what the game's LAN / single player / Battle.net getters returned (-1 = faulted)
    // layout 10: hiding parts of the UI (UiHidePass)
    DWORD uiHide;           // companion: frames to hide, bits: 1 time of day, 2 minimap, 4 upper menu bar, 8 resource bar, 0x10 idle workers, 0x20 the console's background, 0x40 the buff bar
    DWORD uiState;          // module: frames hidden now (same bits); 0x80000000 = one was refused (see the log)
    // layout 11: frames added to the game (Storm.dll's SMemAlloc)
    DWORD stState;          // module: 0 not checked yet, 1 the game's Storm.dll checks out, 2 none loaded in the game, 3 refused (see the log)
    DWORD itOn;             // companion: timers drawn in the game (TimerFramesPass), bits: 1 cooldowns (card, items), 2 buffs
    DWORD itState;          // module: 0 off, 1 on, 2 waiting (no game yet, or no Storm.dll), 3 refused (see the log)
    DWORD frCount;          // module: text frames made in this game
    DWORD hnOn;             // companion: 1 = health numbers over the health bars (BarExtras)
    DWORD hnMode;           // companion: 0 current, 1 current / max, 2 percent
    DWORD hnState;          // module: as itState
    DWORD mbOn;             // companion: 1 = mana bars under the health bars of units with mana
    float mbHeight;         // companion: the mana bar's height, times the health bar's (0.25-2)
    DWORD mbState;          // module: as itState
    DWORD hnCount;          // module: health numbers in use
    DWORD mbCount;          // module: mana bars in use
    float itemLeft[6];      // module: inventory slots (in the game's order): seconds of cooldown left (read with the others)
    float itemTotal[6];     //   and the full cooldown
    DWORD prOn;             // companion: 1 = the portrait's HP / mana lines with regen (PortraitHook)
    DWORD prMode;           // companion: 1 = and the percent
    DWORD prState;          // module: 0 off, 1 on, 2 waiting for a game, 3 refused (see the log)
    // layout 12
    float mbWidth;          // companion: the mana bar's width, times the health bar's (0.25-2; 0 = 1)
    // layout 13: a newer module replaces this one while the game runs
    DWORD unload;           // companion: 1 = turn everything off, give it all back and unload (status 4, then 3)
    DWORD stamp;            // module: its own build stamp (the PE header's TimeDateStamp)
    // layout 14: WFE's widescreen UI layout (UiLayoutPass)
    DWORD ulOn;             // companion: 1 = lay the UI out for a wide window as WFE's Upgraded UI does; | 2 = the buff bar raised (WFE's [BUFFUI] ISUPGRADEDBUFFBAR)
    DWORD ulState;          // module: 0 off, 1 laid out, 2 waiting (no game, or the window isn't wide), 3 refused (see the log)
    DWORD ulCount;          // module: frames moved in this game
    // layout 15: detailed tooltips (TooltipHook)
    DWORD ttOn;             // companion: 1 = the info panel's damage / armor tooltips get WFE-style extra lines
    DWORD ttState;          // module: 0 off, 1 on, 3 refused (see the log)
    // layout 16: fast menus (FastMenuPass)
    DWORD fmOn;             // companion: 1 = the menus' transitions near instant, as WFE's Fast Menu
    DWORD fmState;          // module: 0 off, 1 on, 3 refused (see the log)
    // layout 17: the game start countdown of games you host (CountdownPass)
    DWORD csOn;             // companion: 1 = games you host start csSecs after Start Game
    float csSecs;           // companion: the seconds (0-6; WFE's [DELAY] GAMESTART, default 0)
    DWORD csState;          // module: 0 the game's own, 1 set, 3 refused (see the log)
    float csGame;           // module: the game's own countdown, as read (0 = not read)
    // layout 18: allies' abilities on the command card, and cooldown pings
    DWORD alOn;             // companion: 1 = allied units' abilities and cooldowns on the command card (WFE's ISALLYABILITYBAR)
    DWORD alState;          // module: 0 off, 1 on, 3 refused (see the log)
    DWORD pingOn;           // companion: 1 = keep `hover` up to date (the ping key is on)
    DWORD hover;            // module: 1 the cursor is on a command card or inventory button
    char pingText[128];     // module: command 5's message ("" = nothing to ping)
    // layout 19: WFE's DISPLAYMINUTES, and where the chat opens for a ping
    DWORD tmMinutes;        // companion: m:ss from a minute up, bits: 1 cooldowns ([COOLDOWNUI] DISPLAYMINUTES), 2 buffs ([BUFFUI]); off (WFE's default): whole seconds
    DWORD pingChat;         // module, with command 5: where Enter opens the chat (the Chat dialog's recipient): 0 unknown, 1 all, 2 allies, 3 observers, 4 one player
    // layout 20: how the cooldowns drawn in the game look (every text drawn has a black outline)
    float cdSize;           // companion: their size, times 0.014 (0.75-1.5; 0 = 1)
    float cdGold;           // companion: gold from this many seconds left down (0 = always white)
    DWORD cdReady;          // companion: 1 = "Ready" in green for half a second when one is over
    // layout 21
    DWORD cdNoBadge;        // companion, while cooldowns are drawn, bits: 1 hide the game's number badge on command card buttons (maps' counters), 2 hide the game's cooldown sweep (the clock) on command card and inventory buttons, 4 our cooldown ring around them
    // layout 22: your hero's buffs, read from the unit itself, whatever is selected (ReadHeroBuffs), and how the buff seconds look
    DWORD hrWant;           // companion: 1 = read them too (with the other timers: tmWant on as well)
    DWORD hrHero;           // module: the hero's type id ('Hpal'; 0 = no hero of yours found)
    DWORD hrAlive;          // module: 1 the hero is alive (its health > 0), 0 dead or none (no alerts then)
    DWORD hrCount;          // module: buffs below (<= 24), in the unit's own order
    DWORD hrId[24];         //   the rawcode ([buff+0x34])
    float hrLeft[24];       //   seconds left (0 = no timer)
    float hrTotal[24];      //   the full time (0 = unknown)
    DWORD hrFlags[24];      //   1 a buff, 2 an aura, 4 positive (the game shows its name green), 8 hrName is the game's
    char hrName[24][48];    //   the game's name for it (its Bufftip, colour codes taken out; UTF-8), "" = none found
    float bfSize;           // companion: the buff seconds' size, times WFE's 0.013 (0.75-1.5; 0 = 1)
    float bfGold;           // companion: gold from this many seconds left down (0 = always white)
    DWORD bfOpts;           // companion, bits: 1 seconds on auras too (WFE's ISDRAWAURADURATION), 2 our countdown ring around the buffs
    // layout 23: a bigger buff bar (BuffBarSizePass; with the widescreen UI on, its UlBuffs)
    float bbScale;          // companion: the buff bar and its icons, times the game's size (1-2; 0 or 1 = the game's own)
    DWORD bbState;          // module: 0 the game's own, 1 bigger now, 2 waiting (no buff bar yet), 3 refused (see the log)
    // layout 24: Battle.net login at game start (LoginPass)
    DWORD blOn;             // companion: 1 = at the main menu go to Battle.net and log in (once per game start; Shift held skips)
    DWORD blState;          // module: 0 idle, 1 Battle.net clicked, 2 at the login screen: asking for the account, 3 Logon clicked, 4 left to you (the log says why), 5 refused
    volatile LONG blSeq;    // companion: +1 once blAccount / blPassword are written (written last)
    volatile LONG blDone;   // module: the blSeq it used
    char blAccount[32];     // companion: the account name (UTF-8)
    char blPassword[64];    // companion: its password, only while blState is 2; the module wipes it once typed in
};
#pragma pack(pop)

// -- 1.28f addresses ---------------------------------------------------------
// Offsets into the game module (from the WFE study, ahk/unryze-wfe-tools/
// FINDINGS.md), each checked in the 1.28f Game.dll (test_gamedll). WFE's base
// is GetModuleHandle("Game.dll"), or the exe when there's no Game.dll (the
// user's 1.28f has a Game.dll); the same rule is used here (Probe).
static const DWORD RVA_GET_UI = 0x3a0b70;       // CGameUI *__fastcall GetGameUI(0, 0): the game UI or 0
static const DWORD RVA_UI_VTABLE = 0xaaa730;    // CGameUI's vtable (WFE files it under "CGameUI")
static const DWORD UI_MODE = 0x1b4;             // CGameUI: the current input mode
static const DWORD UI_TARGET_MODE = 0x210;      // CGameUI: the "pick a target" mode; current == it -> targeting

// The functions later features will use. Probe only checks that each one is
// code in the game module; nothing calls them yet.
struct Known { const char *name; DWORD rva; };
static const Known KNOWN[] = {
    { "game UI getter (targeting check)", RVA_GET_UI },
    { "key input dispatch",                0x3a5ab0 },
    { "game start countdown",              0x324100 },
    { "message frame clear",               0x144750 },
    { "multiboard state 0",                0x4127d0 },
    { "multiboard state 1",                0x4128d0 },
    { "camera projection (widescreen)",    0x1554f0 },
    { "its call (widescreen)",             0x1e0829 },
    { "FPS limiter function",              0x0a5090 },
    { "FPS limiter (patched byte)",        0x0a50ba },
    { "game options",                      0x06bf60 },
    { "game option set",                   0x06dbc0 },
    { "game option apply",                 0x06b3a0 },
    { "game option get",                   0x06c030 },
    { "control click (self-cast)",         0x1407b0 },
    { "latency getter (LAN)",              0x924730 },
    { "latency getter (single player)",    0x929670 },
    { "latency getter (Battle.net)",       0x925f00 },
    { "health bar draw",                   0x09b9d0 },
    { "bar visibility getter",             0x35fcc0 },
    { "bar update",                        0x2dd7d0 },
    { "bar position setter",               0x86a3e0 },
    { "ability display update",            0x6b2700 },
    { "ability matcher",                   0x6a2d90 },
    { "unit regen update",                 0x3e1cb0 },
};

typedef void *(__fastcall *GetUiFn)(int, int);

static HMODULE g_self;
static HANDLE g_map;
static HANDLE g_wake;           // "Local\TWC_GameQc_<pid>": the companion sets it after a request
static Shared *g_shared;
static volatile LONG g_stop;
static char g_logPath[MAX_PATH];
static BYTE *g_base;            // the game module the offsets belong to
static GetUiFn g_getUi;         // set only once the probe passed
static DWORD g_uiVtable;
static DWORD g_imageSize;
static BYTE *g_ui;              // the game UI from the last Targeting() that checked out (0 = none)

static void Log(const char *fmt, ...) {
    FILE *f = nullptr;
    if (fopen_s(&f, g_logPath, "a") || !f)
        return;
    SYSTEMTIME t;
    GetLocalTime(&t);
    fprintf(f, "%04d-%02d-%02d %02d:%02d:%02d.%03d  ", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
    va_list a;
    va_start(a, fmt);
    vfprintf(f, fmt, a);
    va_end(a);
    fputc('\n', f);
    fclose(f);
}

// the game's build: the low word of its file version ("1.28.5.7680" -> 7680)
static DWORD GameBuild() {
    char exe[MAX_PATH];
    GetModuleFileNameA(nullptr, exe, MAX_PATH);
    DWORD h = 0, n = GetFileVersionInfoSizeA(exe, &h);
    if (!n)
        return 0;
    void *buf = HeapAlloc(GetProcessHeap(), 0, n);
    DWORD build = 0;
    VS_FIXEDFILEINFO *fi = nullptr;
    UINT len = 0;
    if (buf && GetFileVersionInfoA(exe, 0, n, buf) && VerQueryValueA(buf, "\\", (void **)&fi, &len) && fi)
        build = LOWORD(fi->dwFileVersionLS);
    if (buf)
        HeapFree(GetProcessHeap(), 0, buf);
    return build;
}

// -- memory checks (nothing here faults: every page is queried first) ----------
static const DWORD EXEC = PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY;
static const DWORD READ = EXEC | PAGE_READONLY | PAGE_READWRITE | PAGE_WRITECOPY;

static bool PageIs(const void *p, DWORD kinds) {
    MEMORY_BASIC_INFORMATION mi;
    return VirtualQuery(p, &mi, sizeof(mi)) && mi.State == MEM_COMMIT && (mi.Protect & kinds) && !(mi.Protect & PAGE_GUARD);
}
static DWORD ImageSize(BYTE *mod) {
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)mod;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE)
        return 0;
    IMAGE_NT_HEADERS32 *nt = (IMAGE_NT_HEADERS32 *)(mod + dos->e_lfanew);
    return nt->Signature == IMAGE_NT_SIGNATURE ? nt->OptionalHeader.SizeOfImage : 0;
}
static bool InImage(DWORD addr, DWORD size) {
    return addr >= (DWORD)g_base && addr - (DWORD)g_base < size;
}

// bytes at a module offset, if that memory is code ("" if not)
static void Bytes(BYTE *mod, DWORD rva, char *out, size_t n) {
    out[0] = 0;
    BYTE *p = mod + rva;
    if (!PageIs(p, EXEC) || !PageIs(p + 7, EXEC))
        return;
    size_t o = 0;
    for (int i = 0; i < 8 && o + 4 < n; i++)
        o += sprintf_s(out + o, n - o, "%02X ", p[i]);
}

// The MSVC RTTI class name of a vtable (".?AVCGameUI@@"), or "" if the game
// has no RTTI there: vtable[-1] -> CompleteObjectLocator -> TypeDescriptor.
static void RttiName(DWORD vt, DWORD size, char *out, size_t n) {
    out[0] = 0;
    DWORD *slot = (DWORD *)vt - 1;
    if (!PageIs(slot, READ))
        return;
    DWORD col = *slot;
    if (!InImage(col, size) || !PageIs((void *)col, READ) || !PageIs((void *)(col + 15), READ) || ((DWORD *)col)[0] != 0)
        return;
    DWORD td = ((DWORD *)col)[3];
    if (!InImage(td, size) || !PageIs((void *)td, READ) || !PageIs((void *)(td + 8 + 63), READ))
        return;
    const char *name = (const char *)(td + 8);
    if (name[0] != '.' || name[1] != '?')
        return;
    strncpy_s(out, n, name, _TRUNCATE);
}

// -- the probe ------------------------------------------------------------------
// Which module the offsets belong to, and whether they look right for 1.28f.
// Logged in full; the companion shows the verdict. Nothing is called here.
static bool Probe(char *why, size_t n) {
    HMODULE exe = GetModuleHandleA(nullptr), game = GetModuleHandleA("Game.dll");
    g_base = (BYTE *)(game ? game : exe);
    Log("modules: Warcraft III.exe at %p, Game.dll at %p; using %s", exe, game, game ? "Game.dll" : "the exe");
    DWORD size = g_imageSize = ImageSize(g_base);
    Log("  image size %08lX", size);
    if (size <= RVA_UI_VTABLE + 16) {
        sprintf_s(why, n, "the game module is too small (%lX)", size);
        return false;
    }
    int code = 0;
    for (const Known &k : KNOWN) {
        char a[64];
        Bytes(g_base, k.rva, a, sizeof(a));
        code += a[0] != 0;
        Log("  %-34s +%06lX  %s", k.name, k.rva, a[0] ? a : "(not code)");
    }
    Log("  %d of %d known offsets are code", code, (int)(sizeof(KNOWN) / sizeof(KNOWN[0])));
    // the getter: code, at a function start (MSVC pads between functions with CC / 90)
    BYTE *get = g_base + RVA_GET_UI;
    if (!PageIs(get, EXEC)) {
        strcpy_s(why, n, "the game UI getter isn't code");
        return false;
    }
    if (get[-1] != 0xCC && get[-1] != 0x90 && get[-1] != 0xC3) {
        sprintf_s(why, n, "the game UI getter isn't a function start (%02X before it)", get[-1]);
        return false;
    }
    // the vtable: data (not code) in the module, its first entries code in the module
    DWORD vt = (DWORD)(g_base + RVA_UI_VTABLE);
    if (!PageIs((void *)vt, READ) || PageIs((void *)vt, EXEC)) {
        strcpy_s(why, n, "the game UI vtable isn't data");
        return false;
    }
    for (int i = 0; i < 4; i++) {
        DWORD f = ((DWORD *)vt)[i];
        if (!InImage(f, size) || !PageIs((void *)f, EXEC)) {
            sprintf_s(why, n, "game UI vtable entry %d (%08lX) isn't game code", i, f);
            return false;
        }
    }
    char rtti[64];
    RttiName(vt, size, rtti, sizeof(rtti));
    Log("  game UI vtable +%06lX: RTTI name %s", RVA_UI_VTABLE, rtti[0] ? rtti : "(none)");
    if (rtti[0] && !strstr(rtti, "CGameUI@")) {
        sprintf_s(why, n, "the vtable at +%lX is %s, not CGameUI", RVA_UI_VTABLE, rtti);
        return false;
    }
    g_uiVtable = vt;
    // For detailed tooltips later (study_tooltips2.md): does the game reach the
    // info panel's damage / armor icon updates through their vtables? Logged
    // only (which entry, if any); nothing is changed.
    static const struct { const char *name; DWORD vt, fn; } TIPS[] = {
        { "damage icon", 0xaaf5a8, 0x4089d0 }, { "armor icon", 0xaaf61c, 0x4083a0 } };
    for (const auto &t : TIPS) {
        DWORD *v = (DWORD *)(g_base + t.vt);
        char name[64];
        RttiName((DWORD)v, size, name, sizeof(name));
        int slot = -1;
        for (int i = 0; i < 128 && PageIs(v + i, READ); i++)
            if (v[i] == (DWORD)(g_base + t.fn)) {
                slot = i;
                break;
            }
        if (slot >= 0)
            Log("  tooltips: the %s update +%06lX is vtable +%06lX entry +%X (RTTI %s)", t.name, t.fn, t.vt, slot * 4, name[0] ? name : "(none)");
        else
            Log("  tooltips: the %s update +%06lX isn't in the first 128 entries of vtable +%06lX (RTTI %s)", t.name, t.fn, t.vt, name[0] ? name : "(none)");
    }
    strcpy_s(why, n, "passed");
    return true;
}

// -- Storm.dll ---------------------------------------------------------------------
// The features that add frames to the game (health numbers, mana bars, timers
// drawn in the game) allocate them with Storm's SMemAlloc (ordinal 401), as WFE
// does: the game frees its frames with its own Storm, so only the Storm.dll the
// game has loaded will do, never a copy loaded here (study_storm.md). Checked
// once: ordinals 401 / 403 must be SMemAlloc / SMemFree as in the 1.28f
// Storm.dll (each pushes its own name for its error message).
typedef void *(__stdcall *SMemAllocFn)(DWORD size, const char *name, DWORD line, DWORD flags);
typedef BOOL(__stdcall *SMemFreeFn)(void *p, const char *name, DWORD line, DWORD flags);
static const DWORD STORM_128F_STAMP = 0x5956EFF4, STORM_128F_SIZE = 0x62000;   // the 1.28f Storm.dll (2017-07-01)

static SMemAllocFn g_smemAlloc;
static SMemFreeFn g_smemFree;

// does f start with head and push (at +at) a pointer to name inside the image
static bool StormFn(BYTE *storm, DWORD size, const BYTE *f, const BYTE *head, int nhead, int at, const char *name) {
    if ((DWORD)(f - storm) >= size || !PageIs(f, EXEC) || !PageIs(f + at + 4, EXEC))
        return false;
    if (memcmp(f, head, nhead) || f[at] != 0x68)
        return false;
    DWORD s = *(const DWORD *)(f + at + 1);
    size_t n = strlen(name) + 1;
    return s - (DWORD)storm < size && PageIs((void *)s, READ) && PageIs((void *)(s + n - 1), READ) && !memcmp((void *)s, name, n);
}

// the module and its two functions: 1 checks out, 2 none in the game, 3 not the functions expected
static int StormCheckAt(BYTE *storm, const BYTE *alloc, const BYTE *freeFn) {
    static const BYTE A[] = { 0x55, 0x8B, 0xEC, 0x51, 0x83, 0x3D }, F[] = { 0x55, 0x8B, 0xEC, 0x83, 0x3D };
    if (!storm)
        return 2;
    DWORD size = ImageSize(storm);
    if (!size || storm == g_base)
        return 3;
    IMAGE_NT_HEADERS32 *nt = (IMAGE_NT_HEADERS32 *)(storm + ((IMAGE_DOS_HEADER *)storm)->e_lfanew);
    DWORD stamp = nt->FileHeader.TimeDateStamp;
    bool known = stamp == STORM_128F_STAMP && size == STORM_128F_SIZE;
    Log("Storm.dll: loaded at %p, built %08lX, image %lX (%s)", storm, stamp, size, known ? "the 1.28f Storm.dll" : "not the known 1.28f build");
    if (!alloc || !freeFn || !StormFn(storm, size, alloc, A, sizeof(A), 0x15, "SMemAlloc()") || !StormFn(storm, size, freeFn, F, sizeof(F), 0x27, "SMemFree()")) {
        Log("  refused: ordinals 401 / 403 aren't SMemAlloc / SMemFree as in 1.28f");
        if (alloc && PageIs(alloc, READ) && PageIs(alloc + 31, READ)) {
            char b[3 * 32 + 1];
            for (int i = 0; i < 32; i++)
                sprintf_s(b + 3 * i, sizeof(b) - 3 * i, "%02X ", alloc[i]);
            Log("  401 at %p: %s", alloc, b);
        }
        return 3;
    }
    g_smemAlloc = (SMemAllocFn)alloc, g_smemFree = (SMemFreeFn)freeFn;
    Log("  SMemAlloc (401) at %p, SMemFree (403) at %p: check out", alloc, freeFn);
    return 1;
}

// once, the first time a frame feature is on (1 = SMemAlloc can be used)
static int StormCheck() {
    static int r;
    if (!r) {
        HMODULE st = GetModuleHandleA("Storm.dll");
        if (!st)
            Log("Storm.dll isn't loaded in the game: health numbers, mana bars and timers in the game stay off");
        r = StormCheckAt((BYTE *)st, st ? (BYTE *)GetProcAddress(st, MAKEINTRESOURCEA(401)) : nullptr,
                         st ? (BYTE *)GetProcAddress(st, MAKEINTRESOURCEA(403)) : nullptr);
        g_shared->stState = r;
    }
    return r;
}

// -- the game UI -------------------------------------------------------------------
// The game's getter with (0, 0) only returns the UI (0 outside a game), never
// creates it; WFE calls it the same way. Called from this thread, so every
// read is guarded.
static void *ReadUi(DWORD *vt, DWORD *mode, DWORD *target) {
    __try {
        void *ui = g_getUi(0, 0);
        if (ui) {
            *vt = *(DWORD *)ui;
            *mode = *(DWORD *)((BYTE *)ui + UI_MODE);
            *target = *(DWORD *)((BYTE *)ui + UI_TARGET_MODE);
        }
        return ui;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return (void *)-1;
    }
}

// 1 = waiting for a target, 0 = not, -1 = no game UI (or it can't be trusted)
static int Targeting() {
    if (!g_getUi)
        return -1;
    DWORD vt = 0, mode = 0, target = 0;
    void *ui = ReadUi(&vt, &mode, &target);
    if (ui == (void *)-1) {
        static int faults;
        if (faults++ < 5)
            Log("reading the game UI faulted");
        return -1;
    }
    g_ui = nullptr;
    static int odd;                     // reads in a row whose object wasn't the game UI
    if (!ui)
        return odd = 0, -1;
    if (vt != g_uiVtable) {
        // the getter returned something that isn't the game UI: the addresses are wrong
        // for this game, so stop for good. Only when it stays so (5 reads in a row): this
        // thread reads the game's global while the game thread runs, and one torn read (the
        // UI freed as a game ends) must not end quickcast and the rest until a restart
        if (++odd < 5) {
            if (odd == 1)
                Log("the game UI's getter returned %p with vtable %08lX, not +%lX: watching", ui, vt, RVA_UI_VTABLE);
            return -1;
        }
        g_getUi = nullptr;
        g_shared->probe = 2;
        sprintf_s(g_shared->probeText, "the game UI at %p has vtable %08lX, not +%lX", ui, vt, RVA_UI_VTABLE);
        Log("stopping: %s", g_shared->probeText);
        return -1;
    }
    odd = 0;
    if (!g_shared->ui) {
        g_shared->ui = 1;
        Log("game UI at %p (vtable checks out); mode %08lX, target mode %08lX", ui, mode, target);
    }
    g_ui = (BYTE *)ui;
    return target && mode == target;
}

// -- calling the game's getters --------------------------------------------------
// Buff and cooldown times come from the game's own timer objects, through
// their getters (as WFE does), called on the game's thread (TimersPass). A
// tiny x86 decoder walks each one to its ret first and refuses it if it calls
// out (other than into such getters, up to 3 calls deep: 1.28f's cooldown
// time left is one), jumps indirectly, or uses an instruction it doesn't
// know. A refused getter is logged with its bytes (and the function in it
// that was refused) and never called.
enum { I_BAD = -1, I_OK, I_RET, I_CALL, I_JMP, I_JCC };

static int ModrmLen(const BYTE *p) {        // the ModRM byte, SIB and displacement
    int mod = p[0] >> 6, rm = p[0] & 7, n = 1;
    if (mod == 3)
        return 1;
    if (rm == 4) {
        n++;
        if (mod == 0 && (p[1] & 7) == 5)
            n += 4;
    } else if (mod == 0 && rm == 5)
        n += 4;
    return n + (mod == 1 ? 1 : mod == 2 ? 4 : 0);
}

// one instruction's length (0 and I_BAD if it's not one this allows)
static int Decode(const BYTE *p, int *kind, const BYTE **target) {
    const BYTE *s = p;
    bool o16 = false;
    *kind = I_OK;
    for (;;) {
        BYTE b = *p;
        if (b == 0x66)
            o16 = true, p++;
        else if (b == 0xF2 || b == 0xF3 || b == 0x2E || b == 0x3E || b == 0x26 || b == 0x36 || b == 0x64 || b == 0x65)
            p++;
        else
            break;
        if (p - s > 4)
            return *kind = I_BAD, 0;
    }
    int iz = o16 ? 2 : 4, n = 0;
    BYTE op = *p++;
    if (op < 0x40 && op != 0x0F) {
        if ((op & 7) >= 6)
            return *kind = I_BAD, 0;            // segment push/pop, BCD
        n = (op & 7) < 4 ? ModrmLen(p) : (op & 7) == 4 ? 1 : iz;
    } else if (op >= 0x40 && op <= 0x5F)
        n = 0;
    else if (op == 0x68)
        n = iz;
    else if (op == 0x6A)
        n = 1;
    else if (op == 0x69)
        n = ModrmLen(p) + iz;
    else if (op == 0x6B)
        n = ModrmLen(p) + 1;
    else if (op >= 0x70 && op <= 0x7F)
        *kind = I_JCC, *target = p + 1 + (signed char)*p, n = 1;
    else if (op == 0x80 || op == 0x83 || op == 0xC0 || op == 0xC1 || op == 0xC6)
        n = ModrmLen(p) + 1;
    else if (op == 0x81 || op == 0xC7)
        n = ModrmLen(p) + iz;
    else if ((op >= 0x84 && op <= 0x8B) || op == 0x8D || (op >= 0xD0 && op <= 0xD3) || (op >= 0xD8 && op <= 0xDF))
        n = ModrmLen(p);
    else if ((op >= 0x90 && op <= 0x99) || op == 0x9E || op == 0x9F || op == 0xC9)
        n = 0;
    else if (op >= 0xA0 && op <= 0xA3)
        n = 4;
    else if (op == 0xA8 || (op >= 0xB0 && op <= 0xB7))
        n = 1;
    else if (op == 0xA9 || (op >= 0xB8 && op <= 0xBF))
        n = iz;
    else if (op == 0xC3)
        *kind = I_RET;
    else if (op == 0xC2)
        *kind = I_RET, n = 2;
    else if (op == 0xE8 || op == 0xE9)
        *kind = op == 0xE8 ? I_CALL : I_JMP, *target = p + 4 + *(const LONG *)p, n = 4;
    else if (op == 0xEB)
        *kind = I_JMP, *target = p + 1 + (signed char)*p, n = 1;
    else if (op == 0xF6 || op == 0xF7)
        n = ModrmLen(p) + (((*p >> 3) & 7) < 2 ? (op == 0xF6 ? 1 : iz) : 0);
    else if (op == 0xFE || op == 0xFF) {
        int reg = (*p >> 3) & 7;                // FF /2 /3 call, /4 /5 jmp: refused
        if (reg >= 2 && !(op == 0xFF && reg == 6))
            return *kind = I_BAD, 0;
        n = ModrmLen(p);
    } else if (op == 0x0F) {
        BYTE o2 = *p++;
        if (o2 >= 0x80 && o2 <= 0x8F)
            *kind = I_JCC, *target = p + 4 + *(const LONG *)p, n = 4;
        else if (o2 == 0x10 || o2 == 0x11 || o2 == 0x14 || o2 == 0x15 || o2 == 0x1F || (o2 >= 0x28 && o2 <= 0x2F && o2 != 0x2B)
                 || (o2 >= 0x40 && o2 <= 0x4F) || (o2 >= 0x51 && o2 <= 0x5F) || o2 == 0x6E || o2 == 0x7E || (o2 >= 0x90 && o2 <= 0x9F)
                 || o2 == 0xAF || o2 == 0xB6 || o2 == 0xB7 || o2 == 0xBC || o2 == 0xBD || o2 == 0xBE || o2 == 0xBF || o2 == 0xD6 || o2 == 0xE6)   // BC / BD bsf / bsr (the game's float maths)
            n = ModrmLen(p);
        else
            return *kind = I_BAD, 0;
    } else
        return *kind = I_BAD, 0;
    return (int)(p - s) + n;
}

static bool IsGameCode(const BYTE *p) {
    return g_base && p >= g_base && (DWORD)(p - g_base) < g_imageSize && PageIs(p, EXEC);
}

static void LogBytes(const char *what, const BYTE *f) {
    char b[3 * 48 + 1];
    int o = 0;
    for (int i = 0; i < 48 && PageIs(f + i, READ); i++)
        o += sprintf_s(b + o, sizeof(b) - o, "%02X ", f[i]);
    b[o] = 0;
    Log("  %s +%06lX: %s", what, (DWORD)(f - g_base), b);
}

// Walks a getter to its last ret. A function at depth < most may call (or
// tail-jump to) functions that pass at depth + 1; at most, none. g_walkBad is
// where the walk was refused (the function's start).
static const BYTE *g_walkBad;
static bool WalkGetter(const BYTE *f, int depth, int most = 1) {
    g_walkBad = f;
    if (!IsGameCode(f))
        return false;
    const BYTE *p = f, *furthest = f;              // furthest: the furthest branch target inside it
    for (int i = 0; i < 200; i++) {
        if (!IsGameCode(p) || !PageIs(p + 15, EXEC))
            return false;
        int kind;
        const BYTE *t = nullptr;
        int n = Decode(p, &kind, &t);
        if (kind == I_BAD || n <= 0)
            return false;
        bool inside = t && t >= f && t < f + 1024;
        if (kind == I_CALL && (depth >= most || !WalkGetter(t, depth + 1, most)))
            return false;
        if (kind == I_JCC) {
            if (!inside)
                return g_walkBad = f, false;
            if (t > furthest)
                furthest = t;
        }
        if (kind == I_JMP) {
            if (inside) {
                if (t > furthest)
                    furthest = t;
            } else if (depth >= most || !WalkGetter(t, depth + 1, most))
                return false;
        }
        p += n;
        // the end: a ret or an unconditional jump, with no branch landing further on
        if ((kind == I_RET || kind == I_JMP) && p > furthest)
            return true;
        g_walkBad = f;
    }
    return false;
}

static const int GETTER_DEPTH = 3;

// cached verdict per getter; a refused one is logged once with its bytes
static bool SafeGetter(const BYTE *f) {
    static struct { const BYTE *f; bool ok; } seen[32];
    static int n;
    for (int i = 0; i < n; i++)
        if (seen[i].f == f)
            return seen[i].ok;
    bool ok = WalkGetter(f, 0, GETTER_DEPTH);
    if (n < 32) {
        seen[n].f = f, seen[n].ok = ok, n++;
        if (!ok) {
            Log("timers: refused to call the game getter at +%06lX (not a plain getter):", (DWORD)(f - g_base));
            LogBytes("bytes", f);
            if (g_walkBad != f && IsGameCode(g_walkBad))
                LogBytes("refused in the function", g_walkBad);
        } else
            Log("timers: game getter at +%06lX checks out", (DWORD)(f - g_base));
    }
    if (!ok)
        g_shared->tmFlags |= 0x100;
    return ok;
}

// obj's virtual function at byte offset slot, if it's a game getter that's safe to call
static const BYTE *Virtual(const void *obj, DWORD slot) {
    DWORD fn = 0;
    __try {
        DWORD vt = *(const DWORD *)obj;
        if (vt < (DWORD)g_base || vt - (DWORD)g_base >= g_imageSize)
            return nullptr;
        fn = *(const DWORD *)(vt + slot);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return nullptr;
    }
    return SafeGetter((const BYTE *)fn) ? (const BYTE *)fn : nullptr;
}

static DWORD GameCall(const void *fn, DWORD rc, DWORD rd, int n, const DWORD *a);
static bool Finite(float f) { return f == f && f >= 0 && f < 1e6f; }

// timer->getter(&out): vtable +0x18 the time left, +0x10 the full time (WFE's use). Through
// GameCall: whichever class the object is, esp is right after it (the 1.28f ones pop 4,
// the buff's int getters none; the decoder doesn't look at a ret's size)
static float TimerValue(const void *timer, DWORD slot) {
    const BYTE *f = Virtual(timer, slot);
    if (!f)
        return 0;
    float out = 0;
    __try {
        DWORD a = (DWORD)&out;
        GameCall(f, (DWORD)timer, 0, 1, &a);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return 0;
    }
    return Finite(out) ? out : 0;
}
static int VirtualInt(const void *obj, DWORD slot) {
    const BYTE *f = Virtual(obj, slot);
    if (!f)
        return 0;
    __try {
        return (int)GameCall(f, (DWORD)obj, 0, 0, nullptr);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return 0;
    }
}

// -- cooldown and buff timers ----------------------------------------------------
// Read the way WFE's Cooldown UI and BUFFUI do (study_cooldownui.md,
// study_buffs.md): the command card ([ui+0x3c8]) and the buff bar
// ([[[ui+0x3c4]+0x130]+0x16c]) are both grids: rows +0x124, columns +0x128, a
// row table at +0x154 (16 bytes a row: +4 count, +8 the buttons).
static const DWORD RVA_COMMAND_BUTTON_VTABLE = 0xaad9b8;    // CCommandButton ([0x1013a6ec]): a simple frame, anchored to as it is
static const DWORD ID_AHER = 'AHer', ID_ASID = 'Asid', ID_ASUD = 'Asud', ID_ASEI = 'Asei', ID_AMAI = 'Amai', ID_ASEL = 'Asel', ID_APIT = 'Apit';

static BYTE *GridButton(BYTE *bar, int row, int col) {
    BYTE *rows = *(BYTE **)(bar + 0x154);
    if (!rows)
        return nullptr;
    BYTE *r = rows + row * 16;
    if ((DWORD)col >= *(DWORD *)(r + 4) || !*(BYTE **)(r + 8))
        return nullptr;
    return (*(BYTE ***)(r + 8))[col];
}

// a command or inventory button's cooldown (WFE's 0x10023850 without its shop path)
// a rawcode as it's written ('AHhb'; in memory its bytes are the other way round)
struct IdText { char s[5]; IdText(DWORD id) { for (int i = 0; i < 4; i++) s[i] = (char)(id >> (24 - 8 * i)); s[4] = 0; } };
// -> what it found, for the cooldowns' log: CD_BUTTON, | CD_ABILITY data and an ability with a
// cooldown to show, | CD_COOLING its flags say cooling down, | CD_MODEL the game's cooldown sweep
// [+0x19c] (+0x3e1a60 makes it the first time the button shows a cooldown, +0x4070f4). The times
// are read only with the sweep there, as WFE's Cooldown UI; the rest is counted for the log.
static const int CD_BUTTON = 1, CD_MODEL = 2, CD_ABILITY = 4, CD_COOLING = 8;
static int ButtonCooldown(BYTE *btn, float *left, float *total) {
    BYTE *data, *ab;
    if (!btn)
        return 0;
    int found = CD_BUTTON | (*(DWORD *)(btn + 0x19c) ? CD_MODEL : 0);
    if (!(data = *(BYTE **)(btn + 0x190)) || !(ab = *(BYTE **)(data + 0x6d4)))
        return found;
    DWORD id = *(DWORD *)(ab + 0x34), fl = *(DWORD *)(ab + 0x20);
    if (id == ID_AHER || id == ID_ASID || id == ID_ASUD || id == ID_ASEI || id == ID_AMAI || id == ID_ASEL || id == ID_APIT)
        return found;                           // hero skill menu, shops: no cooldown to show
    bool cooling = (fl & 0x200) && !(fl & 0x400);
    found |= CD_ABILITY | (cooling ? CD_COOLING : 0);
    // the first in-game test showed no cooldowns on the card and nothing static explains it
    // (study_cd2.md): the first abilities seen and the first cooling down ones go to the log
    static int seen, cools;
    if (seen < 4)
        seen++, Log("cooldowns: button %p ability '%s' flags %08lX (cooling: %s, cooldown model: %s)", btn, IdText(id).s, fl, cooling ? "yes" : "no", found & CD_MODEL ? "yes" : "none yet");
    if (!cooling || !(found & CD_MODEL))
        return found;
    *left = TimerValue(ab + 0xd0, 0x18);
    *total = TimerValue(ab + 0xd0, 0x10);
    if (cools < 3)
        cools++, Log("cooldowns: '%s' %.1f s of %.1f left (timer vtable +%06lX)", IdText(id).s, *left, *total, *(DWORD *)(ab + 0xd0) - (DWORD)g_base);
    return found;
}

// what a read of the card found, logged a few times (the first in-game test showed no
// cooldowns and nothing in the log said why): the first read, the first with an ability on a
// button with its cooldown model, the first with one cooling down; an unreadable card once
static void CooldownsLog(BYTE *card, int rows, int cols, const int *found, int n) {
    static int logged;                      // bits: 1 first read, 2 an ability, 4 cooling, 8 unreadable
    int buttons = 0, models = 0, abilities = 0, cooling = 0, cmd = 0;
    for (int i = 0; i < n; i++) {
        buttons += (found[i] & CD_BUTTON) != 0, models += (found[i] & CD_MODEL) != 0;
        abilities += (found[i] & CD_ABILITY) != 0, cooling += (found[i] & CD_COOLING) != 0;
    }
    for (int r = 0; r < rows; r++)
        for (int c = 0; c < cols; c++) {
            BYTE *b = GridButton(card, r, c);
            cmd += b && *(DWORD *)b == (DWORD)(g_base + RVA_COMMAND_BUTTON_VTABLE);
        }
    int why = !(logged & 1) ? 1 : abilities && !(logged & 2) ? 2 : cooling && !(logged & 4) ? 4 : 0;
    if (!why)
        return;
    logged |= why;
    if (why == 1)
        logged |= (abilities ? 2 : 0) | (cooling ? 4 : 0);   // the first read says it all already
    Log("cooldowns: the command card %p is %dx%d: %d buttons (%d command buttons, vtable +%06lX), %d with an ability, %d cooling down, %d with the game's cooldown model [+0x19C]",
        card, rows, cols, buttons, cmd, RVA_COMMAND_BUTTON_VTABLE, abilities, cooling, models);
}
static void ReadCooldowns(BYTE *ui) {
    BYTE *card = *(BYTE **)(ui + 0x3c8);
    int rows = card ? *(int *)(card + 0x124) : 0, cols = card ? *(int *)(card + 0x128) : 0;
    if (!card || rows <= 0 || cols <= 0 || rows > 3 || cols > 4) {
        static bool said;
        if (!said)
            said = true, Log("cooldowns: the command card [ui+0x3C8] = %p (%d x %d) isn't readable: no cooldowns", card, rows, cols);
        return;
    }
    int found[12] = {};
    for (int r = 0; r < rows; r++)
        for (int c = 0; c < cols; c++)
            found[r * 4 + c] = ButtonCooldown(GridButton(card, r, c), &g_shared->cdLeft[r * 4 + c], &g_shared->cdTotal[r * 4 + c]);
    CooldownsLog(card, rows, cols, found, 12);
    g_shared->tmFlags |= 1;
}

// The inventory, as WFE's Cooldown UI finds it (0x1008255e..0x10082892):
// [[ui+0x3c4]+0x148], count +0x12c, 8-byte entries at [+0x130], the button at +4
static BYTE *ItemButton(BYTE *ui, int i) {
    BYTE *p = *(BYTE **)(ui + 0x3c4);
    if (!p || !(p = *(BYTE **)(p + 0x148)))
        return nullptr;
    int n = *(int *)(p + 0x12c);
    BYTE *a = *(BYTE **)(p + 0x130);
    return a && i < n && n <= 6 ? *(BYTE **)(a + i * 8 + 4) : nullptr;
}
static void ReadItems(BYTE *ui) {
    for (int i = 0; i < 6; i++)
        ButtonCooldown(ItemButton(ui, i), &g_shared->itemLeft[i], &g_shared->itemTotal[i]);
    g_shared->tmFlags |= 4;
}

// The buff bar's buffs, as WFE's BUFFUI reads them (study_buffs2.md; read by hand in
// WFEDll and checked in the 1.28f Game.dll): each indicator [+0x90] shown / [+0x94] visible
// (the game's show / hide set them), its buff [+0x978]; aura: vt+0x1e8 (CBuff 0, CBuffAura 1);
// the rawcode [buff+0x34] (the game looks its data up with it, +0x45b9e8); time left from the
// timer at +0x84 (CAgentTimerExtended, vt+0x18), or +0xac while [+0x48] > 0 (paused); the full
// time [+0xc8] when the buff's unit (AgentOwner) is a hero, else [+0xc0] (WFE's 0x10038600,
// its hero test 0x100417b0: a CUnit whose type id starts with a capital, or [unit+0x1f0]).
// Four kinds ('Bpsd', 'BIpd', 'Bcsd', 'Bssd' by their vt+0x1c tag) keep their time on a
// linked buff: the handle pair at +0x114 -> [obj+0x54], tagged 'B...' (WFE's 0x10038550).
static BYTE *V(BYTE *f);
static const DWORD RVA_HANDLE_LOOKUP = 0x7e090; // __fastcall obj(id1, id2) (WFE's [0x1013ba2c])
typedef void *(__fastcall *LookupFn)(DWORD, DWORD);
static const DWORD RVA_UNIT_VT = 0xb68914;       // CUnit (its vt+0xec is the owner [+0x58], +0x6b9f30)
static const DWORD BUFF_UNIT = 0x30, BUFF_ID = 0x34, BUFF_LINK = 0x114;
// A buff's or ability's unit (both are agents): [+0x30] once the game has cached it, else
// through the agent's own handle pair +0xc / +0x10, as the game's +0x7f820 does (lookup
// +0x7e090, tagged '+agl' at [+0xc], its [+0x30] u, alive when [u+0x20] == 0, the unit
// [u+0x54]; e.g. its ability code +0x460914: [+0x30], else +0x7f820). Done by hand as WFE's
// 0x1007f649 (the game's dereferences a refused lookup), with the game's tag check added.
static const DWORD AGENT_HANDLE = 0xc, AGENT_OWNER = 0x30, HANDLE_TAG = 0xc, HANDLE_OWNER = 0x30, HANDLE_DEAD = 0x20, HANDLE_OBJ = 0x54;
static BYTE *AgentObject(DWORD *pair) {
    if (pair[0] == 0xFFFFFFFF || pair[1] == 0xFFFFFFFF)
        return nullptr;
    BYTE *x = (BYTE *)((LookupFn)(g_base + RVA_HANDLE_LOOKUP))(pair[0], pair[1]);
    return x && *(DWORD *)(x + HANDLE_TAG) == '+agl' ? x : nullptr;
}
static BYTE *AgentOwner(BYTE *a) {
    BYTE *u = *(BYTE **)(a + AGENT_OWNER), *x;
    if (u)
        return u;
    if (!(x = AgentObject((DWORD *)(a + AGENT_HANDLE))) || !(u = *(BYTE **)(x + HANDLE_OWNER)))
        return nullptr;
    return !*(DWORD *)(u + HANDLE_DEAD) ? *(BYTE **)(u + HANDLE_OBJ) : nullptr;
}
static bool IsUnit(BYTE *u) {
    return u && (DWORD)(u - (BYTE *)0x10000) <= 0x7ffeffff && *(DWORD *)u == (DWORD)(g_base + RVA_UNIT_VT);
}
// WFE's hero test 0x100417b0: a CUnit whose own handle is alive, with a type id starting with
// a capital, or [unit+0x1f0]
static bool IsHero(BYTE *u) {
    BYTE *x;
    if (!IsUnit(u) || !(x = AgentObject((DWORD *)(u + AGENT_HANDLE))) || *(DWORD *)(x + HANDLE_DEAD))
        return false;
    DWORD id = *(DWORD *)(u + 0x30);
    return (id >> 24) >= 'A' && (id >> 24) <= 'Z' || *(DWORD *)(u + 0x1f0) != 0;
}
// where the buff's times are: itself, or for the four linked kinds the buff they point at
static BYTE *BuffTimes(BYTE *buff) {
    DWORD tag = (DWORD)VirtualInt(buff, 0x1c);
    if (tag != 'Bpsd' && tag != 'BIpd' && tag != 'Bcsd' && tag != 'Bssd')
        return buff;
    DWORD *pair = (DWORD *)(buff + BUFF_LINK);
    if (pair[0] == 0xFFFFFFFF || pair[1] == 0xFFFFFFFF)
        return buff;
    BYTE *o = (BYTE *)((LookupFn)(g_base + RVA_HANDLE_LOOKUP))(pair[0], pair[1]);
    BYTE *b2 = o ? V(*(BYTE **)(o + 0x54)) : nullptr;
    return b2 && ((DWORD)VirtualInt(b2, 0x1c) >> 24) == 'B' ? b2 : buff;
}
// Settled in the 1.28f Game.dll (test_gamedll): +0xc0 / +0xc8 are FloatMini values (objects at
// +0xbc / +0xc4, CBuff's ctor +0x41e632) the game packs (+0x41f509) where it puts an ability's
// level data Dur / HeroDur (+0x4490d0 / +0x449650: level record +8 / +0xc, loaded under "Dur" /
// "HeroDur" at +0x6db8b4 / +0x6db8e9): the normal and the hero duration. [+0xa4] (FloatMini at
// +0xa0) is the time already run when the buff was paused (+0x565540 saves the timer's elapsed
// there and its time left at +0xac; a fresh start +0x566c70 zeroes it); the game's own full time
// (+0x563650) is the timer's total + [+0xa4], or [+0xac] + [+0xa4] while paused ([+0x48] > 0).
static const DWORD BUFF_RAN = 0xa4, BUFF_PAUSED_LEFT = 0xac, BUFF_PAUSED = 0x48, BUFF_DUR = 0xc0, BUFF_HERO_DUR = 0xc8, BUFF_TIMER = 0x84;
static float BuffGameTotal(BYTE *b) {
    float ran = *(float *)(b + BUFF_RAN), t = *(int *)(b + BUFF_PAUSED) > 0 ? *(float *)(b + BUFF_PAUSED_LEFT) : TimerValue(b + BUFF_TIMER, 0x10);
    ran = Finite(ran) ? ran : 0;
    return Finite(t) ? t + ran : 0;
}
// a buff's seconds left and full time, as WFE's 0x1007f530: the hero test on the buff's own
// unit, the times on its source (BuffTimes), whose full time needs a unit of its own
// (0x10038679, else none: then the game's own total). -> the source
static BYTE *BuffTimeOf(BYTE *buff, bool aura, float *left, float *total) {
    BYTE *t = BuffTimes(buff);
    bool hero = IsHero(AgentOwner(buff));
    float l = *(int *)(t + BUFF_PAUSED) > 0 ? *(float *)(t + BUFF_PAUSED_LEFT) : TimerValue(t + BUFF_TIMER, 0x18);
    l = Finite(l) ? l : 0;
    float f = aura ? TimerValue(t + BUFF_TIMER, 0x10) : AgentOwner(t) ? *(float *)(t + (hero ? BUFF_HERO_DUR : BUFF_DUR)) : 0;
    if (!Finite(f) || f <= 0 || f < l)
        f = BuffGameTotal(t);
    *left = l, *total = Finite(f) ? f : 0;
    return t;
}
static void ReadBuffs(BYTE *ui) {
    BYTE *p = *(BYTE **)(ui + 0x3c4);
    if (!p || !(p = *(BYTE **)(p + 0x130)) || !(p = *(BYTE **)(p + 0x16c)))
        return;
    int rows = *(int *)(p + 0x124), cols = *(int *)(p + 0x128);
    if (rows <= 0 || cols <= 0 || rows * cols > 16)
        return;
    for (int r = 0; r < rows; r++)
        for (int c = 0; c < cols; c++) {
            int i = r * cols + c;
            BYTE *btn = GridButton(p, r, c), *buff;
            if (!btn || !*(DWORD *)(btn + 0x90) || !*(DWORD *)(btn + 0x94) || !(buff = V(*(BYTE **)(btn + 0x978))))
                continue;
            bool aura = VirtualInt(buff, 0x1e8) != 0;
            g_shared->buffFlags[i] = aura ? 3 : 1;
            g_shared->buffId[i] = *(DWORD *)(buff + BUFF_ID);
            float left, total;
            BYTE *t = BuffTimeOf(buff, aura, &left, &total);
            g_shared->buffLeft[i] = left;
            g_shared->buffTotal[i] = total;
            static int logs;
            if (left > 0 && logs < 3)
                logs++, Log("buffs: '%s' %s, %.1f s of %.1f left%s", IdText(g_shared->buffId[i]).s, aura ? "aura" : "buff", left, g_shared->buffTotal[i], t != buff ? " (its linked buff's)" : "");
        }
    g_shared->buffCount = rows * cols;
    g_shared->tmFlags |= 2;
}

static void ReadHeroBuffs();
// all of them, guarded: a fault keeps what was read before it
static void ReadTimersGuarded(BYTE *ui) {
    __try {
        ReadCooldowns(ui);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
    __try {
        ReadBuffs(ui);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
    __try {
        ReadItems(ui);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
    if (g_shared->hrWant)
        __try {
            ReadHeroBuffs();
        } __except (EXCEPTION_EXECUTE_HANDLER) {
        }
}

// ui: the worker's last g_ui, or the game thread's own when it draws them in the game
static SRWLOCK g_timersLock = SRWLOCK_INIT;     // the worker and the game thread may both read them (switching over)

static void ReadTimers(BYTE *ui) {
    AcquireSRWLockExclusive(&g_timersLock);
    DWORD keep = g_shared->tmFlags & 0x100;
    ZeroMemory(g_shared->cdLeft, (BYTE *)(g_shared->buffId + 16) - (BYTE *)g_shared->cdLeft);
    ZeroMemory(g_shared->itemLeft, sizeof(g_shared->itemLeft) + sizeof(g_shared->itemTotal));
    g_shared->tmFlags = keep;
    if (ui)
        ReadTimersGuarded(ui);
    InterlockedIncrement(&g_shared->tmSeq);
    ReleaseSRWLockExclusive(&g_timersLock);
}

// -- the game's thread -------------------------------------------------------------
// Game functions that change something (clearing messages, later the
// multiboard, widescreen...) must run on the game's own thread. The module
// subclasses the game window: its window procedure runs on that thread
// (WFE's timer callbacks run there and call the game the same way). No game
// code is patched. It's installed only when a command first needs it, and
// taken out on unload if it's still ours.
static const DWORD RVA_MSG_CLEAR = 0x144750;    // __fastcall ClearMessages(frame, 0) (WFE's [0x1013a954])
static const DWORD UI_MESSAGES = 0x3e8, UI_CHAT = 0x3ec;   // CGameUI: trigger messages / chat frame

static HWND g_gameWnd;
static WNDPROC g_oldProc;
static bool g_wide;
static UINT g_runMsg;
static volatile LONG g_running;     // the command handed to the game thread (0 = none)
static DWORD g_gameTid;

static BOOL CALLBACK FindGameWnd(HWND w, LPARAM) {
    DWORD pid = 0;
    char cls[64];
    GetWindowThreadProcessId(w, &pid);
    if (pid == GetCurrentProcessId() && IsWindowVisible(w) && GetClassNameA(w, cls, sizeof(cls)) && !strcmp(cls, "Warcraft III")) {
        g_gameWnd = w;
        return FALSE;
    }
    return TRUE;
}

static int RunOnGameThread(DWORD cmd);
static void *GameUi();
static void PortraitSitesPass();
static void FinalPass();
static UINT g_finalMsg;
static UINT g_prMsg;                // "TWC_GameThreadPortrait": PortraitSitesPass on the game thread
static volatile LONG g_prQueued;
static void BarsPass();
static UINT g_barsMsg;              // "TWC_GameThreadBars": run BarsPass on the game thread
static volatile LONG g_barsQueued;
static void DisplayPass();
static UINT g_dispMsg;              // "TWC_GameThreadDisplay": run DisplayPass on the game thread
static volatile LONG g_dispQueued;
static int ToggleMultiboard(BYTE *ui);
static int AutocastToggle(BYTE *ui, DWORD slot);
static int PingCommand(BYTE *ui);
static void SelfCast();
static UINT g_selfMsg;              // "TWC_GameThreadSelfCast": run SelfCast on the game thread
static void FramesPass();
static UINT g_framesMsg;            // "TWC_GameThreadFrames": run FramesPass on the game thread
static UINT g_timersMsg;            // "TWC_GameThreadTimers": read the timers on the game thread (for the overlay)
static volatile LONG g_timersQueued;
static volatile LONG g_framesQueued;

static LRESULT CALLBACK GameWndProc(HWND w, UINT m, WPARAM wp, LPARAM lp) {
    if (m == g_barsMsg && g_barsMsg) {
        InterlockedExchange(&g_barsQueued, 0);
        BarsPass();
        return 0;
    }
    if (m == g_dispMsg && g_dispMsg) {
        InterlockedExchange(&g_dispQueued, 0);
        DisplayPass();
        return 0;
    }
    if (m == g_selfMsg && g_selfMsg) {
        SelfCast();
        return 0;
    }
    if (m == g_framesMsg && g_framesMsg) {
        InterlockedExchange(&g_framesQueued, 0);
        FramesPass();
        return 0;
    }
    if (m == g_finalMsg && g_finalMsg) {
        FinalPass();
        return 0;                   // not to the game: it's ours
    }
    if (m == g_prMsg && g_prMsg) {
        InterlockedExchange(&g_prQueued, 0);
        PortraitSitesPass();
        return 0;
    }
    if (m == g_timersMsg && g_timersMsg) {
        InterlockedExchange(&g_timersQueued, 0);
        ReadTimers((BYTE *)GameUi());
        return 0;
    }
    if (m == g_runMsg && g_runMsg) {
        LONG cmd = InterlockedExchange(&g_running, 0);
        if (cmd) {
            if (!g_gameTid) {
                g_gameTid = GetCurrentThreadId();
                Log("game thread: %lu (the game window's)", g_gameTid);
            }
            g_shared->cmdResult = RunOnGameThread((DWORD)cmd);
            InterlockedExchange(&g_shared->cmdDone, (LONG)wp);
        }
        return 0;
    }
    return g_wide ? CallWindowProcW(g_oldProc, w, m, wp, lp) : CallWindowProcA(g_oldProc, w, m, wp, lp);
}

static bool Subclass() {
    if (g_oldProc)
        return true;
    if (!g_gameWnd)
        EnumWindows(FindGameWnd, 0);
    if (!g_gameWnd) {
        Log("game thread: no game window found");
        return false;
    }
    g_runMsg = RegisterWindowMessageA("TWC_GameThreadCall");
    g_barsMsg = RegisterWindowMessageA("TWC_GameThreadBars");
    g_dispMsg = RegisterWindowMessageA("TWC_GameThreadDisplay");
    g_selfMsg = RegisterWindowMessageA("TWC_GameThreadSelfCast");
    g_framesMsg = RegisterWindowMessageA("TWC_GameThreadFrames");
    g_timersMsg = RegisterWindowMessageA("TWC_GameThreadTimers");
    g_prMsg = RegisterWindowMessageA("TWC_GameThreadPortrait");
    g_finalMsg = RegisterWindowMessageA("TWC_GameThreadFinal");
    g_wide = IsWindowUnicode(g_gameWnd) != 0;
    g_oldProc = (WNDPROC)(g_wide ? SetWindowLongPtrW(g_gameWnd, GWLP_WNDPROC, (LONG_PTR)GameWndProc)
                                 : SetWindowLongPtrA(g_gameWnd, GWLP_WNDPROC, (LONG_PTR)GameWndProc));
    Log(g_oldProc ? "game thread: window %p subclassed (%s)" : "game thread: subclassing window %p failed", g_gameWnd, g_wide ? "W" : "A");
    return g_oldProc != nullptr;
}
static void Unsubclass() {
    if (!g_oldProc)
        return;
    LONG_PTR now = g_wide ? GetWindowLongPtrW(g_gameWnd, GWLP_WNDPROC) : GetWindowLongPtrA(g_gameWnd, GWLP_WNDPROC);
    if (now == (LONG_PTR)GameWndProc) {     // else someone subclassed after us: leave theirs (and ours) in place
        g_wide ? SetWindowLongPtrW(g_gameWnd, GWLP_WNDPROC, (LONG_PTR)g_oldProc) : SetWindowLongPtrA(g_gameWnd, GWLP_WNDPROC, (LONG_PTR)g_oldProc);
        g_oldProc = nullptr;
    }
}

// a frame the game UI holds, if it has a vtable in the game's data (message frames, the multiboard)
static BYTE *UiFrame(BYTE *ui, DWORD off) {
    __try {
        BYTE *f = *(BYTE **)(ui + off);
        if (!f)
            return nullptr;
        DWORD vt = *(DWORD *)f;
        if (vt < (DWORD)g_base || vt - (DWORD)g_base >= g_imageSize || PageIs((void *)vt, EXEC))
            return nullptr;
        return f;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return nullptr;
    }
}

typedef void(__fastcall *FrameFn)(void *, int);

static int CallClear(BYTE *frame) {
    __try {
        ((FrameFn)(g_base + RVA_MSG_CLEAR))(frame, 0);
        return 1;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return 3;
    }
}

// the game UI, on the game thread (0 outside a game, or if it doesn't check out)
static void *GameUi() {
    __try {
        void *ui = g_getUi(0, 0);
        return ui && *(DWORD *)ui == g_uiVtable ? ui : nullptr;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return nullptr;
    }
}

// on the game thread: 1 done, 2 refused
static int RunOnGameThread(DWORD cmd) {
    if (!g_getUi || !IsGameCode(g_base + RVA_MSG_CLEAR))
        return 2;
    void *ui = GameUi();
    if (!ui)
        return 2;                       // not in a game
    if (cmd == 1 || cmd == 2) {
        BYTE *f = UiFrame((BYTE *)ui, cmd == 1 ? UI_MESSAGES : UI_CHAT);
        static int logged[3];       // 1 logged, 2 refused for good
        if (!logged[cmd]) {
            logged[cmd] = true;
            char rtti[64] = "";
            if (f)
                RttiName(*(DWORD *)f, g_imageSize, rtti, sizeof(rtti));
            Log("clear %s: frame %p, vtable +%06lX, RTTI %s", cmd == 1 ? "messages" : "chat", f, f ? *(DWORD *)f - (DWORD)g_base : 0, rtti[0] ? rtti : "(none)");
            if (rtti[0] && !strstr(rtti, "MessageFrame")) {
                Log("  not a message frame: refusing (this and later clears of it)");
                logged[cmd] = 2;
            }
        }
        if (!f || logged[cmd] == 2)
            return 2;
        int r = CallClear(f);
        if (r == 3)
            Log("clear %s: the game's clear faulted", cmd == 1 ? "messages" : "chat");
        return r == 1 ? 1 : 2;
    }
    if (cmd == 3)
        return ToggleMultiboard((BYTE *)ui);
    if (cmd == 4)
        return AutocastToggle((BYTE *)ui, g_shared->cmdArg);
    if (cmd == 5)
        return PingCommand((BYTE *)ui);
    return 2;
}

// -- health bar size ----------------------------------------------------------------
// Like WFE's HEALTHBAR HEIGHT (study_healthbar.md): every unit's health bar
// ([[unit+0x50]+0xc], a CStatBar: vtable +0xaad83c, kind [+0x138] = 5) gets the
// wanted height (+0x5c), in the bar's own update (BarAfter) and a few times a
// second on the game thread (BarsPass), then the game's layout refresh. The
// game makes every health bar 0.004 high (+0x3c67f9) and never changes it, so
// the height is absolute: the game's own, from the first bar seen (logged),
// times the setting, put back when turned off. The width isn't: the game's
// per-unit bar work +0x3c6700 sets each bar's width for its unit type on every
// pass ([type+0x54] x SelectionCircle / ScaleFactor x 0.0005, +0x3c68ce..
// +0x3c6905, through +0x13fce0) right before it calls the bar's set-unit +0x78
// (+0x3c68ab) or update +0x74 (+0x3c6912). So the width is multiplied only in
// those two calls (their return address), and the game's next pass puts its
// own back by itself (WFE never writes the width: experimental here).
static const DWORD RVA_UNIT_LIST = 0xd328f0;    // { ?, count +4, units +8 } (WFE's [0x1013a990])
static const DWORD RVA_UNIT_EXTRA = 0xd32900;   // one more unit: [it] is the unit itself (the game: mov eax, [it]; inc [eax+4], +0x3c64ff;
                                                // WFE's slot holds this address, so its [[slot]] is our [it], 0x100414a1)
static const DWORD RVA_BAR_WIDTH_SET_UNIT_RET = 0x3c68ae, RVA_BAR_WIDTH_UPDATE_RET = 0x3c6915;   // right after +0x3c6700's two calls
static const DWORD RVA_STATBAR_VTABLE = 0xaad83c;
static const DWORD RVA_LAYOUT_REFRESH = 0x13f9b0;   // __fastcall(frame, 0, int 0) (WFE's [0x1013a21c])
static const DWORD UNIT_BARS = 0x50, BARS_HEALTH = 0xc, BAR_KIND = 0x138, BAR_WIDTH = 0x58, BAR_HEIGHT = 0x5c;

typedef void(__fastcall *RefreshFn)(void *, int, int);
static float g_defH, g_defW;            // the game's own bar size (0 = not seen yet)
static volatile bool g_barsApplied;     // something was resized and not put back yet

static bool SaneSize(float f) { return f == f && f > 0.0001f && f < 0.5f; }

// the size wanted now (false: none, the bars are the game's)
static bool BarSizeWanted(float *h, float *w) {
    if (!g_shared->hbOn)
        return false;
    *h = g_shared->hbHeight, *w = g_shared->hbWidth;
    *h = *h >= 0.25f && *h <= 4 ? *h : 1, *w = *w >= 0.25f && *w <= 4 ? *w : 1;
    return true;
}
static int SizeThisBar(BYTE *bar, float h, float w, bool freshWidth);
// one unit's health bar (its height: the width is only set in the game's bar work): 1 resized, 0 nothing to do or not a health bar
static int SizeBar(BYTE *unit, float h) {
    __try {
        BYTE *bars = *(BYTE **)(unit + UNIT_BARS), *bar;
        if (!bars || !(bar = *(BYTE **)(bars + BARS_HEALTH)))
            return 0;
        return SizeThisBar(bar, h, 1, false);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return -1;
    }
}
// RenderEdge_Widescreen (the user's mix file) hooks the game's per-unit bar work +0x3c6700
// (called once, from +0x688f65) and divides each unit's health bar width by 0.75 * W/H after
// it, so after our multiplier in the bar's update: the two add up. Only the mana bars, sized
// in that same update, would come out wider than their health bar: they're divided too.
static bool ForeignDetour(DWORD rva, char *who, size_t n);
static float WideK();
static const DWORD RVA_UNIT_BAR_WORK = 0x3c6700;
static bool OtherBarWidth() {
    static int r;                   // 1 ours, 2 another mod's
    if (!r) {
        char who[64];
        r = ForeignDetour(RVA_UNIT_BAR_WORK, who, sizeof(who)) ? 2 : 1;
        if (r == 2)
            Log("health bars: +%06lX is hooked by %s (it narrows the bars for the window after the game's): the mana bars follow it", RVA_UNIT_BAR_WORK, who);
    }
    return r == 2;
}
// a health bar: 1 resized, 0 nothing to do or not a health bar. freshWidth: the game has just
// set the width for the bar's unit (the bar's update called from +0x3c6700): it's multiplied
static int SizeThisBar(BYTE *bar, float h, float w, bool freshWidth) {
    __try {
        if (*(DWORD *)bar != (DWORD)(g_base + RVA_STATBAR_VTABLE) || *(DWORD *)(bar + BAR_KIND) != 5)
            return 0;
        float *ph = (float *)(bar + BAR_HEIGHT), *pw = (float *)(bar + BAR_WIDTH);
        if (!g_defH) {
            if (!SaneSize(*ph) || !SaneSize(*pw))
                return 0;
            g_defH = *ph, g_defW = *pw;
            g_shared->hbDefHeight = g_defH, g_shared->hbDefWidth = g_defW;
            Log("health bars: the game's own size is %.5f high, %.5f wide (UI units; the width is the first unit's)", g_defH, g_defW);
        }
        float th = g_defH * h, tw = freshWidth && SaneSize(*pw) ? *pw * w : *pw;
        if (fabsf(*ph - th) < 1e-6f && fabsf(*pw - tw) < 1e-6f)
            return 0;
        *ph = th, *pw = tw;
        ((RefreshFn)(g_base + RVA_LAYOUT_REFRESH))(bar, 0, 0);
        if (h != 1)
            g_barsApplied = true;       // to put back when turned off (the bar's update sizes most of them, not BarsPass)
        return 1;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return -1;
    }
}

// on the game thread
static void BarsPass() {
    static bool refused;
    if (refused || !g_getUi)
        return;
    if (!IsGameCode(g_base + RVA_LAYOUT_REFRESH) || PageIs(g_base + RVA_STATBAR_VTABLE, EXEC)) {
        refused = true, g_shared->hbState = 3;
        Log("health bars: refused (the layout refresh isn't code, or the bar vtable isn't data)");
        return;
    }
    bool on = g_shared->hbOn != 0;
    float h = on ? g_shared->hbHeight : 1, w = on ? g_shared->hbWidth : 1;
    h = h >= 0.25f && h <= 4 ? h : 1, w = w >= 0.25f && w <= 4 ? w : 1;
    int n = 0, faults = 0;
    __try {
        BYTE *list = g_base + RVA_UNIT_LIST;
        DWORD count = *(DWORD *)(list + 4);
        BYTE **units = *(BYTE ***)(list + 8);
        for (DWORD i = 0; units && i < count && i < 4096; i++)
            if (units[i]) {
                int r = SizeBar(units[i], h);
                n += r > 0, faults += r < 0;
            }
        BYTE *extra = *(BYTE **)(g_base + RVA_UNIT_EXTRA);
        if (extra) {
            int r = SizeBar(extra, h);
            n += r > 0, faults += r < 0;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        faults++;
    }
    static int faultLogs;
    if (faults && faultLogs++ < 3)
        Log("health bars: %d reads faulted in a pass", faults);
    if (n)
        g_barsApplied = on;
    // the first passes are logged: if the count stays high, the game resets the size every frame
    static int passLogs;
    if (n && passLogs < 6)
        passLogs++, Log("health bars: pass resized %d bars (height x%.2f, width x%.2f)", n, h, w);
    g_shared->hbCount = n;
    g_shared->hbState = g_defH ? 1 : 2;
}

// the worker's part: hand a pass to the game thread 4 times a second while on,
// and once more after turning off (to put the bars back)
static void QueueBars() {
    static DWORD at;
    DWORD now = GetTickCount();
    if (!g_getUi || now - at < 250 || (!g_shared->hbOn && !g_barsApplied))
        return;
    at = now;
    if (!g_shared->hbOn)
        g_barsApplied = false;          // this pass puts them back
    if (Subclass() && !InterlockedExchange(&g_barsQueued, 1))
        PostMessageA(g_gameWnd, g_barsMsg, 0, 0);
}

// the timers for the overlay: the game thread reads them (its getters run there)
static void QueueTimers() {
    if (g_getUi && Subclass() && !InterlockedExchange(&g_timersQueued, 1))
        PostMessageA(g_gameWnd, g_timersMsg, 0, 0);
}

// -- health bar colours ---------------------------------------------------------------
// The game repaints a bar's colour on every update of the bar, so the colour
// is set right after the game's own update, as WFE does (study_hpcolours.md).
// WFE gives every bar its own copy of the CStatBar vtable; here the one shared
// entry for the update (vtable +0x74) points at BarUpdateHook while colours are
// on, which calls the game's original first. That's a 4-byte data write in the
// game's vtable, nothing else; it's put back when colours go off or on unload
// (if it's still ours). The hook runs on the game's thread (the game calls it).
static const DWORD STATBAR_UPDATE = 0x74;       // __fastcall Update(bar, 0, unit), ret 4
static const DWORD RVA_PLAYERS = 0xd305e0;      // [it] = the game state: local player id word +0x28, player count +0x54, players +0x58
                                                // (one deref: the game's own +0x22b560 / +0x213720; WFE's slot holds this address, so its [[slot]] is ours [it])
static const DWORD RVA_UNIT_HP = 0x81b30;       // __fastcall(unit + 0x98, 0, float *hp) (WFE's [0x1013ce3c])
static const DWORD BAR_UNIT = 0x154, BAR_FILL = 0x134;      // the bar's unit; its fill (the coloured part)
static const DWORD UNIT_OWNER = 0x58, UNIT_HP = 0x98, UNIT_MAXHP_HANDLE = 0xa0;

typedef void(__fastcall *BarUpdateFn)(void *, int, void *);
typedef void(__fastcall *HpFn)(void *, int, float *);
typedef void(__fastcall *ColourFn)(void *, int);

static BarUpdateFn g_gameBarUpdate;     // the game's own update: set once, never cleared (a call may be in flight)
static bool g_barHooked;
static DWORD g_colourLogged;            // the players whose colour index was logged

// is player b allied to player a (WFE's 0x1003c2a0: a's alliance flags, bit b's slot)
static bool Allied(BYTE *state, int a, int b) {
    BYTE *pa = *(BYTE **)(state + 0x58 + a * 4), *pb = *(BYTE **)(state + 0x58 + b * 4);
    if (!pa || !pb)
        return false;
    BYTE *h = *(BYTE **)(pa + 0x38);
    if (!h)
        return false;
    DWORD *pair = (DWORD *)(h + 0x40);
    if (pair[0] == 0xFFFFFFFF || pair[1] == 0xFFFFFFFF)
        return false;
    BYTE *flags = (BYTE *)((LookupFn)(g_base + RVA_HANDLE_LOOKUP))(pair[0], pair[1]);
    return flags && (*(DWORD *)(flags + 0x78) & (1u << *(BYTE *)(pb + 0x30)));
}

// The owner's player colour, as WFE's player-colour mode (0x100778da): the
// colour index [player+0x264] of players[owner] into the game's 12 colours
// (WFE's own table holds them too, WFEGameColours.ini; these are the game's).
// Neutrals and anything past 11: dark grey.
static const DWORD PLAYER_COLOURS[12] = { 0xFFFF0303, 0xFF0042FF, 0xFF1CE6B9, 0xFF540081, 0xFFFFFC01, 0xFFFE8A0E,
                                          0xFF20C000, 0xFFE55BB0, 0xFF959697, 0xFF7EBFF1, 0xFF106246, 0xFF4E2A04 };
static const DWORD PLAYER_COLOUR = 0x264, NO_PLAYER_COLOUR = 0xFF2E2D2E;
static DWORD PlayerColour(BYTE *state, int owner) {
    BYTE *pl = *(BYTE **)(state + 0x58 + owner * 4);
    DWORD i = pl ? *(DWORD *)(pl + PLAYER_COLOUR) : 0xFFFFFFFF;
    if (!(g_colourLogged >> owner & 1)) {
        g_colourLogged |= 1u << owner;
        Log("health bar colours: player %d's colour index is %ld", owner, (LONG)i);
    }
    return i < 12 ? PLAYER_COLOURS[i] : NO_PLAYER_COLOUR;
}

// -- your hero's buffs, from the unit (buff alerts on 1.28f) -----------------------------
// Not the buff bar: the unit's own list, as the game's bar fill lists it (+0x6b2460, read by
// hand; study_buffs2.md "Settled"): the ability chain from the handle pair [unit+0x1dc], each
// next at [ability+0x24], resolved as +0x8ae90 does (the lookup, alive [x+0x20] == 0, [x+0x54]);
// a buff when vt+0x1e0 (negative) or vt+0x1e4 (positive) says so (CBuff's own both say 0) and its
// class tag is 'buff' or 'B...' (the game asks +0x76930, which allocates: all 224 buff classes'
// tags are those, one 'AItb' item ability aside). Its name: the buff UI table the bar fill uses
// (+0x3de2dc: [+0xd33150] buckets of 12 bytes, mask [+0xd33158], bucket id & mask, chain from
// [bucket+8] through [rec + [bucket] + 4] while > 0, key [rec], name rec+0x11c (64 bytes),
// filled by the game when a buff is first applied, RegisterBuffOnce +0x3fe210), read here.
// The hero: the selection's active unit [[player+0x34]+0x1e0] when it's a hero of yours
// (remembered by its handle), else the one remembered, else the first hero of yours in the
// unit list. All reads; on the game thread with the other timers.
static const DWORD UNIT_ABILITIES = 0x1dc, ABILITY_NEXT = 0x24, BUFF_UI_BUCKETS = 0xd33150, BUFF_UI_MASK = 0xd33158, BUFF_UI_NAME = 0x11c;
static const DWORD SEL_PLAYER_SELECTION = 0x34, SEL_ACTIVE = 0x1e0;
static DWORD g_heroPair[2] = { 0xFFFFFFFF, 0xFFFFFFFF };
// an agent from its handle pair, as the game's +0x8ae90 (none: both -1, as the game's test)
static BYTE *PairObject(const DWORD *pair) {
    if ((pair[0] & pair[1]) == 0xFFFFFFFF)
        return nullptr;
    BYTE *x = (BYTE *)((LookupFn)(g_base + RVA_HANDLE_LOOKUP))(pair[0], pair[1]);
    return x && !*(DWORD *)(x + HANDLE_DEAD) ? *(BYTE **)(x + HANDLE_OBJ) : nullptr;
}
static int LocalPlayer(BYTE **state) {
    *state = *(BYTE **)(g_base + RVA_PLAYERS);
    int local = *state ? *(short *)(*state + 0x28) : -1;
    return local >= 0 && local <= 15 && local < *(int *)(*state + 0x54) ? local : -1;
}
static bool MyHero(BYTE *u, int local) { return IsUnit(u) && *(int *)(u + UNIT_OWNER) == local && IsHero(u); }
static BYTE *FindMyHero() {
    BYTE *state;
    int local = LocalPlayer(&state);
    if (local < 0)
        return nullptr;
    BYTE *player = *(BYTE **)(state + 0x58 + 4 * local), *sel = player ? *(BYTE **)(player + SEL_PLAYER_SELECTION) : nullptr;
    BYTE *u = sel ? *(BYTE **)(sel + SEL_ACTIVE) : nullptr;
    if (!MyHero(u, local)) {
        u = PairObject(g_heroPair);
        if (!MyHero(u, local)) {
            u = nullptr;
            BYTE *list = g_base + RVA_UNIT_LIST;
            DWORD count = *(DWORD *)(list + 4);
            BYTE **units = *(BYTE ***)(list + 8);
            for (DWORD i = 0; units && i < count && i < 4096 && !u; i++)
                if (MyHero(units[i], local))
                    u = units[i];
        }
    }
    if (u)
        g_heroPair[0] = *(DWORD *)(u + AGENT_HANDLE), g_heroPair[1] = *(DWORD *)(u + AGENT_HANDLE + 4);
    return u;
}
// a getter that's just "mov eax, imm32; ret" or "xor eax, eax; ret": its value without a call
static bool ConstGetter(const BYTE *f, DWORD *v) {
    if (!IsGameCode(f))
        return false;
    if (f[0] == 0xB8 && f[5] == 0xC3)
        return *v = *(const DWORD *)(f + 1), true;
    if (f[0] == 0x33 && f[1] == 0xC0 && f[2] == 0xC3)
        return *v = 0, true;
    return false;
}
static DWORD VirtualConst(BYTE *obj, DWORD slot) {
    DWORD vt = *(DWORD *)obj, v;
    if (vt < (DWORD)g_base || vt - (DWORD)g_base >= g_imageSize)
        return 0;
    return ConstGetter(*(const BYTE **)(vt + slot), &v) ? v : (DWORD)VirtualInt(obj, slot);
}
// the game's name for a buff (Bufftip), "|cAARRGGBB" / "|r" taken out, "|n" a space; false: none
static bool BuffName(DWORD id, char *out, int n) {
    out[0] = 0;
    BYTE *buckets = *(BYTE **)(g_base + BUFF_UI_BUCKETS);
    DWORD mask = *(DWORD *)(g_base + BUFF_UI_MASK);
    if (!buckets || mask == 0xFFFFFFFF)
        return false;
    BYTE *b = buckets + (id & mask) * 12, *rec = *(BYTE **)(b + 8);
    for (int k = 0; (LONG)(DWORD)rec > 0 && k < 256; k++) {
        if (*(DWORD *)rec == id) {
            const char *s = (const char *)(rec + BUFF_UI_NAME);
            int o = 0;
            for (int i = 0; i < 64 && s[i] && o < n - 1; i++) {
                if (s[i] == '|' && (s[i + 1] == 'c' || s[i + 1] == 'C') && i + 9 < 64) {
                    i += 9;
                    continue;
                }
                if (s[i] == '|' && (s[i + 1] == 'r' || s[i + 1] == 'R' || s[i + 1] == 'n' || s[i + 1] == 'N')) {
                    if (s[i + 1] == 'n' || s[i + 1] == 'N')
                        out[o++] = ' ';
                    i++;
                    continue;
                }
                out[o++] = s[i];
            }
            while (o && out[o - 1] == ' ')
                o--;
            out[o] = 0;
            return o > 0;
        }
        rec = *(BYTE **)(rec + *(DWORD *)b + 4);
    }
    return false;
}
static void ReadHeroBuffs() {
    Shared *s = g_shared;
    BYTE *u = FindMyHero();
    DWORD count = 0;
    s->hrHero = u ? *(DWORD *)(u + 0x30) : 0;
    float hp = 0;
    if (u)
        ((HpFn)(g_base + RVA_UNIT_HP))(u + UNIT_HP, 0, &hp);
    s->hrAlive = u && hp == hp && hp > 0;     // the unit state +0x81b30 on +0x98, as the health bar colours read it
    static BYTE *logged;                    // the hero last logged; the first rawcodes seen, logged once each
    static DWORD seen[8];
    static int nSeen;
    if (u && u != logged)
        logged = u, Log("hero buffs: your hero is '%s' (unit %p)", IdText(s->hrHero).s, u);
    const DWORD *pair = u ? (DWORD *)(u + UNIT_ABILITIES) : nullptr;
    for (int k = 0; pair && k < 64 && count < 24; k++) {
        BYTE *a = PairObject(pair);
        if (!a || *(DWORD *)a < (DWORD)g_base || *(DWORD *)a - (DWORD)g_base >= g_imageSize)
            break;
        pair = (DWORD *)(a + ABILITY_NEXT);
        DWORD neg = VirtualConst(a, 0x1e0), pos = neg ? 0 : VirtualConst(a, 0x1e4), tag = VirtualConst(a, 0x1c);
        if (!neg && !pos || tag != 'buff' && (tag >> 24) != 'B')
            continue;
        bool aura = VirtualConst(a, 0x1e8) != 0;
        int i = (int)count++;
        float left, total;
        BuffTimeOf(a, aura, &left, &total);
        s->hrId[i] = *(DWORD *)(a + BUFF_ID), s->hrLeft[i] = left, s->hrTotal[i] = total;
        bool named = BuffName(s->hrId[i], s->hrName[i], sizeof(s->hrName[i]));
        s->hrFlags[i] = 1 | (aura ? 2 : 0) | (pos ? 4 : 0) | (named ? 8 : 0);
        bool known = false;
        for (int j = 0; j < nSeen; j++)
            known |= seen[j] == s->hrId[i];
        if (!known && nSeen < 8)
            seen[nSeen++] = s->hrId[i], Log("hero buffs: '%s' %s%s, named '%s'%s, %.1f s of %.1f left", IdText(s->hrId[i]).s, pos ? "positive" : "negative",
                                           aura ? " aura" : "", s->hrName[i], named ? "" : " (not in the game's buff names)", left, total);
    }
    for (DWORD i = count; i < 24; i++)
        s->hrId[i] = s->hrFlags[i] = 0, s->hrLeft[i] = s->hrTotal[i] = 0, s->hrName[i][0] = 0;
    s->hrCount = count;
    static bool none;
    if (!u && !none)
        none = true, Log("hero buffs: no hero of yours found (selection, unit list)");
}

// WFE's by-health colour: green over half, then to yellow, then to red
static DWORD HealthColour(float r) {
    r = r < 0 ? 0 : r > 1 ? 1 : r;
    float g = r >= 0.5f ? 1 : 2 * r, rd = r <= 0.5f ? 1 : 1 - 2 * (r - 0.5f);
    return 0xFF000000 | ((DWORD)(rd * 255) << 16) | ((DWORD)(g * 255) << 8);
}

static DWORD BarColour(BYTE *unit) {
    if (g_shared->hcMode == 1) {
        float hp = 0;
        ((HpFn)(g_base + RVA_UNIT_HP))(unit + UNIT_HP, 0, &hp);
        DWORD *pair = (DWORD *)(unit + UNIT_MAXHP_HANDLE);
        BYTE *mx = pair[0] != 0xFFFFFFFF ? (BYTE *)((LookupFn)(g_base + RVA_HANDLE_LOOKUP))(pair[0], pair[1]) : nullptr;
        float max = mx ? *(float *)(mx + 0x84) : 0;
        return max > 0 && hp == hp ? HealthColour(hp / max) : 0;
    }
    int owner = *(int *)(unit + UNIT_OWNER);
    BYTE *state = *(BYTE **)(g_base + RVA_PLAYERS);
    int players = state ? *(int *)(state + 0x54) : 0, local = state ? *(short *)(state + 0x28) : -1;
    static bool logged;
    if (!logged) {
        logged = true;
        Log("health bar colours: game state %p, local player %d, %d players; the first bar's owner %d", state, local, players, owner);
    }
    if (!state || owner < 0 || owner > 15 || local < 0 || local > 15)
        return 0;
    const DWORD *c = g_shared->hcColours;
    DWORD r = owner == local ? c[0] : owner == 12 ? c[3] : owner == 15 ? c[4] : Allied(state, local, owner) ? c[1] : c[2];
    return r >> 24 ? r : PlayerColour(state, owner);
}

// after the game's update: the fill's colour bytes (A, B, G, R at +0x68), then its redraw
static void ColourBar(BYTE *bar, BYTE *unit) {
    static int faults;
    __try {
        if (*(DWORD *)(bar + BAR_KIND) != 5)
            return;
        if (!unit)
            unit = *(BYTE **)(bar + BAR_UNIT);
        BYTE *fill = *(BYTE **)(bar + BAR_FILL);
        if (!unit || !fill)
            return;
        DWORD c = BarColour(unit);
        if (!c)
            return;
        fill[0x68] = (BYTE)(c >> 24), fill[0x69] = (BYTE)c, fill[0x6a] = (BYTE)(c >> 8), fill[0x6b] = (BYTE)(c >> 16);
        DWORD fvt = *(DWORD *)fill, f = *(DWORD *)(fvt + 0x24);
        if (f >= (DWORD)g_base && f - (DWORD)g_base < g_imageSize)
            ((ColourFn)f)(fill, 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        if (faults++ < 3)
            Log("health bar colours: colouring a bar faulted");
    }
}

static bool g_extrasHooked;                 // mana bars / health numbers: the bar's hide, show and dtor entries are ours too
static bool g_barFresh;                     // BarExtras runs in the game's bar work: the bar's width isn't another mod's yet
static void BarExtras(BYTE *bar, BYTE *unit);

static int SizeThisBar(BYTE *bar, float h, float w, bool freshWidth);
static bool BarSizeWanted(float *h, float *w);

// after the game repainted a bar (its update +0x74, or its set-unit +0x78, which repaints
// without the update): the colour, the size (WFE writes the height here too, every update,
// so the game's own size never shows in between; the width only when the game's bar work
// has just set it, ret = where the hook returns to), the extras
static void BarAfter(BYTE *bar, BYTE *unit, const void *ret) {
    if (g_shared->hcOn)
        ColourBar(bar, unit);
    float h, w;
    bool fresh = ret == g_base + RVA_BAR_WIDTH_SET_UNIT_RET || ret == g_base + RVA_BAR_WIDTH_UPDATE_RET;
    if (BarSizeWanted(&h, &w))
        SizeThisBar(bar, h, w, fresh);
    if (g_extrasHooked)
        g_barFresh = fresh, BarExtras(bar, unit), g_barFresh = false;
}
static void __fastcall BarUpdateHook(void *bar, int edx, void *unit) {
    g_gameBarUpdate(bar, edx, unit);        // the game's own update, untouched
    BarAfter((BYTE *)bar, (BYTE *)unit, _ReturnAddress());
}
// vt+0x78 (+0x4101c0): sets the bar's unit and repaints it, through the update or on its own
// (WFE replaces it, 0x100793e0; here the game's runs first)
static BarUpdateFn g_gameBarSetUnit;
static void __fastcall BarSetUnitHook(void *bar, int edx, void *unit) {
    g_gameBarSetUnit(bar, edx, unit);
    BarAfter((BYTE *)bar, (BYTE *)unit, _ReturnAddress());
}

// point the shared vtable entries (update +0x74, set-unit +0x78) at the hooks (on) or back at the game's (off)
static const DWORD STATBAR_SET_UNIT = 0x78;
static bool SwapBarUpdate(bool on) {
    DWORD *slot = (DWORD *)(g_base + RVA_STATBAR_VTABLE + STATBAR_UPDATE), *slot2 = slot + (STATBAR_SET_UNIT - STATBAR_UPDATE) / 4;
    if (on == g_barHooked)
        return true;
    if (!PageIs(slot, READ) || PageIs(slot, EXEC))
        return false;
    DWORD cur = *slot, cur2 = *slot2;
    if (on && ((!g_gameBarUpdate && !IsGameCode((BYTE *)cur)) || (!g_gameBarSetUnit && !IsGameCode((BYTE *)cur2)))) {
        Log("health bar colours: refused, the bar update / set-unit entries (%08lX / %08lX) aren't game code", cur, cur2);
        return false;
    }
    if (!on && (cur != (DWORD)BarUpdateHook || cur2 != (DWORD)BarSetUnitHook)) {
        Log("health bar colours: the bar update entries were changed by someone else: left as they are");
        return false;
    }
    if (on && !g_gameBarUpdate)
        g_gameBarUpdate = (BarUpdateFn)cur;   // before the swap: the hooks call them
    if (on && !g_gameBarSetUnit)
        g_gameBarSetUnit = (BarUpdateFn)cur2;
    DWORD want = on ? (DWORD)BarUpdateHook : (DWORD)g_gameBarUpdate, want2 = on ? (DWORD)BarSetUnitHook : (DWORD)g_gameBarSetUnit, old;
    if (!VirtualProtect(slot, 8, PAGE_READWRITE, &old))
        return false;
    InterlockedExchange((volatile LONG *)slot, (LONG)want);
    InterlockedExchange((volatile LONG *)slot2, (LONG)want2);
    VirtualProtect(slot, 8, old, &old);
    g_barHooked = on;
    Log(on ? "bar update: wrapped (+%06lX, set-unit +%06lX)" : "bar update: the game's own again (+%06lX, set-unit +%06lX)",
        (DWORD)g_gameBarUpdate - (DWORD)g_base, (DWORD)g_gameBarSetUnit - (DWORD)g_base);
    return true;
}

static volatile LONG g_extrasWant;      // the game thread: mana bars / health numbers need the bar update wrapped

// the worker's part: follow the companion's switch (and keep the update wrapped
// while mana bars or health numbers need it)
static void FollowColours() {
    static bool refused, colours;
    if (!g_getUi || refused)
        return;
    bool want = g_shared->hcOn || g_extrasWant || g_shared->hbOn;
    if (want && !g_barHooked) {
        if (!IsGameCode(g_base + RVA_HANDLE_LOOKUP) || !IsGameCode(g_base + RVA_UNIT_HP) || !SwapBarUpdate(true)) {
            refused = true, g_shared->hcState = 2;
            Log("health bar colours: refused (the bar update can't be wrapped)");
            return;
        }
    } else if (!want && g_barHooked)
        SwapBarUpdate(false);
    bool c = g_shared->hcOn && g_barHooked;
    if (c != colours)
        colours = c, Log(c ? "health bar colours: on" : "health bar colours: off");
    g_shared->hcState = c ? 1 : 0;
}

static bool FnStart(DWORD rva);

// -- frames added to the game ---------------------------------------------------------
// Timers drawn in the game, health numbers and mana bars (study_timerframes.md,
// study_hpmp_bars.md, study_storm.md; every address re-checked by hand in WFE's
// 1.28f branches). New frames are made as WFE makes them: the game's Storm
// SMemAlloc, then the game's own constructor, on the game thread.
// Text frames are children of the game UI: the game frees them when the game
// ends, and the module only forgets them then (another game UI, or none).
// A mana bar is a second CStatBar made by the game's own constructor for a
// unit's health bar (WFE packs the two into one object of its own instead):
// it's updated, shown and hidden with the health bar, and destroyed with it,
// through the hide, show and dtor entries of the shared CStatBar vtable (data
// writes, as the update's; put back when both features are off and no mana
// bar is left).
static const DWORD RVA_TEXT_CTOR = 0x12b3d0;        // CTextFrame __fastcall(mem, 0, parent, layer, id) -> it (WFE's [0x1013a5a0])
static const DWORD RVA_TEXT_FLAGS = 0x12c240;       // __fastcall(text, 0, flags changed) ([0x1013a5a4])
static const DWORD RVA_TEXT_SET = 0x12c500;         // __fastcall(text, 0, const char *): the game copies it ([0x1013a5a8])
static const DWORD RVA_SET_FONT = 0x11f210;         // __fastcall(text, 0, path, float height, flags) ([0x1013a1e4])
static const DWORD RVA_SET_POINT = 0x13fc20;        // __fastcall(layout, 0, point, relative, its point, float x, float y, 1) ([0x1013a220])
static const DWORD RVA_SET_ABS_POINT = 0x13fbb0;    // __fastcall(layout, 0, point, float x, float y, 1) ([0x1013a228])
static const DWORD RVA_SKIN_LOOKUP = 0x3761e0;      // __fastcall(key, 0) -> const char * ([0x1013c87c]: "MasterFont" -> the font file)
static const DWORD RVA_TEXT_VTABLE = 0xa7b3d0;      // CTextFrame ([0x1013a598])
static const DWORD RVA_TEXT_LAYOUT_VTABLE = 0xa7b4e4;   // its layout part, at +0xb4 ([0x1013a59c])
static const DWORD RVA_BAR_CTOR = 0x3d57f0;         // CStatBar __fastcall(mem, 0, 0, [health bar+0x154], kind) -> it ([0x1013a970])
static const DWORD RVA_BAR_LEVEL = 0x3a7ca0;        // __fastcall(bar, 0, [health bar+0x84]) ([0x1013a980])
static const DWORD RVA_REGION_HIDE = 0x141ce0;      // a region's (texture, font string) hide, __fastcall(region, 0) ([0x1013aa3c]): WFE hides a bar's own text [bar+0x140] with it
static const DWORD RVA_REGION_SHOW = 0x141e80;      // and its show ([0x1013aa40])
static const DWORD TEXT_LAYOUT = 0xb4, TEXT_FLAGS = 0x1f0, TEXT_COLOURS = 0x1f4, TEXT_SIZE = 0x240, TEXT_ID = 0x1388;
static const DWORD TEXT_HIDE = 0xd0, TEXT_SHOW = 0xd4, TEXT_SHADOW = 0x200, TEXT_SHADOW_OFFSET = 0x208;
static const DWORD BAR_SIZE = 0x160;                // WFE fits two in 0x2bc (the second at +0x158)
static const DWORD BAR_DTOR = 0x08, BAR_HIDE = 0x64, BAR_SHOW = 0x68, BAR_RATIO = 0x6c;
static const DWORD BAR_POS = 0xc, BAR_SHOWN = 0x94, BAR_LEVEL_ARG = 0x84, BAR_TEXT = 0x140, BAR_CUR = 0x148, BAR_MAX = 0x14c;
static const DWORD UNIT_MANA = 0xb8, UNIT_MAXMANA_HANDLE = 0xc0;
enum { PT_TOP = 1, PT_CENTER = 4, PT_BOTTOM = 7 };

// A game function with ecx, edx and n stack arguments. esp is put back after
// the call whoever cleans the stack, so the call can't unbalance it. Floats
// go as their bits (F).
static __declspec(noinline) DWORD GameCall(const void *fn, DWORD rc, DWORD rd, int n, const DWORD *a) {
    DWORD r;
    __asm {
        mov esi, esp
        mov edi, a
        mov eax, n
    push_next:
        test eax, eax
        jz call_it
        dec eax
        push dword ptr [edi + eax * 4]
        jmp push_next
    call_it:
        mov ecx, rc
        mov edx, rd
        mov eax, fn
        call eax
        mov esp, esi
        mov r, eax
    }
    return r;
}
static DWORD Game(DWORD rva, const void *ecx, std::initializer_list<DWORD> a = {}) {
    return GameCall(g_base + rva, (DWORD)ecx, 0, (int)a.size(), a.begin());
}
static DWORD Virt(const void *obj, DWORD slot, std::initializer_list<DWORD> a = {}) {
    return GameCall(*(void **)(*(BYTE **)obj + slot), (DWORD)obj, 0, (int)a.size(), a.begin());
}
static DWORD F(float f) {
    DWORD d;
    memcpy(&d, &f, 4);
    return d;
}

// data in the game module whose first entries (and these) are game code
// an entry that's ours: one of the module's own hooks swapped in (the bar update when colours went on first)
static bool OurCode(const void *p) {
    HMODULE m = nullptr;            // this module (g_self; or, in a test, whatever holds this code)
    if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)&OurCode, &m))
        m = g_self;
    BYTE *b = (BYTE *)m;
    return b && (BYTE *)p >= b && (DWORD)((BYTE *)p - b) < ImageSize(b);
}
static bool GameVtable(DWORD rva, std::initializer_list<DWORD> slots) {
    DWORD *vt = (DWORD *)(g_base + rva);
    if (!PageIs(vt, READ) || PageIs(vt, EXEC) || !IsGameCode((BYTE *)vt[0]) || !IsGameCode((BYTE *)vt[1]))
        return false;
    for (DWORD s : slots)
        if (!PageIs(vt + s / 4, READ) || (!IsGameCode((BYTE *)vt[s / 4]) && !OurCode((BYTE *)vt[s / 4])))
            return false;
    return true;
}

// Once: Storm, and every game function and vtable the frames use. 1 ready,
// 2 no Storm.dll in the game, 3 refused (logged)
static int FramesCheck() {
    static int r;
    if (r)
        return r;
    int s = g_smemAlloc ? 1 : StormCheck();
    if (s != 1)
        return r = s;
    static const struct { const char *name; DWORD rva; } FNS[] = {
        { "text frame constructor", RVA_TEXT_CTOR }, { "text flags", RVA_TEXT_FLAGS }, { "text setter", RVA_TEXT_SET },
        { "font setter", RVA_SET_FONT }, { "anchor", RVA_SET_POINT }, { "position", RVA_SET_ABS_POINT },
        { "skin lookup", RVA_SKIN_LOOKUP }, { "layout refresh", RVA_LAYOUT_REFRESH }, { "bar constructor", RVA_BAR_CTOR },
        { "bar level", RVA_BAR_LEVEL }, { "region hide", RVA_REGION_HIDE }, { "unit state", RVA_UNIT_HP },
        { "handle lookup", RVA_HANDLE_LOOKUP } };
    for (const auto &f : FNS)
        if (!FnStart(f.rva)) {
            Log("frames: refused, the %s +%06lX isn't a function start", f.name, f.rva);
            if (PageIs(g_base + f.rva, READ))
                LogBytes("  its bytes", g_base + f.rva);
            return r = 3;
        }
    if (!GameVtable(RVA_TEXT_VTABLE, { TEXT_HIDE, TEXT_SHOW }) || !GameVtable(RVA_TEXT_LAYOUT_VTABLE, {})
        || !GameVtable(RVA_COMMAND_BUTTON_VTABLE, {}) || !GameVtable(RVA_STATBAR_VTABLE, { BAR_DTOR, BAR_HIDE, BAR_SHOW, BAR_RATIO, STATBAR_UPDATE })) {
        Log("frames: refused, a vtable (text frame +%06lX / +%06lX, command button +%06lX, bar +%06lX) isn't game data with code entries",
            RVA_TEXT_VTABLE, RVA_TEXT_LAYOUT_VTABLE, RVA_COMMAND_BUTTON_VTABLE, RVA_STATBAR_VTABLE);
        return r = 3;
    }
    Log("frames: the game's frame functions check out");
    return r = 1;
}

// the game's own font for the frames ("MasterFont" in its skin), read once
static const char *FontPath() {
    static char path[MAX_PATH];
    if (!path[0]) {
        const char *p = nullptr;
        __try {
            p = (const char *)Game(RVA_SKIN_LOOKUP, "MasterFont");
            if (p && PageIs(p, READ))
                strncpy_s(path, p, _TRUNCATE);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            path[0] = 0;
        }
        if (!path[0] || !strchr(path, '.'))
            strcpy_s(path, "Fonts\\FRIZQT__.TTF");
        Log("frames: font %s (%s)", path, p ? "the skin's MasterFont" : "the default");
    }
    return path;
}

static bool g_framesBad;            // a new frame didn't check out, or a frame call faulted: no more frames (logged)

static void FramesStop(const char *why) {
    if (!g_framesBad)
        Log("frames: %s: no more frames in this session", why);
    g_framesBad = true;
}

static void TextColour(BYTE *t, DWORD argb) {
    DWORD *c = (DWORD *)(t + TEXT_COLOURS);
    if (c[0] != argb || c[1] != argb || c[2] != argb)
        c[0] = c[1] = c[2] = argb, *(DWORD *)(t + 0x22c) = 1;
}

// a new CTextFrame under the game UI (hidden), in the game's font: WFE's
// 0x100214f0 + 0x10080f60. 0 if refused or it didn't work (then never again)
static BYTE *NewText(BYTE *ui, DWORD layer, float height, DWORD argb) {
    if (g_framesBad)
        return nullptr;
    void *mem = g_smemAlloc(TEXT_SIZE, "TWC text frame", __LINE__, 0);
    if (!mem) {
        FramesStop("SMemAlloc gave no memory");
        return nullptr;
    }
    BYTE *t;
    __try {
        t = (BYTE *)Game(RVA_TEXT_CTOR, mem, { (DWORD)ui, layer, TEXT_ID });
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        FramesStop("the text frame constructor faulted");      // the memory is left: the game may hold it
        return nullptr;
    }
    if (t != mem || *(DWORD *)t != (DWORD)(g_base + RVA_TEXT_VTABLE) || *(DWORD *)(t + TEXT_LAYOUT) != (DWORD)(g_base + RVA_TEXT_LAYOUT_VTABLE)) {
        Log("frames: the new text frame %p (memory %p) has vtables %08lX / %08lX, not +%06lX / +%06lX", t, mem,
            t == mem ? *(DWORD *)t : 0, t == mem ? *(DWORD *)(t + TEXT_LAYOUT) : 0, RVA_TEXT_VTABLE, RVA_TEXT_LAYOUT_VTABLE);
        FramesStop("a text frame didn't check out");
        return nullptr;
    }
    __try {
        Game(RVA_SET_FONT, t, { (DWORD)FontPath(), F(height), 0 });
        *(DWORD *)(t + 0x220) = 1, *(DWORD *)(t + 0x21c) = 1, *(DWORD *)(t + 0x224) = 1;
        DWORD *fl = *(DWORD **)(t + TEXT_FLAGS);
        if (fl) {
            DWORD old = fl[0], now = old | fl[1] | 0x8c;
            fl[0] = now;
            if (now ^ old)
                Game(RVA_TEXT_FLAGS, t, { now ^ old });
            *(DWORD *)(t + 0x224) = 1, *(DWORD *)(t + 0x22c) = 1, *(DWORD *)(t + 0x230) = 1, *(DWORD *)(t + 0x23c) = 1;
        }
        TextColour(t, argb);
        // no shadow of its own: the game's constructor gives a text frame a black one 0.015 right
        // and down (+0x200 = FF000000, +0x210 / +0x214 = 0.015 / -0.015, +0x12b48a): the dark
        // second number beside each health number (the user's screenshot). As WFE's 0x10080f60:
        // +0x200 = 0, the 16 bytes at +0x208 cleared, then marked to be laid out again.
        *(DWORD *)(t + TEXT_SHADOW) = 0, *(DWORD *)(t + 0x22c) = 1;
        memset(t + TEXT_SHADOW_OFFSET, 0, 16);
        *(DWORD *)(t + 0xc) |= *(DWORD *)(t + 0x10) | 2;
        Virt(t, TEXT_HIDE);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        FramesStop("setting up a text frame faulted");
        return nullptr;
    }
    if (!g_shared->frCount++)
        Log("frames: the first text frame %p checks out", t);
    return t;
}

static void TextShow(BYTE *t, bool on) { Virt(t, on ? TEXT_SHOW : TEXT_HIDE); }
static void TextSet(BYTE *t, const char *s) { Game(RVA_TEXT_SET, t, { (DWORD)s }); }
// anchored to another frame (WFE's refresh, then its anchor)
static void TextAnchor(BYTE *t, BYTE *to, int pt, int toPt, float x, float y) {
    Game(RVA_LAYOUT_REFRESH, t + TEXT_LAYOUT, { 1 });
    Game(RVA_SET_POINT, t + TEXT_LAYOUT, { (DWORD)pt, (DWORD)to, (DWORD)toPt, F(x), F(y), 1 });
}
// at a spot on the screen (UI units), not tied to any frame
static void TextAt(BYTE *t, int pt, float x, float y) {
    Game(RVA_SET_ABS_POINT, t + TEXT_LAYOUT, { (DWORD)pt, F(x), F(y), 1 });
}

// -- timers drawn in the game ----------------------------------------------------------
// As WFE's Cooldown UI and BUFFUI, text only (no models): seconds left in the
// middle of each command card and inventory button that's cooling down (both
// CCommandButtons: WFE's class 0x2d is only that vtable), and under each buff
// icon (WFE's spot: bottom to bottom, 0.0115 lower). The times are read here on
// the game thread, 10 times a second.
// Better seen than WFE's (which puts four black copies under white): every text has a
// full black outline, eight copies around it (the game's text frames have only one
// drop shadow, and its font flags no outline); cooldowns can be bigger (cdSize), turn
// gold near the end (cdGold) and say "Ready" in green for half a second when over
// (cdReady); the buffs' seconds the same with bfSize / bfGold, and on auras with bfOpts 1.
// The copies go first, so the text is drawn over them.
static const int OUTLINES = 8;
struct TimerSlot { BYTE *btn, *text, *out[OUTLINES]; char shown[12]; float height; DWORD colour; float last; DWORD readyUntil; };
static TimerSlot g_tCd[12], g_tBuff[16], g_tItem[6];
static BYTE *g_framesUi;            // the game UI the text frames belong to (another one: they're gone)
static const float OUTLINE = 0.0008f, CD_TEXT = 0.014f, BUFF_TEXT_Y = -0.0115f, READY_SIZE = 0.75f;
static const DWORD WHITE = 0xFFFFFFFF, BLACK = 0xFF000000, GOLD = 0xFFFFCC00, GREEN = 0xFF40FF40;
static const float OUT_DIR[OUTLINES][2] = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.7f, 0.7f }, { -0.7f, 0.7f }, { 0.7f, -0.7f }, { -0.7f, -0.7f } };
// WFE's [BUFFUI] TEXTSIZE 0.013, 0.0105 with its Upgraded UI on and the buff bar not raised;
// times bfSize (0.75-1.5), as the cooldowns' cdSize
static float BuffTextHeight() {
    float k = g_shared->bfSize;
    return (g_shared->ulOn && !(g_shared->ulOn & 2) ? 0.0105f : 0.013f) * (k >= 0.75f && k <= 1.5f ? k : 1);
}
// a buff bar slot gets its seconds: a buff, or an aura with bfOpts bit 1 (WFE's ISDRAWAURADURATION:
// its 0x1007f774..0x1007f785 takes the aura switch for auras, the duration switch for the rest)
static const DWORD BF_AURAS = 1, BF_RING = 2;
static bool BuffSlotDrawn(DWORD flags) { return (flags & 1) && (!(flags & 2) || (g_shared->bfOpts & BF_AURAS)); }
// the cooldowns' size (cdSize, 0.75-1.5 times 0.014)
static float CdTextHeight() {
    float k = g_shared->cdSize;
    return CD_TEXT * (k >= 0.75f && k <= 1.5f ? k : 1);
}

// as WFE's 0x10033b60: tenths under 1 s, else whole seconds rounded up; m:ss from a minute
// only with DISPLAYMINUTES (tmMinutes; WFE's default is off: 0x1006c70e reads it with 0)
static const DWORD MIN_COOLDOWNS = 1, MIN_BUFFS = 2;
static void TimeText(float s, char *b, size_t n, bool minutes) {
    if (!(s > 0) || s > 99 * 60)
        b[0] = 0;
    else if (s < 1)
        sprintf_s(b, n, "%.1f", s);
    else {
        int c = (int)ceilf(s);
        if (c < 60 || !minutes)
            sprintf_s(b, n, "%d", c);
        else
            sprintf_s(b, n, "%d:%02d", c / 60, c % 60);
    }
}

static void SlotHide(TimerSlot &s) {
    if (s.shown[0] && s.text) {
        for (BYTE *o : s.out)
            if (o)
                TextShow(o, false);
        TextShow(s.text, false);
    }
    s.shown[0] = 0;
}

// a slot's text on its button: the buffs' where WFE's BUFFUI puts them (bottom to the icon's
// bottom 0.0115 lower), the cooldowns' in the middle; each with its outline
static void SlotDraw(BYTE *ui, TimerSlot &s, BYTE *btn, float left, bool buff) {
    char t[12];
    TimeText(left, t, sizeof(t), (g_shared->tmMinutes & (buff ? MIN_BUFFS : MIN_COOLDOWNS)) != 0);
    // a cooldown that just ran out on the same button (not another unit selected): "Ready"
    DWORD now = GetTickCount();
    if (!buff && btn && btn == s.btn && !t[0] && s.last > 0 && s.last < 0.6f && g_shared->cdReady)
        s.readyUntil = now + 500;
    s.last = btn ? left : 0;
    bool ready = !buff && !t[0] && btn && btn == s.btn && s.readyUntil && (LONG)(now - s.readyUntil) < 0;
    if (!ready)
        s.readyUntil = 0;
    if (ready)
        strcpy_s(t, "Ready");
    if (!t[0] || !btn) {
        SlotHide(s);
        return;
    }
    float h = buff ? BuffTextHeight() : CdTextHeight() * (ready ? READY_SIZE : 1);
    if (!s.text) {
        for (BYTE *&o : s.out)
            if (!(o = NewText(ui, buff ? 0 : 4, h, BLACK)))
                return;                     // frames stopped (logged): nothing more is made
        if (!(s.text = NewText(ui, buff ? 0 : 4, h, WHITE)))
            return;
        s.btn = nullptr, s.height = h, s.colour = WHITE;
    }
    if (s.height != h) {                    // another size: the widescreen UI's buff bar, cdSize, "Ready"
        for (BYTE *o : s.out)
            Game(RVA_SET_FONT, o, { (DWORD)FontPath(), F(h), 0 });
        Game(RVA_SET_FONT, s.text, { (DWORD)FontPath(), F(h), 0 });
        s.height = h;
        if (s.btn == btn)
            s.btn = nullptr;                // anchored again: the outline's distance follows the size
    }
    if (s.btn != btn) {
        int pt = buff ? PT_BOTTOM : PT_CENTER;
        float y = buff ? BUFF_TEXT_Y : 0, d = OUTLINE * h / CD_TEXT;
        for (int i = 0; i < OUTLINES; i++)
            TextAnchor(s.out[i], btn, pt, pt, d * OUT_DIR[i][0], y + d * OUT_DIR[i][1]);
        TextAnchor(s.text, btn, pt, pt, 0, y);
        s.btn = btn;
    }
    float gold = buff ? g_shared->bfGold : g_shared->cdGold;
    DWORD c = ready ? GREEN : gold > 0 && left <= gold ? GOLD : WHITE;
    if (c != s.colour)
        TextColour(s.text, c), s.colour = c;
    if (strcmp(t, s.shown)) {
        for (BYTE *o : s.out)
            TextSet(o, t);
        TextSet(s.text, t);
        if (!s.shown[0]) {
            for (BYTE *o : s.out)
                TextShow(o, true);
            TextShow(s.text, true);
        }
        strcpy_s(s.shown, t);
    }
}

// the command card button at a slot, if it's a command button
static BYTE *CardButton(BYTE *card, int i) {
    BYTE *b = GridButton(card, i / 4, i % 4);
    if (b && *(DWORD *)b != (DWORD)(g_base + RVA_COMMAND_BUTTON_VTABLE)) {
        static int logs;
        if (logs++ < 3)
            Log("timers in the game: the command card button %p has vtable +%06lX, not +%06lX: no text on it", b, *(DWORD *)b - (DWORD)g_base, RVA_COMMAND_BUTTON_VTABLE);
        return nullptr;
    }
    return b;
}
// a buff bar button, if its vtable is game data
static BYTE *BuffButton(BYTE *bar, int cols, int i) {
    BYTE *b = GridButton(bar, i / cols, i % cols);
    return b && InImage(*(DWORD *)b, g_imageSize) && !PageIs((void *)*(DWORD *)b, EXEC) ? b : nullptr;
}

// the frames, from what's in shared memory
static void TimerFramesDraw(BYTE *ui) {
    bool cds = (g_shared->itOn & 1) != 0, buffs = (g_shared->itOn & 2) != 0;
    BYTE *card = *(BYTE **)(ui + 0x3c8);
    int rows = card ? *(int *)(card + 0x124) : 0, cols = card ? *(int *)(card + 0x128) : 0;
    bool cardOk = rows > 0 && cols > 0 && rows <= 3 && cols <= 4;
    for (int i = 0; i < 12; i++)
        SlotDraw(ui, g_tCd[i], cds && cardOk && i / 4 < rows && i % 4 < cols ? CardButton(card, i) : nullptr, g_shared->cdLeft[i], false);
    static bool cdDrawn;                    // the end of the cooldowns' trail in the log: one is on screen
    for (int i = 0; i < 12 && !cdDrawn; i++)
        if (g_tCd[i].shown[0])
            cdDrawn = true, Log("timers in the game: the first cooldown drawn ('%s' on the command card button %p, slot %d)", g_tCd[i].shown, g_tCd[i].btn, i + 1);
    BYTE *bar = *(BYTE **)(ui + 0x3c4);
    if (bar && (bar = *(BYTE **)(bar + 0x130)))
        bar = *(BYTE **)(bar + 0x16c);
    rows = bar ? *(int *)(bar + 0x124) : 0, cols = bar ? *(int *)(bar + 0x128) : 0;
    bool barOk = rows > 0 && cols > 0 && rows * cols <= 16;
    for (int i = 0; i < 16; i++)
        SlotDraw(ui, g_tBuff[i], buffs && barOk && i < rows * cols && BuffSlotDrawn(g_shared->buffFlags[i]) ? BuffButton(bar, cols, i) : nullptr, g_shared->buffLeft[i], true);
    for (int i = 0; i < 6; i++) {
        BYTE *b = ItemButton(ui, i);
        SlotDraw(ui, g_tItem[i], cds && b && *(DWORD *)b == (DWORD)(g_base + RVA_COMMAND_BUTTON_VTABLE) ? b : nullptr, g_shared->itemLeft[i], false);
    }
}

static volatile bool g_itReading;   // the game thread reads the timers (the worker leaves them)

// The game's number badge on command card buttons (cdNoBadge): maps use it for counters of
// their own (TWRPG: a number counting down on abilities), which sits over our cooldowns. The
// button keeps it at [btn+0x194], a simple frame made the first time a number is set
// (+0x3e1cb0, from +0x4034b0 SetNumber: '%d' into the font string [btn+0x198] and the frame
// shown; +0x403540 shows / hides it). Its regions (the badge texture and the number) are
// hidden here with the region hide +0x141ce0, which takes a region out of its frame's drawing
// ([r+0x7c] bit 1, frame [r+0x74]); showing the frame again (SetNumber) doesn't put them back,
// nothing in the button code shows them, so a pass only finds new ones. Inventory buttons are
// left (item charges). Shown again with +0x141e80 when turned off; forgotten with the game UI.
static const DWORD BTN_BADGE = 0x194, FRAME_REGIONS = 0xd8, REGION_FRAME = 0x74, REGION_SHOWN = 0x7c;
static BYTE *g_badgeRegions[48];
static int g_badgeN;
static bool g_badgeBad;
static void BadgesPass(BYTE *ui, bool on) {
    if (g_badgeBad)
        return;
    __try {
        if (!on || !ui) {
            for (int i = 0; i < g_badgeN; i++)
                ((FrameFn)(g_base + RVA_REGION_SHOW))(g_badgeRegions[i], 0);
            if (g_badgeN)
                Log("badges: the game's number badges shown again (%d regions)", g_badgeN);
            g_badgeN = 0;
            return;
        }
        BYTE *card = *(BYTE **)(ui + 0x3c8);
        int rows = card ? *(int *)(card + 0x124) : 0, cols = card ? *(int *)(card + 0x128) : 0;
        if (rows <= 0 || cols <= 0 || rows > 3 || cols > 4)
            return;
        int before = g_badgeN;
        for (int i = 0; i < rows * 4; i++) {
            if (i % 4 >= cols)
                continue;
            BYTE *b = GridButton(card, i / 4, i % 4), *ov;
            if (!b || *(DWORD *)b != (DWORD)(g_base + RVA_COMMAND_BUTTON_VTABLE) || !(ov = V(*(BYTE **)(b + BTN_BADGE))))
                continue;
            int k = 0;
            for (BYTE *l = *(BYTE **)(ov + FRAME_REGIONS); l && (DWORD)(l - (BYTE *)0x10000) <= 0x7ffeffff && k < 8; l = *(BYTE **)(l + 4), k++) {
                BYTE *r = V(*(BYTE **)(l + 8));
                if (!r || *(BYTE **)(r + REGION_FRAME) != ov || !(*(DWORD *)(r + REGION_SHOWN) & 1))
                    continue;
                ((FrameFn)(g_base + RVA_REGION_HIDE))(r, 0);
                bool known = false;
                for (int j = 0; j < g_badgeN && !known; j++)
                    known = g_badgeRegions[j] == r;
                if (!known && g_badgeN < 48)
                    g_badgeRegions[g_badgeN++] = r;
            }
        }
        static bool logged;
        if (!logged && g_badgeN > before)
            logged = true, Log("badges: the game's number badge hidden on the command card (%d regions, the first %p of its frame %p)", g_badgeN, g_badgeRegions[0], *(BYTE **)(g_badgeRegions[0] + REGION_FRAME));
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        g_badgeBad = true;
        Log("badges: hiding the game's number badge faulted: left to the game");
    }
}

// The game's cooldown sweep (the clock over a button cooling down; cdNoBadge bit 2): the
// button's [+0x19c] (CommandButtonCooldown, +0x3e1a60), a sprite frame whose model is squeezed
// flat (x 0) the way WFE hides it with its indicator off (study_ul2_cooldown: S.x 0 "which
// hides it"): its matrix written as the Widescreen UI's squeeze does (ModelMatrix, saved
// first), 10 times a second so a reset by the game is undone at once. Command card and
// inventory buttons. Put back (the matrix as found, or as the Widescreen UI found it) when off;
// forgotten with the game UI. The Widescreen UI leaves these models alone meanwhile.
static float *ModelMatrix(BYTE *frame, BYTE **sprite);
static BYTE *P(BYTE *f, DWORD off);
struct SweepSave { BYTE *frame, *sprite; float orig[9]; };
static SweepSave g_sweeps[24];
static int g_sweepN;
static bool g_sweepBad, g_sweepOn;
static float *UlOriginal(BYTE *sprite);
static void SweepHide(BYTE *b) {
    BYTE *s, *f = b ? P(b, 0x19c) : nullptr;
    float *m = f ? ModelMatrix(f, &s) : nullptr;
    if (!m)
        return;
    SweepSave *sv = nullptr;
    for (int i = 0; i < g_sweepN && !sv; i++)
        if (g_sweeps[i].sprite == s)
            sv = &g_sweeps[i];
    if (!sv) {
        static const int OFF[] = { 1, 2, 3, 5, 6, 7 };
        for (int i : OFF)
            if (fabsf(m[i]) > 1e-4f)
                return;                     // turned: left alone (as the Widescreen UI's squeeze)
        if (m[0] <= 0 || m[4] <= 0 || m[8] <= 0 || g_sweepN >= 24)
            return;
        sv = &g_sweeps[g_sweepN++];
        sv->frame = f, sv->sprite = s;
        float *ul = UlOriginal(s);
        memcpy(sv->orig, ul ? ul : m, sizeof(sv->orig));
        static bool logged;
        if (!logged)
            logged = true, Log("sweeps: the game's cooldown clock hidden (model %p, x %.3f -> 0)", s, m[0]);
    }
    m[0] = 0;
}
static void SweepsPass(BYTE *ui, bool on) {
    if (g_sweepBad)
        return;
    __try {
        g_sweepOn = on && ui;
        if (!g_sweepOn) {
            for (int i = 0; i < g_sweepN && ui; i++) {
                BYTE *s2 = nullptr;
                float *m2 = ModelMatrix(g_sweeps[i].frame, &s2);
                if (m2 && s2 == g_sweeps[i].sprite)     // still the same model on that button
                    memcpy(m2, g_sweeps[i].orig, sizeof(g_sweeps[i].orig));
            }
            if (g_sweepN && ui)
                Log("sweeps: the game's cooldown clocks shown again (%d)", g_sweepN);
            g_sweepN = 0;
            return;
        }
        if (BYTE *card = P(ui, 0x3c8)) {
            int rows = *(int *)(card + 0x124), cols = *(int *)(card + 0x128);
            for (int r = 0; rows > 0 && rows <= 3 && cols > 0 && cols <= 4 && r < rows; r++)
                for (int c = 0; c < cols; c++)
                    SweepHide(GridButton(card, r, c));
        }
        for (int i = 0; i < 6; i++)
            SweepHide(ItemButton(ui, i));
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        g_sweepBad = true, g_sweepOn = false;
        Log("sweeps: hiding the game's cooldown clock faulted: left to the game");
    }
}

// Our cooldown ring (cdNoBadge bit 4, an option next to the game's clock): a line around the
// button's edge that runs out as the cooldown does, clockwise from the top-left corner. Made the
// way the game makes the number badge (+0x3e1cb0): a simple frame of ours over the button
// (CSimpleFrame +0x13ae90(mem, button), ret 4; SetAllPoints +0x13fad0 onto it, shown as SetNumber
// shows the badge: [+0x90] = 1, vt+0x68), and in it four textures (CSimpleTexture +0x141fe0(mem,
// frame, layer 2, shown 1), ret 12; SetTexture +0x1435f0(path, 0), ret 8): the game's yellow team
// colour, a solid square. Each side anchored to its corner (SetPoint +0x13fc20, ret 24, a region's
// layout at +0), its length set with the width / height setters (+0x13fce0 / +0x13fb40, the
// layout's +0x58 / +0x5c), hidden with the region hide when empty. Made once per button, kept
// with the game UI (the game frees them with it), hidden when the button isn't cooling down.
// Buffs too (bfOpts bit 2): the buff bar's indicators are simple frames as the buttons are
// (CBuffIndicator: CSimpleFrame / CLayoutFrame at +0, RTTI), so the same ring goes round a buff's
// icon with its time left of its full time (the slots that get seconds: no auras unless asked).
static const DWORD RVA_SIMPLEFRAME_CTOR = 0x13ae90, RVA_SIMPLEFRAME_VT = 0xa7cc14, RVA_TEXTURE_CTOR = 0x141fe0, RING_TEXTURE_VT = 0xa7d13c;
static const DWORD RVA_SET_TEXTURE = 0x1435f0, RVA_SET_ALL_POINTS = 0x13fad0, RVA_SET_WIDTH = 0x13fce0, RVA_SET_HEIGHT = 0x13fb40;
static const DWORD SIMPLEFRAME_SIZE = 0x124, TEXTURE_SIZE = 0xe8, LAYOUT_WIDTH = 0x58, LAYOUT_HEIGHT = 0x5c;
static const char RING_TEXTURE[] = "ReplaceableTextures\\TeamColor\\TeamColor04.blp";
static const float RING_THICK = 0.0018f, BUTTON_SIZE = 0.039f;
struct Ring { BYTE *btn, *frame, *side[4]; float len[4]; bool shown[4]; };
static const int RINGS = 12 + 6 + 8;       // the command card, the inventory, the buff bar
static Ring g_rings[RINGS];
static int g_ringN;
static bool g_ringBad;

static Ring *RingFor(BYTE *btn) {
    for (int i = 0; i < g_ringN; i++)
        if (g_rings[i].btn == btn)
            return &g_rings[i];
    if (g_ringN >= RINGS || g_framesBad)
        return nullptr;
    Ring *r = &g_rings[g_ringN];
    ZeroMemory(r, sizeof(*r));
    void *mem = g_smemAlloc(SIMPLEFRAME_SIZE, "TWC cooldown ring", __LINE__, 0);
    if (!mem)
        return nullptr;
    BYTE *f = (BYTE *)Game(RVA_SIMPLEFRAME_CTOR, mem, { (DWORD)btn });
    if (f != mem || *(DWORD *)f != (DWORD)(g_base + RVA_SIMPLEFRAME_VT)) {
        Log("cooldown ring: the new frame %p has vtable %08lX, not +%06lX: no rings", f, f == mem ? *(DWORD *)f : 0, RVA_SIMPLEFRAME_VT);
        g_ringBad = true;
        return nullptr;
    }
    Game(RVA_SET_ALL_POINTS, f, { (DWORD)btn, 1 });
    *(DWORD *)(f + 0x90) = 1;
    Virt(f, 0x68);
    static const int PT[4] = { 0, 2, 8, 6 };                  // top, right, bottom, left
    for (int k = 0; k < 4; k++) {
        void *tm = g_smemAlloc(TEXTURE_SIZE, "TWC cooldown ring", __LINE__, 0);
        BYTE *t = tm ? (BYTE *)Game(RVA_TEXTURE_CTOR, tm, { (DWORD)f, 2, 1 }) : nullptr;
        if (!t || t != tm || *(DWORD *)t != (DWORD)(g_base + RING_TEXTURE_VT)) {
            Log("cooldown ring: a new texture %p isn't a CSimpleTexture: no rings", t);
            g_ringBad = true;
            return nullptr;
        }
        Game(RVA_SET_TEXTURE, t, { (DWORD)RING_TEXTURE, 0 });
        Game(RVA_SET_POINT, t, { (DWORD)PT[k], (DWORD)f, (DWORD)PT[k], F(0), F(0), 1 });
        Game(k % 2 ? RVA_SET_WIDTH : RVA_SET_HEIGHT, t, { F(RING_THICK) });
        Game(RVA_REGION_HIDE, t);
        r->side[k] = t, r->len[k] = -1;
    }
    r->btn = btn, r->frame = f;
    if (!g_ringN++)
        Log("cooldown ring: the first one made (frame %p over the button %p, textures %s)", f, btn, RING_TEXTURE);
    return r;
}
// the line left: 4 x the time left / the full time, from the top-left corner clockwise
static void RingDraw(BYTE *btn, float left, float total) {
    bool on = btn && left > 0 && total > 0;
    Ring *r = nullptr;
    for (int i = 0; i < g_ringN && !r; i++)
        if (g_rings[i].btn == btn)
            r = &g_rings[i];
    if (!on && !r)
        return;
    if (on && !r && !(r = RingFor(btn)))
        return;
    float w = *(float *)(btn + LAYOUT_WIDTH), h = *(float *)(btn + LAYOUT_HEIGHT);
    w = w > 0.005f && w < 0.2f ? w : BUTTON_SIZE, h = h > 0.005f && h < 0.2f ? h : BUTTON_SIZE;
    float l4 = on ? 4 * min(1.0f, left / total) : 0;
    for (int k = 0; k < 4; k++) {
        float part = max(0.0f, min(1.0f, l4 - k)), len = part * (k % 2 ? h : w);
        bool show = part > 0.01f;
        if (show && fabsf(len - r->len[k]) > 0.0002f)
            Game(k % 2 ? RVA_SET_HEIGHT : RVA_SET_WIDTH, r->side[k], { F(len) }), r->len[k] = len;
        if (show != r->shown[k])
            Game(show ? RVA_REGION_SHOW : RVA_REGION_HIDE, r->side[k]), r->shown[k] = show;
    }
}
// the buff bar (its grid as ReadBuffs reads it) and its buttons, or 0
static BYTE *BuffBarOf(BYTE *ui, int *rows, int *cols) {
    BYTE *bar = ui ? *(BYTE **)(ui + 0x3c4) : nullptr;
    if (bar && (bar = *(BYTE **)(bar + 0x130)))
        bar = *(BYTE **)(bar + 0x16c);
    *rows = bar ? *(int *)(bar + 0x124) : 0, *cols = bar ? *(int *)(bar + 0x128) : 0;
    return bar && *rows > 0 && *cols > 0 && *rows * *cols <= 16 ? bar : nullptr;
}
// cd: rings on cooling down command card / inventory buttons; bf: on the buffs that get seconds
static void RingsPass(BYTE *ui, bool cd, bool bf) {
    if (g_ringBad || g_framesBad)
        return;
    __try {
        BYTE *card = ui ? *(BYTE **)(ui + 0x3c8) : nullptr;
        int rows = card ? *(int *)(card + 0x124) : 0, cols = card ? *(int *)(card + 0x128) : 0;
        bool cardOk = rows > 0 && cols > 0 && rows <= 3 && cols <= 4;
        int brows, bcols;
        BYTE *bar = bf ? BuffBarOf(ui, &brows, &bcols) : nullptr;
        // every ring hidden first unless its button is still counting (another unit selected: other buttons)
        for (int i = 0; i < g_ringN; i++) {
            bool still = false;
            for (int s = 0; cd && cardOk && s < 12 && !still; s++)
                still = s / 4 < rows && s % 4 < cols && GridButton(card, s / 4, s % 4) == g_rings[i].btn && g_shared->cdLeft[s] > 0;
            for (int s = 0; cd && s < 6 && !still; s++)
                still = ItemButton(ui, s) == g_rings[i].btn && g_shared->itemLeft[s] > 0;
            for (int s = 0; bar && s < brows * bcols && !still; s++)
                still = GridButton(bar, s / bcols, s % bcols) == g_rings[i].btn && BuffSlotDrawn(g_shared->buffFlags[s]) && g_shared->buffLeft[s] > 0;
            if (!still)
                RingDraw(g_rings[i].btn, 0, 0);
        }
        if (!ui)
            return;
        for (int s = 0; cd && cardOk && s < 12; s++)
            if (s / 4 < rows && s % 4 < cols)
                if (BYTE *b = CardButton(card, s))
                    RingDraw(b, g_shared->cdLeft[s], g_shared->cdTotal[s]);
        for (int s = 0; cd && s < 6; s++) {
            BYTE *b = ItemButton(ui, s);
            if (b && *(DWORD *)b == (DWORD)(g_base + RVA_COMMAND_BUTTON_VTABLE))
                RingDraw(b, g_shared->itemLeft[s], g_shared->itemTotal[s]);
        }
        for (int s = 0; bar && s < brows * bcols; s++)
            if (BuffSlotDrawn(g_shared->buffFlags[s]))
                if (BYTE *b = BuffButton(bar, bcols, s)) {
                    RingDraw(b, g_shared->buffLeft[s], g_shared->buffTotal[s]);
                    static bool logged;
                    if (!logged && g_shared->buffLeft[s] > 0 && g_shared->buffTotal[s] > 0)
                        logged = true, Log("buff ring: the first one on the buff icon %p (vtable +%06lX), %.1f s of %.1f", b, *(DWORD *)b - (DWORD)g_base, g_shared->buffLeft[s], g_shared->buffTotal[s]);
                }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        g_ringBad = true;
        Log("cooldown ring: a frame call faulted: no more rings");
    }
}

// on the game thread
static void TimerFramesPass(BYTE *ui) {
    BadgesPass(ui, (g_shared->itOn & 1) && (g_shared->cdNoBadge & 1));
    SweepsPass(ui, (g_shared->itOn & 1) && (g_shared->cdNoBadge & 2));
    if (!g_shared->itOn) {
        g_itReading = false;
        RingsPass(ui, false, false);
        __try {
            for (TimerSlot &s : g_tCd)
                SlotHide(s);
            for (TimerSlot &s : g_tBuff)
                SlotHide(s);
            for (TimerSlot &s : g_tItem)
                SlotHide(s);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            FramesStop("timers in the game: hiding them faulted");
        }
        g_shared->itState = 0;
        return;
    }
    int fc = FramesCheck();
    if (fc != 1 || g_framesBad) {
        g_itReading = false;
        g_shared->itState = fc == 2 ? 2 : 3;
        return;
    }
    if (!ui) {
        g_itReading = false;
        g_shared->itState = 2;
        return;
    }
    g_itReading = true;
    ReadTimers(ui);
    __try {
        TimerFramesDraw(ui);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        FramesStop("timers in the game: a frame call faulted");
    }
    RingsPass(ui, (g_shared->itOn & 1) && (g_shared->cdNoBadge & 4), (g_shared->itOn & 2) && (g_shared->bfOpts & BF_RING));
    static bool logged;
    if (!logged && g_shared->frCount)
        logged = true, Log("timers in the game: drawing (%lu text frames)", g_shared->frCount);
    g_shared->itState = g_framesBad ? 3 : 1;
}

// -- health numbers and mana bars ------------------------------------------------------
// Per health bar (kind 5), from the bar update the game calls (the vtable
// entry wrapped above): its number just over it (a text frame placed at the
// bar's own spot each update, tied to no frame), and its mana bar just under
// it (WFE's 0.002 gap), filled and coloured like WFE's.
// shown: the health bar's own visibility, from [+0x94] when the entry is made (WFE's
// test), then from the game's hide / show calls only
struct BarExtra { BYTE *bar, *mana, *text; char last[32]; bool shown, manaShown, textShown; };   // last: the number shown
static const int BX_N = 2048;
static BarExtra g_bx[BX_N];         // open addressing on the bar's address
static int g_bxCount;
static BYTE *g_textPool[512];       // hidden number frames of this game UI, free to use
static int g_textPoolN;
static BYTE *g_textHide[BX_N];      // numbers of bars that went away: hidden on the next pass (one per entry at most)
static int g_textHideN;
static bool g_manaBad;              // a mana bar didn't check out: no more of them
static const float NUM_TEXT = 0.0085f, NUM_Y = 0.0008f, MANA_GAP = 0.002f;
static const DWORD MANA_COLOUR = 0xFF2060FF;

typedef DWORD(__fastcall *BarFn)(void *, int);
typedef DWORD(__fastcall *BarDtorFn)(void *, int, int);
static BarFn g_gameBarHide, g_gameBarShow;      // the game's own: set once, never cleared
static BarDtorFn g_gameBarDtor;

static DWORD BxHome(const BYTE *bar) { return ((DWORD)bar >> 3) * 2654435761u >> 21; }   // 11 bits
static BarExtra *BxFind(BYTE *bar, bool add) {
    for (DWORD i = BxHome(bar), k = 0; k < (DWORD)BX_N; k++, i = (i + 1) & (BX_N - 1)) {
        if (g_bx[i].bar == bar)
            return &g_bx[i];
        if (!g_bx[i].bar) {
            if (!add || g_bxCount >= BX_N * 3 / 4)
                return nullptr;
            ZeroMemory(&g_bx[i], sizeof(BarExtra));
            g_bx[i].bar = bar;
            g_bxCount++;
            return &g_bx[i];
        }
    }
    return nullptr;
}
static void BxRemove(BarExtra *e) {
    DWORD i = (DWORD)(e - g_bx), j = i;
    ZeroMemory(e, sizeof(BarExtra));
    g_bxCount--;
    for (;;) {                                      // shift back what probed past the hole
        j = (j + 1) & (BX_N - 1);
        if (!g_bx[j].bar)
            return;
        DWORD k = BxHome(g_bx[j].bar);
        if (i <= j ? (k <= i || k > j) : (k <= i && k > j)) {
            g_bx[i] = g_bx[j];
            ZeroMemory(&g_bx[j], sizeof(BarExtra));
            i = j;
        }
    }
}

// a unit's state value now and its maximum (HP: +0x98 / +0xa0, mana: +0xb8 / +0xc0), as WFE's 0x10044440
static bool UnitStat(BYTE *unit, DWORD state, DWORD maxHandle, float *cur, float *max, BYTE **maxObj = nullptr) {
    float c = 0;
    ((HpFn)(g_base + RVA_UNIT_HP))(unit + state, 0, &c);
    DWORD *pair = (DWORD *)(unit + maxHandle);
    BYTE *mx = pair[0] != 0xFFFFFFFF && pair[1] != 0xFFFFFFFF ? (BYTE *)((LookupFn)(g_base + RVA_HANDLE_LOOKUP))(pair[0], pair[1]) : nullptr;
    *cur = c, *max = mx ? *(float *)(mx + 0x84) : 0;
    if (maxObj)
        *maxObj = mx;
    return *max > 0 && c == c;
}

static void ManaDestroy(BYTE *m) {
    __try {
        g_gameBarDtor(m, 0, 0);                     // destroy only (WFE calls it on its inner bar too)
        g_smemFree(m, "TWC mana bar", __LINE__, 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        Log("mana bars: destroying one faulted");
        g_manaBad = true;
    }
    g_shared->mbCount--;
}

static float ManaHeight(float h) {
    float k = g_shared->mbHeight;
    return h * (k >= 0.25f && k <= 2 ? k : 0.75f);
}
static float ManaWidth(float w) {
    float k = g_shared->mbWidth;
    w *= k >= 0.25f && k <= 2 ? k : 1;
    // in the game's bar work, with RenderEdge's hook on it: the health bar gets narrowed by
    // 0.75 * W/H after this, so the mana bar is now (OtherBarWidth)
    float r = g_barFresh && OtherBarWidth() ? WideK() : 0;
    return r > 0.25f && r < 4 ? w / r : w;
}

// a mana bar for a health bar, as WFE's 0x10078400 makes its inner one (0 = refused / failed)
static BYTE *NewManaBar(BYTE *bar) {
    void *mem = g_smemAlloc(BAR_SIZE, "TWC mana bar", __LINE__, 0);
    if (!mem)
        return nullptr;
    BYTE *m = (BYTE *)Game(RVA_BAR_CTOR, mem, { 0, *(DWORD *)(bar + BAR_UNIT), 0 });
    if (m != mem || *(DWORD *)m != (DWORD)(g_base + RVA_STATBAR_VTABLE) || *(DWORD *)(m + BAR_KIND) != 0) {
        Log("mana bars: the new bar %p (memory %p) has vtable %08lX, kind %lu, not +%06lX, 0: no more mana bars", m, mem,
            m == mem ? *(DWORD *)m : 0, m == mem ? *(DWORD *)(m + BAR_KIND) : 0, RVA_STATBAR_VTABLE);
        g_manaBad = true;                           // left as it is: it may be half made
        return nullptr;
    }
    *(DWORD *)(m + BAR_UNIT) = *(DWORD *)(bar + BAR_UNIT);
    *(float *)(m + BAR_WIDTH) = ManaWidth(*(float *)(bar + BAR_WIDTH));
    Game(RVA_LAYOUT_REFRESH, m, { 0 });
    *(float *)(m + BAR_HEIGHT) = ManaHeight(*(float *)(bar + BAR_HEIGHT));
    Game(RVA_LAYOUT_REFRESH, m, { 0 });
    Game(RVA_BAR_LEVEL, m, { *(DWORD *)(bar + BAR_LEVEL_ARG) });
    g_gameBarHide(m, 0);
    if (!g_shared->mbCount++)
        Log("mana bars: the first one %p checks out (for the bar %p)", m, bar);
    return m;
}

// after the health bar's update: the mana bar's own update, size, place, fill and colour
static void ManaUpdate(BarExtra *e, BYTE *unit, float cur, float max, bool shown) {
    BYTE *bar = e->bar, *m = e->mana;
    g_gameBarUpdate(m, 0, unit);
    float h = *(float *)(bar + BAR_HEIGHT), w = ManaWidth(*(float *)(bar + BAR_WIDTH)), mh = ManaHeight(h);
    if (*(float *)(m + BAR_WIDTH) != w || *(float *)(m + BAR_HEIGHT) != mh) {
        *(float *)(m + BAR_WIDTH) = w, *(float *)(m + BAR_HEIGHT) = mh;
        Game(RVA_LAYOUT_REFRESH, m, { 0 });
    }
    BYTE *pos = *(BYTE **)(bar + BAR_POS);
    if (pos)
        Game(RVA_SET_ABS_POINT, m, { PT_TOP, F(*(float *)(pos + 4)), F(*(float *)(pos + 8) - (h + MANA_GAP)), 1 });
    *(int *)(m + BAR_CUR) = (int)cur, *(int *)(m + BAR_MAX) = (int)max;
    Virt(m, BAR_RATIO, { F(cur / max) });
    if (*(BYTE **)(m + BAR_TEXT))
        Game(RVA_REGION_HIDE, *(BYTE **)(m + BAR_TEXT));
    BYTE *fill = *(BYTE **)(m + BAR_FILL);
    if (fill && IsGameCode(*(BYTE **)(*(BYTE **)fill + 0x24))) {
        DWORD c = MANA_COLOUR;
        fill[0x68] = (BYTE)(c >> 24), fill[0x69] = (BYTE)c, fill[0x6a] = (BYTE)(c >> 8), fill[0x6b] = (BYTE)(c >> 16);
        Virt(fill, 0x24);
    }
    if (shown != e->manaShown)
        (shown ? g_gameBarShow : g_gameBarHide)(m, 0), e->manaShown = shown;
}

static void NumberText(int mode, float cur, float max, char *b, size_t n) {
    int c = (int)ceilf(cur);
    if (mode == 2)
        sprintf_s(b, n, "%d%%", (int)ceilf(cur * 100 / max));
    else if (mode == 1)
        sprintf_s(b, n, "%d / %d", c, (int)max);
    else
        sprintf_s(b, n, "%d", c);
}

static void NumberUpdate(BarExtra *e, BYTE *ui, float cur, float max, bool shown) {
    if (!e->text) {
        e->text = g_textPoolN ? g_textPool[--g_textPoolN] : NewText(ui, 0, NUM_TEXT, 0xFFFFFFFF);
        if (!e->text)
            return;
        e->last[0] = 0, e->textShown = false;
        if (!g_shared->hnCount++) {
            static int logs;
            if (logs++ < 3)
                Log("health numbers: the first one %p (for the bar %p)", e->text, e->bar);
        }
    }
    char t[sizeof(e->last)];
    NumberText(g_shared->hnMode <= 2 ? (int)g_shared->hnMode : 0, cur, max, t, sizeof(t));
    if (strcmp(t, e->last)) {
        TextSet(e->text, t);
        strcpy_s(e->last, t);
    }
    BYTE *pos = *(BYTE **)(e->bar + BAR_POS);
    if (pos)
        TextAt(e->text, PT_BOTTOM, *(float *)(pos + 4), *(float *)(pos + 8) + NUM_Y);
    if (shown != e->textShown)
        TextShow(e->text, shown), e->textShown = shown;
}

static void NumberDrop(BarExtra *e) {
    if (!e->text)
        return;
    if (e->textShown)
        TextShow(e->text, false);
    if (g_textPoolN < 512)
        g_textPool[g_textPoolN++] = e->text;
    e->text = nullptr;
    g_shared->hnCount--;
}

// in the game's bar update, on the game thread
static void BarExtras(BYTE *bar, BYTE *unit) {
    static int faults;
    __try {
        if (*(DWORD *)(bar + BAR_KIND) != 5)
            return;
        bool hn = g_shared->hnOn && !g_framesBad, mb = g_shared->mbOn && !g_manaBad;
        int before = g_bxCount;
        BarExtra *e = BxFind(bar, hn || mb);
        if (!e)
            return;
        if (g_bxCount != before)                    // just added
            e->shown = *(DWORD *)(bar + BAR_SHOWN) != 0;
        if (!unit)
            unit = *(BYTE **)(bar + BAR_UNIT);
        bool shown = e->shown;
        float cur, max;
        if (mb && unit && UnitStat(unit, UNIT_MANA, UNIT_MAXMANA_HANDLE, &cur, &max)) {
            if (!e->mana)
                e->mana = NewManaBar(bar), e->manaShown = false;
            if (e->mana)
                ManaUpdate(e, unit, cur, max, shown);
        } else if (e->mana) {
            ManaDestroy(e->mana);
            e->mana = nullptr;
        }
        BYTE *ui = hn ? (BYTE *)GameUi() : nullptr;
        if (hn && ui && ui == g_framesUi && unit && UnitStat(unit, UNIT_HP, UNIT_MAXHP_HANDLE, &cur, &max)) {
            NumberUpdate(e, ui, cur, max, shown);
            if (*(BYTE **)(bar + BAR_TEXT))             // the bar's own text, a dark copy beside ours: hidden as WFE does (0x100796a1)
                Game(RVA_REGION_HIDE, *(BYTE **)(bar + BAR_TEXT));
        }
        else if (e->text && (!hn || ui == g_framesUi))
            NumberDrop(e);
        if (!e->mana && !e->text)
            BxRemove(e);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        if (faults++ < 3)
            Log("health numbers / mana bars: a bar's update faulted");
        if (faults >= 3)
            g_manaBad = true, FramesStop("health numbers / mana bars faulted 3 times");
    }
}

// the hide / show / dtor entries: the game's own first (the dtor's last), then the bar's extras
static DWORD __fastcall BarHideHook(void *bar, int edx) {
    DWORD r = g_gameBarHide(bar, edx);
    BarExtra *e = g_bxCount ? BxFind((BYTE *)bar, false) : nullptr;
    if (e)
        __try {
            e->shown = false;
            if (e->mana && e->manaShown)
                g_gameBarHide(e->mana, 0), e->manaShown = false;
            if (e->text && e->textShown)
                TextShow(e->text, false), e->textShown = false;
        } __except (EXCEPTION_EXECUTE_HANDLER) {
        }
    return r;
}
static DWORD __fastcall BarShowHook(void *bar, int edx) {
    DWORD r = g_gameBarShow(bar, edx);
    BarExtra *e = g_bxCount ? BxFind((BYTE *)bar, false) : nullptr;
    if (e)
        __try {
            e->shown = true;
            if (e->mana && !e->manaShown)
                g_gameBarShow(e->mana, 0), e->manaShown = true;
            if (e->text && !e->textShown)
                TextShow(e->text, true), e->textShown = true;
        } __except (EXCEPTION_EXECUTE_HANDLER) {
        }
    return r;
}
static DWORD __fastcall BarDtorHook(void *bar, int edx, int flags) {
    BarExtra *e = g_bxCount ? BxFind((BYTE *)bar, false) : nullptr;
    if (e) {
        if (e->mana)
            ManaDestroy(e->mana);
        if (e->text) {                              // the game UI may be going too: hidden on the next pass, if it's still there
            if (g_textHideN < BX_N)
                g_textHide[g_textHideN++] = e->text;
            g_shared->hnCount--;
        }
        BxRemove(e);
    } else if (g_shared->mbCount) {
        // one of the mana bars, destroyed by the game itself (if its constructor
        // put it in a list of the game's): forget it, so it isn't destroyed twice
        __try {
            if (*(DWORD *)((BYTE *)bar + BAR_KIND) == 0)
                for (BarExtra &x : g_bx)
                    if (x.bar && x.mana == bar) {
                        x.mana = nullptr;
                        g_shared->mbCount--;
                        static int logs;
                        if (logs++ < 3)
                            Log("mana bars: the game destroyed the mana bar %p itself (its health bar %p stays)", bar, x.bar);
                        break;
                    }
        } __except (EXCEPTION_EXECUTE_HANDLER) {
        }
    }
    return g_gameBarDtor(bar, edx, flags);
}

// the three entries: ours (on) or the game's again (off, where they're still ours)
static bool SwapBarExtras(bool on) {
    if (on == g_extrasHooked)
        return true;
    DWORD *vt = (DWORD *)(g_base + RVA_STATBAR_VTABLE);
    DWORD *slots[3] = { vt + BAR_HIDE / 4, vt + BAR_SHOW / 4, vt + BAR_DTOR / 4 };
    DWORD hooks[3] = { (DWORD)BarHideHook, (DWORD)BarShowHook, (DWORD)BarDtorHook };
    if (on && !g_gameBarDtor) {
        for (int i = 0; i < 3; i++)
            if (!IsGameCode((BYTE *)*slots[i])) {
                Log("health numbers / mana bars: refused, the bar's entry +%lX (%08lX) isn't game code", (DWORD)((BYTE *)slots[i] - (BYTE *)vt), *slots[i]);
                return false;
            }
        g_gameBarHide = (BarFn)*slots[0], g_gameBarShow = (BarFn)*slots[1], g_gameBarDtor = (BarDtorFn)*slots[2];
    }
    DWORD orig[3] = { (DWORD)g_gameBarHide, (DWORD)g_gameBarShow, (DWORD)g_gameBarDtor };
    DWORD old;
    if (!VirtualProtect(vt, BAR_SHOW + 4, PAGE_READWRITE, &old))
        return false;
    for (int i = 0; i < 3; i++)
        if (on || *slots[i] == hooks[i])
            InterlockedExchange((volatile LONG *)slots[i], (LONG)(on ? hooks[i] : orig[i]));
        else
            Log("health numbers / mana bars: the bar's entry +%lX was changed by someone else: left as it is", (DWORD)((BYTE *)slots[i] - (BYTE *)vt));
    VirtualProtect(vt, BAR_SHOW + 4, old, &old);
    g_extrasHooked = on;
    Log(on ? "health numbers / mana bars: the bar's hide, show and dtor are wrapped" : "health numbers / mana bars: the bar's hide, show and dtor are the game's again");
    return true;
}

// on the game thread: switch on and off, numbers left over from bars that went away, and the states
static void ExtrasPass(BYTE *ui) {
    bool hn = g_shared->hnOn != 0, mb = g_shared->mbOn != 0;
    int fc = hn || mb ? FramesCheck() : 1;
    if ((hn || mb) && !g_extrasHooked && fc == 1 && g_barHooked && !g_framesBad)
        SwapBarExtras(true);
    __try {
        for (int i = 0; i < g_textHideN; i++)
            if (ui && ui == g_framesUi) {
                TextShow(g_textHide[i], false);
                if (g_textPoolN < 512)
                    g_textPool[g_textPoolN++] = g_textHide[i];
            }
        g_textHideN = 0;
        if (!hn || !mb || g_framesBad || g_manaBad) {           // turned off: take them away (the bar update does it for bars it sees)
            for (int i = 0; i < BX_N; i++) {
                BarExtra *e = &g_bx[i];
                if (!e->bar)
                    continue;
                if (e->mana && (!mb || g_manaBad))
                    ManaDestroy(e->mana), e->mana = nullptr;
                if (e->text && (!hn || g_framesBad) && ui == g_framesUi)
                    NumberDrop(e);
            }
            for (int i = 0; i < BX_N; i++)                      // then the empty ones
                while (g_bx[i].bar && !g_bx[i].mana && !g_bx[i].text)
                    BxRemove(&g_bx[i]);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        FramesStop("health numbers / mana bars: cleaning up faulted");
    }
    if (!hn && !mb && g_extrasHooked && !g_bxCount)
        SwapBarExtras(false);
    InterlockedExchange(&g_extrasWant, (hn || mb || g_bxCount) && fc == 1 ? 1 : 0);
    bool hooksBad = g_shared->hcState == 2 || fc == 3;     // the bar update couldn't be wrapped, or a check failed
    g_shared->hnState = !hn ? 0 : hooksBad || g_framesBad ? 3 : g_extrasHooked && ui ? 1 : 2;
    g_shared->mbState = !mb ? 0 : hooksBad || g_manaBad ? 3 : g_extrasHooked && ui ? 1 : 2;
}

// another game UI (or none): its text frames are gone with the last one. A
// new game UI: any bar still listed is from the last game (its bars are gone
// by now, even if their dtor never came through ours), so forgotten too
static void FramesForget(BYTE *newUi) {
    ZeroMemory(g_tCd, sizeof(g_tCd));
    ZeroMemory(g_tBuff, sizeof(g_tBuff));
    ZeroMemory(g_tItem, sizeof(g_tItem));
    g_badgeN = 0, g_sweepN = 0, g_ringN = 0;    // the badges' regions, the sweeps and our rings went with the game UI
    g_textPoolN = g_textHideN = 0;
    for (BarExtra &e : g_bx)
        if (e.bar && e.text)
            e.text = nullptr, g_shared->hnCount--;
    if (newUi && g_bxCount) {
        Log("frames: %d bars from the last game were still listed (%lu mana bars): forgotten, not touched", g_bxCount, g_shared->mbCount);
        ZeroMemory(g_bx, sizeof(g_bx));
        g_bxCount = 0, g_shared->mbCount = 0, g_shared->hnCount = 0;
    }
    g_shared->frCount = 0;
}

static void HoverPass(BYTE *ui);
static void FramesPass() {
    if (!g_getUi)
        return;
    BYTE *ui = (BYTE *)GameUi();
    if (ui != g_framesUi) {
        if (g_framesUi)
            Log("frames: the game UI changed (%p -> %p): its frames are the game's to free", g_framesUi, ui);
        FramesForget(ui);
        g_framesUi = ui;
    }
    TimerFramesPass(ui);
    ExtrasPass(ui);
    if (g_shared->pingOn)
        HoverPass(ui);
}

// while any is on, and from then on (a pass also hides and cleans up after them)
static bool FramesWork() {
    static bool used;
    used |= g_shared->itOn || g_shared->hnOn || g_shared->mbOn || g_shared->pingOn;
    return used;
}

// the worker's part: a pass 10 times a second
static void QueueFrames() {
    static DWORD at;
    DWORD now = GetTickCount();
    if (!g_getUi || now - at < 100 || !FramesWork())
        return;
    at = now;
    if (Subclass() && !InterlockedExchange(&g_framesQueued, 1))
        PostMessageA(g_gameWnd, g_framesMsg, 0, 0);
}

// -- the portrait's HP / mana lines with regen ------------------------------------------
// WFE (study_portrait.md) detours the portrait update +0x40d0e0 and draws
// frames of its own over the game's lines. Here the update is wrapped through
// its CPortraitButton vtable entry (found at run time), and right after the
// game's own update its two lines (CSimpleFontStrings) get the full text:
// "cur / max", the regen in green (red when losing), and the percent if asked.
// Off: the entry is the game's again, and the game's next update writes its
// own text back. Nothing new is made, so no Storm.dll is needed.
// 1.28f doesn't have it in that vtable (the first in-game report): then the
// game UI's own portrait's vtable is searched, and failing that, the update's
// direct callers (call / jmp rel32 to it in the game's code, at most 8) are
// pointed at the hook instead, on the game thread, and put back when off.
static const DWORD RVA_PORTRAIT_VTABLE = 0xab05b4;     // CPortraitButton (WFE's [0x1013a48c])
static const DWORD RVA_PORTRAIT_VTABLE2 = 0xab06dc;    // its second one ([0x1013a490]): another base, another this (logged only)
static const DWORD UI_PORTRAIT = 0x3f4;                // the game UI's portrait (also self-cast's)
static const DWORD RVA_PORTRAIT_UPDATE = 0x40d0e0;     // its update, __fastcall(portrait, 0) ([0x1013a4a4])
static const DWORD RVA_FONTSTRING_VTABLE = 0xa7d178;   // CSimpleFontString ([0x1013aa0c])
static const DWORD RVA_FONTSTRING_SET = 0x143430;      // __fastcall(string, 0, const char *) ([0x1013aa28])
static const DWORD PORTRAIT_UNIT = 0x238, PORTRAIT_HP = 0x240, PORTRAIT_MP = 0x244, STAT_REGEN = 0x7c;

typedef DWORD(__fastcall *PortraitFn)(void *, int);
static PortraitFn g_gamePortrait;       // the game's own update: set once, never cleared
static DWORD *g_portraitSlot;           // its vtable entry (0 = not found yet)
static bool g_portraitHooked;
static volatile LONG g_portraitCalls;

// one line: "250 / 500 +1.3" (+ " (50%)"), regen and percent as asked; regen NAN: the game's own "250 / 500"
static void StatLine(float cur, float max, float regen, bool pct, char *b, size_t n) {
    int o = sprintf_s(b, n, "%d / %d", (int)ceilf(cur), (int)max);
    if (regen == regen && fabsf(regen) >= 0.05f && regen < 1e5f && regen > -1e5f)
        o += sprintf_s(b + o, n - o, " |cFF%s%+.1f|r", regen > 0 ? "40E040" : "E04040", regen);
    if (pct)
        sprintf_s(b + o, n - o, " (%d%%)", (int)ceilf(cur * 100 / max));
}

static void PortraitLine(BYTE *p, DWORD off, BYTE *unit, DWORD state, DWORD maxHandle, bool plain = false) {
    BYTE *fs = *(BYTE **)(p + off);
    if (!fs || *(DWORD *)fs != (DWORD)(g_base + RVA_FONTSTRING_VTABLE))
        return;
    float cur, max;
    BYTE *mx;
    if (!UnitStat(unit, state, maxHandle, &cur, &max, &mx))
        return;
    char t[96];
    StatLine(cur, max, plain ? NAN : mx ? *(float *)(mx + STAT_REGEN) : 0, !plain && (g_shared->prMode & 1) != 0, t, sizeof(t));
    Game(RVA_FONTSTRING_SET, fs, { (DWORD)t });
}

static bool g_portraitBad;              // writing a line faulted 3 times: no more (the companion can't turn it back on)
static bool g_ptOn;                     // the widescreen UI's portrait text is on (UlPortraitText): it needs the update wrapped too
static void PortraitTextUpdate(BYTE *p);
static volatile bool g_prPutBack;       // regen just went off: the next update writes the plain lines, then it's unwrapped
static bool PortraitWanted() { return g_shared->prOn || g_ptOn || g_prPutBack; }

static DWORD __fastcall PortraitHook(void *portrait, int edx) {
    DWORD r = g_gamePortrait(portrait, edx);
    if (PortraitWanted() && !g_portraitBad) {
        static int faults;
        __try {
            BYTE *p = (BYTE *)portrait, *unit = *(BYTE **)(p + PORTRAIT_UNIT);
            if (unit && g_shared->prOn) {
                PortraitLine(p, PORTRAIT_HP, unit, UNIT_HP, UNIT_MAXHP_HANDLE);
                PortraitLine(p, PORTRAIT_MP, unit, UNIT_MANA, UNIT_MAXMANA_HANDLE);
            } else if (g_prPutBack) {
                // regen just went off: the game writes a line only when its value changes, so
                // the regen would stay until then; the plain "cur / max" now, then unwrapped
                if (unit)
                    PortraitLine(p, PORTRAIT_HP, unit, UNIT_HP, UNIT_MAXHP_HANDLE, true), PortraitLine(p, PORTRAIT_MP, unit, UNIT_MANA, UNIT_MAXMANA_HANDLE, true);
                g_prPutBack = false;
            }
            PortraitTextUpdate(p);
            if (InterlockedIncrement(&g_portraitCalls) == 1)
                Log("portrait: the first update wrapped (portrait %p, unit %p, lines +%lX %08lX / +%lX %08lX)", p, unit,
                    PORTRAIT_HP, *(DWORD *)(p + PORTRAIT_HP), PORTRAIT_MP, *(DWORD *)(p + PORTRAIT_MP));
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            if (faults++ < 3)
                Log("portrait: writing a line faulted");
            if (faults >= 3)
                g_portraitBad = true, g_shared->prState = 3, Log("portrait: stopping");
        }
    }
    return r;
}

static bool WriteCode(BYTE *p, const BYTE *b, int n) {
    DWORD old;
    if (!VirtualProtect(p, n, PAGE_EXECUTE_READWRITE, &old))
        return false;
    memcpy(p, b, n);
    VirtualProtect(p, n, old, &old);
    FlushInstructionCache(GetCurrentProcess(), p, n);
    return true;
}

static bool SwapPortrait(bool on) {
    if (on == g_portraitHooked)
        return true;
    DWORD want = on ? (DWORD)PortraitHook : (DWORD)g_gamePortrait, old;
    if (!on && *g_portraitSlot != (DWORD)PortraitHook) {
        Log("portrait: the update entry was changed by someone else: left as it is");
        g_portraitHooked = false;
        return false;
    }
    if (!VirtualProtect(g_portraitSlot, 4, PAGE_READWRITE, &old))
        return false;
    InterlockedExchange((volatile LONG *)g_portraitSlot, (LONG)want);
    VirtualProtect(g_portraitSlot, 4, old, &old);
    g_portraitHooked = on;
    Log(on ? "portrait: on (its update +%06lX is wrapped)" : "portrait: off (the update is the game's again)", RVA_PORTRAIT_UPDATE);
    return true;
}

// -- its direct callers
static BYTE *g_prSite[8];
static int g_prSites;                   // > 0: the update is wrapped at these call sites (no vtable entry)
static bool g_prSitesBad;

static const BYTE *SiteTarget(const BYTE *site) { return site + 5 + *(const LONG *)(site + 1); }

// the call / jmp rel32 in the game's code that go to fn: their count, the first `most` in out
static int FindCallSites(const BYTE *fn, BYTE **out, int most) {
    int n = 0;
    for (DWORD pg = 0; pg + 5 <= g_imageSize; pg += 0x1000) {
        BYTE *p = g_base + pg;
        if (!PageIs(p, EXEC))
            continue;
        DWORD end = g_imageSize - pg < 0x1000 ? g_imageSize - pg : 0x1000;
        if (!(end == 0x1000 && pg + 0x1000 < g_imageSize && PageIs(p + 0x1000, EXEC)))
            end -= 4;                       // the rel32 mustn't run off the code
        for (DWORD i = 0; i < end; i++)
            if ((p[i] == 0xE8 || p[i] == 0xE9) && SiteTarget(p + i) == fn) {
                if (n < most)
                    out[n] = p + i;
                n++;
            }
    }
    return n;
}

// on the game thread (and on unload): every site to the hook, or back
static bool PointSites(bool on) {
    const BYTE *from = on ? (BYTE *)g_gamePortrait : (BYTE *)PortraitHook, *to = on ? (BYTE *)PortraitHook : (BYTE *)g_gamePortrait;
    for (int i = 0; i < g_prSites; i++)
        if (SiteTarget(g_prSite[i]) != from && SiteTarget(g_prSite[i]) != to) {
            Log("portrait: the call at +%06lX was changed by someone else: stopping", (DWORD)(g_prSite[i] - g_base));
            return false;
        }
    for (int i = 0; i < g_prSites; i++) {
        LONG rel = (LONG)(to - (g_prSite[i] + 5));
        if (SiteTarget(g_prSite[i]) != to && !WriteCode(g_prSite[i] + 1, (const BYTE *)&rel, 4)) {
            Log("portrait: writing the call at +%06lX failed", (DWORD)(g_prSite[i] - g_base));
            return false;
        }
    }
    g_portraitHooked = on;
    if (on)
        Log("portrait: on (its update +%06lX is wrapped at %d call sites)", RVA_PORTRAIT_UPDATE, g_prSites);
    else
        Log("portrait: off (its %d call sites go to the game's update again)", g_prSites);
    return true;
}
static void PortraitSitesPass() {
    bool on = PortraitWanted() && !g_portraitBad;
    if (g_prSites && !g_prSitesBad && on != g_portraitHooked && !PointSites(on))
        g_prSitesBad = true, g_shared->prState = 3;
}

// the update's entry in a vtable's first 128
static DWORD *FindEntry(DWORD *vt, DWORD fn) {
    for (int i = 0; i < 128 && PageIs(vt + i, READ); i++)
        if (vt[i] == fn)
            return vt + i;
    return nullptr;
}

// where to wrap the update: true = a vtable entry or call sites found, false = refused (logged)
static bool FindPortrait() {
    DWORD *vt = (DWORD *)(g_base + RVA_PORTRAIT_VTABLE), fn = (DWORD)(g_base + RVA_PORTRAIT_UPDATE);
    bool ok = PageIs(vt, READ) && !PageIs(vt, EXEC) && FnStart(RVA_PORTRAIT_UPDATE) && FnStart(RVA_FONTSTRING_SET)
        && FnStart(RVA_UNIT_HP) && FnStart(RVA_HANDLE_LOOKUP) && PageIs(g_base + RVA_FONTSTRING_VTABLE, READ) && !PageIs(g_base + RVA_FONTSTRING_VTABLE, EXEC);
    if (!ok) {
        Log("portrait: refused (its functions or vtables aren't where 1.28f has them)");
        return false;
    }
    g_gamePortrait = (PortraitFn)fn;
    if ((g_portraitSlot = FindEntry(vt, fn)) != nullptr) {
        Log("portrait: the update +%06lX is vtable +%06lX entry +%X", RVA_PORTRAIT_UPDATE, RVA_PORTRAIT_VTABLE, (DWORD)((BYTE *)g_portraitSlot - (BYTE *)vt));
        return true;
    }
    Log("portrait: the update +%06lX isn't in the first 128 entries of vtable +%06lX", RVA_PORTRAIT_UPDATE, RVA_PORTRAIT_VTABLE);
    DWORD *vt2 = (DWORD *)(g_base + RVA_PORTRAIT_VTABLE2), *e;
    if (PageIs(vt2, READ) && !PageIs(vt2, EXEC) && (e = FindEntry(vt2, fn)) != nullptr)
        Log("  it's entry +%X of the second vtable +%06lX (not used: that one passes another this)", (DWORD)((BYTE *)e - (BYTE *)vt2), RVA_PORTRAIT_VTABLE2);
    // the game UI's own portrait may be of a class of its own
    BYTE *pb = g_ui ? UiFrame(g_ui, UI_PORTRAIT) : nullptr;
    if (pb) {
        DWORD pv = *(DWORD *)pb;
        char rtti[96];
        RttiName(pv, g_imageSize, rtti, sizeof(rtti));
        Log("  the game UI's portrait %p: vtable +%06lX, RTTI %s", pb, pv - (DWORD)g_base, rtti[0] ? rtti : "(none)");
        if (pv != (DWORD)vt && strstr(rtti, "Portrait") && (g_portraitSlot = FindEntry((DWORD *)pv, fn)) != nullptr) {
            Log("portrait: the update +%06lX is vtable +%06lX entry +%X", RVA_PORTRAIT_UPDATE, pv - (DWORD)g_base, (DWORD)((BYTE *)g_portraitSlot - (BYTE *)pv));
            return true;
        }
    }
    int n = FindCallSites((const BYTE *)fn, g_prSite, 8);
    for (int i = 0; i < n && i < 8; i++)
        Log("  called directly at +%06lX (%s)", (DWORD)(g_prSite[i] - g_base), g_prSite[i][0] == 0xE8 ? "call" : "jmp");
    if (n < 1 || n > 8) {
        Log("portrait: refused, %d direct calls to the update (1 to 8 are wrapped)", n);
        return false;
    }
    g_prSites = n;
    Log("portrait: the update will be wrapped at its %d call sites (on the game thread)", n);
    return true;
}

// the worker's part: find where to wrap it once (in a game), then follow the switch
static void FollowPortrait() {
    static bool refused, wasOn;
    if (!g_getUi || refused)
        return;
    bool pr = g_shared->prOn != 0;
    if (wasOn && !pr && g_portraitHooked && !g_portraitBad)
        g_prPutBack = true;             // one more update, with the plain lines
    wasOn = pr;
    bool on = PortraitWanted();
    if (on && !g_portraitSlot && !g_prSites) {
        if (!g_ui) {
            g_shared->prState = 2;              // waits for a game: the game UI's portrait is one place to look
            return;
        }
        if (!FindPortrait()) {
            refused = true, g_shared->prState = 3;
            return;
        }
    }
    if (g_prSites) {
        if ((on && !g_portraitBad) != g_portraitHooked && Subclass() && !InterlockedExchange(&g_prQueued, 1))
            PostMessageA(g_gameWnd, g_prMsg, 0, 0);
        if (g_prSitesBad)
            refused = true, g_shared->prState = 3;
    } else if (g_portraitSlot) {
        if (on != g_portraitHooked && !SwapPortrait(on))
            refused = true, g_shared->prState = 3;
        if (g_portraitBad && g_portraitHooked)
            SwapPortrait(false);
    }
    if (g_portraitBad && !g_portraitHooked)
        refused = true, g_shared->prState = 3;
    else if (g_shared->prState != 3)
        g_shared->prState = !g_shared->prOn ? 0 : g_ui ? 1 : 2;
}

// -- allies' abilities on the command card (WFE's [UPGRADEDUI] ISALLYABILITYBAR) ----------
// WFE (study_cd2.md; read by hand: 0x10095f30, 0x100960a0, its installer 0x100320e0) has
// the game show allied units' abilities on the command card the way observers see them;
// the cooldowns are then drawn on them as on yours. Two places, checked in the 1.28f
// Game.dll:
//  +0x6bffd0 "the local player sees every unit's commands" (no stack arguments, ret 0; the
//  game's ignores ecx, its 24 callers all pass the unit there, e.g. +0x39ea4e, +0x3a0554):
//  its first 7 bytes (push esi; mov esi, [+0xd305e0]) go to a copy that jumps back, and the
//  start to AllySeesHook: the game's answer, or true for your and allies' units;
//  +0x3e4060 the per-ability display callback (fastcall(unit, ability), ret 0; its only
//  reference is the push at +0x3fae1a, given to the enumerator +0x2c2250): it updates an
//  ability's display (+0x6b2700, ret 4) only for units the local player controls
//  (+0x6a2d90 with ecx = the unit, +0x3e4081: +0x6a2da0(unit, local player), the owner
//  [+0x58] or shared control); the push is pointed at AllyAbilityHook, which also does it
//  for allies' units it doesn't (as WFE's 0x100960a0, which calls it with the unit too).
// Clicking an ally's ability: the button's click (vt+0x6c +0x13d7f0) posts event 0x30064
// to the game UI, whose normal mode's handler +0x3c6da0 calls +0x3c6b60: it returns at once
// unless the local player controls the selection's active unit [[player+0x34]+0x1e0]
// (+0x3c6b67..+0x3c6b95, the same +0x6a2d90), so no order is issued and no targeting starts.
// Before that gate it sends the skill / build menu's "show" net command (+0x3c6e22..: the
// orders [+0xb68840..+0xb68858]), so the click is dropped here too (AllyClickHook, a swap of
// CCommandButton's vtable entry +0x6c, as the bar and tooltip hooks) while the card shows a
// unit only this feature shows: an ally's you don't control, when you aren't an observer.
// All on the game thread, put back when off and on unload.
static const DWORD RVA_SEES_ALL = 0x6bffd0, RVA_ABILITY_CB = 0x3e4060, RVA_ABILITY_CB_PUSH = 0x3fae1a,
    RVA_CONTROLS = 0x6a2d90, RVA_ABILITY_DISPLAY = 0x6b2700, DATA_ABILITY_DEFAULT = 0xb68800,
    RVA_BUTTON_CLICK = 0x13d7f0, PLAYER_SELECTION = 0x34, SELECTION_ACTIVE = 0x1e0;
typedef int(__fastcall *SeesFn)(void *, int);
typedef int(__fastcall *AbilityCbFn)(void *, void *);
typedef void(__fastcall *ButtonClickFn)(void *, int, DWORD);
static BYTE *g_alTramp;             // the 7 bytes and a jmp back (stays allocated, as Fast menu's)
static bool g_alHooked, g_alBad, g_alClickHooked;

// a unit of yours or an ally's (a CUnit: owner [+0x58], the alliance test of the colours)
static bool MineOrAllied(BYTE *unit) {
    if (!unit || (DWORD)(unit - (BYTE *)0x10000) > 0x7ffeffff || *(DWORD *)unit != (DWORD)(g_base + RVA_UNIT_VT))
        return false;
    BYTE *state = *(BYTE **)(g_base + RVA_PLAYERS);
    if (!state)
        return false;
    int owner = *(int *)(unit + UNIT_OWNER), local = *(short *)(state + 0x28);
    if (owner < 0 || owner > 15 || local < 0 || local > 15)
        return false;
    return owner == local || Allied(state, local, owner);
}
// the game's own: does the local player control this unit
static bool Controls(BYTE *unit) { return GameCall(g_base + RVA_CONTROLS, (DWORD)unit, 0, 0, nullptr) != 0; }
static int __fastcall AllySeesHook(void *unit, int edx) {
    int r = ((SeesFn)g_alTramp)(unit, edx);
    if (r || !g_shared->alOn || g_alBad)
        return r;
    __try {
        return MineOrAllied((BYTE *)unit) ? 1 : 0;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        g_alBad = true;
        return 0;
    }
}
static int __fastcall AllyAbilityHook(void *unit, void *ability) {
    int r = ((AbilityCbFn)(g_base + RVA_ABILITY_CB))(unit, ability);
    if (!g_shared->alOn || g_alBad || !ability || !unit)
        return r;
    __try {
        if (MineOrAllied((BYTE *)unit) && !Controls((BYTE *)unit)) {    // the game's own did the ones you control
            BYTE *a = (BYTE *)ability, *e = *(BYTE **)(a + 0x1bc);     // as the game's: [+0x1bc] > 0 ? [[+0x1bc]+8] : [+0xb68800]
            DWORD arg = (LONG)(DWORD)e > 0 ? *(DWORD *)(e + 8) : *(DWORD *)(g_base + DATA_ABILITY_DEFAULT);
            GameCall(g_base + RVA_ABILITY_DISPLAY, (DWORD)unit, 0, 1, &arg);
            static int logs;
            if (!logs++)
                Log("allies' abilities: the first ability shown for unit %p (owner %d)", unit, *(int *)((BYTE *)unit + UNIT_OWNER));
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        g_alBad = true, g_shared->alState = 3;
        Log("allies' abilities: showing one faulted: stopping");
    }
    return r;
}
// the selection's active unit is one only this feature shows (see above)
static bool ClickOnAlly() {
    BYTE *state = *(BYTE **)(g_base + RVA_PLAYERS);
    int local = state ? *(short *)(state + 0x28) : -1;
    if (local < 0 || local >= *(int *)(state + 0x54) || local > 15)
        return false;
    BYTE *player = *(BYTE **)(state + 0x58 + 4 * local), *sel = player ? *(BYTE **)(player + PLAYER_SELECTION) : nullptr;
    BYTE *unit = sel ? *(BYTE **)(sel + SELECTION_ACTIVE) : nullptr;
    return MineOrAllied(unit) && !Controls(unit) && !((SeesFn)g_alTramp)(unit, 0);
}
static void __fastcall AllyClickHook(void *btn, int edx, DWORD mouse) {
    if (g_alHooked && !g_alBad && g_alTramp) {
        bool drop = false;
        __try {
            drop = ClickOnAlly();
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            drop = false;
        }
        if (drop) {
            static int logs;
            if (logs++ < 3)
                Log("allies' abilities: a click on an ally's command card dropped (button %p)", btn);
            return;
        }
    }
    ((ButtonClickFn)(g_base + RVA_BUTTON_CLICK))(btn, edx, mouse);
}
// CCommandButton's click entry: ours or the game's again. false: it wasn't the expected one (logged)
static bool SwapAllyClick(bool on) {
    if (on == g_alClickHooked)
        return true;
    DWORD *slot = (DWORD *)(g_base + RVA_COMMAND_BUTTON_VTABLE + 0x6c), want = on ? (DWORD)(g_base + RVA_BUTTON_CLICK) : (DWORD)AllyClickHook;
    if (*slot != want) {
        Log("allies' abilities: the command button's click entry is %08lX, not the %s: left as it is", *slot, on ? "game's" : "hook");
        if (!on)
            g_alClickHooked = false;
        return false;
    }
    DWORD to = on ? (DWORD)AllyClickHook : (DWORD)(g_base + RVA_BUTTON_CLICK), old;
    if (!VirtualProtect(slot, 4, PAGE_READWRITE, &old))
        return false;
    *slot = to;
    VirtualProtect(slot, 4, old, &old);
    g_alClickHooked = on;
    return true;
}
// the two places as 1.28f has them (the start's abs32 is the game state's address)
static bool AlliesPatchable() {
    BYTE *f = g_base + RVA_SEES_ALL, *push = g_base + RVA_ABILITY_CB_PUSH;
    return FnStart(RVA_SEES_ALL) && f[0] == 0x56 && f[1] == 0x8B && f[2] == 0x35 && *(DWORD *)(f + 3) == (DWORD)(g_base + RVA_PLAYERS)
        && f[7] == 0xE8 && FnStart(RVA_ABILITY_CB) && FnStart(RVA_CONTROLS) && FnStart(RVA_ABILITY_DISPLAY) && FnStart(RVA_BUTTON_CLICK)
        && PageIs(push, EXEC) && push[0] == 0x68 && *(DWORD *)(push + 1) == (DWORD)(g_base + RVA_ABILITY_CB);
}
// on the game thread (and on unload): both in or out. false = refused (logged)
static bool AlliesHook(bool on) {
    if (on == g_alHooked)
        return true;
    BYTE *f = g_base + RVA_SEES_ALL, *push = g_base + RVA_ABILITY_CB_PUSH;
    if (on) {
        if (!AlliesPatchable()) {
            Log("allies' abilities: refused, +%06lX / +%06lX aren't as 1.28f has them", RVA_SEES_ALL, RVA_ABILITY_CB_PUSH);
            LogBytes("  +6BFFD0", f), LogBytes("  +3FAE1A", push);
            return false;
        }
        if (!g_alTramp && (g_alTramp = (BYTE *)VirtualAlloc(nullptr, 16, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE)) != nullptr) {
            memcpy(g_alTramp, f, 7);
            g_alTramp[7] = 0xE9, *(LONG *)(g_alTramp + 8) = (LONG)((f + 7) - (g_alTramp + 12));
            FlushInstructionCache(GetCurrentProcess(), g_alTramp, 16);
        }
        BYTE jmp[7] = { 0xE9, 0, 0, 0, 0, 0x90, 0x90 };
        *(LONG *)(jmp + 1) = (LONG)((BYTE *)AllySeesHook - (f + 5));
        DWORD to = (DWORD)AllyAbilityHook;
        if (!g_alTramp || !WriteCode(f, jmp, 7) || !WriteCode(push + 1, (const BYTE *)&to, 4)) {
            Log("allies' abilities: writing the hooks failed");
            return false;
        }
        g_alHooked = true;
        bool clicks = SwapAllyClick(true);
        Log("allies' abilities: on (+%06lX detoured, the callback at +%06lX is ours; clicks on allies' cards %s)", RVA_SEES_ALL, RVA_ABILITY_CB_PUSH,
            clicks ? "dropped" : "left to the game's own control test");
        return true;
    }
    SwapAllyClick(false);
    if (f[0] == 0xE9 && f + 5 + *(LONG *)(f + 1) == (BYTE *)AllySeesHook && g_alTramp)
        WriteCode(f, g_alTramp, 7);
    else
        Log("allies' abilities: +%06lX was changed by someone else: left as it is", RVA_SEES_ALL);
    DWORD game = (DWORD)(g_base + RVA_ABILITY_CB);
    if (push[0] == 0x68 && *(DWORD *)(push + 1) == (DWORD)AllyAbilityHook)
        WriteCode(push + 1, (const BYTE *)&game, 4);
    g_alHooked = false;
    Log("allies' abilities: off (the game's own again)");
    return true;
}
// on the game thread
static void AlliesPass() {
    bool on = g_shared->alOn && !g_alBad;
    if (on != g_alHooked && !(on && g_shared->alState == 3) && !AlliesHook(on))
        g_shared->alState = 3;
    if (g_shared->alState != 3)
        g_shared->alState = g_alHooked ? 1 : 0;
}

// -- the cooldown ping (WFE's Alt + click on an ability or item) ---------------------------
// WFE (study_cd2.md; 0x10068043, 0x10053cb0) takes the frame under the cursor, the game's
// CSimpleTop [+0xd0f948]'s +0x16c (its mouse-move pass hit-tests the frames and keeps the
// one hit there, +0x13a2f0..+0x13a320), and for a command or inventory button says in the
// allies' chat "<unit> >> <ability> | Cooldown: 7" or "| Ready!". Here the module keeps
// `hover` up to date for the companion's Alt + click key, and command 5 writes the line
// (pingText): the ability's name (the string at [button+0x190]+0x2c, as WFE reads it), the
// unit's name from the info panel ([[[ui+0x3c4]+0x130]+0x128]'s text), the cooldown as the
// timers read it. The companion sends it (its chat line).
// WFE's "Not enough mana!" (0x10053fcf): the button data's int [+0x594] over the unit's mana.
// In the 1.28f Game.dll [+0x594] is the mana cost the tooltip shows: the button's tooltip
// (+0x3fdfb0, ability kind) passes it first to +0x4002b0, whose first cost sets the flag
// +0x164 that +0x40dc7a draws with icon 0 of the table +0xaac684, 'ToolTipManaIcon'. The unit
// is the ability's ([data+0x6d4], AgentOwner, as the game's own ability code reads it), its
// mana the state at +0xb8 (WFE's unit state 2: +0x81b30, as the mana bars).
// Where Enter opens the chat (the companion's way of sending): the chat bar's show
// (+0x3e3890, from the game's Enter) picks allies with Ctrl held, all with Shift held, else
// the Chat dialog's recipient: [ui+0x23c] CChatMode (stored at +0x3a4250), its [+0xc]
// CChatDialog (multiplayer only, +0x3d10c8), [+0x1a0] through +0x3ea100: 0 a player
// ([+0x1a4], -1 = all), 1 allies, 2 observers, 3 all; the dialog starts as allies when the
// local player has an ally (+0x3d0b7b..+0x3d0bf7). pingChat says which, for the companion.
static const DWORD RVA_SIMPLE_TOP = 0xd0f948, RVA_SIMPLE_TOP_VT = 0xa7cae4, TOP_HOVER = 0x16c, DATA_NAME = 0x2c;
static const DWORD DATA_ABILITY = 0x6d4, DATA_MANA_COST = 0x594;
static const DWORD UI_CHAT_MODE = 0x23c, RVA_CHAT_MODE_VT = 0xaade54, CHAT_DIALOG = 0xc, RVA_CHAT_DIALOG_VT = 0xaadb6c, DIALOG_TO = 0x1a0, DIALOG_PLAYER = 0x1a4;
static const char *const CHAT_TO[5] = { "? (no Chat dialog: single player?)", "all", "allies", "observers", "one player" };
static const DWORD FS_TEXT = 0x9c;                  // a CSimpleFontString's text (its setter +0x143430 writes it there)
static BYTE *P(BYTE *f, DWORD off);
// pingChat's value: 0 unknown, 1 all, 2 allies, 3 observers, 4 one player
static DWORD ChatRecipient(BYTE *ui) {
    BYTE *m = P(ui, UI_CHAT_MODE), *d = m && *(DWORD *)m == (DWORD)(g_base + RVA_CHAT_MODE_VT) ? P(m, CHAT_DIALOG) : nullptr;
    if (!d || *(DWORD *)d != (DWORD)(g_base + RVA_CHAT_DIALOG_VT))
        return 0;
    switch (*(DWORD *)(d + DIALOG_TO)) {
    case 0: return *(int *)(d + DIALOG_PLAYER) == -1 ? 1 : 4;
    case 1: return 2;
    case 2: return 3;
    case 3: return 1;
    }
    return 0;
}
// the command card or inventory button under the cursor (nullptr: none)
static BYTE *HoveredButton(BYTE *ui) {
    BYTE *top = *(BYTE **)(g_base + RVA_SIMPLE_TOP);
    if (!top || (DWORD)(top - (BYTE *)0x10000) > 0x7ffeffff || *(DWORD *)top != (DWORD)(g_base + RVA_SIMPLE_TOP_VT))
        return nullptr;
    BYTE *f = *(BYTE **)(top + TOP_HOVER), *card = *(BYTE **)(ui + 0x3c8);
    if (!f)
        return nullptr;
    int rows = card ? *(int *)(card + 0x124) : 0, cols = card ? *(int *)(card + 0x128) : 0;
    for (int r = 0; rows > 0 && rows <= 3 && cols > 0 && cols <= 4 && r < rows; r++)
        for (int c = 0; c < cols; c++)
            if (GridButton(card, r, c) == f)
                return f;
    for (int i = 0; i < 6; i++)
        if (ItemButton(ui, i) == f)
            return f;
    return nullptr;
}
// a game string without its colour codes (|cAARRGGBB, |r), at most n - 1 characters
static void PlainText(const char *src, char *out, size_t n) {
    size_t o = 0;
    for (size_t i = 0; src && src[i] && o + 1 < n && i < 256; i++) {
        if (src[i] == '|' && (src[i + 1] == 'c' || src[i + 1] == 'C') && strlen(src + i) >= 10)
            i += 9;
        else if (src[i] == '|' && (src[i + 1] == 'r' || src[i + 1] == 'R'))
            i++;
        else if ((BYTE)src[i] >= 0x20)
            out[o++] = src[i];
    }
    out[o] = 0;
}
// on the game thread, 10 times a second while the ping key is on
static void HoverPass(BYTE *ui) {
    __try {
        g_shared->hover = ui && HoveredButton(ui) ? 1 : 0;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        g_shared->hover = 0;
    }
}
// command 5, on the game thread: 1 pingText written, 2 nothing to ping
static int PingCommand(BYTE *ui) {
    g_shared->pingText[0] = 0, g_shared->pingChat = 0;
    __try {
        BYTE *btn = HoveredButton(ui), *data = btn ? *(BYTE **)(btn + 0x190) : nullptr;
        if (!data || !PageIs(data + DATA_NAME, READ))
            return 2;
        char ability[64], who[64] = "", t[12];
        PlainText((const char *)(data + DATA_NAME), ability, sizeof(ability));
        if (!ability[0])
            return 2;
        BYTE *name = P(P(P(ui, 0x3c4), 0x130), 0x128);
        if (name && *(DWORD *)name == (DWORD)(g_base + RVA_FONTSTRING_VTABLE) && PageIs(*(BYTE **)(name + FS_TEXT), READ))
            PlainText(*(const char **)(name + FS_TEXT), who, sizeof(who));
        float left = 0, total = 0;
        ButtonCooldown(btn, &left, &total);
        TimeText(left, t, sizeof(t), (g_shared->tmMinutes & MIN_COOLDOWNS) != 0);
        // WFE's order (0x10053fcf..0x1005401c): the mana cost over the unit's mana, else the
        // cooldown, else ready; the seconds after either of the first two
        float mana = -1, maxMana = 0;
        BYTE *ab = *(BYTE **)(data + DATA_ABILITY), *owner = ab ? AgentOwner(ab) : nullptr;
        int cost = ab ? *(int *)(data + DATA_MANA_COST) : 0;
        if (cost > 0 && IsUnit(owner))
            UnitStat(owner, UNIT_MANA, UNIT_MAXMANA_HANDLE, &mana, &maxMana);
        bool noMana = cost > 0 && mana >= 0 && (float)cost > mana;
        char state[40];
        sprintf_s(state, "%s%s%s", noMana ? "Not enough mana!" : t[0] ? "Cooldown:" : "Ready!", t[0] ? " " : "", t);
        sprintf_s(g_shared->pingText, who[0] ? "%s >> %s | %s" : "%s%s | %s", who, ability, state);
        g_shared->pingChat = ChatRecipient(ui);
        static int logs;
        if (logs++ < 3)
            Log("ping: \"%s\" (button %p, mana cost %d, the unit's mana %.0f; Enter opens the chat to %s)", g_shared->pingText, btn, cost, mana,
                CHAT_TO[g_shared->pingChat < 5 ? g_shared->pingChat : 0]);
        return 1;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        Log("ping: reading the button faulted");
        g_shared->pingText[0] = 0;
        return 2;
    }
}

// -- detailed tooltips -----------------------------------------------------------------
// WFE (study_tooltips2/3.md) detours the info panel's damage and armor icon
// updates and rewrites their tooltips with more numbers. 1.28f reaches them
// through their vtables (the first in-game report: CInfoPanelIconDamage
// +0xaaf5a8 and CInfoPanelIconArmor +0xaaf61c, entry +0x6C), so here the entry
// is swapped (a data write, as the bar update's): the game's own update runs
// first and sets the tooltip (+0x4028c0 on [icon+0x128]: it copies its three
// strings to the frame's +0x124 (0x100), +0x224 (0x401, the body) and +0x625
// (0x400)); then the body gets the extra lines and the setter is called again
// with the frame's own strings. A body that already ends with them is left.
static const DWORD RVA_DAMAGE_ICON_VT = 0xaaf5a8, RVA_ARMOR_ICON_VT = 0xaaf61c, ICON_UPDATE = 0x6c;
static const DWORD RVA_DAMAGE_UPDATE = 0x4089d0, RVA_ARMOR_UPDATE = 0x4083a0, RVA_TOOLTIP_SET = 0x4028c0;
static const DWORD ICON_TIP = 0x128, TIP_LINE = 0x124, TIP_BODY = 0x224, TIP_THIRD = 0x625;
typedef DWORD(__fastcall *DamageFn)(void *, int, void *, void *, void *, DWORD);
typedef DWORD(__fastcall *ArmorFn)(void *, int, void *, void *, void *);   // 3 stack arguments: ret 0xC (+0x4089ca)
static DamageFn g_gameDamageTip;
static ArmorFn g_gameArmorTip;
static bool g_ttHooked, g_ttBad;
static volatile LONG g_ttCalls;
static bool TooltipLines(bool damage, BYTE *unit, DWORD attack, char *out, size_t n);
static BYTE *V(BYTE *f);

// after the game's update, on the game thread
static void TooltipAppend(BYTE *icon, bool damage, BYTE *unit, DWORD attack) {
    static int faults;
    if (!g_shared->ttOn || g_ttBad || !unit)
        return;
    __try {
        BYTE *f = V(*(BYTE **)(icon + ICON_TIP));
        if (!f)
            return;
        char extra[256];
        if (!TooltipLines(damage, unit, attack, extra, sizeof(extra)) || !extra[0])
            return;
        char line[0x100], body[0x401], third[0x400];
        strncpy_s(line, (const char *)f + TIP_LINE, _TRUNCATE);
        strncpy_s(body, (const char *)f + TIP_BODY, _TRUNCATE);
        strncpy_s(third, (const char *)f + TIP_THIRD, _TRUNCATE);
        size_t bl = strlen(body), el = strlen(extra);
        if (!line[0] || (bl >= el && !strcmp(body + bl - el, extra)) || bl + el >= sizeof(body))
            return;
        strcat_s(body, extra);
        Game(RVA_TOOLTIP_SET, f, { (DWORD)line, (DWORD)body, (DWORD)third });
        if (InterlockedIncrement(&g_ttCalls) == 1) {
            char rtti[64] = "";
            RttiName(*(DWORD *)f, g_imageSize, rtti, sizeof(rtti));
            Log("tooltips: the first %s tooltip got its lines (frame %p, %s): \"%s\"", damage ? "damage" : "armor", f, rtti[0] ? rtti : "no RTTI", extra);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        if (faults++ < 3)
            Log("tooltips: adding the lines faulted");
        if (faults >= 3)
            g_ttBad = true, g_shared->ttState = 3, Log("tooltips: stopping");
    }
}
static DWORD __fastcall DamageTipHook(void *icon, int edx, void *unit, void *p2, void *p3, DWORD attack) {
    DWORD r = g_gameDamageTip(icon, edx, unit, p2, p3, attack);
    TooltipAppend((BYTE *)icon, true, (BYTE *)unit, attack);
    return r;
}
static DWORD __fastcall ArmorTipHook(void *icon, int edx, void *unit, void *p2, void *p3) {
    DWORD r = g_gameArmorTip(icon, edx, unit, p2, p3);
    TooltipAppend((BYTE *)icon, false, (BYTE *)unit, 0);
    return r;
}

// the two vtable entries: to the hooks, or back. false: refused (logged)
static bool SwapTooltips(bool on) {
    if (on == g_ttHooked)
        return true;
    DWORD *slot[2] = { (DWORD *)(g_base + RVA_DAMAGE_ICON_VT + ICON_UPDATE), (DWORD *)(g_base + RVA_ARMOR_ICON_VT + ICON_UPDATE) };
    DWORD game[2] = { (DWORD)(g_base + RVA_DAMAGE_UPDATE), (DWORD)(g_base + RVA_ARMOR_UPDATE) }, ours[2] = { (DWORD)DamageTipHook, (DWORD)ArmorTipHook };
    for (int i = 0; i < 2; i++)
        if (*slot[i] != (on ? game[i] : ours[i])) {
            Log("tooltips: vtable +%06lX entry +%X is %08lX, not the %s: left as it is", i ? RVA_ARMOR_ICON_VT : RVA_DAMAGE_ICON_VT, ICON_UPDATE, *slot[i], on ? "game's update" : "hook");
            if (!on)
                g_ttHooked = false;
            return false;
        }
    g_gameDamageTip = (DamageFn)game[0], g_gameArmorTip = (ArmorFn)game[1];
    for (int i = 0; i < 2; i++) {
        DWORD old;
        if (!VirtualProtect(slot[i], 4, PAGE_READWRITE, &old))
            return false;
        InterlockedExchange((volatile LONG *)slot[i], (LONG)(on ? ours[i] : game[i]));
        VirtualProtect(slot[i], 4, old, &old);
    }
    g_ttHooked = on;
    Log(on ? "tooltips: on (the damage / armor icon updates are wrapped)" : "tooltips: off (the updates are the game's again)");
    return true;
}

// The lines (study_tooltips3.md, read in the 1.28f Game.dll and against WFE's
// 0x10079f10 / 0x1007c200): the game's body already has damage, range, a
// speed word, armor, damage reduction and a move speed word, so only the
// numbers behind the words are added, in WFE's colours. The attack: atk =
// [unit+0x1e8], skipped when [atk+0x88+4i] is 0 (as +0x408a2c); its cooldown
// from the game's own getter +0x4cc9e0 (atk, float *out, i) (base
// [atk+0x158+8i] over the clamped speed factor, as the attack code uses it),
// attacks a second 1 / cooldown. Move speed: the game's +0x630a30 (mv, float
// *out) on mv = [unit+0x1ec] (buffs and the map's limits in), as +0x40884d.
static const DWORD RVA_ATTACK_COOLDOWN = 0x4cc9e0, RVA_MOVE_SPEED = 0x630a30;
static const DWORD UNIT_ATTACKS = 0x1e8, UNIT_MOVE = 0x1ec, ATTACK_ON = 0x88;
static bool TooltipLines(bool damage, BYTE *unit, DWORD attack, char *out, size_t n) {
    out[0] = 0;
    if (damage) {
        BYTE *atk = *(BYTE **)(unit + UNIT_ATTACKS);
        if (attack > 1 || !atk || (DWORD)(atk - (BYTE *)0x10000) > 0x7ffeffff || !*(int *)(atk + ATTACK_ON + 4 * attack))
            return false;
        float cd = 0;
        Game(RVA_ATTACK_COOLDOWN, atk, { (DWORD)&cd, attack });
        if (!(cd > 0.01f && cd < 100))
            return false;
        sprintf_s(out, n, "|nCooldown: |cFF00FF00%.2f sec|r|nAttacks: |cFF00FF00%.3f/sec|r", cd, 1 / cd);
    } else {
        BYTE *mv = *(BYTE **)(unit + UNIT_MOVE);
        if (!mv || (DWORD)(mv - (BYTE *)0x10000) > 0x7ffeffff)
            return false;
        float sp = -1;
        Game(RVA_MOVE_SPEED, mv, { (DWORD)&sp });
        if (!(sp >= 0 && sp < 10000))
            return false;
        sprintf_s(out, n, "|nMove speed: |cFF00FF00%.0f|r", sp);
    }
    return true;
}

// the worker's part: check once, then follow the switch
static void FollowTooltips() {
    static int checked;             // 1 checked out, 2 refused
    if (!g_getUi || checked == 2)
        return;
    bool on = g_shared->ttOn && !g_ttBad;
    if (on && !checked) {
        bool ok = FnStart(RVA_DAMAGE_UPDATE) && FnStart(RVA_ARMOR_UPDATE) && FnStart(RVA_TOOLTIP_SET) && FnStart(RVA_ATTACK_COOLDOWN) && FnStart(RVA_MOVE_SPEED)
            && GameVtable(RVA_DAMAGE_ICON_VT, { ICON_UPDATE }) && GameVtable(RVA_ARMOR_ICON_VT, { ICON_UPDATE });
        checked = ok ? 1 : 2;
        if (!ok) {
            g_shared->ttState = 3;
            Log("tooltips: refused (the icon updates, their vtables or the tooltip setter aren't where 1.28f has them)");
            return;
        }
    }
    if (checked && on != g_ttHooked && !SwapTooltips(on))
        checked = 2, g_shared->ttState = 3;
    else if (g_shared->ttState != 3)
        g_shared->ttState = g_ttHooked ? 1 : 0;
}

// -- widescreen, FPS unlock, the multiboard ----------------------------------------
// Ported from WFE's 1.28f branches (each address re-checked against WFEDll:
// the tables at 0x10073232, 0x10035715, 0x10070429, 0x1006ff59, 0x1001fec2
// are the `cmp build, 0x1e00; je` ones). All three run on the game thread.

// a game function the module calls: code, right after padding or a ret
static bool FnStart(DWORD rva) {
    BYTE *f = g_base + rva;
    if (!IsGameCode(f) || !PageIs(f - 3, EXEC))
        return false;
    return f[-1] == 0xCC || f[-1] == 0x90 || f[-1] == 0xC3 || (f[-3] == 0xC2 && f[-1] == 0);
}

// Widescreen, as WFE's WIDESCREEN does it on 1.28f (read in the game's
// Game.dll, 2026-10-26): WFE detours the game's perspective projection
// +0x1554f0 (__fastcall(matrix, 0, float fov, float aspect, near, far), ret
// 0x10; WFE's [0x1013a1c8], its 0x1001b8fe for build 0x1E00) with 0x1001b430,
// which builds the same matrix but with the horizontal scale m[0] divided by
// k = 0.75 * width / height of the game window's client area (1 at 4:3): the
// world isn't stretched sideways on a wide screen, you see more of it. Here
// the game's only call to it (+0x1e0829, the camera's update) is pointed at
// ProjHook instead, on the game thread, and back when it's turned off or on
// unload: the game's own function runs, then m[0] /= k. k follows the window
// size. The 2D UI stays the game's 4:3 one stretched to the window, as with
// WFE's WIDESCREEN alone.
// (The setter +0x16f6b0 this used before, WFE's [0x1013ce08] / 0x100665a0, is
// WFE's MOUSELOCK: in Game.dll it's ClipCursor on the game window.)
static const DWORD RVA_PROJECTION = 0x1554f0, RVA_PROJECTION_CALL = 0x1e0829;

typedef void(__fastcall *ProjFn)(float *, int, float, float, float, float);

static volatile float g_wsK;    // the horizontal squeeze while it's on (0 = off)
static bool g_wsApplied;        // the call points at ProjHook
static bool g_wsBad;            // refused for good

// As WFE's 0x1001b430 and RenderEdge_Widescreen (the user's mix file, the same
// matrix): the world's horizontal scale m[0] divided by k = 0.75 * W/H of the
// window, whatever aspect the game passes (it's built for 4:3).
static volatile LONG g_wsLogged;
static void __fastcall ProjHook(float *m, int edx, float fov, float aspect, float zn, float zf) {
    ((ProjFn)(g_base + RVA_PROJECTION))(m, edx, fov, aspect, zn, zf);
    float k = g_wsK;
    if (!InterlockedExchange(&g_wsLogged, 1))
        Log("widescreen: the first projection: the game's aspect argument %.4f, m[0] / %.4f", aspect, k);
    if (k > 0.25f && k < 4)
        m[0] /= k;
}

// the call to the projection: to ProjHook, or back to the game's. false: it isn't what it should be
static bool PointProjection(bool hook) {
    BYTE *site = g_base + RVA_PROJECTION_CALL;
    const BYTE *game = g_base + RVA_PROJECTION, *to = hook ? (const BYTE *)ProjHook : game;
    if (site[0] != 0xE8 || (SiteTarget(site) != game && SiteTarget(site) != (const BYTE *)ProjHook)) {
        Log("widescreen: the call at +%06lX isn't the game's call to its projection +%06lX: left alone", RVA_PROJECTION_CALL, RVA_PROJECTION);
        return false;
    }
    if (SiteTarget(site) == to)
        return true;
    LONG rel = (LONG)(to - (site + 5));
    if (!WriteCode(site + 1, (const BYTE *)&rel, 4)) {
        Log("widescreen: writing the call at +%06lX failed (%lu)", RVA_PROJECTION_CALL, GetLastError());
        return false;
    }
    return true;
}

// k for the game window as it is now (0 if it has no size)
static float WideK() {
    RECT r;
    if (!g_gameWnd || !GetClientRect(g_gameWnd, &r) || r.right <= 0 || r.bottom <= 0)
        return 0;
    return 0.75f * (float)r.right / (float)r.bottom;
}

// on the game thread
// Another module's hook at a game function's start (a Detours jmp out of the game,
// e.g. RenderEdge_Widescreen's mix file): its file name into who. false: the game's own bytes
static bool ForeignDetour(DWORD rva, char *who, size_t n) {
    BYTE *f = g_base + rva;
    if (!PageIs(f, EXEC) || f[0] != 0xE9)
        return false;
    BYTE *t = f + 5 + *(LONG *)(f + 1);
    if (t >= g_base && (DWORD)(t - g_base) < g_imageSize)
        return false;
    HMODULE m = nullptr;
    char path[MAX_PATH] = "";
    if (PageIs(t, EXEC) && GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)t, &m))
        GetModuleFileNameA(m, path, MAX_PATH);
    const char *name = strrchr(path, '\\');
    strncpy_s(who, n, path[0] ? (name ? name + 1 : path) : "unknown code", _TRUNCATE);
    return true;
}

static void WidescreenPass() {
    bool on = g_shared->wsOn != 0;
    if (g_wsBad)
        return;
    // another widescreen mod (RenderEdge_Widescreen) already builds the projection for the
    // window: ours would squeeze it a second time, so it's left to that one (state 4)
    static char other[64];
    static int otherChecked;
    if (on && !g_wsApplied && !otherChecked) {
        otherChecked = 1;
        if (ForeignDetour(RVA_PROJECTION, other, sizeof(other))) {
            otherChecked = 2;
            Log("widescreen: the projection +%06lX is already hooked by %s (another widescreen mod): left to it", RVA_PROJECTION, other);
        }
    }
    if (otherChecked == 2) {
        g_shared->wsState = on ? 4 : 0;
        return;
    }
    if (!on) {
        if (g_wsApplied) {
            g_wsK = 0;
            if (PointProjection(false))
                Log("widescreen: off (the camera calls the game's projection again)");
            g_wsApplied = false;
        }
        g_shared->wsState = 0;
        return;
    }
    if (!g_wsApplied) {
        if (!FnStart(RVA_PROJECTION) || !IsGameCode(g_base + RVA_PROJECTION_CALL)) {
            g_wsBad = true, g_shared->wsState = 3;
            Log("widescreen: refused (the projection +%06lX isn't a function start)", RVA_PROJECTION);
            return;
        }
        if (!PointProjection(true)) {
            g_wsBad = true, g_shared->wsState = 3;
            return;
        }
        g_wsApplied = true;
    }
    float k = WideK();
    if (k != g_wsK) {
        g_wsK = k;
        static int logs;
        RECT r = {};
        if (logs++ < 4 && g_gameWnd && GetClientRect(g_gameWnd, &r))
            Log("widescreen: on, the window is %ldx%ld, so the world's width is divided by %.3f", r.right, r.bottom, k);
    }
    g_shared->wsState = k > 0 ? 1 : 2;
}

// FPS unlock, as WFE's 0x1004a440 does it on 1.28f: one byte in the game's
// frame limiter (+0xa50ba, inside +0xa5090) becomes 0xC9, and the game's frame
// limit setting (game option 0x17) is raised to the wanted ceiling (64 at
// least). WFE never puts either back; here the old byte and setting are kept
// and put back when it's turned off (the byte also on unload). Left out: WFE's
// refresh rate options (4 and 0x12) and its detour of the D3D present setup
// (vsync and refresh rate).
static const DWORD RVA_FPS_FN = 0xa5090, RVA_FPS_BYTE = 0xa50ba;   // WFE's [0x1013c344], [0x1013c348]
static const DWORD RVA_OPTIONS = 0x6bf60;       // options *(void) (WFE's [0x1013c39c])
static const DWORD RVA_OPT_SET = 0x6dbc0;       // __fastcall(options, 0, id, value) ([0x1013c3a0])
static const DWORD RVA_OPT_APPLY = 0x6b3a0;     // __fastcall(options, 0, id) ([0x1013c3a4])
static const DWORD RVA_OPT_GET = 0x6c030;       // __fastcall(options, 0, id, DWORD *out) ([0x1013c3a8])
static const DWORD OPT_FPS_LIMIT = 0x17;

typedef void *(__cdecl *OptionsFn)();
typedef void(__fastcall *OptSetFn)(void *, int, DWORD, DWORD);
typedef void(__fastcall *OptApplyFn)(void *, int, DWORD);
typedef void(__fastcall *OptGetFn)(void *, int, DWORD, DWORD *);

static bool g_fpsPatched;       // the limiter's byte is ours
static BYTE g_fpsOrig;          //   and what it was
static DWORD g_fpsSetTo;        // the frame limit setting we set (0 = the game's own)
static DWORD g_fpsOld;          // the game's own setting, to put back
static bool g_fpsOldRead;

static DWORD FpsLimit() {
    DWORD l = g_shared->fpsLimit;
    return l < 64 ? 64 : l > 1000 ? 1000 : l;
}

static bool WriteCodeByte(BYTE *p, BYTE b) {
    DWORD old;
    if (!VirtualProtect(p, 1, PAGE_EXECUTE_READWRITE, &old))
        return false;
    *(volatile BYTE *)p = b;
    VirtualProtect(p, 1, old, &old);
    FlushInstructionCache(GetCurrentProcess(), p, 1);
    return true;
}

// on: the limiter's byte becomes 0xC9; off: its own again, if it's still ours
static bool FpsPatch(bool on, bool quiet = false) {
    BYTE *p = g_base + RVA_FPS_BYTE;
    if (on == g_fpsPatched)
        return true;
    if (on) {
        if (*p == 0xC9) {
            Log("FPS: the limiter's byte is C9 already (patched by something else): left as it is");
            return false;
        }
        g_fpsOrig = *p;
        LogBytes("FPS: the limiter before the patch", g_base + RVA_FPS_FN);
    } else if (*p != 0xC9) {
        if (!quiet)
            Log("FPS: the limiter's byte was changed by someone else: left as it is");
        g_fpsPatched = false;
        return false;
    }
    if (!WriteCodeByte(p, on ? 0xC9 : g_fpsOrig))
        return false;
    g_fpsPatched = on;
    if (!quiet)
        Log(on ? "FPS: limiter patched (+%06lX: %02X -> C9)" : "FPS: limiter put back (+%06lX: C9 -> %02X)", RVA_FPS_BYTE, g_fpsOrig);
    return true;
}

// the game's frame limit setting (0 = the game's own again): 1 set, 0 no options yet, -1 faulted
static int FpsOption(DWORD want) {
    __try {
        void *opts = ((OptionsFn)(g_base + RVA_OPTIONS))();
        if (!opts || !PageIs(opts, READ) || PageIs(opts, EXEC))
            return 0;
        if (!g_fpsOldRead) {
            DWORD cur = 0;
            ((OptGetFn)(g_base + RVA_OPT_GET))(opts, 0, OPT_FPS_LIMIT, &cur);
            g_fpsOld = cur, g_fpsOldRead = true;
            g_shared->fpsGameLimit = cur;
            Log("FPS: the game's own frame limit setting (option %lX) is %lu", OPT_FPS_LIMIT, cur);
        }
        ((OptSetFn)(g_base + RVA_OPT_SET))(opts, 0, OPT_FPS_LIMIT, want ? want : g_fpsOld);
        ((OptApplyFn)(g_base + RVA_OPT_APPLY))(opts, 0, OPT_FPS_LIMIT);
        return 1;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return -1;
    }
}

static bool FpsWork() {
    return g_shared->fpsOn ? !g_fpsPatched || FpsLimit() != g_fpsSetTo : g_fpsPatched || g_fpsSetTo;
}

static void FpsPass() {
    static bool refused;
    if (refused || !FpsWork())
        return;
    if (!FnStart(RVA_FPS_FN) || !IsGameCode(g_base + RVA_FPS_BYTE) || !FnStart(RVA_OPTIONS) || !FnStart(RVA_OPT_SET)
        || !FnStart(RVA_OPT_APPLY) || !FnStart(RVA_OPT_GET)) {
        refused = true, g_shared->fpsState = 3;
        Log("FPS: refused (the limiter or the game's option functions aren't where 1.28f has them)");
        return;
    }
    int r = 1;
    if (g_shared->fpsOn) {
        if (!FpsPatch(true)) {
            refused = true, g_shared->fpsState = 3;
            return;
        }
        DWORD want = FpsLimit();
        if (want != g_fpsSetTo && (r = FpsOption(want)) == 1) {
            g_fpsSetTo = want;
            Log("FPS: frame limit setting %lu", want);
        }
    } else {
        if (g_fpsSetTo && (r = FpsOption(0)) == 1) {
            g_fpsSetTo = 0;
            Log("FPS: frame limit setting back to %lu", g_fpsOld);
        }
        FpsPatch(false);
        g_fpsSetTo = 0;                 // put back, or no options to put it back in: either way, done
    }
    if (r < 0) {
        Log("FPS: the game's option functions faulted: stopping (limiter put back)");
        FpsPatch(false);
        refused = true, g_fpsSetTo = 0, g_shared->fpsState = 3;
        return;
    }
    g_shared->fpsState = g_fpsPatched ? 1 : 0;
}

// Lobby latency (games you host), as WFE's [DELAY]: WFE replaces three game
// getters with `mov eax, [value]; ret` (its 0x1001b3d0 / e0 / f0, installed
// at 0x10073030..62): +0x924730 LAN, +0x929670 single player (LAN's value
// too), +0x925f00 Battle.net (WFE's order; the game side isn't confirmed).
// Here each getter's first 6 bytes become `mov eax, ms; ret`, only if the
// decoder finds a plain getter there (no calls) that nothing jumps back
// into within those 6 bytes; the game's own values are read and logged
// first. Put back when turned off, and on unload, if they're still ours.
static const DWORD RVA_LATENCY[3] = { 0x924730, 0x929670, 0x925f00 };   // WFE's [0x1013a1b8], [+4], [+8]
static const char *const LATENCY_NAME[3] = { "LAN", "single player", "Battle.net" };
static BYTE g_latOrig[3][6];
static DWORD g_latSet;              // the ms patched in (0 = the game's own)

typedef int(__cdecl *LatencyFn)();

// can f's first 6 bytes be overwritten safely
static bool LatencyPatchable(const BYTE *f) {
    if (!FnStart((DWORD)(f - g_base)) || !WalkGetter(f, 1))     // depth 1: a getter that calls nothing
        return false;
    const BYTE *p = f, *furthest = f;
    for (int i = 0; i < 200; i++) {
        int kind;
        const BYTE *t = nullptr;
        int n = Decode(p, &kind, &t);
        if (kind == I_BAD || n <= 0)
            return false;
        if (t && t > f && t < f + 6)
            return false;                       // something jumps into the bytes we'd overwrite
        if (t && (kind == I_JCC || kind == I_JMP) && t > furthest)
            furthest = t;
        p += n;
        if ((kind == I_RET || kind == I_JMP) && p > furthest) {
            for (const BYTE *q = p; q < f + 6; q++)
                if (*q != 0xCC && *q != 0x90)
                    return false;               // shorter than 6 bytes, and not padding after it
            return true;
        }
    }
    return false;
}

static void LatencyBytes(DWORD ms, BYTE *b) {
    b[0] = 0xB8, memcpy(b + 1, &ms, 4), b[5] = 0xC3;   // mov eax, ms; ret
}

// put the game's own getters back (where they're still ours)
static void LatencyRestore(bool quiet) {
    if (!g_latSet)
        return;
    BYTE ours[6];
    LatencyBytes(g_latSet, ours);
    for (int i = 0; i < 3; i++) {
        BYTE *f = g_base + RVA_LATENCY[i];
        if (!memcmp(f, ours, 6))
            WriteCode(f, g_latOrig[i], 6);
        else if (!quiet) {
            Log("latency: the %s getter was changed by someone else: left as it is", LATENCY_NAME[i]);
            LogBytes("  its bytes now", f);
        }
    }
    if (!quiet)
        Log("latency: the game's own again");
    g_latSet = 0;
}

static DWORD LatencyWanted() {
    DWORD ms = g_shared->latMs;
    return !g_shared->latOn ? 0 : ms < 5 ? 5 : ms > 1000 ? 1000 : ms;
}

static void LatencyPass() {
    static bool refused;
    DWORD want = LatencyWanted();
    if (refused || want == g_latSet)
        return;
    if (!want) {
        LatencyRestore(false);
        g_shared->latState = 0;
        return;
    }
    BYTE b[6];
    if (!g_latSet) {
        for (int i = 0; i < 3; i++)
            if (!LatencyPatchable(g_base + RVA_LATENCY[i])) {
                refused = true, g_shared->latState = 3;
                Log("latency: refused, the %s getter +%06lX isn't a plain getter that can take the patch:", LATENCY_NAME[i], RVA_LATENCY[i]);
                LogBytes("bytes", g_base + RVA_LATENCY[i]);
                return;
            }
        for (int i = 0; i < 3; i++) {
            BYTE *f = g_base + RVA_LATENCY[i];
            memcpy(g_latOrig[i], f, 6);
            int own = -1;
            __try {
                own = ((LatencyFn)f)();
            } __except (EXCEPTION_EXECUTE_HANDLER) {
            }
            g_shared->latGame[i] = (DWORD)own;
            Log("latency: the game's %s getter +%06lX returns %d", LATENCY_NAME[i], RVA_LATENCY[i], own);
            LogBytes("  its bytes", f);
        }
    } else {
        LatencyBytes(g_latSet, b);      // already ours: just the new value, if still ours
        for (int i = 0; i < 3; i++)
            if (memcmp(g_base + RVA_LATENCY[i], b, 6)) {
                Log("latency: a getter was changed by someone else: stopping");
                refused = true, g_shared->latState = 3;
                return;
            }
    }
    LatencyBytes(want, b);
    for (int i = 0; i < 3; i++)
        if (!WriteCode(g_base + RVA_LATENCY[i], b, 6)) {
            Log("latency: writing the patch failed (%lu)", GetLastError());
            LatencyRestore(true);
            refused = true, g_shared->latState = 3;
            return;
        }
    g_latSet = want;
    g_shared->latState = 1;
    Log("latency: %lu ms (LAN, single player and Battle.net)", want);
}

// The game start countdown (games you host), as WFE's [DELAY] GAMESTART: WFE
// replaces the lobby's start handler +0x324100 (called from +0x322458) with its
// own copy 0x10057c10, which starts the same two timers but the countdown's
// (id 3, on [this+0x1dc], +0x86a3e0) with GAMESTART + 0.1 s (0x100fa7c8)
// instead of the game's 6.0 (+0x324143: mov dword [esp], 0x40C00000). Its copy
// isn't the 1.28f function (it passes this+0x1f8 to +0x2dd7d0 where the game
// passes [this+0x1f8]), so here only that float is changed: the 4 bytes at
// +0x324146, checked in their instruction first (the lea of the timer, the
// mov, the call), on the game thread, put back when off and on unload.
static const DWORD RVA_COUNTDOWN = 0x324100, RVA_COUNTDOWN_SECS = 0x324146, RVA_TIMER_START = 0x86a3e0;
static const BYTE COUNTDOWN_HEAD[] = { 0x6A, 0x00, 0x56, 0x6A, 0x03, 0x51, 0x8D, 0x8E, 0xDC, 0x01, 0x00, 0x00, 0xC7, 0x04, 0x24 };   // +0x324137
static float g_csOrig;              // the game's own countdown (read once)
static float g_csSet;               // the seconds patched in (0 = the game's own)

static float CountdownWanted() {
    float s = g_shared->csSecs;
    return !g_shared->csOn ? 0 : (s == s && s > 0 ? (s < 6 ? s : 6) : 0) + 0.1f;
}
// the countdown's float, if its instruction is where 1.28f has it (else nullptr)
static float *CountdownFloat() {
    BYTE *at = g_base + RVA_COUNTDOWN_SECS;
    if (!FnStart(RVA_COUNTDOWN) || !PageIs(at + 8, EXEC) || memcmp(at - sizeof(COUNTDOWN_HEAD), COUNTDOWN_HEAD, sizeof(COUNTDOWN_HEAD))
        || at[4] != 0xE8 || SiteTarget(at + 4) != g_base + RVA_TIMER_START)
        return nullptr;
    return (float *)at;
}
static void CountdownRestore(bool quiet) {
    if (!g_csSet)
        return;
    float *f = CountdownFloat();
    if (f && *f == g_csSet)
        WriteCode((BYTE *)f, (const BYTE *)&g_csOrig, 4);
    else if (!quiet)
        Log("start countdown: +%06lX was changed by someone else: left as it is", RVA_COUNTDOWN_SECS);
    if (!quiet)
        Log("start countdown: the game's own again (%.1f s)", g_csOrig);
    g_csSet = 0;
}
// on the game thread
static void CountdownPass() {
    static bool refused;
    float want = CountdownWanted();
    if (refused || want == g_csSet)
        return;
    if (!want) {
        CountdownRestore(false);
        g_shared->csState = 0;
        return;
    }
    float *f = CountdownFloat();
    if (!f || (g_csSet ? *f != g_csSet : !(*f >= 1 && *f <= 60))) {
        refused = true, g_shared->csState = 3;
        Log("start countdown: refused, +%06lX isn't the game's countdown as 1.28f has it (or it was changed)", RVA_COUNTDOWN_SECS);
        LogBytes("  its bytes", g_base + RVA_COUNTDOWN_SECS - sizeof(COUNTDOWN_HEAD));
        return;
    }
    if (!g_csSet) {
        g_csOrig = *f, g_shared->csGame = g_csOrig;
        Log("start countdown: the game's own is %.1f s (+%06lX)", g_csOrig, RVA_COUNTDOWN_SECS);
    }
    if (!WriteCode((BYTE *)f, (const BYTE *)&want, 4)) {
        Log("start countdown: writing it failed (%lu)", GetLastError());
        refused = true, g_shared->csState = 3;
        return;
    }
    g_csSet = want;
    g_shared->csState = 1;
    Log("start countdown: %.1f s in games you host", want);
}

// Hiding parts of the UI, as WFE's INTERFACE IS* keys do it for the frames
// it hides with their own calls (study_uihide.md): each is a CGameUI field
// whose vtable has a hide / show pair, __fastcall(frame, 0). The CFrame ones
// +0xd0 / +0xd4, the CSimpleFrame ones +0x64 / +0x68; the minimap gets its
// vtable +0xe4 after either (WFE does; its role isn't known). Hidden again
// every 1.5 s (WFE re-applies too: the game may show them itself) and at each
// game start; shown again once when you turn one off.
// The console's background (WFE's ISCONSOLE, 0x100890c0; study_uihide2.md):
// the black panel under the bottom UI that stays where the parts were. Its
// pieces are the CSimpleTextures in the console frame's region list
// ([ui+0x428], first link [+0xd8], next [link+4], the region [link+8]; WFE
// takes 9), each hidden with the region hide +0x141ce0 and shown with
// +0x141e80 (WFE's [0x1013aa3c] / [0x1013aa40]). That alone leaves black:
// the game draws the world only inside the world frame ([ui+0x3bc], a
// CWorldFrameWar3), which sits between the top bar and the console. So with
// the background, the world frame is stretched over the whole screen as
// WFE's 0x100221c0 does it: SetPoint(world+0xb4, top right / bottom left,
// ui+0xb4, the same point, 0, 0) (study_uihide3.md), after clearing its own
// anchors. Those are saved first (the 9 point slots at layout+8: relative points vtable
// +0xa7d7e0, absolute ones +0xa7d7cc, as WFE's 0x10087510 reads them) and
// put back when it's turned off.
static const struct UiPart { const char *name; DWORD off, hide, show, after; const char *rtti; } UI_PARTS[5] = {
    { "time of day",    0x3f8, 0xd0, 0xd4, 0,    "TimeOfDay" },     // WFE 0x1008b880
    { "minimap",        0x3c0, 0xd0, 0xd4, 0xe4, "Minimap" },       // 0x1008a250
    { "upper menu bar", 0x3d0, 0x64, 0x68, 0,    nullptr },         // 0x10087cf0
    { "resource bar",   0x3cc, 0x64, 0x68, 0,    nullptr },         // 0x10088100
    { "idle workers",   0x3e0, 0x64, 0x68, 0,    nullptr },         // 0x1008afa0
};
static const DWORD UI_CONSOLE = 0x428, CONSOLE_REGIONS = 0xd8;
static const DWORD UI_WORLD = 0x3bc, FRAME_LAYOUT = 0xb4, LAYOUT_POINTS = 8, RVA_CLEAR_POINTS = 0x13ee90;   // ClearAllPoints __fastcall(layout, 0, 1) ([0x1013a224])
static const DWORD RVA_REL_POINT_VT = 0xa7d7e0, RVA_ABS_POINT_VT = 0xa7d7cc;      // relFrame +4, its point byte +8, x +0xc, y +0x10 / x +4, y +8
enum { PT_TOPRIGHT = 2, PT_BOTTOMLEFT = 6 };
struct SavedPoint { int kind; DWORD rel, relPt; float x, y; };     // kind 0 none, 1 absolute, 2 relative
static SavedPoint g_worldPts[9];
static void *g_worldUi;             // the game UI whose world frame we stretched (its anchors are saved)
static const int UI_PART_COUNT = 7;     // the 5 above, the console's background (bit 0x20) and the buff bar (0x40)
static DWORD g_uiHidden;            // bits hidden by us in this game
static void *g_uiHideUi;

// one frame: hide (or show). 1 done, 0 not there, -1 refused for good
static int UiPartCall(BYTE *ui, int i, bool hide) {
    static int checked[5];          // 1 checked out, 2 refused
    const UiPart &p = UI_PARTS[i];
    if (checked[i] == 2)
        return -1;
    BYTE *f = UiFrame(ui, p.off);
    if (!f)
        return 0;
    __try {
        DWORD vt = *(DWORD *)f;
        BYTE *fn = *(BYTE **)(vt + (hide ? p.hide : p.show)), *after = p.after ? *(BYTE **)(vt + p.after) : nullptr;
        if (!IsGameCode(fn) || (p.after && !IsGameCode(after))) {
            checked[i] = 2;
            Log("hide UI: %s refused, its vtable +%06lX entries aren't game code", p.name, vt - (DWORD)g_base);
            return -1;
        }
        if (!checked[i]) {
            checked[i] = 1;
            char rtti[64];
            RttiName(vt, g_imageSize, rtti, sizeof(rtti));
            Log("hide UI: %s %p, vtable +%06lX, RTTI %s", p.name, f, vt - (DWORD)g_base, rtti[0] ? rtti : "(none)");
            if (rtti[0] && p.rtti && !strstr(rtti, p.rtti)) {
                Log("  not the %s: refusing it", p.name);
                checked[i] = 2;
                return -1;
            }
        }
        ((FrameFn)fn)(f, 0);
        if (after)
            ((FrameFn)after)(f, 0);
        return 1;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        checked[i] = 2;
        Log("hide UI: the game's call for the %s faulted: refusing it", p.name);
        return -1;
    }
}

// the console's background textures: hide (or show). 1 done, 0 none there, -1 refused for good
// the console's background textures (up to 9), as WFE's ISCONSOLE walks its region list (it takes
// the ones its vtable map calls type 5; here CSimpleTexture by RTTI). Hide the UI and the layout use it
static int ConsoleTextures(BYTE *con, BYTE **tex, int *links) {
    int n = 0, k = 0;
    char rtti[64];
    for (BYTE *l = *(BYTE **)(con + CONSOLE_REGIONS); l && (DWORD)(l - (BYTE *)0x10000) <= 0x7ffeffff && k < 64 && n < 9; l = *(BYTE **)(l + 4), k++) {
        BYTE *r = *(BYTE **)(l + 8);
        if (!r || (DWORD)(r - (BYTE *)0x10000) > 0x7ffeffff)
            continue;
        DWORD vt = *(DWORD *)r;
        if (vt < (DWORD)g_base || vt - (DWORD)g_base >= g_imageSize)
            continue;
        RttiName(vt, g_imageSize, rtti, sizeof(rtti));
        if (strstr(rtti, "CSimpleTexture"))
            tex[n++] = r;
    }
    if (links)
        *links = k;
    return n;
}
static int ConsoleCall(BYTE *ui, bool hide) {
    static int checked;             // 1 checked out, 2 refused
    if (checked == 2)
        return -1;
    BYTE *con = UiFrame(ui, UI_CONSOLE);
    if (!con)
        return 0;
    if (!FnStart(RVA_REGION_HIDE) || !FnStart(RVA_REGION_SHOW)) {
        checked = 2;
        Log("hide UI: the console's background refused (the region hide / show aren't functions)");
        return -1;
    }
    BYTE *tex[9];
    int n = 0, links = 0;
    char rtti[64];
    __try {
        n = ConsoleTextures(con, tex, &links);
        if (!checked) {
            checked = 1;
            RttiName(*(DWORD *)con, g_imageSize, rtti, sizeof(rtti));
            Log("hide UI: console %p, vtable +%06lX, RTTI %s: %d regions, %d textures", con, *(DWORD *)con - (DWORD)g_base, rtti[0] ? rtti : "(none)", links, n);
        }
        for (int i = 0; i < n; i++)
            ((FrameFn)(g_base + (hide ? RVA_REGION_HIDE : RVA_REGION_SHOW)))(tex[i], 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        checked = 2;
        Log("hide UI: the console's background faulted: refusing it");
        return -1;
    }
    return n ? 1 : 0;
}
// the world frame: over the whole screen (or back where the game had it). 1 done, 0 not there, -1 refused for good
static int WorldCall(BYTE *ui, bool full) {
    static int checked;             // 1 checked out, 2 refused
    if (checked == 2)
        return -1;
    BYTE *w = UiFrame(ui, UI_WORLD);
    if (!w)
        return 0;
    if (!FnStart(RVA_SET_POINT) || !FnStart(RVA_SET_ABS_POINT) || !FnStart(RVA_CLEAR_POINTS)) {
        checked = 2;
        Log("hide UI: the world frame refused (the point functions aren't functions)");
        return -1;
    }
    BYTE *lay = w + FRAME_LAYOUT, *root = ui + FRAME_LAYOUT;
    __try {
        if (!checked) {
            char rtti[64];
            RttiName(*(DWORD *)w, g_imageSize, rtti, sizeof(rtti));
            Log("hide UI: world frame %p, vtable +%06lX, RTTI %s", w, *(DWORD *)w - (DWORD)g_base, rtti[0] ? rtti : "(none)");
            if (rtti[0] && !strstr(rtti, "WorldFrame")) {
                Log("  not the world frame: refusing it");
                checked = 2;
                return -1;
            }
            checked = 1;
        }
        if (full) {
            if (g_worldUi != ui) {          // its own anchors, before the first change in this game
                SavedPoint pts[9] = {};
                char b[200];
                int o = 0;
                for (int i = 0; i < 9; i++) {
                    BYTE *pt = *(BYTE **)(lay + LAYOUT_POINTS + i * 4);
                    if (!pt)
                        continue;
                    DWORD vt = *(DWORD *)pt;
                    if (vt == (DWORD)(g_base + RVA_REL_POINT_VT))
                        pts[i] = { 2, *(DWORD *)(pt + 4), pt[8], *(float *)(pt + 0xc), *(float *)(pt + 0x10) };
                    else if (vt == (DWORD)(g_base + RVA_ABS_POINT_VT))
                        pts[i] = { 1, 0, 0, *(float *)(pt + 4), *(float *)(pt + 8) };
                    else {
                        Log("hide UI: the world frame's point %d has vtable %08lX, neither kind: refusing it (it couldn't be put back)", i, vt);
                        checked = 2;
                        return -1;
                    }
                    o += sprintf_s(b + o, sizeof(b) - o, " %d:%s %.3f,%.3f", i, pts[i].kind == 2 ? "rel" : "abs", pts[i].x, pts[i].y);
                }
                memcpy(g_worldPts, pts, sizeof(pts));
                g_worldUi = ui;
                static int logs;
                if (logs++ < 2)
                    Log("hide UI: the world frame's own points:%s", o ? b : " none");
            }
            Game(RVA_CLEAR_POINTS, lay, { 1 });  // the game's own anchors would fight the two (they're saved)
            Game(RVA_SET_POINT, lay, { PT_TOPRIGHT, (DWORD)root, PT_TOPRIGHT, F(0), F(0), 1 });
            Game(RVA_SET_POINT, lay, { PT_BOTTOMLEFT, (DWORD)root, PT_BOTTOMLEFT, F(0), F(0), 1 });
        } else if (g_worldUi == ui) {
            Game(RVA_CLEAR_POINTS, lay, { 1 });
            for (int i = 0; i < 9; i++) {
                const SavedPoint &p = g_worldPts[i];
                if (p.kind == 2)
                    Game(RVA_SET_POINT, lay, { (DWORD)i, p.rel, p.relPt, F(p.x), F(p.y), 1 });
                else if (p.kind == 1)
                    Game(RVA_SET_ABS_POINT, lay, { (DWORD)i, F(p.x), F(p.y), 1 });
            }
            g_worldUi = nullptr;
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        checked = 2;
        Log("hide UI: the world frame's calls faulted: refusing it");
        return -1;
    }
    return 1;
}

// The buff bar, as WFE's ISBUFFBAR (0x100902e0) does with its UI hidden: it's called with
// cl = WFE's UI shown flag [0x1010c09f] (0x10092ffb, 0x100919a6) and hides the bar with its
// vtable +0x64 when it's 0, shows it with +0x68 when it's 1 (0x1009051c), whether the
// Upgraded UI is on or not. The bar: [[[ui+0x3c4]+0x130]+0x16c], a CBuffBar (simple frame).
static BYTE *P(BYTE *f, DWORD off);
static const DWORD RVA_BUFF_BAR_VT = 0xaad510;
static int BuffBarCall(BYTE *ui, bool hide) {
    static int checked;             // 1 checked out, 2 refused
    if (checked == 2)
        return -1;
    BYTE *bar = P(P(P(ui, 0x3c4), 0x130), 0x16c);
    if (!bar)
        return 0;
    __try {
        DWORD vt = *(DWORD *)bar;
        BYTE *fn = *(BYTE **)(vt + (hide ? 0x64 : 0x68));
        if (!checked) {
            char rtti[64];
            RttiName(vt, g_imageSize, rtti, sizeof(rtti));
            Log("hide UI: buff bar %p, vtable +%06lX, RTTI %s", bar, vt - (DWORD)g_base, rtti[0] ? rtti : "(none)");
            if (vt != (DWORD)(g_base + RVA_BUFF_BAR_VT) || (rtti[0] && !strstr(rtti, "CBuffBar"))) {
                Log("  not the buff bar (+%06lX): refusing it", RVA_BUFF_BAR_VT);
                checked = 2;
                return -1;
            }
            checked = 1;
        }
        if (!IsGameCode(fn)) {
            checked = 2;
            Log("hide UI: the buff bar refused, its vtable +%06lX entries aren't game code", vt - (DWORD)g_base);
            return -1;
        }
        ((FrameFn)fn)(bar, 0);
        return 1;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        checked = 2;
        Log("hide UI: the game's call for the buff bar faulted: refusing it");
        return -1;
    }
}

// the console's background goes with the world frame over the whole screen
static int UiHideCall(BYTE *ui, int i, bool hide) {
    if (i == 6)
        return BuffBarCall(ui, hide);
    if (i != 5)
        return UiPartCall(ui, i, hide);
    int r = ConsoleCall(ui, hide);
    WorldCall(ui, hide);
    return r;
}

static void UiHidePass() {
    static DWORD at;
    DWORD want = g_shared->uiHide & 0x7f, now = GetTickCount();
    void *ui = GameUi();
    if (!ui) {
        g_uiHidden = 0, g_uiHideUi = nullptr;           // between games: the next one starts fresh
        g_shared->uiState &= 0x80000000;
        return;
    }
    if (ui != g_uiHideUi)
        g_uiHideUi = ui, g_uiHidden = 0, at = 0;
    for (int i = 0; i < UI_PART_COUNT; i++)             // turned off: show it again, once
        if ((g_uiHidden & (1u << i)) && !(want & (1u << i))) {
            UiHideCall((BYTE *)ui, i, false);
            g_uiHidden &= ~(1u << i);
        }
    bool fresh = (want & ~g_uiHidden) != 0;
    if (want && (fresh || now - at >= 1500)) {
        at = now;
        for (int i = 0; i < UI_PART_COUNT; i++)
            if (want & (1u << i)) {
                int r = UiHideCall((BYTE *)ui, i, true);
                if (r == 1)
                    g_uiHidden |= 1u << i;
                else if (r < 0)
                    g_shared->uiState |= 0x80000000;
            }
    }
    g_shared->uiState = (g_shared->uiState & 0x80000000) | g_uiHidden;
}


// -- WFE's widescreen UI layout ("Upgraded UI") ------------------------------------------
// On a wide window the game draws its 0.8 x 0.6 UI stretched. WFE's Upgraded
// UI ([UPGRADEDUI] ISENABLED, aspect index 1 = 16:9) lays the frames out
// again in that same space so they look right: narrower widths and moved
// anchors, frame by frame, from its tables (study_upgradedui_a/b/c.md, each
// value read in WFEDll). Here the same calls on the game thread: each frame's
// own anchors and size are saved before its first change (WFE's 0x10087510:
// the 9 point slots at layout+8, width +0x58, height +0x5c), the layout is
// applied at game start and again every 2 s (the game may move frames
// itself), and turning it off puts every saved frame back (WFE's 0x100872d0).
// A frame's layout part, as WFE's 0x10087510 finds it: the object itself for
// a region (CSimpleRegion / CSimpleFontString / CSimpleTexture vtable) or a
// simple frame ([+0x68] a CSimpleTop), frame+0xb4 for a CFrame ([+0x44] is
// itself), else none (WFE leaves it alone too). Some of WFE's writes skip
// that and go to [frame+0x58] directly (hero buttons, a button's [+0x194]):
// "raw" here. Only on a window at least 1.5 wide for 1 tall: WFE's 4:3
// values are a different layout, not the game's.
// Every op below was checked by hand in WFEDll (2026-10-26) after the first
// version crashed: the studies had the upper menu bar's anchor on the wrong
// child and relative to the bar's +0xb4, which a simple frame doesn't have.
struct LaySave { BYTE *frame, *lay; SavedPoint pts[9]; float w, h; bool raw, cleared; };
static const DWORD RVA_REGION_VT = 0xa7d100, RVA_TEXTURE_VT = 0xa7d13c;   // WFE's [0x1013aa34], - (CSimpleTop's +0xa7cae4: [0x1013a4f8], with the ping)
static LaySave g_ul[160];
static int g_ulN;
static void *g_ulUi;                // the game UI the saves belong to
static bool g_ulBad;                // a frame's point couldn't be read: no more layout this session
static DWORD g_ulAt;

static int g_ulLogSaves;             // log this many more saves (a handler's first frames)
static BYTE *V(BYTE *f);
static BYTE *LayOf(BYTE *f) {
    if (!f)
        return nullptr;
    DWORD vt = *(DWORD *)f;
    if (vt == (DWORD)(g_base + RVA_REGION_VT) || vt == (DWORD)(g_base + RVA_FONTSTRING_VTABLE) || vt == (DWORD)(g_base + RVA_TEXTURE_VT))
        return f;                                   // kind 1: a region
    BYTE *top = V(*(BYTE **)(f + 0x68));
    if (top && *(DWORD *)top == (DWORD)(g_base + RVA_SIMPLE_TOP_VT))
        return f;                                   // kind 2: a simple frame
    if (*(BYTE **)(f + 0x44) == f)
        return f + FRAME_LAYOUT;                    // kind 3: a CFrame
    return nullptr;
}

// a frame's own anchors and size, once per game (nullptr: refused, or no layout part)
static LaySave *UlSave(BYTE *f, bool raw = false) {
    if (!V(f))
        return nullptr;
    for (int i = 0; i < g_ulN; i++)
        if (g_ul[i].frame == f && g_ul[i].raw == raw)
            return &g_ul[i];
    if (g_ulN >= (int)(sizeof(g_ul) / sizeof(g_ul[0])))
        return nullptr;
    BYTE *lay = raw ? f : LayOf(f);
    if (!lay) {
        if (g_ulLogSaves > 0)           // WFE leaves these alone too (0x10087510 kind 0)
            g_ulLogSaves--, Log("  frame %p (vtable +%06lX): no layout part of a known kind, left alone", f, *(DWORD *)f - (DWORD)g_base);
        return nullptr;
    }
    LaySave &s = g_ul[g_ulN];
    s.frame = f, s.lay = lay, s.raw = raw, s.cleared = false;
    for (int i = 0; i < 9; i++) {
        BYTE *pt = *(BYTE **)(s.lay + LAYOUT_POINTS + i * 4);
        s.pts[i] = {};
        if (!pt)
            continue;
        DWORD vt = *(DWORD *)pt;
        if (vt == (DWORD)(g_base + RVA_REL_POINT_VT))
            s.pts[i] = { 2, *(DWORD *)(pt + 4), pt[8], *(float *)(pt + 0xc), *(float *)(pt + 0x10) };
        else if (vt == (DWORD)(g_base + RVA_ABS_POINT_VT))
            s.pts[i] = { 1, 0, 0, *(float *)(pt + 4), *(float *)(pt + 8) };
        else {
            Log("UI layout: frame %p's point %d has vtable %08lX, neither kind: stopping (it couldn't be put back)", f, i, vt);
            g_ulBad = true;
            return nullptr;
        }
    }
    s.w = *(float *)(s.lay + 0x58), s.h = *(float *)(s.lay + 0x5c);
    g_ulN++;
    if (g_ulLogSaves > 0) {             // the first frames of a handler, the first time: their own anchors
        g_ulLogSaves--;
        char b[240];
        int o = 0;
        for (int i = 0; i < 9; i++)
            if (s.pts[i].kind)
                o += sprintf_s(b + o, sizeof(b) - o, " %d:%s %.4f,%.4f", i, s.pts[i].kind == 2 ? "rel" : "abs", s.pts[i].x, s.pts[i].y);
        Log("  frame %p (layout +%lX): %.4f x %.4f, points%s", f, (DWORD)(s.lay - f), s.w, s.h, o ? b : " none");
    }
    return &s;
}
static void UlRestore(LaySave &s) {
    Game(RVA_CLEAR_POINTS, s.lay, { 1 });
    for (int i = 0; i < 9; i++) {
        const SavedPoint &p = s.pts[i];
        if (p.kind == 2)
            Game(RVA_SET_POINT, s.lay, { (DWORD)i, p.rel, p.relPt, F(p.x), F(p.y), 1 });
        else if (p.kind == 1)
            Game(RVA_SET_ABS_POINT, s.lay, { (DWORD)i, F(p.x), F(p.y), 1 });
    }
    *(float *)(s.lay + 0x58) = s.w;
    Game(RVA_LAYOUT_REFRESH, s.lay, { 0 });
    *(float *)(s.lay + 0x5c) = s.h;
    Game(RVA_LAYOUT_REFRESH, s.lay, { 0 });
}

// the ops (each saves the frame first; a frame that can't be saved is left alone)
static void UlWidth(BYTE *f, float w, bool raw = false) {
    LaySave *s = UlSave(f, raw);
    if (s && *(float *)(s->lay + 0x58) != w)
        *(float *)(s->lay + 0x58) = w, Game(RVA_LAYOUT_REFRESH, s->lay, { 0 });
}
static void UlHeight(BYTE *f, float h, bool raw = false) {
    LaySave *s = UlSave(f, raw);
    if (s && *(float *)(s->lay + 0x5c) != h)
        *(float *)(s->lay + 0x5c) = h, Game(RVA_LAYOUT_REFRESH, s->lay, { 0 });
}
// Every op checks the frame first and only calls the game when it isn't so
// already: the layout is applied again every 2 s, and setting a point the
// frame already has still makes the game lay it out again (the minimap
// flickered with it, the user's report).
static bool HasPoint(BYTE *lay, DWORD pt, BYTE *rel, DWORD relPt, float x, float y) {
    BYTE *p = pt < 9 ? *(BYTE **)(lay + LAYOUT_POINTS + pt * 4) : nullptr;
    if (!p)
        return false;
    if (rel)
        return *(DWORD *)p == (DWORD)(g_base + RVA_REL_POINT_VT) && *(BYTE **)(p + 4) == rel && p[8] == relPt
            && *(float *)(p + 0xc) == x && *(float *)(p + 0x10) == y;
    return *(DWORD *)p == (DWORD)(g_base + RVA_ABS_POINT_VT) && *(float *)(p + 4) == x && *(float *)(p + 8) == y;
}
// a raw SetPoint: the object itself is the layout, as WFE passes it in places. true: it changed
static bool UlPointRaw(BYTE *f, DWORD pt, BYTE *rel, DWORD relPt, float x, float y) {
    LaySave *s = UlSave(f, true);
    if (!s || !rel || HasPoint(s->lay, pt, rel, relPt, x, y))
        return false;
    Game(RVA_SET_POINT, s->lay, { pt, (DWORD)rel, relPt, F(x), F(y), 1 });
    return true;
}
// rel: the layout part anchored to (as WFE passes it). true: it changed
static bool UlPoint(BYTE *f, DWORD pt, BYTE *rel, DWORD relPt, float x, float y) {
    LaySave *s = UlSave(f);
    if (!s || !rel || HasPoint(s->lay, pt, rel, relPt, x, y))
        return false;
    Game(RVA_SET_POINT, s->lay, { pt, (DWORD)rel, relPt, F(x), F(y), 1 });
    return true;
}
static void UlAbs(BYTE *f, DWORD pt, float x, float y) {
    LaySave *s = UlSave(f);
    if (s && !HasPoint(s->lay, pt, nullptr, 0, x, y))
        Game(RVA_SET_ABS_POINT, s->lay, { pt, F(x), F(y), 1 });
}
// cleared once a game (the points set after it stay ours; one the game changes is set again by its op)
static void UlClear(BYTE *f, bool raw = false) {
    LaySave *s = UlSave(f, raw);
    if (s && !s->cleared)
        Game(RVA_CLEAR_POINTS, s->lay, { 1 }), s->cleared = true;
}
// a game object: its vtable is in the game's data (else nullptr: nothing is written to it)
static BYTE *V(BYTE *f) {
    if (!f || (DWORD)(f - (BYTE *)0x10000) > 0x7ffeffff)
        return nullptr;
    DWORD vt = *(DWORD *)f;
    return vt >= (DWORD)g_base && vt - (DWORD)g_base < g_imageSize && !PageIs((void *)vt, EXEC) ? f : nullptr;
}
static BYTE *P(BYTE *f, DWORD off) { return f ? V(*(BYTE **)(f + off)) : nullptr; }

// WFE's handlers' widescreen path (aspect index 1), in its order (0x100919a0)
// One function per handler: they're taken one at a time the first time in a
// game (each logged first, with its frame's class), so a log shows how far
// it got; each is guarded on its own.
static void UlMinimap(BYTE *ui, BYTE *root) {
    // ISMINIMAP 0x1008a250: two corners, then CMinimap +0xe4 as WFE does
    BYTE *mm = P(ui, 0x3c0);
    if (mm) {
        bool moved = UlPoint(mm, 6, root, 6, 0.1075f, 0.007f);
        moved |= UlPoint(mm, 2, root, 6, 0.210f, 0.145f);
        DWORD f = *(DWORD *)(*(DWORD *)mm + 0xe4);
        if (moved && IsGameCode((BYTE *)f))             // its refresh only when it moved (every 2 s it flickered)
            ((FrameFn)f)(mm, 0);
    }
}
static void UlMinimapButtons(BYTE *ui, BYTE *root) {
    // ISMINIMAPBUTTONS 0x1008a580: 5 buttons
    for (DWORD o = 0x408; o <= 0x418; o += 4) {
        UlWidth(P(ui, o), 0.016f);
        UlPoint(P(ui, o), 0, root, 0, 0.2165f, -0.456f);
    }
}
static void UlHeroes(BYTE *ui, BYTE *) {
    // ISHEROBAR 0x1008b2b0: every hero button and its parts
    BYTE *hb = P(ui, 0x3dc);
    if (hb) {
        int rows = *(int *)(hb + 0x124), cols = *(int *)(hb + 0x128);
        for (int r = 0; rows > 0 && rows <= 12 && cols > 0 && cols <= 12 && r < rows; r++)
            for (int c = 0; c < cols; c++) {
                BYTE *b = GridButton(hb, r, c);
                if (!b)
                    continue;
                UlWidth(b, 0.0275f, true);          // all four straight to +0x58
                UlWidth(P(b, 0x1cc), 0.0275f, true);
                UlWidth(P(b, 0x1d0), 0.0275f, true);
                UlWidth(P(b, 0x194), 0.0125f, true);
            }
    }
}
static void UlCard(BYTE *ui, BYTE *root) {
    // ISABILITYBAR 0x1008c0a0: the command card narrower, its buttons and their small part too, to the top right
    BYTE *card = P(ui, 0x3c8);
    if (card) {
        UlWidth(card, 0.130f);
        int rows = *(int *)(card + 0x124), cols = *(int *)(card + 0x128);
        for (int r = 0; rows > 0 && rows <= 3 && cols > 0 && cols <= 4 && r < rows; r++)
            for (int c = 0; c < cols; c++)
                if (BYTE *b = GridButton(card, r, c))
                    UlWidth(b, 0.0275f), UlWidth(P(b, 0x194), 0.0125f, true);
        UlPoint(card, 8, root, 8, -0.107f, 0.003f);
    }
}
static void UlPortrait(BYTE *ui, BYTE *) {
    // ISPORTRAIT 0x1008ac30: narrower, anchored to [ui+0x424]'s layout
    if (BYTE *pf = P(ui, UI_PORTRAIT))
        if (BYTE *pa = P(ui, 0x424))
            UlWidth(pf, 0.060f), UlPoint(pf, 6, pa + FRAME_LAYOUT, 6, 0.260f, 0.031f);
}
static void UlCover(BYTE *ui, BYTE *) {
    // ISINVENTORYCOVER 0x1008bc80
    BYTE *info0 = P(ui, 0x3c4);
    if (BYTE *cover = P(info0, 0x14c))
        UlWidth(cover, 0.095f), UlClear(cover), UlAbs(cover, 8, 0.550f, 0);
}
static void UlItems(BYTE *ui, BYTE *root) {
    BYTE *info0 = P(ui, 0x3c4);
    // ISITEMBAR 0x1008d790: the inventory around the screen's centre, its slots 2 a row
    if (BYTE *inv = P(info0, 0x150)) {
        UlClear(inv), UlPoint(inv, 4, root, 4, 0.110f, -0.175f);
        BYTE *list = P(info0, 0x148);
        int n = list ? *(int *)(list + 0x12c) : 0;
        float y0 = (float)(n >> 1) * 0.039f - 0.32f;
        for (int i = 0; n > 0 && n <= 6 && i < n; i++)
            if (BYTE *slot = ItemButton(ui, i)) {
                UlClear(slot), UlWidth(slot, 0.021f);
                UlPoint(slot, 4, root, 4, (float)(i & 1) * 0.030f + 0.0975f, y0 - (float)(i >> 1) * 0.039f);
                UlWidth(P(slot, 0x194), 0.013f, true);
            }
    }
}

// ISINFOBAR 0x10090940 (read by hand: 0x100909d3..0x100916cf): the info panel
// [ui+0x3c4] to the console's bottom left at 0.33, its unit panel P = [+0x130]:
// P's [+0x128] (the name) on P's top, the two bars [+0x144] / [+0x148] (XP,
// ...) 0.135 wide, and each stat block Q = [P+0x14c..0x168]: its icon
// [Q+0x124] 0.02 wide, some anchored to Q's corner, and its text [Q+0x134]
// beside the icon. Raw pointers where WFE passes them raw.
static void UlInfo(BYTE *ui, BYTE *) {
    BYTE *info = P(ui, 0x3c4), *con = P(ui, 0x428), *pp = P(info, 0x130);
    if (!info || !con || !pp)
        return;
    UlClear(info), UlPoint(info, 6, con, 6, 0.33f, 0);
    UlPoint(P(pp, 0x128), 1, pp, 1, -0.0225f, 0);
    UlWidth(P(pp, 0x144), 0.135f), UlWidth(P(pp, 0x148), 0.135f);
    static const struct { DWORD off; int anchor; bool text; } Q[] = {
        { 0x14c, -1, true }, { 0x150, 0, true }, { 0x154, -1, true }, { 0x158, 0, true },
        { 0x15c, 0, false }, { 0x160, -1, false }, { 0x164, 3, false }, { 0x168, 3, false } };
    for (const auto &q : Q) {
        BYTE *blk = P(pp, q.off), *icon = P(blk, 0x124);
        if (!blk || !icon)
            continue;
        UlWidth(icon, 0.02f);
        if (q.off == 0x164)
            UlHeight(icon, 0.034f);
        if (q.anchor >= 0)
            UlPoint(icon, (DWORD)q.anchor, blk, (DWORD)q.anchor, -0.01f, 0);
        if (q.text)
            if (BYTE *t = P(blk, 0x134))
                UlPointRaw(t, 4, icon, 8, -0.004f, 0.00687f);
    }
}

// ISUPPERMENUBAR 0x10087cf0 (read by hand): the bar [ui+0x3d0] (CUpperButtonBar)
// isn't moved; its Quests button [bar+0x138] (the leftmost) 0.064 wide (.rdata
// 0x100fabd0[0]) and its top left on the game UI's at 0.1, 0 (0x100fad10[0];
// pushes 1, 0, x, 0, ui+0xb4, 0 at 0x10087f4c), the Menu [+0x130], Allies
// [+0x134] and Chat [+0x160] buttons 0.064 wide too. Each through its layout
// part (0x10087510 states 0x1013e7b0 / e930 / eab0 / ec30). WFE's bar show
// (vtable +0x68) and its quest sprite squeeze (0x10087750) are left out.
static void UlMenuBar(BYTE *ui, BYTE *root) {
    BYTE *bar = P(ui, 0x3d0), *quests = P(bar, 0x138);
    if (!quests)
        return;
    UlWidth(quests, 0.064f);
    UlPoint(quests, 0, root, 0, 0.1f, 0);
    UlWidth(P(bar, 0x130), 0.064f), UlWidth(P(bar, 0x134), 0.064f), UlWidth(P(bar, 0x160), 0.064f);
}

// ISRESOURCEBAR 0x10088100 (read by hand): the bar [ui+0x3cc] (CResourceBar) stays;
// its two font strings [+0x148] / [+0x14c] raw, top to the game UI's top at
// -0.045 / 0.0375, -0.1 (0x100881fd / 0x10088237); its first 7 regions (the
// list [bar+0xd8], next [link+4], region [link+8], as the console's; states
// 0x1013edb0 + i * 0x180), each anchored to the bar raw at y -0.003125:
// 0..2 0.0125 wide (0x100faa10[0]), top left at -0.015 / 0.05 / 0.115
// (0x100fae90 / fab40 / fac20), 3..6 top right at -0.2975 / -0.2325 /
// -0.1675 / -0.0925 (0x100fafc0 / fafa0 / faf90 / faf10), in WFE's order.
static void UlResources(BYTE *ui, BYTE *root) {
    BYTE *bar = P(ui, 0x3cc);
    if (!bar)
        return;
    UlPointRaw(P(bar, 0x148), PT_TOP, root, PT_TOP, -0.045f, -0.1f);
    UlPointRaw(P(bar, 0x14c), PT_TOP, root, PT_TOP, 0.0375f, -0.1f);
    BYTE *r[7] = {};
    int n = 0;
    for (BYTE *l = *(BYTE **)(bar + 0xd8); l && (DWORD)(l - (BYTE *)0x10000) <= 0x7ffeffff && n < 7; l = *(BYTE **)(l + 4))
        r[n++] = V(*(BYTE **)(l + 8));
    static void *logged;
    if (logged != ui) {
        logged = ui;
        for (int i = 0; i < n; i++) {
            char rtti[64] = "";
            if (r[i])
                RttiName(*(DWORD *)r[i], g_imageSize, rtti, sizeof(rtti));
            Log("  resource bar region %d: %p %s", i, r[i], r[i] ? (rtti[0] ? rtti : "no RTTI") : "not an object");
        }
    }
    const float Y = -0.003125f;
    UlWidth(r[0], 0.0125f), UlPoint(r[0], 0, bar, 0, -0.015f, Y);
    UlPoint(r[3], 2, bar, 2, -0.2975f, Y);
    UlWidth(r[1], 0.0125f), UlPoint(r[1], 0, bar, 0, 0.05f, Y);
    UlPoint(r[4], 2, bar, 2, -0.2325f, Y);
    UlWidth(r[2], 0.0125f), UlPoint(r[2], 0, bar, 0, 0.115f, Y);
    UlPoint(r[5], 2, bar, 2, -0.1675f, Y);
    UlPoint(r[6], 2, bar, 2, -0.0925f, Y);
}

// ISIDLEWORKERS 0x1008afa0 (read by hand): [ui+0x3e0] (CPeonBar, a simple frame)
// 0.0275 wide (0x100fab00[0]), its bottom left on the game UI's at 0.1, 0.1725
// (0x100fad20[0]; pushes 1, y, x, 6, ui+0xb4, 6 at 0x1008b227); no clear.
static void UlIdle(BYTE *ui, BYTE *root) {
    if (BYTE *pb = P(ui, 0x3e0))
        UlWidth(pb, 0.0275f), UlPoint(pb, 6, root, 6, 0.1f, 0.1725f);
}

// ISTIMEOFDAYINDICATOR 0x1008b880 (read by hand): [ui+0x3f8] (CTimeOfDayIndicator,
// a CFrame: its layout +0xb4) cleared and its centre at 0.1635, 0 on the screen
// (0x100fad40[0]; SetAbsPoint pushes 1, 0, x, 4 at 0x1008bbad). The clock
// model's x squeeze (0.75, 0x100fae10) goes with the other models.
static void UlTimeOfDay(BYTE *ui, BYTE *) {
    if (BYTE *tod = P(ui, 0x3f8))
        UlClear(tod), UlAbs(tod, PT_CENTER, 0.1635f, 0);
}

// ISTOOLTIP 0x10091730 (read by hand): the tooltip [ui+0x1cc] (CUberToolTipWar3,
// made by the game the first time one shows) raw, its bottom right to the game
// UI's top left at 0.6875 (0x100fa874 with Upgraded UI), -0.435 (pushes 1, y,
// x, 0, ui+0xb4, 8 at 0x100918fe). WFE's [INTERFACE] ISCUSTOMUIDRAW
// ([0x1013d0f8]) only skips it when its tooltip follows the cursor.
static void UlTooltip(BYTE *ui, BYTE *root) {
    if (BYTE *tt = P(ui, 0x1cc))
        UlPointRaw(tt, 8, root, 0, 0.6875f, -0.435f);
}

// 0x10088b90 (read by hand; the studies called it black bars): the message frames
// (CSimpleMessageFrame): the world messages [ui+0x3e4] bottom to the console
// [ui+0x428]'s bottom (raw) at -0.025 (0x100fab90[0]), 0.18; the unit messages
// [ui+0x3e8] bottom to their top (raw) at -0.098125 + 0.025 (0x100fa98c),
// 0.0005, so they stay where they were. All three or nothing.
static void UlMessages(BYTE *ui, BYTE *) {
    BYTE *con = P(ui, 0x428), *msg = P(ui, 0x3e4), *unit = P(ui, 0x3e8);
    if (!con || !msg || !unit)
        return;
    UlPoint(msg, PT_BOTTOM, con, PT_BOTTOM, -0.025f, 0.18f);
    UlPoint(unit, PT_BOTTOM, msg, PT_TOP, -0.098125f + 0.025f, 0.0005f);
}

// 0x10088dd0 (read by hand): the chat box [ui+0x3fc] (CChatEditBar, a CFrame)
// left / right to the full-screen frame [ui+0x41c]'s bottom corners (its +0xb4)
// at +-0.25 (0x100fad80 / 0x100fafb0[0]), 0.2: clear of the minimap. The
// two slots replaced, no clear (pushes 1, y, x, 6, rel, 3 / 1, y, x, 8, rel, 5).
static void UlChat(BYTE *ui, BYTE *) {
    BYTE *chat = P(ui, 0x3fc), *full = P(ui, 0x41c);
    if (chat && full)
        UlPoint(chat, 3, full + FRAME_LAYOUT, 6, 0.25f, 0.2f), UlPoint(chat, 5, full + FRAME_LAYOUT, 8, -0.25f, 0.2f);
}

// ISCONSOLE 0x100890c0 (read by hand 0x10089113..0x1008a213, its apply 0x100873d0):
// the console's 9 background textures (ConsoleTextures, WFE's states 0x1013fb30
// + i * 0x180), each cleared, sized and put on the console [ui+0x428]'s same
// point (raw) at x, 0: the 4:3 art squeezed into the middle of the screen,
// every width x 0.75 (aspect index 1 of the tables below; the case's point at
// 0x10089367 .. 0x1008a08d). Hiding them stays with Hide the UI.
static const struct { float w, h, x; DWORD pt; } UL_CONSOLE[9] = {
    { 0.192f, 0.032f, 0.0993f, 0 },         // 0x100891bd: width 0x100face0, x 0x100facf0, height 0.032
    { 0.065f, 0.032f, 0.2915f, 0 },         // 0x10089370: 0x100fabe0, 0x100fadb0
    { 0.040185f, 0.032f, -0.31525f, 2 },    // 0x10089520: 0x100faba0, 0x100fafd0
    { 0.192f, 0.032f, -0.123f, 2 },         // 0x100896d3: 0x100facc0, 0x100faf70
    { 0.0228f, 0.032f, -0.10085f, 2 },      // 0x10089860: 0x100faaa0, 0x100faf30
    { 0.192f, 0.176f, 0.1f, 6 },            // 0x100899d2: 0x100facd0, 0x100fad00
    { 0.192f, 0.15f, 0.292f, 6 },           // 0x10089b70: 0x100facd0, 0x100fada0
    { 0.192f, 0.176f, -0.125f, 8 },         // 0x10089d26: 0x100facd0, 0x100faf80
    { 0.025f, 0.176f, -0.1f, 8 },           // 0x10089edc: 0x100faae0, 0x100faf40
};
static void UlConsole(BYTE *ui, BYTE *) {
    BYTE *con = P(ui, UI_CONSOLE), *tex[9];
    int n = con ? ConsoleTextures(con, tex, nullptr) : 0;
    for (int i = 0; i < n; i++) {
        const auto &c = UL_CONSOLE[i];
        UlClear(tex[i]), UlWidth(tex[i], c.w), UlHeight(tex[i], c.h);
        UlPoint(tex[i], c.pt, con, c.pt, c.x, 0);
    }
}

// ISBUFFBAR 0x100902e0 (read by hand 0x1009033f..0x100908f6): the buff bar
// B = [[[ui+0x3c4]+0x130]+0x16c] (CBuffBar), all raw (no 0x10087510 here):
// cleared, k x cols x 0.0182725 wide (0x100faa70[0]) and rows x 0.0165 (x h)
// high (0x100fab50[0]), its bottom right on the game UI's at cols x 0.0182725
// - 0.435 (0x100fa860), y; its label [B+0x15c] right to B's left at -0.0025
// (0x100fa948); each indicator 0.0182725 x 0.0165. WFE's [BUFFUI] options:
// ISDRAWBUFFDURATION (it draws the seconds under the buffs: here when the
// timers are drawn in the game, itOn) k = 1.1 (0x100fa89c), h = 1.25
// (0x100fa8a0), y = 0.00375 (0x100fa6dc), else k = 1.05 (0x100fa898), h = 1,
// y = 0 (0x10090761..0x10090787); ISUPGRADEDBUFFBAR (ulOn bit 2) raises it
// by rows x 0.0165 + 0.13 (0x100fa7e8, 0x1009079a) and puts the label off
// at x -1 (0x100fa9c0, 0x100907fa). WFE's show / hide of the bar with its UI
// is Hide the UI's (BuffBarCall).
static const float BUFF_W = 0.0182725f, BUFF_H = 0.0165f;
static float BuffBarScale() {
    float k = g_shared->bbScale;
    return k > 1 && k <= 2 ? k : 1;
}
static void UlBuffs(BYTE *ui, BYTE *root) {
    BYTE *bar = P(P(P(ui, 0x3c4), 0x130), 0x16c);
    if (!bar)
        return;
    int rows = *(int *)(bar + 0x124), cols = *(int *)(bar + 0x128);
    if (rows < 1 || rows > 4 || cols < 1 || cols > 16)
        return;
    // bbScale: the bar and its icons k times bigger, WFE's left edge kept (its right edge moves out)
    bool dur = g_shared->itOn != 0, up = (g_shared->ulOn & 2) != 0;
    float k = BuffBarScale(), bw = (dur ? 1.1f : 1.05f) * (float)cols * BUFF_W;
    float h = (float)rows * BUFF_H, y = dur ? 0.00375f : 0;
    if (up)
        y += h * k + 0.13f;
    UlClear(bar, true);
    UlWidth(bar, bw * k, true), UlHeight(bar, (dur ? h * 1.25f : h) * k, true);
    UlPointRaw(bar, 8, root, 8, (float)cols * BUFF_W - 0.435f + bw * (k - 1), y);
    BYTE *label = P(bar, 0x15c);
    if (label && *(DWORD *)label == (DWORD)(g_base + RVA_FONTSTRING_VTABLE))
        UlPointRaw(label, 5, bar, 3, up ? -1.0f : -0.0025f, 0);
    for (int r = 0; r < rows; r++)
        for (int c = 0; c < cols; c++)
            if (BYTE *b = GridButton(bar, r, c))
                UlWidth(b, BUFF_W * k, true), UlHeight(b, BUFF_H * k, true);
}

// A bigger buff bar without the widescreen UI (bbScale). The bar is a grid (CBuffBar: 1 row of 8
// CBuffIndicators, its ctor +0x3d0100: 0.12 x 0.015, each icon 0.015 x 0.015, +0x13d380(1, 8));
// a grid lays its cells out again whenever its rect changes (CBuffBar vt+0 = +0x13cc90: cell =
// the rect / rows or columns, each item pointed to its cell), and the info panel pins the bar by
// its bottom right (+0x3e8126: SetPoint 8 -> 8, -0.003, 0.0057). So the bar and each icon get
// k times the game's size here, and the bar grows left and up with its icons spread over it. The
// width / height written as the layout ops do (+0x58 / +0x5c, the layout refresh), only when not
// so already; back to the game's sizes when off. With the widescreen UI on, its UlBuffs does it.
static const float GAME_BUFF_BAR_W = 0.12f, GAME_BUFF_BAR_H = 0.015f, GAME_BUFF_ICON = 0.015f;
static const DWORD RVA_BUFF_INDICATOR_VT = 0xaad470;
static float g_bbApplied;          // the scale this pass left the bar at (0: the game's own)
static bool SizeRaw(BYTE *f, float w, float h) {
    bool changed = false;
    if (fabsf(*(float *)(f + LAYOUT_WIDTH) - w) > 1e-6f)
        *(float *)(f + LAYOUT_WIDTH) = w, Game(RVA_LAYOUT_REFRESH, f, { 0 }), changed = true;
    if (fabsf(*(float *)(f + LAYOUT_HEIGHT) - h) > 1e-6f)
        *(float *)(f + LAYOUT_HEIGHT) = h, Game(RVA_LAYOUT_REFRESH, f, { 0 }), changed = true;
    return changed;
}
static void BuffBarSizePass() {
    static bool bad;
    float k = BuffBarScale();
    if (bad || g_shared->ulOn || k == 1 && !g_bbApplied) {
        if (!bad)
            g_shared->bbState = g_shared->ulOn && k > 1 ? 1 : 0;
        if (g_shared->ulOn)
            g_bbApplied = 0;                    // the widescreen UI's layout has it (and puts back what it found)
        return;
    }
    BYTE *ui = (BYTE *)GameUi();
    int rows, cols;
    BYTE *bar = BuffBarOf(ui, &rows, &cols);
    if (!bar) {
        g_shared->bbState = k > 1 ? 2 : 0;
        return;
    }
    __try {
        if (*(DWORD *)bar != (DWORD)(g_base + RVA_BUFF_BAR_VT)) {
            bad = true, g_shared->bbState = 3;
            Log("buff bar size: the bar %p has vtable +%06lX, not CBuffBar's +%06lX: refused", bar, *(DWORD *)bar - (DWORD)g_base, RVA_BUFF_BAR_VT);
            return;
        }
        int n = SizeRaw(bar, GAME_BUFF_BAR_W * (float)cols / 8 * k, GAME_BUFF_BAR_H * (float)rows * k);
        for (int r = 0; r < rows; r++)
            for (int c = 0; c < cols; c++)
                if (BYTE *b = GridButton(bar, r, c))
                    n += *(DWORD *)b == (DWORD)(g_base + RVA_BUFF_INDICATOR_VT) && SizeRaw(b, GAME_BUFF_ICON * k, GAME_BUFF_ICON * k);
        if (n && g_bbApplied != k)
            Log("buff bar size: x%.2f (%d frames resized; bar %p %dx%d)", k, n, bar, rows, cols);
        g_bbApplied = k > 1 ? k : 0;
        g_shared->bbState = k > 1 ? 1 : 0;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        bad = true, g_shared->bbState = 3;
        Log("buff bar size: resizing faulted: left to the game");
    }
}

// -- the buttons' models, squeezed sideways (the cooldown sweep, autocast, hero point, the clock)
// A model frame draws its model at the frame's height, so on the narrower
// square buttons it overhangs them. WFE (read by hand: ISABILITYBAR
// 0x1008c499, ISHEROBAR 0x1008b6fb, ISTIMEOFDAYINDICATOR 0x1008b9c4, its
// Cooldown UI 0x100811b0) takes the frame's first sprite ([frame+0x174] > 0,
// [[frame+0x178]]), its 3x3 matrix by the sprite's vtable (0x10036d80: +0x64
// for CSpriteMini_, +0x108 for CSpriteUber_; the game's own vtable +0x38
// getters read the same 36 bytes), takes the matrix apart into angles
// (0x10035310 atan2, 0x10035570) and rebuilds it as a pure rotation times
// (sx, 1, 1) (0x10035390: m0, m1 x sx; m3, m4 x sy; m8 x sz), written straight
// in. sx = 0.725 (0x1008bfd0: .rdata 0x100fae00[0]) for the buttons, 0.75
// (0x100fae10[0]) for the time of day clock. For an unrotated model that's
// diag(sx, 1, 1), which is what's written here, only to unrotated ones (WFE's
// angle round trip isn't exact otherwise), each saved first and put back
// while its frame still holds the same sprite. The models: a command button's
// cooldown sweep [+0x19c] (WFE's Cooldown UI does it) and autocast [+0x1a8], an
// inventory button's sweep [+0x19c], a hero button's point model [+0x1d8], the
// time of day [ui+0x3f8] itself, the upper menu bar's quest sprite [+0x13c]. The game makes the sweep and autocast ones
// the first time they're needed (+0x3e1a60 / +0x3e1930; WFE detours the
// autocast maker): the 2 s pass picks them up.
static const DWORD RVA_SPRITE_MINI_VT[2] = { 0xa825a4, 0xa82784 }, RVA_SPRITE_UBER_VT[2] = { 0xa8266c, 0xa8270c };
struct ModelSave { BYTE *frame, *sprite; float orig[9], sx; };
static ModelSave g_ulModels[64];
static int g_ulModelN, g_ulModelResets;

static float *ModelMatrix(BYTE *frame, BYTE **sprite) {
    int n = V(frame) ? *(int *)(frame + 0x174) : 0;
    BYTE **list = n > 0 && n < 64 ? *(BYTE ***)(frame + 0x178) : nullptr;
    BYTE *s = list && (DWORD)((BYTE *)list - (BYTE *)0x10000) <= 0x7ffeffff ? V(list[0]) : nullptr;
    if (!s)
        return nullptr;
    DWORD vt = *(DWORD *)s - (DWORD)g_base;
    *sprite = s;
    if (vt == RVA_SPRITE_MINI_VT[0] || vt == RVA_SPRITE_MINI_VT[1])
        return (float *)(s + 0x64);
    if (vt == RVA_SPRITE_UBER_VT[0] || vt == RVA_SPRITE_UBER_VT[1])
        return (float *)(s + 0x108);
    return nullptr;
}
static void UlModel(BYTE *frame, float sx) {
    BYTE *s;
    float *m = ModelMatrix(frame, &s);
    if (!m)
        return;
    ModelSave *sv = nullptr;
    for (int i = 0; i < g_ulModelN && !sv; i++)
        if (g_ulModels[i].sprite == s)
            sv = &g_ulModels[i];
    if (!sv) {
        static const int OFF[] = { 1, 2, 3, 5, 6, 7 };
        for (int i : OFF)
            if (fabsf(m[i]) > 1e-4f) {
                Log("UI layout: model %p (frame %p) is turned (m[%d] %.3f): left alone", s, frame, i, m[i]);
                return;
            }
        if (m[0] <= 0 || m[4] <= 0 || m[8] <= 0 || g_ulModelN >= (int)(sizeof(g_ulModels) / sizeof(g_ulModels[0])))
            return;
        sv = &g_ulModels[g_ulModelN++];
        sv->frame = frame, sv->sprite = s, sv->sx = sx;
        memcpy(sv->orig, m, sizeof(sv->orig));
        if (g_ulModelN <= 3)
            Log("  model %p (frame %p, %s): %.3f / %.3f / %.3f -> x %.3f", s, frame, (BYTE *)m - s == 0x64 ? "mini" : "uber", m[0], m[4], m[8], sx);
    } else if (m[0] != sx && !g_ulModelResets++)
        Log("UI layout: the game put model %p's matrix back (m[0] %.3f): squeezed again every 2 s", s, m[0]);
    m[0] = sx, m[4] = 1, m[8] = 1;
}
// the matrix the Widescreen UI's squeeze found on a sprite (0: it hasn't touched it)
static float *UlOriginal(BYTE *sprite) {
    for (int i = 0; i < g_ulModelN; i++)
        if (g_ulModels[i].sprite == sprite)
            return g_ulModels[i].orig;
    return nullptr;
}
// put back while the frame still holds the same sprite (else it's gone, or a new one)
static void UlModelsRestore() {
    for (int i = g_ulModelN - 1; i >= 0; i--) {
        BYTE *s = nullptr;
        float *m = ModelMatrix(g_ulModels[i].frame, &s);
        if (m && s == g_ulModels[i].sprite)
            memcpy(m, g_ulModels[i].orig, sizeof(g_ulModels[i].orig));
    }
    if (g_ulModelN)
        Log("UI layout: %d models put back", g_ulModelN);
    g_ulModelN = 0;
}
static const float UL_MODEL_X = 0.725f, UL_CLOCK_X = 0.75f;
static void UlModels(BYTE *ui, BYTE *) {
    if (BYTE *card = P(ui, 0x3c8)) {
        int rows = *(int *)(card + 0x124), cols = *(int *)(card + 0x128);
        for (int r = 0; rows > 0 && rows <= 3 && cols > 0 && cols <= 4 && r < rows; r++)
            for (int c = 0; c < cols; c++)
                if (BYTE *b = GridButton(card, r, c))
                    (g_sweepOn ? (void)0 : UlModel(P(b, 0x19c), UL_MODEL_X)), UlModel(P(b, 0x1a8), UL_MODEL_X);
    }
    if (BYTE *hb = P(ui, 0x3dc)) {
        int rows = *(int *)(hb + 0x124), cols = *(int *)(hb + 0x128);
        for (int r = 0; rows > 0 && rows <= 12 && cols > 0 && cols <= 12 && r < rows; r++)
            for (int c = 0; c < cols; c++)
                if (BYTE *b = GridButton(hb, r, c))
                    UlModel(P(b, 0x1d8), UL_MODEL_X);
    }
    for (int i = 0; i < 6; i++)
        if (BYTE *b = g_sweepOn ? nullptr : ItemButton(ui, i))
            UlModel(P(b, 0x19c), UL_MODEL_X);
    UlModel(P(ui, 0x3f8), UL_CLOCK_X);
    // the quest sprite (WFE's 0x10087750, after ISUPPERMENUBAR and in its hook of the game's
    // +0x3e4d80): the menu bar's [+0x13c], a CSpriteFrame the game makes the first time a quest
    // flashes (+0x3e4df8) and fits onto the Quests button itself (SetAllPoints +0x13fad0 on
    // [bar+0x138], +0x3e4e36), so with the button narrowed only its model needs the squeeze
    // (0x100fae00[0] = 0.725, as the buttons'); the 2 s pass picks it up once it's made
    UlModel(P(P(ui, 0x3d0), 0x13c), UL_MODEL_X);
}

// -- the portrait's HP / mana text, as WFE's Upgraded UI draws it
// WFE (read by hand: 0x10086cd0, its object 0x1013e008) doesn't move the
// portrait's own two lines: after each portrait update it empties them
// (0x100863c0: [0x1013aa28] = +0x143430 with "" on [portrait+0x240] / +0x244)
// and shows text frames of its own, WFEHPTextFrame / WFEMPTextFrame
// (0x100214f0: SMemAlloc(0x240) + the CTextFrame constructor, parent the game
// UI, layer 0; set up as NewText does, 0x10085250), each centred on the game
// UI's centre (0x10086aa0: SetPoint(text+0xb4, 4, ui+0xb4, 4, x, y, 1),
// x = -0.11 for 16:9 (.rdata 0x100faef0[0]), y -0.278 HP / -0.2915 mana), in
// the game's font at FontHeights / PortraitStats (the game reads it with
// +0x71240 for its own lines, +0x40d2f7) times 0.8 with the console's art
// shown, 1.3635 without (0x100867a0 / 0x10086950: [INTERFACE] ISCONSOLE),
// shown while the portrait has a unit and [ui+0x180] is 0, 2 or 4
// (0x10086710). Here the same frames, with the game's own lines' text (its
// buffer [string+0x9c], "%u / %u", or the regen lines when those are on) and
// colour (+0x68..+0x6b, as +0x141e40 stores it) copied in. The game only
// writes a line when the value changes, so the last text is kept; turning it
// off writes it back into the game's lines.
static const DWORD RVA_FONT_HEIGHT = 0x71240;      // __fastcall(section, key, float default) -> float in st0 (the game's FontHeights lookup)
static const DWORD RVA_FONT_HEIGHTS_NAME = 0xcb30a4;   // data: -> "FontHeights" (what +0x40d2ea passes)
static const DWORD UI_STATE180 = 0x180, FS_COLOUR = 0x68;     // (FS_TEXT = 0x9c: with the ping)
static const float PT_X = -0.11f, PT_Y[2] = { -0.278f, -0.2915f };
static BYTE *g_pt[2];                // our two text frames (the game UI's children: the game frees them)
static BYTE *g_ptUi;                // the game UI they belong to
static float g_ptHeight;            // the font height they have
static char g_ptText[2][96];        // the last text of the game's lines
static bool g_ptBad;                // refused for the session (logged); g_ptOn (above): the portrait's lines go to ours

static DWORD __declspec(noinline) GameCallFloat(const void *fn, DWORD rc, DWORD rd, DWORD a0, float *out) {
    float r;
    __asm {
        mov esi, esp
        push a0
        mov ecx, rc
        mov edx, rd
        mov eax, fn
        call eax
        mov esp, esi
        fstp dword ptr r
    }
    *out = r;
    return 0;
}
static float PortraitFontHeight() {
    static float h;
    if (!h) {
        const char *const *sec = (const char *const *)(g_base + RVA_FONT_HEIGHTS_NAME);
        float v = 0;
        __try {
            if (FnStart(RVA_FONT_HEIGHT) && PageIs(sec, READ) && PageIs(*sec, READ) && !strcmp(*sec, "FontHeights"))
                GameCallFloat(g_base + RVA_FONT_HEIGHT, (DWORD)*sec, (DWORD)"PortraitStats", 0, &v);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            v = 0;
        }
        h = v > 0.004f && v < 0.05f ? v : 0.0115f;
        Log("portrait text: FontHeights / PortraitStats %.4f (%s)", v, h == v ? "the game's" : "not usable: 0.0115");
    }
    return h;
}
static DWORD FsColour(BYTE *fs) {    // ARGB, from the bytes +0x141e40 stores (A, B, G, R)
    BYTE *c = fs + FS_COLOUR;
    return (DWORD)c[0] << 24 | (DWORD)c[3] << 16 | (DWORD)c[2] << 8 | c[1];
}
static BYTE *PortraitString(BYTE *p, int i) {
    BYTE *fs = *(BYTE **)(p + (i ? PORTRAIT_MP : PORTRAIT_HP));
    return fs && *(DWORD *)fs == (DWORD)(g_base + RVA_FONTSTRING_VTABLE) ? fs : nullptr;
}

// from PortraitHook, on the game thread, after the game's update (and the regen lines)
static void PortraitTextUpdate(BYTE *p) {
    if (!g_ptOn || !g_pt[0] || !g_pt[1] || (BYTE *)GameUi() != g_ptUi)
        return;
    for (int i = 0; i < 2; i++)
        if (BYTE *fs = PortraitString(p, i)) {
            const char *t = *(const char **)(fs + FS_TEXT);
            if (t && t[0]) {
                strncpy_s(g_ptText[i], t, _TRUNCATE);
                TextSet(g_pt[i], g_ptText[i]);
                TextColour(g_pt[i], FsColour(fs));
                Game(RVA_FONTSTRING_SET, fs, { (DWORD)"" });
            }
        }
    DWORD mode = *(DWORD *)(g_ptUi + UI_STATE180);
    bool show = *(BYTE **)(p + PORTRAIT_UNIT) && (mode == 0 || mode == 2 || mode == 4);
    TextShow(g_pt[0], show), TextShow(g_pt[1], show);
}

// the game's lines get their text back, ours hide (on the game thread)
static void PortraitTextOff() {
    if (!g_ptOn)
        return;
    g_ptOn = false;
    BYTE *ui = (BYTE *)GameUi(), *p = ui == g_ptUi ? P(ui, UI_PORTRAIT) : nullptr;
    __try {
        for (int i = 0; i < 2; i++) {
            BYTE *fs = p ? PortraitString(p, i) : nullptr;
            if (fs && g_ptText[i][0] && !(*(const char **)(fs + FS_TEXT) && **(const char **)(fs + FS_TEXT)))
                Game(RVA_FONTSTRING_SET, fs, { (DWORD)g_ptText[i] });
            if (g_pt[i] && ui == g_ptUi)
                TextShow(g_pt[i], false);
        }
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        Log("portrait text: giving the lines back faulted");
    }
    Log("portrait text: off (the portrait's own lines again)");
}

// with the layout, on the game thread: make the two frames (once a game), place them and set their font
static void UlPortraitText(BYTE *ui, BYTE *root) {
    if (g_ptBad)
        return;
    if (g_shared->prState == 3) {       // the update can't be wrapped: the game would write its lines again
        g_ptBad = true;
        Log("portrait text: the portrait update isn't wrapped (refused, see above): the portrait's own lines stay");
        return;
    }
    if (ui != g_ptUi)
        g_pt[0] = g_pt[1] = nullptr, g_ptUi = ui, g_ptHeight = 0, g_ptText[0][0] = g_ptText[1][0] = 0;
    if (!g_pt[0] || !g_pt[1]) {
        int fc = FramesCheck();
        if (fc != 1 || g_framesBad) {
            g_ptBad = true;
            Log("portrait text: no frames (%s): the portrait's own lines stay", fc == 2 ? "no Storm.dll in the game" : "refused, see above");
            return;
        }
        for (int i = 0; i < 2; i++)
            if (!g_pt[i] && !(g_pt[i] = NewText(ui, 0, PortraitFontHeight(), 0xffffffff))) {
                g_ptBad = true;
                Log("portrait text: making its frames failed: the portrait's own lines stay");
                return;
            }
        for (int i = 0; i < 2; i++) {
            BYTE *t = g_pt[i];
            *(DWORD *)(t + 0x200) = 0xe6000000, *(DWORD *)(t + 0x22c) = 1;     // as 0x10085250: its shadow colour,
            *(float *)(t + 0x208) = 0, *(float *)(t + 0x20c) = 0;              // and offset (.rdata 0x100fae60)
            *(float *)(t + 0x210) = 0.0012f, *(float *)(t + 0x214) = -0.0012f;
        }
        Log("portrait text: frames %p / %p (game UI mode [ui+%lX] = %lu)", g_pt[0], g_pt[1], UI_STATE180, *(DWORD *)(ui + UI_STATE180));
    }
    float h = PortraitFontHeight() * ((g_uiHidden & 0x20) ? 1.3635f : 0.8f);
    for (int i = 0; h != g_ptHeight && i < 2; i++) {        // once, and when the font changes (not every pass: no flicker)
        Game(RVA_SET_FONT, g_pt[i], { (DWORD)FontPath(), F(h), 0 });
        TextAnchor(g_pt[i], root, PT_CENTER, PT_CENTER, PT_X, PT_Y[i]);
    }
    g_ptHeight = h;
    if (!g_ptOn) {
        g_ptOn = true;
        Log("portrait text: on (font height %.4f)", h);
        if (BYTE *p = P(ui, UI_PORTRAIT))
            PortraitTextUpdate(p);
    }
}

typedef void (*UlFn)(BYTE *, BYTE *);
static const struct UlGroup { const char *name; UlFn fn; DWORD frame; } UL_GROUPS[] = {
    // each read by hand in WFEDll (2026-10-26); the newer ones last, so a log that stops names them
    { "minimap", UlMinimap, 0x3c0 }, { "minimap buttons", UlMinimapButtons, 0x408 }, { "hero buttons", UlHeroes, 0x3dc },
    { "command card", UlCard, 0x3c8 }, { "portrait", UlPortrait, UI_PORTRAIT }, { "inventory cover", UlCover, 0x3c4 },
    { "inventory", UlItems, 0x3c4 }, { "info panel", UlInfo, 0x3c4 }, { "portrait text", UlPortraitText, UI_PORTRAIT },
    { "upper menu bar", UlMenuBar, 0x3d0 }, { "resource bar", UlResources, 0x3cc }, { "idle workers", UlIdle, 0x3e0 },
    { "time of day", UlTimeOfDay, 0x3f8 }, { "tooltip", UlTooltip, 0x1cc }, { "messages", UlMessages, 0x3e4 },
    { "chat box", UlChat, 0x3fc }, { "console art", UlConsole, UI_CONSOLE }, { "buff bar", UlBuffs, 0x3c4 },
    { "button models", UlModels, 0x3c8 },
};
static const int UL_GROUP_COUNT = sizeof(UL_GROUPS) / sizeof(UL_GROUPS[0]);
static int g_ulStage;               // groups taken so far in this game (one more each pass at first)
static DWORD g_ulGroupBad;          // groups that faulted: left out

// the groups up to `upTo`, each guarded; the newest is logged first
static void UlApply(BYTE *ui, int upTo, bool logNewest) {
    BYTE *root = ui + FRAME_LAYOUT;     // the game UI's own layout: the whole screen
    for (int i = 0; i < upTo && i < UL_GROUP_COUNT; i++) {
        if (g_ulGroupBad >> i & 1)
            continue;
        const UlGroup &g = UL_GROUPS[i];
        if (logNewest && i == upTo - 1) {
            char rtti[64] = "";
            BYTE *f = P(ui, g.frame);
            if (f)
                RttiName(*(DWORD *)f, g_imageSize, rtti, sizeof(rtti));
            Log("UI layout: %s ([ui+%lX] %p, %s)", g.name, g.frame, f, f ? (rtti[0] ? rtti : "no RTTI") : "not there");
            g_ulLogSaves = 3;
        }
        __try {
            g.fn(ui, root);
        } __except (EXCEPTION_EXECUTE_HANDLER) {
            g_ulGroupBad |= 1u << i;
            Log("UI layout: the %s faulted: left out", g.name);
        }
    }
}

// on the game thread
static void UiLayoutPass() {
    bool on = g_shared->ulOn != 0 && !g_ulBad;
    BYTE *ui = (BYTE *)GameUi();
    if (ui != g_ulUi) {
        g_ulN = 0, g_ulUi = ui, g_ulAt = 0, g_shared->ulCount = 0, g_ulStage = 0;    // a new game: its own frames
        g_ptOn = false, g_ulModelN = 0;                                                 // (the old models went with the old game)
    }
    RECT r = {};
    bool wide = g_gameWnd && GetClientRect(g_gameWnd, &r) && r.bottom > 0 && r.right * 2 >= r.bottom * 3;
    if (!on || !ui || !wide) {
        PortraitTextOff();
        if (g_ulModelN && ui) {
            __try {
                UlModelsRestore();
            } __except (EXCEPTION_EXECUTE_HANDLER) {
                Log("UI layout: putting a model back faulted");
                g_ulModelN = 0;
            }
        }
        if (g_ulN && ui) {
            __try {
                for (int i = g_ulN - 1; i >= 0; i--)
                    UlRestore(g_ul[i]);
            } __except (EXCEPTION_EXECUTE_HANDLER) {
                Log("UI layout: putting a frame back faulted");
            }
            Log("UI layout: %d frames put back", g_ulN);
            g_ulN = 0, g_shared->ulCount = 0;
        }
        g_ulStage = 0;
        g_ulAt = 0;                 // laid out at once when it's wanted again
        g_shared->ulState = g_ulBad ? 3 : !g_shared->ulOn ? 0 : 2;
        return;
    }
    DWORD now = GetTickCount();
    bool rampUp = g_ulStage < UL_GROUP_COUNT;   // at first one more handler a pass (4 a second)
    if (!rampUp && g_ulAt && now - g_ulAt < 2000)
        return;
    g_ulAt = now;
    if (rampUp)
        g_ulStage++;
    int before = g_ulN;
    UlApply(ui, g_ulStage, rampUp);
    if (g_ulN != before && !rampUp)
        Log("UI layout: %d more frames laid out", g_ulN - before);
    if (g_ulStage == UL_GROUP_COUNT && rampUp)
        Log("UI layout: %d frames laid out for a %ldx%ld window", g_ulN, r.right, r.bottom);
    g_shared->ulCount = g_ulN;
    g_shared->ulState = g_ulBad ? 3 : 1;
}

// -- fast menus ----------------------------------------------------------------------
// WFE's Fast Menu ([FUNCTIONS] FASTMENU, read by hand: 0x1006f5b7..0x1006f7a8,
// its hook 0x10053a60): the menus' (glue screens') transitions go through
// the game's +0x33a790 (__fastcall(model, anim, a, b, c, d) -> float in st0,
// ret 0x10; about 95 callers): it plays the backdrop model's animation, has
// the game call back when it ends, and returns how long it takes. WFE calls
// it, then sets the animation speed of the glue's two backdrop models (the
// first sprite +0x190 of [glue+0x194] / [glue+0x198], glue = the game's
// +0x3112a0()) to 100 (.rdata 0x100fa910) and returns 0.01. With so many
// callers the function's own start is detoured here (its first 6 bytes,
// 55 8B EC 83 EC 18, go to a copy that jumps back; nothing in it jumps into
// them), on the game thread; off and unload put the bytes back and the
// models' speed to 1, as WFE's off branch writes.
static const DWORD RVA_MENU_ANIM = 0x33a790, RVA_GLUE = 0x3112a0, DATA_GLUE = 0xd31824, GLUE_MODELS = 0x194, SPRITE_SPEED = 0x190;
static const BYTE MENU_ANIM_START[6] = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x18 };
static const float FAST_MENU_SPEED = 100, FAST_MENU_TIME = 0.01f;
typedef float(__fastcall *MenuAnimFn)(DWORD, DWORD, DWORD, DWORD, DWORD, DWORD);
static BYTE *g_fmTramp;             // the 6 bytes and a jmp back (stays allocated: a retired module may still be on the stack)
static bool g_fmHooked, g_fmBad;
static volatile LONG g_fmCalls;

// the glue's singleton as +0x3112a0 keeps it ([+0xd31824]; that getter makes one when there's none, so it isn't called here)
static void GlueSpeed(float speed) {
    BYTE *glue = *(BYTE **)(g_base + DATA_GLUE);
    if (!glue || (DWORD)(glue - (BYTE *)0x10000) > 0x7ffeffff)
        return;
    for (int i = 0; i < 2; i++) {
        BYTE *f = V(*(BYTE **)(glue + GLUE_MODELS + i * 4));
        BYTE **list = f && *(int *)(f + 0x174) > 0 ? *(BYTE ***)(f + 0x178) : nullptr;
        BYTE *sp = list ? V(list[0]) : nullptr;
        if (sp)
            *(float *)(sp + SPRITE_SPEED) = speed;
    }
}
static float __fastcall MenuAnimHook(DWORD model, DWORD anim, DWORD a, DWORD b, DWORD c, DWORD d) {
    float t = ((MenuAnimFn)g_fmTramp)(model, anim, a, b, c, d);
    if (!g_shared->fmOn || g_fmBad)
        return t;
    __try {
        GlueSpeed(FAST_MENU_SPEED);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        g_fmBad = true, g_shared->fmState = 3;
        Log("fast menu: setting the models' speed faulted: stopping");
        return t;
    }
    if (InterlockedIncrement(&g_fmCalls) == 1)
        Log("fast menu: the first transition sped up (the game's %.2f s -> %.2f s)", t, FAST_MENU_TIME);
    return FAST_MENU_TIME;
}

// nothing branches into the first 6 bytes (the function's own jumps, up to its last ret)
static bool MenuAnimPatchable(const BYTE *f) {
    if (!FnStart((DWORD)(f - g_base)) || memcmp(f, MENU_ANIM_START, 6))
        return false;
    const BYTE *p = f, *furthest = f;
    for (int i = 0; i < 400; i++) {
        int kind;
        const BYTE *t = nullptr;
        int n = Decode(p, &kind, &t);
        if (kind == I_BAD || n <= 0)
            return false;
        if (t && t > f && t < f + 6)
            return false;
        if (t && (kind == I_JCC || kind == I_JMP) && t > furthest)
            furthest = t;
        p += n;
        if ((kind == I_RET || kind == I_JMP) && p > furthest)
            return true;
    }
    return false;
}

// on the game thread (and on unload): the detour in or out. false = refused (logged)
static bool FastMenuHook(bool on) {
    if (on == g_fmHooked)
        return true;
    BYTE *f = g_base + RVA_MENU_ANIM;
    if (on) {
        if (!MenuAnimPatchable(f)) {
            Log("fast menu: refused, +%06lX isn't the game's menu animation as 1.28f has it", RVA_MENU_ANIM);
            LogBytes("  its bytes", f);
            return false;
        }
        if (!g_fmTramp && (g_fmTramp = (BYTE *)VirtualAlloc(nullptr, 16, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE)) != nullptr) {
            memcpy(g_fmTramp, MENU_ANIM_START, 6);
            g_fmTramp[6] = 0xE9, *(LONG *)(g_fmTramp + 7) = (LONG)((f + 6) - (g_fmTramp + 11));
            FlushInstructionCache(GetCurrentProcess(), g_fmTramp, 16);
        }
        BYTE jmp[6] = { 0xE9, 0, 0, 0, 0, 0x90 };
        *(LONG *)(jmp + 1) = (LONG)((BYTE *)MenuAnimHook - (f + 5));
        if (!g_fmTramp || !WriteCode(f, jmp, 6)) {
            Log("fast menu: writing the detour failed");
            return false;
        }
        g_fmHooked = true;
        Log("fast menu: on (+%06lX detoured)", RVA_MENU_ANIM);
        return true;
    }
    if (f[0] != 0xE9 || f + 5 + *(LONG *)(f + 1) != (BYTE *)MenuAnimHook) {
        Log("fast menu: +%06lX was changed by someone else: left as it is", RVA_MENU_ANIM);
        g_fmHooked = false;
        return false;
    }
    WriteCode(f, MENU_ANIM_START, 6);
    g_fmHooked = false;
    __try {
        GlueSpeed(1);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
    Log("fast menu: off (the game's menu animation again)");
    return true;
}

// on the game thread
static void FastMenuPass() {
    bool on = g_shared->fmOn && !g_fmBad;
    if (on != g_fmHooked && !(on && g_shared->fmState == 3) && !FastMenuHook(on))
        g_shared->fmState = 3;
    if (g_shared->fmState != 3)
        g_shared->fmState = g_fmHooked ? 1 : 0;
}

// on the game thread
static void LoginPass();
static int g_blStep;                // Battle.net login: 0 waiting for the main menu, 1 Battle.net clicked, 2 at the login screen, 9 done for this game start
static void DisplayPass() {
    if (!g_getUi)
        return;
    FastMenuPass();
    WidescreenPass();
    FpsPass();
    LatencyPass();
    CountdownPass();
    AlliesPass();
    UiHidePass();
    UiLayoutPass();
    BuffBarSizePass();
    LoginPass();
}

// the worker's part: a pass 4 times a second while any is on, or has something to put back
static void QueueDisplay() {
    static DWORD at;
    DWORD now = GetTickCount();
    if (!g_getUi || now - at < 250 || (!g_shared->wsOn && !g_wsApplied && !FpsWork() && LatencyWanted() == g_latSet && !g_shared->uiHide && !g_uiHidden && !g_shared->ulOn && !g_ulN && !g_ulModelN && !g_ptOn && !g_shared->fmOn && !g_fmHooked && CountdownWanted() == g_csSet && !g_shared->alOn && !g_alHooked && BuffBarScale() == 1 && !g_bbApplied && !(g_shared->blOn && g_blStep != 9)))
        return;
    at = now;
    if (Subclass() && !InterlockedExchange(&g_dispQueued, 1))
        PostMessageA(g_gameWnd, g_dispMsg, 0, 0);
}

// The multiboard, as WFE's Toggle Multiboard State (its readme: minimise /
// maximise; handler 0x1005c3f5): the game UI's multiboard [ui+0x3ac], and
// [+0x1b8] 0 -> +0x4128d0, else +0x4127d0, each __fastcall(board, 0).
static const DWORD UI_MULTIBOARD = 0x3ac, MB_STATE = 0x1b8;
static const DWORD RVA_MB_STATE0 = 0x4127d0, RVA_MB_STATE1 = 0x4128d0;    // WFE's [0x1013a468], [0x1013a46c]

static int ToggleMultiboard(BYTE *ui) {
    static int checked;             // 1 checked out, 2 refused for good
    if (!checked && (!FnStart(RVA_MB_STATE0) || !FnStart(RVA_MB_STATE1))) {
        checked = 2;
        Log("multiboard: refused (its functions aren't function starts)");
    }
    BYTE *mb = checked == 2 ? nullptr : UiFrame(ui, UI_MULTIBOARD);
    if (!mb)
        return 2;
    __try {
        DWORD st = *(DWORD *)(mb + MB_STATE);
        if (!checked) {
            checked = 1;
            char rtti[64];
            RttiName(*(DWORD *)mb, g_imageSize, rtti, sizeof(rtti));
            Log("multiboard: %p, vtable +%06lX, RTTI %s, state %lu", mb, *(DWORD *)mb - (DWORD)g_base, rtti[0] ? rtti : "(none)", st);
            if (rtti[0] && !strstr(rtti, "Multiboard")) {
                Log("  not a multiboard: refusing (this and later toggles)");
                checked = 2;
                return 2;
            }
        }
        ((FrameFn)(g_base + (st ? RVA_MB_STATE0 : RVA_MB_STATE1)))(mb, 0);
        return 1;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        Log("multiboard: the game's call faulted");
        return 2;
    }
}

// -- self-cast and the autocast toggle -------------------------------------------------
// Both as WFE's key handler (0x10066a20) does them on 1.28f, without its hook
// of the game's key input.
// Self-cast: when the game waits for a target while the self-cast key is
// held, WFE clicks the portrait (0x10067b00): [ui+0x3f4], through the CControl
// function +0x1407b0 (WFE's [0x1013a2a0]), __fastcall(control, 0, 1). The
// game takes that as the target: your selected unit. Here the worker watches
// for it (once per aim) and hands the click to the game thread.
static const DWORD RVA_CONTROL_CLICK = 0x1407b0;

typedef int(__fastcall *ClickFn)(void *, int, int);

// -- Battle.net login (layout 24) ------------------------------------------------------
// The menus, read by hand in Game.dll (study: the commit message): the main menu (CMainMenu)
// registers its "BattleNetButton" as command 1 (+0x30e9b7, through +0x314480 -> +0x141430:
// the click event 0x40090064 sent to the menu), which connects to the gateway chosen in the
// game (+0x318eb0, BNET_CONNECT_INIT); the login screen (CBattleNetMain, its init +0x30a420)
// keeps the "AccountName" / "Password" edit boxes at +0x1f8 / +0x1fc and registers its
// "LogonButton" as command 5 (+0x30a4c8), whose handler +0x32d450 reads both boxes' text
// (+0x1311c0: [box+0x1e4]), sends the logon and empties the password box. Frames are found
// by name as the game's screens find theirs (+0x1212f0, fastcall(name, 0): a read-only
// lookup, the record's +0x18); a frame is shown when ([+0xb0] & 3) == 0 (+0x11cdf0: bit 1
// its own hide, bit 2 a hidden parent); a click is the control's own +0x1407b0(control, 0, 1)
// (it sends 0x40090064 through the control's vt+0x10, as a mouse click does); text goes in
// with the edit box's setter +0x132820(text, 1), ret 8 (the screen's own fill of the last
// account name, +0x30aff8). Once per game start, only outside a game: the main menu's
// Battle.net clicked (unless Shift is held then), then on the login screen the companion is
// asked for the account (blState 2), it's typed in and Logon clicked; the password's copy here
// is wiped at once. A failed logon isn't tried again (the game shows its own message).
static const DWORD RVA_FRAME_BY_NAME = 0x1212f0, RVA_EDIT_SET_TEXT = 0x132820, FRAME_HIDDEN = 0xb0;
// the login screen's boxes are plain CEditBoxes (+0xa7c03c, the first in-game test), the glue one derives from it;
// the setter +0x132820 and the text [+0x1e4] are CEditBox's own (its ctor +0x13069f)
static const DWORD RVA_GLUE_BUTTON_VT[2] = { 0xa93b68, 0xa93ca4 }, RVA_EDIT_VT[2] = { 0xa93f1c, 0xa7c03c };
typedef BYTE *(__fastcall *FrameByNameFn)(const char *, int);
static DWORD g_blAt;
static BYTE *GlueFrame(const char *name, bool edit) {
    BYTE *f = ((FrameByNameFn)(g_base + RVA_FRAME_BY_NAME))(name, 0);
    if (!f || (DWORD)(f - (BYTE *)0x10000) > 0x7ffeffff)
        return nullptr;
    DWORD vt = *(DWORD *)f - (DWORD)g_base;
    if (edit ? vt != RVA_EDIT_VT[0] && vt != RVA_EDIT_VT[1] : vt != RVA_GLUE_BUTTON_VT[0] && vt != RVA_GLUE_BUTTON_VT[1]) {
        static int logs;
        if (logs < 4)
            logs++, Log("battle.net login: the frame '%s' %p has vtable +%06lX, not a%s: left alone", name, f, vt, edit ? "n edit box" : " glue button");
        return nullptr;
    }
    return f;
}
static bool GlueShown(BYTE *f) { return f && !(*(DWORD *)(f + FRAME_HIDDEN) & 3); }
static void LoginEnd(DWORD state, const char *why) {
    g_blStep = 9, g_shared->blState = state;
    SecureZeroMemory(g_shared->blPassword, sizeof(g_shared->blPassword));
    Log("battle.net login: %s", why);
}
static void LoginPass() {
    static bool bad;
    Shared *s = g_shared;
    if (bad || g_blStep == 9)
        return;
    if (!s->blOn) {
        if (g_blStep)
            LoginEnd(4, "turned off: left to you");
        return;
    }
    if (GameUi())
        return LoginEnd(4, "a game is running: not now (only at game start)");
    DWORD now = GetTickCount();
    __try {
        BYTE *bn = GlueFrame("BattleNetButton", false), *logon = GlueFrame("LogonButton", false);
        BYTE *acc = GlueFrame("AccountName", true), *pw = GlueFrame("Password", true);
        bool atLogin = GlueShown(logon) && GlueShown(acc) && GlueShown(pw);
        if (g_blStep == 0) {
            if (atLogin) {
                g_blStep = 2, g_blAt = now, s->blState = 2;
                Log("battle.net login: at the login screen (account box %p, password %p, Logon %p): asking for the account", acc, pw, logon);
            } else if (GlueShown(bn)) {
                if (!g_blAt) {
                    g_blAt = now;                       // the menu's own animation first
                    Log("battle.net login: the main menu is up (Battle.net button %p, vtable +%06lX)", bn, *(DWORD *)bn - (DWORD)g_base);
                } else if (now - g_blAt > 1000) {
                    if (GetAsyncKeyState(VK_SHIFT) & 0x8000)
                        return LoginEnd(4, "Shift held at the main menu: skipped this time");
                    ((ClickFn)(g_base + RVA_CONTROL_CLICK))(bn, 0, 1);
                    g_blStep = 1, g_blAt = now, s->blState = 1;
                    Log("battle.net login: Battle.net clicked");
                }
            }
            return;
        }
        if (g_blStep == 1) {
            if (atLogin) {
                g_blStep = 2, g_blAt = now, s->blState = 2;
                Log("battle.net login: at the login screen (account box %p, password %p, Logon %p): asking for the account", acc, pw, logon);
            } else if (now - g_blAt > 30000)
                LoginEnd(4, "no login screen within 30 s (not connected?): left to you");
            return;
        }
        // at the login screen: the companion's account (blSeq moved past blDone)
        if (!atLogin || s->blSeq == s->blDone) {
            if (now - g_blAt > 15000)
                LoginEnd(4, "the companion gave no account in 15 s: left to you");
            return;
        }
        s->blDone = s->blSeq;
        s->blAccount[sizeof(s->blAccount) - 1] = 0, s->blPassword[sizeof(s->blPassword) - 1] = 0;
        if (!s->blAccount[0] || !s->blPassword[0])
            return LoginEnd(4, "no account name or password set in the companion: left to you");
        Game(RVA_EDIT_SET_TEXT, acc, { (DWORD)s->blAccount, 1 });
        Game(RVA_EDIT_SET_TEXT, pw, { (DWORD)s->blPassword, 1 });
        SecureZeroMemory(s->blPassword, sizeof(s->blPassword));
        ((ClickFn)(g_base + RVA_CONTROL_CLICK))(logon, 0, 1);
        g_blStep = 9, s->blState = 3;
        Log("battle.net login: account '%s' typed in, Logon clicked", s->blAccount);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        bad = true, s->blState = 5;
        SecureZeroMemory(s->blPassword, sizeof(s->blPassword));
        Log("battle.net login: a menu call faulted: no more tries");
    }
}

static bool GameInFront();
static bool SelfHeld() { return g_shared->scHeld == 2; }

// the worker's part: t is this round's Targeting()
static void WatchSelfCast(int t) {
    static bool aimDone;            // this aim was handed over: once per aim (the key held as it began, or pressed during it)
    if (t != 1) {
        aimDone = false;
        return;
    }
    if (aimDone || !SelfHeld() || !GameInFront() || g_shared->scState == 3)
        return;
    aimDone = true;
    if (Subclass())
        PostMessageA(g_gameWnd, g_selfMsg, 0, 0);
}

// on the game thread
static void SelfCast() {
    static int checked;             // 1 checked out, 2 refused for good
    if (checked == 2)
        return;
    if (!checked && !FnStart(RVA_CONTROL_CLICK)) {
        checked = 2, g_shared->scState = 3;
        Log("self-cast: refused (the control click isn't a function start)");
        return;
    }
    BYTE *ui = (BYTE *)GameUi();
    BYTE *pb = ui ? UiFrame(ui, UI_PORTRAIT) : nullptr;
    if (!pb)
        return;
    __try {
        DWORD target = *(DWORD *)(ui + UI_TARGET_MODE);
        if (!target || *(DWORD *)(ui + UI_MODE) != target)
            return;                     // the aim ended before the game thread got here
        if (!checked) {
            checked = 1;
            char rtti[64];
            RttiName(*(DWORD *)pb, g_imageSize, rtti, sizeof(rtti));
            Log("self-cast: portrait %p, vtable +%06lX, RTTI %s", pb, *(DWORD *)pb - (DWORD)g_base, rtti[0] ? rtti : "(none)");
            if (rtti[0] && !strstr(rtti, "Portrait")) {
                Log("  not the portrait: refusing (this and later self-casts)");
                checked = 2, g_shared->scState = 3;
                return;
            }
        }
        ((ClickFn)(g_base + RVA_CONTROL_CLICK))(pb, 0, 1);
        g_shared->scCount++;
        static int logs;
        if (logs < 3)
            logs++, Log("self-cast: clicked the portrait");
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        Log("self-cast: the game's click faulted: stopping");
        checked = 2, g_shared->scState = 3;
    }
}

// The autocast toggle: WFE's 0x10053c20 presses a command button through its
// own click, vtable +0x6c __fastcall(button, 0, mouse button), with 4 (the
// right button: autocast on / off) while the autocast key is held, and with
// [button+0x138] bit 2 set for the call. The button: the command card
// [ui+0x3c8] grid, slot row by row; it needs an ability ([+0x190]).
static const DWORD BTN_CLICK = 0x6c, BTN_FLAGS = 0x138, BTN_DATA = 0x190;

static int AutocastToggle(BYTE *ui, DWORD slot) {
    static int checked;             // 1 checked out, 2 refused for good
    if (checked == 2 || slot > 11)
        return 2;
    __try {
        BYTE *card = *(BYTE **)(ui + 0x3c8);
        if (!card)
            return 2;
        int rows = *(int *)(card + 0x124), cols = *(int *)(card + 0x128);
        if (rows <= 0 || cols <= 0 || rows > 3 || cols > 4 || (int)slot >= rows * 4)
            return 2;
        BYTE *btn = (int)(slot % 4) < cols ? GridButton(card, slot / 4, slot % 4) : nullptr;
        if (!btn || !*(DWORD *)(btn + BTN_DATA))
            return 2;                   // an empty slot
        DWORD vt = *(DWORD *)btn;
        if (!InImage(vt, g_imageSize) || PageIs((void *)vt, EXEC))
            return 2;
        BYTE *fn = *(BYTE **)(vt + BTN_CLICK);
        if (!IsGameCode(fn)) {
            Log("autocast: refused, the button's click (%p) isn't game code", fn);
            checked = 2;
            return 2;
        }
        if (!checked) {
            checked = 1;
            char rtti[64];
            RttiName(vt, g_imageSize, rtti, sizeof(rtti));
            Log("autocast: button %p, vtable +%06lX (click +%06lX), RTTI %s", btn, vt - (DWORD)g_base, (DWORD)(fn - g_base), rtti[0] ? rtti : "(none)");
            if (rtti[0] && !strstr(rtti, "CommandButton")) {
                Log("  not a command button: refusing (this and later toggles)");
                checked = 2;
                return 2;
            }
        }
        DWORD flags = *(DWORD *)(btn + BTN_FLAGS);
        *(DWORD *)(btn + BTN_FLAGS) = flags | 2;
        ((ClickFn)fn)(btn, 0, 4);
        *(DWORD *)(btn + BTN_FLAGS) = flags;
        return 1;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        Log("autocast: the game's click faulted: stopping");
        checked = 2;
        return 2;
    }
}

// a command from the companion: handed to the game thread, answered within 1 s
static void ServeCommand(LONG seq) {
    DWORD cmd = g_shared->cmd;
    int result = 2;
    if (g_getUi && Subclass()) {
        InterlockedExchange(&g_running, (LONG)cmd);
        g_shared->cmdResult = 0;
        if (!PostMessageA(g_gameWnd, g_runMsg, (WPARAM)seq, 0))
            Log("game thread: posting to the game window failed (%lu)", GetLastError());
        for (int i = 0; i < 100 && g_shared->cmdDone != seq; i++)
            Sleep(10), g_shared->heartbeat = GetTickCount();   // a slow game thread isn't a dead module (quickcast would stand down)
        if (g_shared->cmdDone == seq)
            return;                     // answered by the game thread
        InterlockedExchange(&g_running, 0);
        result = 3;
    }
    g_shared->cmdResult = result;
    InterlockedExchange(&g_shared->cmdDone, seq);
}

// -- the click -------------------------------------------------------------------
static bool GameInFront() {
    DWORD pid = 0;
    HWND w = GetForegroundWindow();
    return w && GetWindowThreadProcessId(w, &pid) && pid == GetCurrentProcessId();
}
static void Key(INPUT *in, int &n, WORD vk, bool up) {
    ZeroMemory(&in[n], sizeof(INPUT));
    in[n].type = INPUT_KEYBOARD;
    in[n].ki.wVk = vk;
    in[n].ki.dwFlags = up ? KEYEVENTF_KEYUP : 0;
    n++;
}
static void Mouse(INPUT *in, int &n, DWORD flags) {
    ZeroMemory(&in[n], sizeof(INPUT));
    in[n].type = INPUT_MOUSE;
    in[n].mi.dwFlags = flags;
    n++;
}
// A left click at the cursor. Modifiers still held from your hotkey are let go
// around it and pressed again after (as AutoHotkey's Send does), so Ctrl+Q
// doesn't become a Ctrl+click; Shift stays for a queued order. Letting go of
// Alt or Win alone would open a menu, so a dummy key (vkE8) goes first.
static void Click(DWORD flags) {
    static const WORD MODS[] = { VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU, VK_LWIN, VK_RWIN, VK_LSHIFT, VK_RSHIFT };
    INPUT in[32];
    int n = 0;
    WORD lifted[8];
    int nl = 0;
    bool mask = false;
    for (WORD vk : MODS) {
        if ((vk == VK_LSHIFT || vk == VK_RSHIFT) && (flags & 1))
            continue;
        if (GetAsyncKeyState(vk) & 0x8000) {
            if (vk != VK_LSHIFT && vk != VK_RSHIFT && vk != VK_LCONTROL && vk != VK_RCONTROL && !mask) {
                Key(in, n, 0xE8, false), Key(in, n, 0xE8, true);
                mask = true;
            }
            Key(in, n, vk, true);
            lifted[nl++] = vk;
        }
    }
    if (GetAsyncKeyState(VK_LBUTTON) & 0x8000)
        Mouse(in, n, MOUSEEVENTF_LEFTUP);
    Mouse(in, n, MOUSEEVENTF_LEFTDOWN);
    Mouse(in, n, MOUSEEVENTF_LEFTUP);
    for (int i = 0; i < nl; i++)
        Key(in, n, lifted[i], false);
    SendInput(n, in, sizeof(INPUT));
}

// -- the loop ----------------------------------------------------------------------
// A quickcast request is answered once: clicked when the game waits for a
// target (and is in front), or given up at its deadline. Between requests the
// targeting flag is refreshed now and then for the companion's status.
// -- unloading (a newer module replaces this one) ---------------------------------------
// The companion asks (unload = 1) and stops writing. Every switch goes off here,
// so the passes take their frames and changes away (2 s), then the game thread
// gives back what's left (vtable entries, rewritten calls, code bytes, the
// window) and the worker waits a second more, so no game call can still be in
// our code. Then it retires: the module stays mapped (nothing of ours left
// running), its shared memory and names go so the new copy can make its own.
// Not FreeLibrary: the game may keep a pointer into our data (the names our
// frames were allocated under), and the first live swap crashed the game
// right after freeing. If someone subclassed the window after us, ours
// can't be taken out: the module stays (status 5).
static volatile LONG g_finalDone;   // 1 given back, 2 can't unload
static bool g_unloadNow;            // Worker retires the module when Run returns
static Shared g_retired;            // what g_shared points at once retired (nothing reads it)

static void SwitchesOff() {
    Shared *s = g_shared;
    s->hbOn = s->hcOn = s->wsOn = s->fpsOn = s->latOn = s->uiHide = s->itOn = s->hnOn = s->mbOn = s->prOn = s->tmWant = s->scHeld = s->ulOn = s->ttOn = s->fmOn = s->csOn = s->alOn = s->pingOn = s->hrWant = 0;
    s->bbScale = 0, s->blOn = 0;
    SecureZeroMemory(s->blPassword, sizeof(s->blPassword));
    s->qcUntil = 0;
}
static void RestoreAll() {
    if (g_portraitSlot)
        SwapPortrait(false);
    SwapTooltips(false);
    FastMenuHook(false);
    if (g_prSites && g_portraitHooked)
        PointSites(false);
    if (g_wsApplied)
        PointProjection(false), g_wsApplied = false;
    SwapBarExtras(false), SwapBarUpdate(false), FpsPatch(false, true), LatencyRestore(true), CountdownRestore(true), AlliesHook(false);
}
// on the game thread: the last of it, and the window back
static void FinalPass() {
    RestoreAll();
    Unsubclass();
    InterlockedExchange(&g_finalDone, g_oldProc ? 2 : 1);  // still in the window's chain: can't go
}

// true when Run should end (unloading)
static bool UnloadStep(DWORD now) {
    static DWORD askedAt, finalAt;
    static bool asked, posted;
    if (g_shared->unload != 1 && !asked)
        return false;
    if (!asked) {
        asked = true, askedAt = now;
        g_shared->status = 4;
        Log("unloading: a newer module replaces this one; turning everything off");
    }
    SwitchesOff();
    if (now - askedAt < 2000)
        return false;
    if (!posted) {
        posted = true, finalAt = now;
        if (g_oldProc && g_gameWnd)
            PostMessageA(g_gameWnd, g_finalMsg, 0, 0);
        else
            RestoreAll(), InterlockedExchange(&g_finalDone, 1);     // never subclassed: nothing runs on the game thread
    }
    LONG done = g_finalDone;
    if (!done && now - finalAt < 5000)
        return false;
    if (done != 1) {
        g_shared->status = 5;
        g_shared->unload = 2;
        Log(done == 2 ? "unloading: the game window was subclassed after us: the module stays (restart the game for the new one)"
                      : "unloading: the game thread didn't answer: the module stays");
        asked = posted = false;
        return false;
    }
    Sleep(1000);                    // any game call still in our code returns
    Log("unloading: everything given back");
    asked = posted = false;
    g_unloadNow = true;
    return true;
}

static void Run() {
    LONG handled = g_shared->qcDone;     // not qcSeq: a request made while probing (probe already 1) is answered too
    DWORD askedAt = 0;
    bool fast = false;
    int clicks = 0;
    DWORD timersAt = 0;
    while (!g_stop) {
        DWORD now = GetTickCount();
        g_shared->heartbeat = now;
        if (UnloadStep(now))
            break;
        if (!g_getUi) {
            if (fast)
                timeEndPeriod(1), fast = false;
            Sleep(50);
            continue;
        }
        LONG seq = g_shared->qcSeq;
        bool asked = seq != handled;
        if (asked && !fast) {
            timeBeginPeriod(1);         // 1 ms sleeps while a request is open
            fast = true, askedAt = now;
        }
        int t = Targeting();
        g_shared->targeting = t == 1;
        if (g_shared->scState != 3)
            g_shared->scState = g_shared->scHeld ? 1 : 0;
        WatchSelfCast(t);
        if (g_shared->tmWant && !g_itReading && now - timersAt >= 100) {
            timersAt = now;                     // 10 a second is plenty for whole seconds
            QueueTimers();                      // (drawn in the game: TimerFramesPass reads them)
        }
        QueueBars();
        FollowColours();
        FollowPortrait();
        FollowTooltips();
        QueueDisplay();
        QueueFrames();
        LONG cseq = g_shared->cmdSeq;
        if (cseq != g_shared->cmdDone)
            ServeCommand(cseq);
        if (asked) {
            DWORD result = 0;
            if (t == 1 && GameInFront() && SelfHeld() && g_shared->scState == 1)
                result = 1;                     // self-cast takes this aim: no click at the cursor
            else if (t == 1 && GameInFront()) {
                Click(g_shared->qcFlags);
                result = 1;
                if (clicks++ < 3)
                    Log("quickcast: clicked %lu ms after the request", now - askedAt);
            } else if (!g_shared->qcUntil || (LONG)(now - g_shared->qcUntil) >= 0)
                result = t == 1 ? 3 : 2;
            if (result) {
                g_shared->qcMs = now - askedAt;
                g_shared->qcResult = result;
                g_shared->qcDone = seq;
                handled = seq;
            }
        }
        if (fast && seq == handled) {
            timeEndPeriod(1);
            fast = false;
        }
        if (fast)
            Sleep(1);
        else
            WaitForSingleObject(g_wake, 30);
    }
    if (fast)
        timeEndPeriod(1);
}

static DWORD WINAPI Worker(void *) {
    DWORD build = GameBuild();
    g_shared->build = build;
    if (build != BUILD_128F) {
        g_shared->status = 2;
        Log("game build %lu is not 1.28f (7680): staying idle", build);
        return 0;
    }
    g_shared->status = 1;
    Log("1.28f found: probing");
    char why[sizeof(g_shared->probeText)];
    bool ok = Probe(why, sizeof(why));
    strcpy_s(g_shared->probeText, why);
    g_shared->probe = ok ? 1 : 2;
    Log(ok ? "probe passed: quickcast can run" : "probe failed: %s. Staying idle", why);
    if (ok)
        g_getUi = (GetUiFn)(g_base + RVA_GET_UI);
    Run();
    if (g_unloadNow) {
        // Retired, not freed: the game may still hold pointers into this
        // module's data (e.g. the names given to Storm with our frames), so
        // the code and data stay mapped; only the names go, for the new one
        Log("unloading: retired (stays mapped, idle); the shared memory is the next module's");
        g_shared->status = 3;
        Shared *sh = g_shared;
        g_shared = &g_retired;
        UnmapViewOfFile(sh);
        if (g_map)
            CloseHandle(g_map), g_map = nullptr;
        if (g_wake)
            CloseHandle(g_wake), g_wake = nullptr;
    }
    return 0;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_self = inst;
        DisableThreadLibraryCalls(inst);
        GetModuleFileNameA(inst, g_logPath, MAX_PATH);
        char *slash = strrchr(g_logPath, '\\');
        strcpy_s(slash ? slash + 1 : g_logPath, MAX_PATH - (slash ? slash + 1 - g_logPath : 0), "twc-game.log");
        char name[64];
        sprintf_s(name, "Local\\TWC_Game_%lu", GetCurrentProcessId());
        g_map = CreateFileMappingA(INVALID_HANDLE_VALUE, nullptr, PAGE_READWRITE, 0, sizeof(Shared), name);
        if (!g_map)
            return FALSE;
        g_shared = (Shared *)MapViewOfFile(g_map, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(Shared));
        if (!g_shared)
            return FALSE;
        ZeroMemory(g_shared, sizeof(Shared));
        g_shared->magic = 'TWC1';
        g_shared->layout = 24;
        g_shared->stamp = ((IMAGE_NT_HEADERS *)((BYTE *)inst + ((IMAGE_DOS_HEADER *)inst)->e_lfanew))->FileHeader.TimeDateStamp;
        sprintf_s(name, "Local\\TWC_GameQc_%lu", GetCurrentProcessId());
        g_wake = CreateEventA(nullptr, FALSE, FALSE, name);
        Log("---- twc-game.dll loaded into pid %lu", GetCurrentProcessId());
        HANDLE t = CreateThread(nullptr, 0, Worker, nullptr, 0, nullptr);
        if (t)
            CloseHandle(t);
    } else if (reason == DLL_PROCESS_DETACH) {
        g_stop = 1;
        if (!reserved)
            Unsubclass(), g_portraitSlot && SwapPortrait(false), g_prSites && g_portraitHooked && PointSites(false), g_wsApplied && PointProjection(false), SwapBarExtras(false), SwapBarUpdate(false), FpsPatch(false, true), LatencyRestore(true), CountdownRestore(true), AlliesHook(false);  // FreeLibrary, not the game exiting: give back the window, the bar update, the limiter, the latency getters, the allies hooks
                                                    // (the frame limit setting and widescreen need the game thread: they stay)
        if (g_shared)
            g_shared->status = 3;
        if (!reserved) {            // unloaded: free the names for the next module (the companion's view keeps it until it lets go)
            if (g_shared)
                UnmapViewOfFile(g_shared), g_shared = nullptr;
            if (g_map)
                CloseHandle(g_map), g_map = nullptr;
            if (g_wake)
                CloseHandle(g_wake), g_wake = nullptr;
        }
    }
    return TRUE;
}
