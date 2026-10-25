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

#pragma comment(lib, "version.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "winmm.lib")

static const DWORD BUILD_128F = 7680;

#pragma pack(push, 4)
struct Shared {             // keep in step with engine/GameModule.ahk
    DWORD magic;            // 'TWC1'
    DWORD layout;           // 2
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
    { "mana bar draw",                     0x2f10b0 },
    { "message frame clear",               0x144750 },
    { "multiboard display",                0x4127d0 },
    { "widescreen setter",                 0x136660 },
    { "FPS limiter",                       0x07b7aa },
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
    DWORD size = ImageSize(g_base);
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
    return target && mode == target;
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

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID) {
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
        g_shared->layout = 2;
        sprintf_s(name, "Local\\TWC_GameQc_%lu", GetCurrentProcessId());
        g_wake = CreateEventA(nullptr, FALSE, FALSE, name);
        Log("---- twc-game.dll loaded into pid %lu", GetCurrentProcessId());
        HANDLE t = CreateThread(nullptr, 0, Worker, nullptr, 0, nullptr);
        if (t)
            CloseHandle(t);
    } else if (reason == DLL_PROCESS_DETACH) {
        g_stop = 1;
        if (g_shared)
            g_shared->status = 3;
    }
    return TRUE;
}
