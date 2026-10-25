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
//  only writes into the game itself: the health bar colours' vtable entry,
//  the FPS unlock's one byte and the latency getters' first 6 bytes, all put
//  back when turned off.
//
//  Build: native\build.bat (32-bit, MSVC).
// ============================================================================
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#include <math.h>

#pragma comment(lib, "version.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "winmm.lib")

static const DWORD BUILD_128F = 7680;

#pragma pack(push, 4)
struct Shared {             // keep in step with engine/GameModule.ahk
    DWORD magic;            // 'TWC1'
    DWORD layout;           // 9
    DWORD build;            // the game's build number (7680 = 1.28f)
    DWORD status;           // 0 starting, 1 running, 2 not 1.28f (idle), 3 stopping
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
    DWORD tmFlags;          // module: 1 cooldowns read, 2 buffs read, 0x100 a game getter was refused (see the log)
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
                            //   4 autocast toggle on the command card slot cmdArg
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
    DWORD hcColours[5];     // companion: 0xAARRGGBB for yours, allies, enemies, neutral hostile, neutral passive
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
};
#pragma pack(pop)

// -- 1.28f addresses ---------------------------------------------------------
// Offsets into the game module (from the WFE study, ahk/unryze-wfe-tools/
// FINDINGS.md). WFE's base is GetModuleHandle("Game.dll"), or the exe when
// there's no Game.dll; 1.28 merged Game.dll into Warcraft III.exe, so on 1.28f
// it's the exe. The same rule is used here (GameBase).
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
    { "widescreen setter",                 0x16f6b0 },
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
    strcpy_s(why, n, "passed");
    return true;
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
    if (!ui)
        return -1;
    if (vt != g_uiVtable) {
        // the getter returned something that isn't the game UI: the addresses
        // are wrong for this game, so stop for good
        g_getUi = nullptr;
        g_shared->probe = 2;
        sprintf_s(g_shared->probeText, "the game UI at %p has vtable %08lX, not +%lX", ui, vt, RVA_UI_VTABLE);
        Log("stopping: %s", g_shared->probeText);
        return -1;
    }
    if (!g_shared->ui) {
        g_shared->ui = 1;
        Log("game UI at %p (vtable checks out); mode %08lX, target mode %08lX", ui, mode, target);
    }
    g_ui = (BYTE *)ui;
    return target && mode == target;
}

// -- calling the game's getters --------------------------------------------------
// Buff and cooldown times come from the game's own timer objects, through
// their getters (as WFE does). These run on this thread, not the game's, so
// only small read-only getters are called: a tiny x86 decoder walks each one
// to its ret first and refuses it if it calls out (other than into another
// such getter), jumps indirectly, or uses an instruction it doesn't know. A
// refused getter is logged with its bytes and never called.
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
                 || o2 == 0xAF || o2 == 0xB6 || o2 == 0xB7 || o2 == 0xBE || o2 == 0xBF || o2 == 0xD6 || o2 == 0xE6)
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

// Walks a getter to its last ret. depth 0 may call (or tail-jump to) getters
// that call nothing themselves.
static bool WalkGetter(const BYTE *f, int depth) {
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
        if (kind == I_CALL && (depth > 0 || !WalkGetter(t, depth + 1)))
            return false;
        if (kind == I_JCC) {
            if (!inside)
                return false;
            if (t > furthest)
                furthest = t;
        }
        if (kind == I_JMP) {
            if (inside) {
                if (t > furthest)
                    furthest = t;
            } else if (depth > 0 || !WalkGetter(t, depth + 1))
                return false;
        }
        p += n;
        // the end: a ret or an unconditional jump, with no branch landing further on
        if ((kind == I_RET || kind == I_JMP) && p > furthest)
            return true;
    }
    return false;
}

// cached verdict per getter; a refused one is logged once with its bytes
static bool SafeGetter(const BYTE *f) {
    static struct { const BYTE *f; bool ok; } seen[32];
    static int n;
    for (int i = 0; i < n; i++)
        if (seen[i].f == f)
            return seen[i].ok;
    bool ok = WalkGetter(f, 0);
    if (n < 32) {
        seen[n].f = f, seen[n].ok = ok, n++;
        if (!ok) {
            Log("timers: refused to call the game getter at +%06lX (not a plain getter):", (DWORD)(f - g_base));
            LogBytes("bytes", f);
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

typedef void(__fastcall *TimeFn)(const void *, int, float *);
typedef int(__fastcall *IntFn)(const void *, int);

static bool Finite(float f) { return f == f && f >= 0 && f < 1e6f; }

// timer->getter(&out): vtable +0x18 the time left, +0x10 the full time (WFE's use)
static float TimerValue(const void *timer, DWORD slot) {
    const BYTE *f = Virtual(timer, slot);
    if (!f)
        return 0;
    float out = 0;
    __try {
        ((TimeFn)f)(timer, 0, &out);
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
        return ((IntFn)f)(obj, 0);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return 0;
    }
}

// -- cooldown and buff timers ----------------------------------------------------
// Read the way WFE's Cooldown UI and BUFFUI do (study_cooldownui.md,
// study_buffs.md): the command card ([ui+0x3c8]) and the buff bar
// ([[[ui+0x3c4]+0x130]+0x16c]) are both grids: rows +0x124, columns +0x128, a
// row table at +0x154 (16 bytes a row: +4 count, +8 the buttons).
static const DWORD ID_AHER = 'AHer', ID_ASID = 'Asid', ID_ASUD = 'Asud', ID_ASEI = 'Asei', ID_AMAI = 'Amai', ID_ASEL = 'Asel';

static BYTE *GridButton(BYTE *bar, int row, int col) {
    BYTE *rows = *(BYTE **)(bar + 0x154);
    if (!rows)
        return nullptr;
    BYTE *r = rows + row * 16;
    if ((DWORD)col >= *(DWORD *)(r + 4) || !*(BYTE **)(r + 8))
        return nullptr;
    return (*(BYTE ***)(r + 8))[col];
}

static void ReadCooldowns(BYTE *ui) {
    BYTE *card = *(BYTE **)(ui + 0x3c8);
    if (!card)
        return;
    int rows = *(int *)(card + 0x124), cols = *(int *)(card + 0x128);
    if (rows <= 0 || cols <= 0 || rows > 3 || cols > 4)
        return;
    for (int r = 0; r < rows; r++)
        for (int c = 0; c < cols; c++) {
            int i = r * 4 + c;
            BYTE *btn = GridButton(card, r, c), *data, *ab;
            if (!btn || !*(DWORD *)(btn + 0x19c) || !(data = *(BYTE **)(btn + 0x190)) || !(ab = *(BYTE **)(data + 0x6d4)))
                continue;
            DWORD id = *(DWORD *)(ab + 0x34), fl = *(DWORD *)(ab + 0x20);
            if (id == ID_AHER || id == ID_ASID || id == ID_ASUD || id == ID_ASEI || id == ID_AMAI || id == ID_ASEL)
                continue;                       // hero skill menu, shops: no cooldown to show
            if (!(fl & 0x200) || (fl & 0x400))
                continue;                       // not cooling down
            g_shared->cdLeft[i] = TimerValue(ab + 0xd0, 0x18);
            g_shared->cdTotal[i] = TimerValue(ab + 0xd0, 0x10);
        }
    g_shared->tmFlags |= 1;
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
            if (!btn || !*(DWORD *)(btn + 0x90) || !*(DWORD *)(btn + 0x94) || !(buff = *(BYTE **)(btn + 0x978)))
                continue;
            bool aura = VirtualInt(buff, 0x1e8) != 0;
            g_shared->buffFlags[i] = aura ? 3 : 1;
            g_shared->buffId[i] = (DWORD)VirtualInt(buff, 0x1c);
            float left = *(int *)(buff + 0x48) > 0 ? *(float *)(buff + 0xac) : TimerValue(buff + 0x84, 0x18);
            left = Finite(left) ? left : 0;
            float total;
            if (aura)
                total = TimerValue(buff + 0x84, 0x10);
            else {
                // WFE picks +0xc0 or +0xc8 by the buff's owner (normal vs hero
                // duration, it seems); without that check: the shorter one that fits
                float a = *(float *)(buff + 0xc0), b = *(float *)(buff + 0xc8);
                a = Finite(a) ? a : 0, b = Finite(b) ? b : 0;
                float lo = a < b ? a : b, hi = a < b ? b : a;
                total = lo >= left && lo > 0 ? lo : hi;
            }
            g_shared->buffLeft[i] = left;
            g_shared->buffTotal[i] = total;
        }
    g_shared->buffCount = rows * cols;
    g_shared->tmFlags |= 2;
}

// both, guarded: a fault keeps what was read before it
static void ReadTimersGuarded(BYTE *ui) {
    __try {
        ReadCooldowns(ui);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
    __try {
        ReadBuffs(ui);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
    }
}

static void ReadTimers() {
    DWORD keep = g_shared->tmFlags & 0x100;
    ZeroMemory(g_shared->cdLeft, (BYTE *)(g_shared->buffId + 16) - (BYTE *)g_shared->cdLeft);
    g_shared->tmFlags = keep;
    if (g_ui)
        ReadTimersGuarded(g_ui);
    InterlockedIncrement(&g_shared->tmSeq);
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
static void BarsPass();
static UINT g_barsMsg;              // "TWC_GameThreadBars": run BarsPass on the game thread
static volatile LONG g_barsQueued;
static void DisplayPass();
static UINT g_dispMsg;              // "TWC_GameThreadDisplay": run DisplayPass on the game thread
static volatile LONG g_dispQueued;
static volatile LONG g_resized;     // the game window changed size: widescreen is set again
static int ToggleMultiboard(BYTE *ui);
static int AutocastToggle(BYTE *ui, DWORD slot);
static void SelfCast();
static UINT g_selfMsg;              // "TWC_GameThreadSelfCast": run SelfCast on the game thread

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
    if (m == WM_SIZE || m == WM_DISPLAYCHANGE)
        InterlockedExchange(&g_resized, 1);
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
    if (now == (LONG_PTR)GameWndProc)   // someone subclassed after us: leave theirs (and ours) in place
        g_wide ? SetWindowLongPtrW(g_gameWnd, GWLP_WNDPROC, (LONG_PTR)g_oldProc) : SetWindowLongPtrA(g_gameWnd, GWLP_WNDPROC, (LONG_PTR)g_oldProc);
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
    return 2;
}

// -- health bar size ----------------------------------------------------------------
// Like WFE's HEALTHBAR HEIGHT (study_healthbar.md), without its hooks or vtable
// swaps: a few times a second, on the game thread, every unit in the game's
// list gets its health bar ([[unit+0x50]+0xc], a CStatBar: vtable +0xaad83c,
// kind [+0x138] = 5) set to the wanted height (+0x5c) and width (+0x58,
// experimental: WFE never writes it), then the game's layout refresh. The
// game's own size is taken from the first bar seen and logged, and put back
// when the feature is turned off.
static const DWORD RVA_UNIT_LIST = 0xd328f0;    // { ?, count +4, units +8 } (WFE's [0x1013a990])
static const DWORD RVA_UNIT_EXTRA = 0xd32900;   // one more unit, [it] (WFE's [0x1013cfac])
static const DWORD RVA_STATBAR_VTABLE = 0xaad83c;
static const DWORD RVA_LAYOUT_REFRESH = 0x13f9b0;   // __fastcall(frame, 0, int 0) (WFE's [0x1013a21c])
static const DWORD UNIT_BARS = 0x50, BARS_HEALTH = 0xc, BAR_KIND = 0x138, BAR_WIDTH = 0x58, BAR_HEIGHT = 0x5c;

typedef void(__fastcall *RefreshFn)(void *, int, int);
static float g_defH, g_defW;            // the game's own bar size (0 = not seen yet)
static bool g_barsApplied;              // something was resized and not put back yet

static bool SaneSize(float f) { return f == f && f > 0.0001f && f < 0.5f; }

// one unit's health bar: 1 resized, 0 nothing to do or not a health bar
static int SizeBar(BYTE *unit, float h, float w) {
    __try {
        BYTE *bars = *(BYTE **)(unit + UNIT_BARS), *bar;
        if (!bars || !(bar = *(BYTE **)(bars + BARS_HEALTH)))
            return 0;
        if (*(DWORD *)bar != (DWORD)(g_base + RVA_STATBAR_VTABLE) || *(DWORD *)(bar + BAR_KIND) != 5)
            return 0;
        float *ph = (float *)(bar + BAR_HEIGHT), *pw = (float *)(bar + BAR_WIDTH);
        if (!g_defH) {
            if (!SaneSize(*ph) || !SaneSize(*pw))
                return 0;
            g_defH = *ph, g_defW = *pw;
            g_shared->hbDefHeight = g_defH, g_shared->hbDefWidth = g_defW;
            Log("health bars: the game's own size is %.5f high, %.5f wide (UI units)", g_defH, g_defW);
        }
        float th = g_defH * h, tw = g_defW * w;
        if (fabsf(*ph - th) < 1e-6f && fabsf(*pw - tw) < 1e-6f)
            return 0;
        *ph = th, *pw = tw;
        ((RefreshFn)(g_base + RVA_LAYOUT_REFRESH))(bar, 0, 0);
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
                int r = SizeBar(units[i], h, w);
                n += r > 0, faults += r < 0;
            }
        BYTE *extra = *(BYTE **)(g_base + RVA_UNIT_EXTRA);
        if (extra && *(BYTE **)extra) {
            int r = SizeBar(*(BYTE **)extra, h, w);
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

// -- health bar colours ---------------------------------------------------------------
// The game repaints a bar's colour on every update of the bar, so the colour
// is set right after the game's own update, as WFE does (study_hpcolours.md).
// WFE gives every bar its own copy of the CStatBar vtable; here the one shared
// entry for the update (vtable +0x74) points at BarUpdateHook while colours are
// on, which calls the game's original first. That's a 4-byte data write in the
// game's vtable, nothing else; it's put back when colours go off or on unload
// (if it's still ours). The hook runs on the game's thread (the game calls it).
static const DWORD STATBAR_UPDATE = 0x74;       // __fastcall Update(bar, 0, unit), ret 4
static const DWORD RVA_PLAYERS = 0xd305e0;      // [[it]] = the game state: local player id word +0x28, players +0x58
static const DWORD RVA_HANDLE_LOOKUP = 0x7e090; // __fastcall obj(id1, id2) (WFE's [0x1013ba2c])
static const DWORD RVA_UNIT_HP = 0x81b30;       // __fastcall(unit + 0x98, 0, float *hp) (WFE's [0x1013ce3c])
static const DWORD BAR_UNIT = 0x154, BAR_FILL = 0x134;      // the bar's unit; its fill (the coloured part)
static const DWORD UNIT_OWNER = 0x58, UNIT_HP = 0x98, UNIT_MAXHP_HANDLE = 0xa0;

typedef void(__fastcall *BarUpdateFn)(void *, int, void *);
typedef void *(__fastcall *LookupFn)(DWORD, DWORD);
typedef void(__fastcall *HpFn)(void *, int, float *);
typedef void(__fastcall *ColourFn)(void *, int);

static BarUpdateFn g_gameBarUpdate;     // the game's own update: set once, never cleared (a call may be in flight)
static bool g_barHooked;

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
    state = state ? *(BYTE **)state : nullptr;
    if (!state || owner < 0 || owner > 15)
        return 0;
    int local = *(short *)(state + 0x28);
    if (local < 0 || local > 15)
        return 0;
    const DWORD *c = g_shared->hcColours;
    return owner == local ? c[0] : owner == 12 ? c[3] : owner == 15 ? c[4] : Allied(state, local, owner) ? c[1] : c[2];
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

static void __fastcall BarUpdateHook(void *bar, int edx, void *unit) {
    g_gameBarUpdate(bar, edx, unit);        // the game's own update, untouched
    if (g_shared->hcOn)
        ColourBar((BYTE *)bar, (BYTE *)unit);
}

// point the shared vtable entry at the hook (on) or back at the game's (off)
static bool SwapBarUpdate(bool on) {
    DWORD *slot = (DWORD *)(g_base + RVA_STATBAR_VTABLE + STATBAR_UPDATE);
    if (on == g_barHooked)
        return true;
    if (!PageIs(slot, READ) || PageIs(slot, EXEC))
        return false;
    DWORD cur = *slot;
    if (on && !g_gameBarUpdate && !IsGameCode((BYTE *)cur)) {
        Log("health bar colours: refused, the bar update entry (%08lX) isn't game code", cur);
        return false;
    }
    if (!on && cur != (DWORD)BarUpdateHook) {
        Log("health bar colours: the bar update entry was changed by someone else: left as it is");
        return false;
    }
    if (on && !g_gameBarUpdate)
        g_gameBarUpdate = (BarUpdateFn)cur;   // before the swap: the hook calls it
    DWORD want = on ? (DWORD)BarUpdateHook : (DWORD)g_gameBarUpdate, old;
    if (!VirtualProtect(slot, 4, PAGE_READWRITE, &old))
        return false;
    InterlockedExchange((volatile LONG *)slot, (LONG)want);
    VirtualProtect(slot, 4, old, &old);
    g_barHooked = on;
    Log(on ? "health bar colours: on (the bar update +%06lX is wrapped)" : "health bar colours: off (the bar update +%06lX is the game's again)",
        (DWORD)g_gameBarUpdate - (DWORD)g_base);
    return true;
}

// the worker's part: follow the companion's switch
static void FollowColours() {
    static bool refused;
    if (!g_getUi || refused)
        return;
    bool on = g_shared->hcOn != 0;
    if (on && !g_barHooked) {
        if (!IsGameCode(g_base + RVA_HANDLE_LOOKUP) || !IsGameCode(g_base + RVA_UNIT_HP) || !SwapBarUpdate(true)) {
            refused = true, g_shared->hcState = 2;
            return;
        }
    } else if (!on && g_barHooked)
        SwapBarUpdate(false);
    g_shared->hcState = g_barHooked ? 1 : 0;
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

// Widescreen: the game's own setter, called the way WFE's SetWidescreen
// (0x100665a0) calls it on 1.28f: __fastcall(obj + (mode == 1 ? 0x754 : 0x59c),
// 0, on, 0), obj = [+0xd1aca8], mode = [+0xcb1d9c]. WFE passes 1 only in a game,
// and also detours the setter so the game's own calls keep it on. Nothing is
// patched here: it's set again when a game starts (and 1 s and 5 s later, in
// case the game sets it itself while loading) and after the window changes size.
static const DWORD RVA_WIDE_SET = 0x16f6b0;     // WFE's [0x1013ce08]
static const DWORD RVA_WIDE_OBJ = 0xd1aca8;     // [it] = the object (WFE's [0x1013ba38])
static const DWORD RVA_WIDE_MODE = 0xcb1d9c;    // [it] = 1 -> +0x754, else +0x59c (WFE's [0x1013ba34])

typedef void(__fastcall *WideFn)(void *, int, int, int);

static void *g_wsUi;            // the game it was last set in (0 = none)
static DWORD g_wsAgain[2];      // GetTickCount() when to set it again (0 = no)
static bool g_wsApplied;        // set on, not put back yet

// 1 set, 0 no object to set, -1 faulted
static int CallWide(int on) {
    __try {
        BYTE *obj = *(BYTE **)(g_base + RVA_WIDE_OBJ);
        if (!obj)
            return 0;
        DWORD vt = *(DWORD *)obj;
        if (!InImage(vt, g_imageSize) || PageIs((void *)vt, EXEC))
            return 0;
        DWORD mode = *(DWORD *)(g_base + RVA_WIDE_MODE);
        DWORD off = mode == 1 ? 0x754 : 0x59c;
        static bool logged;
        if (!logged) {
            logged = true;
            char rtti[64];
            RttiName(vt, g_imageSize, rtti, sizeof(rtti));
            Log("widescreen: object %p (vtable +%06lX, RTTI %s), mode %lu, so +%lX", obj, vt - (DWORD)g_base, rtti[0] ? rtti : "(none)", mode, off);
        }
        ((WideFn)(g_base + RVA_WIDE_SET))(obj + off, 0, on, 0);
        return 1;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return -1;
    }
}

static void WidescreenPass() {
    static bool refused;
    static int faults;
    bool on = g_shared->wsOn != 0;
    if (refused)
        return;
    if (!on && !g_wsApplied) {
        g_shared->wsState = 0;
        return;
    }
    if (!FnStart(RVA_WIDE_SET) || !PageIs(g_base + RVA_WIDE_OBJ, READ) || PageIs(g_base + RVA_WIDE_OBJ, EXEC)
        || !PageIs(g_base + RVA_WIDE_MODE, READ) || PageIs(g_base + RVA_WIDE_MODE, EXEC)) {
        refused = true, g_shared->wsState = 3;
        Log("widescreen: refused (the setter isn't a function start, or its globals aren't data)");
        return;
    }
    void *ui = GameUi();
    DWORD now = GetTickCount();
    int r;
    if (!on) {
        // turned off: back to 4:3 (WFE sets 0 outside a game as well)
        r = CallWide(0);
        Log(r == 1 ? "widescreen: off" : "widescreen: turning it off didn't reach the game (%d)", r);
        g_wsApplied = false, g_wsUi = nullptr, g_shared->wsState = 0;
        return;
    }
    if (!ui) {
        g_wsUi = nullptr, g_shared->wsState = 2;    // between games
        return;
    }
    bool again = InterlockedExchange(&g_resized, 0) != 0;
    if (ui != g_wsUi) {
        g_wsUi = ui, again = true;
        g_wsAgain[0] = (now + 1000) | 1, g_wsAgain[1] = (now + 5000) | 1;
    }
    for (DWORD &t : g_wsAgain)
        if (t && (LONG)(now - t) >= 0)
            t = 0, again = true;
    if (!again)
        return;
    r = CallWide(1);
    if (r < 0 && ++faults >= 3) {
        refused = true, g_shared->wsState = 3;
        Log("widescreen: the game's setter faulted 3 times: stopping");
        return;
    }
    static int logs;
    if (r == 1 && logs < 6)
        logs++, Log("widescreen: set in the game at %p", ui);
    g_wsApplied |= r == 1;
    g_shared->wsState = r == 1 ? 1 : 2;
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

static bool WriteCode(BYTE *p, const BYTE *b, int n) {
    DWORD old;
    if (!VirtualProtect(p, n, PAGE_EXECUTE_READWRITE, &old))
        return false;
    memcpy(p, b, n);
    VirtualProtect(p, n, old, &old);
    FlushInstructionCache(GetCurrentProcess(), p, n);
    return true;
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
        else if (!quiet)
            Log("latency: the %s getter was changed by someone else: left as it is", LATENCY_NAME[i]);
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

// on the game thread
static void DisplayPass() {
    if (!g_getUi)
        return;
    WidescreenPass();
    FpsPass();
    LatencyPass();
}

// the worker's part: a pass 4 times a second while any is on, or has something to put back
static void QueueDisplay() {
    static DWORD at;
    DWORD now = GetTickCount();
    if (!g_getUi || now - at < 250 || (!g_shared->wsOn && !g_wsApplied && !FpsWork() && LatencyWanted() == g_latSet))
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
static const DWORD UI_PORTRAIT = 0x3f4;
static const DWORD RVA_CONTROL_CLICK = 0x1407b0;

typedef int(__fastcall *ClickFn)(void *, int, int);

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
            Sleep(10);
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
static void Run() {
    LONG handled = g_shared->qcSeq;
    DWORD askedAt = 0;
    bool fast = false;
    int clicks = 0;
    DWORD timersAt = 0;
    while (!g_stop) {
        DWORD now = GetTickCount();
        g_shared->heartbeat = now;
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
        if (g_shared->tmWant && now - timersAt >= 100) {
            timersAt = now;                     // 10 a second is plenty for whole seconds
            ReadTimers();
        }
        QueueBars();
        FollowColours();
        QueueDisplay();
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
        g_shared->layout = 9;
        sprintf_s(name, "Local\\TWC_GameQc_%lu", GetCurrentProcessId());
        g_wake = CreateEventA(nullptr, FALSE, FALSE, name);
        Log("---- twc-game.dll loaded into pid %lu", GetCurrentProcessId());
        HANDLE t = CreateThread(nullptr, 0, Worker, nullptr, 0, nullptr);
        if (t)
            CloseHandle(t);
    } else if (reason == DLL_PROCESS_DETACH) {
        g_stop = 1;
        if (!reserved)
            Unsubclass(), SwapBarUpdate(false), FpsPatch(false, true), LatencyRestore(true);  // FreeLibrary, not the game exiting: give back the window, the bar update, the limiter, the latency getters
                                                    // (the frame limit setting and widescreen need the game thread: they stay)
        if (g_shared)
            g_shared->status = 3;
    }
    return TRUE;
}
