// ============================================================================
//  twc-game.dll - the TW Companion's in-game module for Warcraft III 1.28f.
//  Loaded into the game by twc-inject.exe when Settings > Game module is on.
//  It does nothing unless the game is exactly 1.28f (build 7680): every
//  address it uses belongs to that build.
//
//  It talks to the companion through shared memory "Local\TWC_Game_<pid>"
//  (the layout is Shared below; engine/GameModule.ahk reads it): a heartbeat,
//  the game build, and live game state such as "waiting for a target".
//  It logs to twc-game.log next to this DLL.
//
//  Build: native\build.bat (32-bit, MSVC).
// ============================================================================
#include <windows.h>
#include <stdio.h>
#include <stdarg.h>

#pragma comment(lib, "version.lib")

static const DWORD BUILD_128F = 7680;

#pragma pack(push, 4)
struct Shared {             // keep in step with engine/GameModule.ahk
    DWORD magic;            // 'TWC1'
    DWORD layout;           // 1
    DWORD build;            // the game's build number (7680 = 1.28f)
    DWORD status;           // 0 starting, 1 running, 2 not 1.28f (idle), 3 stopping
    DWORD heartbeat;        // GetTickCount() at the last update
    DWORD targeting;        // 1 while the game waits for a target (not read yet: 0)
};
#pragma pack(pop)

// The 1.28f functions the features will use, as offsets into the game module
// (from the WFE study, ahk/unryze-wfe-tools/FINDINGS.md). Not called yet: the
// first build only checks that each one starts like code, and in which module.
struct Known { const char *name; DWORD rva; };
static const Known KNOWN[] = {
    { "game UI getter (targeting check)", 0x3a0b70 },
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

static HMODULE g_self;
static HANDLE g_map;
static Shared *g_shared;
static volatile LONG g_stop;
static char g_logPath[MAX_PATH];

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

// bytes at a module offset, if that memory is readable code ("" if not)
static void Bytes(HMODULE mod, DWORD rva, char *out, size_t n) {
    out[0] = 0;
    BYTE *p = (BYTE *)mod + rva;
    MEMORY_BASIC_INFORMATION mi;
    if (!VirtualQuery(p, &mi, sizeof(mi)) || mi.State != MEM_COMMIT
        || !(mi.Protect & (PAGE_EXECUTE | PAGE_EXECUTE_READ | PAGE_EXECUTE_READWRITE | PAGE_EXECUTE_WRITECOPY)))
        return;
    size_t o = 0;
    for (int i = 0; i < 8 && o + 4 < n; i++)
        o += sprintf_s(out + o, n - o, "%02X ", p[i]);
}

// Which module the offsets belong to, and what's there: logged, nothing called
static void Probe() {
    HMODULE exe = GetModuleHandleA(nullptr), game = GetModuleHandleA("Game.dll");
    Log("modules: Warcraft III.exe at %p, Game.dll at %p", exe, game);
    for (const Known &k : KNOWN) {
        char a[64], b[64];
        Bytes(exe, k.rva, a, sizeof(a));
        if (game)
            Bytes(game, k.rva, b, sizeof(b));
        else
            b[0] = 0;
        Log("  %-34s +%06lX  exe: %-26s Game.dll: %s", k.name, k.rva, a[0] ? a : "(not code)", game ? (b[0] ? b : "(not code)") : "(none)");
    }
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
    Log("1.28f found: running");
    Probe();
    while (!g_stop) {
        g_shared->heartbeat = GetTickCount();
        Sleep(5);
    }
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
        g_shared->layout = 1;
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
