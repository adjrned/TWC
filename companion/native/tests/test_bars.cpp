#include "../twc-game.cpp"
#include "check.h"
static DWORD mainTid; static void *fakeUi;
static void *__fastcall FakeGetUi(int, int) { return fakeUi; }
static BYTE units[4][0x60], holders[4][0x10], bars[4][0x140];
static float H(int i) { return *(float *)(bars[i] + BAR_HEIGHT); }
static float Wd(int i) { return *(float *)(bars[i] + BAR_WIDTH); }
static DWORD WINAPI Tester(void *) {
    g_shared->hbOn = 1; g_shared->hbHeight = 2.0f; g_shared->hbWidth = 1.5f;
    for (int k = 0; k < 6; k++) { QueueBars(); Sleep(300); }
    CHECK(fabsf(H(0) - 0.008f) < 1e-6f && fabsf(Wd(0) - 0.05f) < 1e-6f && fabsf(H(1) - 0.008f) < 1e-6f && fabsf(H(2) - 0.004f) < 1e-6f
        && g_shared->hbState == 1 && fabsf(g_shared->hbDefHeight - 0.004f) < 1e-6f && *(DWORD *)(g_base + 0x200000 - 16) == 3,
        "on x2 / x1.5: bars %.4f x %.4f and %.4f (the width is the game's bar work's), the mana bar left (%.4f), state %lu, refreshes %lu", H(0), Wd(0), H(1), H(2), g_shared->hbState, *(DWORD *)(g_base + 0x200000 - 16));
    CHECK(fabsf(H(3) - 0.008f) < 1e-6f && fabsf(Wd(3) - 0.06f) < 1e-6f, "the extra unit [+0xd32900] (the unit itself, one deref) is resized too: %.4f x %.4f", H(3), Wd(3));
    g_shared->hbOn = 0;
    for (int k = 0; k < 4; k++) { QueueBars(); Sleep(300); }
    CHECK(fabsf(H(0) - 0.004f) < 1e-6f && fabsf(Wd(0) - 0.05f) < 1e-6f && fabsf(H(1) - 0.004f) < 1e-6f && fabsf(H(3) - 0.004f) < 1e-6f && *(DWORD *)(g_base + 0x200000 - 16) == 6,
        "off: put back (%.4f x %.4f), refreshes %lu", H(0), Wd(0), *(DWORD *)(g_base + 0x200000 - 16));
    // sized only by the bar's own update (BarAfter), no pass resizing anything: still put back when turned off
    g_shared->hbOn = 1; g_barsApplied = false;
    SizeThisBar(bars[0], 2, 1, false), SizeThisBar(bars[1], 2, 1, false);
    g_shared->hbOn = 0;
    for (int k = 0; k < 3; k++) { QueueBars(); Sleep(300); }
    CHECK(fabsf(H(0) - 0.004f) < 1e-6f && fabsf(H(1) - 0.004f) < 1e-6f, "sized in the bar's update only, then off: put back too (%.4f, %.4f)", H(0), H(1));
    Verdict();
    PostThreadMessageA(mainTid, WM_QUIT, 0, 0);
    return 0;
}
int main() {
    strcpy_s(g_logPath, "bars.log"); DeleteFileA("bars.log");
    static Shared sh; g_shared = &sh;
    BYTE *img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    // the layout refresh: inc dword [img+0x200000-16]; ret 4
    BYTE fn[] = { 0xFF, 0x05, 0, 0, 0, 0, 0xC2, 0x04, 0x00 }; *(DWORD *)(fn + 2) = (DWORD)(img + 0x200000 - 16);
    memcpy(img + RVA_LAYOUT_REFRESH, fn, sizeof(fn));
    DWORD old; VirtualProtect(img + 0xaad000, 0x1000, PAGE_READWRITE, &old);
    VirtualProtect(img + 0xd32000, 0x1000, PAGE_READWRITE, &old);
    static BYTE ui[0x400]; *(DWORD *)ui = (DWORD)(img + RVA_UI_VTABLE); g_uiVtable = (DWORD)(img + RVA_UI_VTABLE);
    fakeUi = ui; g_getUi = FakeGetUi;
    static BYTE *list[3];
    for (int i = 0; i < 4; i++) {
        *(BYTE **)(units[i] + UNIT_BARS) = holders[i]; *(BYTE **)(holders[i] + BARS_HEALTH) = bars[i];
        *(DWORD *)bars[i] = (DWORD)(img + RVA_STATBAR_VTABLE);
        *(DWORD *)(bars[i] + BAR_KIND) = i == 2 ? 4 : 5;            // bar 2: not a health bar
        *(float *)(bars[i] + BAR_HEIGHT) = 0.004f; *(float *)(bars[i] + BAR_WIDTH) = i == 3 ? 0.06f : 0.05f;
        if (i < 3)
            list[i] = units[i];
    }
    *(BYTE **)(img + RVA_UNIT_EXTRA) = units[3];        // [it] is the unit (the game's own read)
    *(DWORD *)(img + RVA_UNIT_LIST + 4) = 3; *(BYTE ***)(img + RVA_UNIT_LIST + 8) = list;
    mainTid = GetCurrentThreadId();
    WNDCLASSA wc = {}; wc.lpfnWndProc = DefWindowProcA; wc.lpszClassName = "Warcraft III"; wc.hInstance = GetModuleHandleA(0);
    RegisterClassA(&wc);
    HWND w = CreateWindowA("Warcraft III", "Warcraft III", WS_OVERLAPPEDWINDOW, 0, 0, 200, 100, 0, 0, wc.hInstance, 0);
    ShowWindow(w, SW_SHOWNOACTIVATE);
    CreateThread(0, 0, Tester, 0, 0, 0);
    MSG m; while (GetMessageA(&m, 0, 0, 0) > 0) { TranslateMessage(&m); DispatchMessageA(&m); }
    Unsubclass(); DestroyWindow(w);
    return g_fails;
}
