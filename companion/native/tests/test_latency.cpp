// harness: the latency getters' patch against a fake game image with real x86 getters
#include "../twc-game.cpp"
#include "check.h"
#include <stddef.h>
static_assert(offsetof(Shared, latOn) == 652 && offsetof(Shared, latGame) == 664 && sizeof(Shared) >= 684, "layout 9");
static DWORD mainTid; static BYTE *img; static DWORD lanVal = 100;
static void *__fastcall FakeGetUi(int, int) { return nullptr; }
static int Get(int i) { return ((LatencyFn)(img + RVA_LATENCY[i]))(); }
static void Pump(int n) { for (int k = 0; k < n; k++) { QueueDisplay(); Sleep(260); } }
static DWORD WINAPI Tester(void *) {
    Pump(2);
    CHECK(Get(0) == 100 && Get(1) == 0 && Get(2) == 250 && !g_oldProc, "off: the game's own (100, 0, 250), nothing queued");
    g_shared->latOn = 1; g_shared->latMs = 50; Pump(2);
    CHECK(Get(0) == 50 && Get(1) == 50 && Get(2) == 50 && g_shared->latState == 1, "on 50: all three return 50 (state %lu)", g_shared->latState);
    CHECK(g_shared->latGame[0] == 100 && g_shared->latGame[1] == 0 && g_shared->latGame[2] == 250, "the game's own values logged: %lu %lu %lu", g_shared->latGame[0], g_shared->latGame[1], g_shared->latGame[2]);
    g_shared->latMs = 2; Pump(2);
    CHECK(Get(0) == 5, "2 ms: at least 5 (%d)", Get(0));
    g_shared->latOn = 0; Pump(2);
    lanVal = 120;
    CHECK(Get(0) == 120 && Get(1) == 0 && Get(2) == 250 && g_shared->latState == 0, "off: the originals again (reads the live global: %d)", Get(0));
    g_shared->latOn = 1; g_shared->latMs = 75; Pump(2);
    LatencyRestore(true);
    CHECK(Get(0) == 120 && Get(2) == 250, "unload: put back");
    Verdict();
    PostThreadMessageA(mainTid, WM_QUIT, 0, 0);
    return 0;
}
int main(int argc, char **argv) {
    strcpy_s(g_logPath, "latency.log"); DeleteFileA("latency.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    memset(img + 0x924000, 0xCC, 0x6000);
    BYTE *g0 = img + RVA_LATENCY[0]; g0[0] = 0xA1; *(DWORD **)(g0 + 1) = &lanVal; g0[5] = 0xC3;   // mov eax, [lanVal]; ret
    BYTE *g1 = img + RVA_LATENCY[1]; g1[0] = 0x33; g1[1] = 0xC0; g1[2] = 0xC3;                     // xor eax, eax; ret (short, padding after)
    BYTE *g2 = img + RVA_LATENCY[2]; g2[0] = 0xB8; *(DWORD *)(g2 + 1) = 250; g2[5] = 0xC3;          // mov eax, 250; ret
    if (argc > 1) {     // refusal case: a getter that calls out
        g1[0] = 0xE8; *(LONG *)(g1 + 1) = 0x10; g1[5] = 0xC3;
    }
    g_uiVtable = (DWORD)(img + RVA_UI_VTABLE); g_getUi = FakeGetUi;
    mainTid = GetCurrentThreadId();
    WNDCLASSA wc = {}; wc.lpfnWndProc = DefWindowProcA; wc.lpszClassName = "Warcraft III"; wc.hInstance = GetModuleHandleA(0);
    RegisterClassA(&wc);
    HWND w = CreateWindowA("Warcraft III", "Warcraft III", WS_OVERLAPPEDWINDOW, 0, 0, 200, 100, 0, 0, wc.hInstance, 0);
    ShowWindow(w, SW_SHOWNOACTIVATE);
    if (argc > 1) {
        g_shared->latOn = 1; g_shared->latMs = 50;
        for (int k = 0; k < 3; k++) { QueueDisplay(); Sleep(260); MSG m; while (PeekMessageA(&m, 0, 0, 0, PM_REMOVE)) DispatchMessageA(&m); }
        CHECK(g_shared->latState == 3 && Get(0) == 100, "refusal (a getter that calls out): state %lu, LAN still %d", g_shared->latState, Get(0));
        Verdict();
        Unsubclass(); return g_fails;
    }
    CreateThread(0, 0, Tester, 0, 0, 0);
    MSG m; while (GetMessageA(&m, 0, 0, 0) > 0) { TranslateMessage(&m); DispatchMessageA(&m); }
    Unsubclass(); DestroyWindow(w);
    return g_fails;
}
