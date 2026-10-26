// harness: widescreen, FPS unlock and the multiboard toggle against a fake game image
#include "../twc-game.cpp"
#include "check.h"
#include <stddef.h>
static_assert(offsetof(Shared, wsOn) == 612 && offsetof(Shared, fpsGameLimit) == 632 && sizeof(Shared) >= 684, "layout 7");
static DWORD mainTid, gameTid; static void *fakeUi; static BYTE *img;
static void *__fastcall FakeGetUi(int, int) { return fakeUi; }
static int projCalls; static float projAspect;
static void __fastcall FakeProj(float *m, int, float, float a, float, float) { projCalls++, projAspect = a; m[0] = 2, m[5] = 3; }
static DWORD opt17 = 64; static int optSets, optApplies; static BYTE optObj[64];
static void *__cdecl FakeOpts() { return optObj; }
static void __fastcall FakeSet(void *o, int, DWORD id, DWORD v) { if (o == optObj && id == 0x17) opt17 = v, optSets++; }
static void __fastcall FakeApply(void *o, int, DWORD id) { if (o == optObj && id == 0x17) optApplies++; }
static void __fastcall FakeGet(void *o, int, DWORD id, DWORD *out) { if (o == optObj && id == 0x17) *out = opt17; }
static BYTE *mb; static int mbCalls0, mbCalls1;
static void __fastcall FakeMb0(void *b, int) { mbCalls0++; *(DWORD *)((BYTE *)b + MB_STATE) = 0; }
static void __fastcall FakeMb1(void *b, int) { mbCalls1++; *(DWORD *)((BYTE *)b + MB_STATE) = 1; }
static void Stub(DWORD rva, void *to) {
    BYTE *p = img + rva; p[-1] = 0xCC; p[0] = 0xE9; *(LONG *)(p + 1) = (LONG)((BYTE *)to - (p + 5));
}
static void Pump(int n) { for (int k = 0; k < n; k++) { QueueDisplay(); Sleep(260); } }
static HWND wnd;
static int Cmd(LONG seq) { g_shared->cmd = 3; g_shared->cmdSeq = seq; ServeCommand(seq); return (int)g_shared->cmdResult; }
static DWORD WINAPI Tester(void *) {
    // nothing on: no passes, nothing called
    Pump(3);
    CHECK(projCalls == 0 && *(img + RVA_FPS_BYTE) == 0x74 && !g_oldProc, "all off: nothing called, nothing patched, no subclass");
    // widescreen on: the camera's call to the projection goes to ProjHook, which squeezes m[0] by 0.75 * w / h
    BYTE *site = img + RVA_PROJECTION_CALL;
    g_shared->wsOn = 1; Pump(2);
    RECT r; GetClientRect(wnd, &r); float k = 0.75f * r.right / r.bottom;
    CHECK(SiteTarget(site) == (BYTE *)ProjHook && g_shared->wsState == 1 && fabsf(g_wsK - k) < 1e-5f, "on: the call points at the hook, k %.3f (window %ldx%ld)", g_wsK, r.right, r.bottom);
    float m[16] = {}; ProjHook(m, 0, 1.0f, 0.75f, 1, 100);
    CHECK(projCalls == 1 && projAspect == 0.75f && fabsf(m[0] - 2 / k) < 1e-5f && m[5] == 3, "the game's projection runs, then m[0] / k (%.3f), m[5] left (%.1f)", m[0], m[5]);
    float m2[16] = {}; ProjHook(m2, 0, 1.0f, (float)r.bottom / r.right, 1, 100);
    CHECK(m2[0] == 2, "a viewport already the window's shape (the game's own widescreen): m[0] left (%.3f)", m2[0]);
    SetWindowPos(wnd, 0, 0, 0, 800, 300, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE); Pump(2);
    GetClientRect(wnd, &r);
    CHECK(fabsf(g_wsK - 0.75f * r.right / r.bottom) < 1e-5f, "the window resized: k follows (%.3f)", g_wsK);
    g_shared->wsOn = 0; Pump(2);
    CHECK(SiteTarget(site) == img + RVA_PROJECTION && g_wsK == 0 && g_shared->wsState == 0, "off: the call is the game's again");
    *(site + 1) ^= 0x55; g_shared->wsOn = 1; Pump(2);
    CHECK(g_shared->wsState == 3 && site[0] == 0xE8, "a call that isn't the game's: refused, left alone");
    *(site + 1) ^= 0x55; g_shared->wsOn = 0;
    static BYTE ui[0x400]; *(DWORD *)ui = g_uiVtable; *(BYTE **)(ui + UI_MULTIBOARD) = mb; fakeUi = ui;      // a game, for the multiboard
    // FPS on at 240
    g_shared->fpsOn = 1; g_shared->fpsLimit = 240; Pump(2);
    CHECK(*(img + RVA_FPS_BYTE) == 0xC9 && opt17 == 240 && optApplies == 1 && g_shared->fpsState == 1 && g_shared->fpsGameLimit == 64,
        "FPS on: byte C9, option 0x17 = %lu, applied %d, game's own %lu, state %lu", opt17, optApplies, g_shared->fpsGameLimit, g_shared->fpsState);
    Pump(3);
    CHECK(optSets == 1, "no more sets while nothing changes (%d)", optSets);
    g_shared->fpsLimit = 30; Pump(2);
    CHECK(opt17 == 64, "limit 30: floored at 64 (%lu)", opt17);
    g_shared->fpsOn = 0; Pump(2);
    CHECK(*(img + RVA_FPS_BYTE) == 0x74 && opt17 == 64 && g_shared->fpsState == 0, "FPS off: byte %02X again, option %lu", *(img + RVA_FPS_BYTE), opt17);
    // set the option to 100 as the "game's own", on and off again: put back to the first read (64)
    g_shared->fpsOn = 1; g_shared->fpsLimit = 500; Pump(2);
    CHECK(opt17 == 500 && *(img + RVA_FPS_BYTE) == 0xC9, "FPS on again at 500");
    // something else changes the byte: off leaves it
    *(img + RVA_FPS_BYTE) = 0x90; g_shared->fpsOn = 0; Pump(2);
    CHECK(*(img + RVA_FPS_BYTE) == 0x90 && opt17 == 64, "byte changed by someone else: left (%02X), option back %lu", *(img + RVA_FPS_BYTE), opt17);
    *(img + RVA_FPS_BYTE) = 0x74;
    // multiboard toggle: state 0 -> fn 1, then fn 0
    int r1 = Cmd(1), r2 = Cmd(2);
    CHECK(r1 == 1 && r2 == 1 && mbCalls1 == 1 && mbCalls0 == 1, "multiboard: toggled twice (results %d %d, fn1 %d, fn0 %d)", r1, r2, mbCalls1, mbCalls0);
    fakeUi = nullptr;
    int r3 = Cmd(3);
    CHECK(r3 == 2, "multiboard outside a game: refused (%d)", r3);
    // unload path: patched byte is put back
    g_shared->fpsOn = 1; fakeUi = ui; Pump(2);
    FpsPatch(false, true);
    CHECK(*(img + RVA_FPS_BYTE) == 0x74, "unload: limiter byte put back");
    Verdict();
    PostThreadMessageA(mainTid, WM_QUIT, 0, 0);
    return 0;
}
int main() {
    strcpy_s(g_logPath, "display.log"); DeleteFileA("display.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_PROJECTION, FakeProj);
    img[RVA_PROJECTION_CALL] = 0xE8; *(LONG *)(img + RVA_PROJECTION_CALL + 1) = (LONG)(RVA_PROJECTION - (RVA_PROJECTION_CALL + 5));
    Stub(RVA_OPTIONS, FakeOpts); Stub(RVA_OPT_SET, FakeSet); Stub(RVA_OPT_APPLY, FakeApply); Stub(RVA_OPT_GET, FakeGet);
    Stub(RVA_MB_STATE0, FakeMb0); Stub(RVA_MB_STATE1, FakeMb1);
    img[RVA_FPS_FN - 1] = 0xCC; img[RVA_FPS_FN] = 0x55; img[RVA_FPS_BYTE] = 0x74;
    memset(img + RVA_MSG_CLEAR - 1, 0xCC, 1); img[RVA_MSG_CLEAR] = 0xC3;
    DWORD old;
    VirtualProtect(img + 0xaaa000, 0x4000, PAGE_READWRITE, &old);       // vtables: data
    VirtualProtect(img + 0xcb1000, 0x1000, PAGE_READWRITE, &old);
    VirtualProtect(img + 0xd1a000, 0x1000, PAGE_READWRITE, &old);
    static BYTE board[0x200]; *(DWORD *)board = (DWORD)(img + 0xaac000); mb = board;
    g_uiVtable = (DWORD)(img + RVA_UI_VTABLE); g_getUi = FakeGetUi;
    mainTid = gameTid = GetCurrentThreadId();
    WNDCLASSA wc = {}; wc.lpfnWndProc = DefWindowProcA; wc.lpszClassName = "Warcraft III"; wc.hInstance = GetModuleHandleA(0);
    RegisterClassA(&wc);
    wnd = CreateWindowA("Warcraft III", "Warcraft III", WS_OVERLAPPEDWINDOW, 0, 0, 200, 100, 0, 0, wc.hInstance, 0);
    ShowWindow(wnd, SW_SHOWNOACTIVATE);
    CreateThread(0, 0, Tester, 0, 0, 0);
    MSG m; while (GetMessageA(&m, 0, 0, 0) > 0) { TranslateMessage(&m); DispatchMessageA(&m); }
    Unsubclass(); DestroyWindow(wnd);
    return g_fails;
}
