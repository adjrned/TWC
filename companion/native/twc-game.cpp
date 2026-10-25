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
//  No hooks and no writes into the game: it only reads the game UI (through
//  the game's own getter) and clicks with SendInput, as WFE does.
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
    DWORD layout;           // 5
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
    DWORD cmd;              // companion: 1 clear messages, 2 clear chat
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
    { "multiboard display",                0x4127d0 },
    { "widescreen setter",                 0x16f6b0 },
    { "FPS limiter",                       0x0a50ba },
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

static LRESULT CALLBACK GameWndProc(HWND w, UINT m, WPARAM wp, LPARAM lp) {
    if (m == g_barsMsg && g_barsMsg) {
        InterlockedExchange(&g_barsQueued, 0);
        BarsPass();
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

// a frame the game UI holds, if it looks like a message frame
static BYTE *MessageFrame(BYTE *ui, DWORD off) {
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

// on the game thread: 1 done, 2 refused
static int RunOnGameThread(DWORD cmd) {
    if (!g_getUi || !IsGameCode(g_base + RVA_MSG_CLEAR))
        return 2;
    void *ui = nullptr;
    __try {
        ui = g_getUi(0, 0);
        if (ui && *(DWORD *)ui != g_uiVtable)
            ui = nullptr;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        ui = nullptr;
    }
    if (!ui)
        return 2;                       // not in a game
    if (cmd == 1 || cmd == 2) {
        BYTE *f = MessageFrame((BYTE *)ui, cmd == 1 ? UI_MESSAGES : UI_CHAT);
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
        if (g_shared->tmWant && now - timersAt >= 100) {
            timersAt = now;                     // 10 a second is plenty for whole seconds
            ReadTimers();
        }
        QueueBars();
        LONG cseq = g_shared->cmdSeq;
        if (cseq != g_shared->cmdDone)
            ServeCommand(cseq);
        if (asked) {
            DWORD result = 0;
            if (t == 1 && GameInFront()) {
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
        g_shared->layout = 5;
        sprintf_s(name, "Local\\TWC_GameQc_%lu", GetCurrentProcessId());
        g_wake = CreateEventA(nullptr, FALSE, FALSE, name);
        Log("---- twc-game.dll loaded into pid %lu", GetCurrentProcessId());
        HANDLE t = CreateThread(nullptr, 0, Worker, nullptr, 0, nullptr);
        if (t)
            CloseHandle(t);
    } else if (reason == DLL_PROCESS_DETACH) {
        g_stop = 1;
        if (!reserved)
            Unsubclass();               // FreeLibrary, not the game exiting: give the window back
        if (g_shared)
            g_shared->status = 3;
    }
    return TRUE;
}
