// The inventory cover off (layout 46, WFE's ISINVENTORYCOVER unticked), against a fake game
// UI whose point calls really set points: with the Widescreen UI off the cover alone goes off
// the screen (its bottom right corner at x 2.0) on any window, put back when it's turned off;
// with the Widescreen UI on it's the layout's own cover (x 0.55) or off the screen, and the
// Widescreen UI turned off with the cover still off: all put back, then the cover off again.
#include "../twc-game.cpp"
#include "check.h"
static DWORD mainTid; static BYTE *img; static HWND wnd; static void *fakeUi;
static void *__fastcall FakeGetUi(int, int) { return fakeUi; }
static BYTE pts[64][0x20]; static int nPts;
static BYTE *NewPoint(DWORD vt) { BYTE *p = pts[nPts++ % 64]; memset(p, 0, 0x20); *(DWORD *)p = (DWORD)(img + vt); return p; }
static void __fastcall FSetPoint(BYTE *lay, int, DWORD pt, DWORD rel, DWORD rp, float x, float y, DWORD) {
    BYTE *p = NewPoint(RVA_REL_POINT_VT); *(DWORD *)(p + 4) = rel; p[8] = (BYTE)rp; *(float *)(p + 0xc) = x; *(float *)(p + 0x10) = y;
    *(BYTE **)(lay + LAYOUT_POINTS + pt * 4) = p;
}
static void __fastcall FSetAbs(BYTE *lay, int, DWORD pt, float x, float y, DWORD) {
    BYTE *p = NewPoint(RVA_ABS_POINT_VT); *(float *)(p + 4) = x; *(float *)(p + 8) = y;
    *(BYTE **)(lay + LAYOUT_POINTS + pt * 4) = p;
}
static void __fastcall FClear(BYTE *lay, int, DWORD) { memset(lay + LAYOUT_POINTS, 0, 9 * 4); }
static void __fastcall FRefresh(BYTE *, int, DWORD) {}
static void Stub(DWORD rva, void *to) { BYTE *p = img + rva; p[-1] = 0xCC; p[0] = 0xE9; *(LONG *)(p + 1) = (LONG)((BYTE *)to - (p + 5)); }
static BYTE ui[0x500], info[0x200], cover[0x200], top[0x20], anchor[0x20];
static void Pump(int n) { for (int k = 0; k < n; k++) { QueueDisplay(); Sleep(300); } }
template <class F> static void PumpUntil(F done, int ms) { for (DWORD t0 = GetTickCount(); !done() && GetTickCount() - t0 < (DWORD)ms; ) Pump(1); }
static BYTE *Pt(int i) { return *(BYTE **)(cover + LAYOUT_POINTS + i * 4); }
static bool AbsAt(int i, float x) { BYTE *p = Pt(i); return p && *(DWORD *)p == (DWORD)(img + RVA_ABS_POINT_VT) && *(float *)(p + 4) == x; }
static bool Original() { BYTE *p = Pt(0); return p && *(DWORD *)p == (DWORD)(img + RVA_REL_POINT_VT) && *(BYTE **)(p + 4) == anchor && !Pt(8) && *(float *)(cover + 0x58) == 0.12f; }
static DWORD WINAPI Tester(void *) {
    SetWindowPos(wnd, 0, 0, 0, 400, 300, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);     // 4:3: the Widescreen UI would wait
    g_shared->icOn = 1;
    PumpUntil([] { return g_shared->icState == 1; }, 10000);
    CHECK(g_shared->icState == 1 && AbsAt(8, 2.0f) && !Pt(0) && g_ulN == 1 && g_shared->ulState == 0, "cover off, Widescreen UI off, 4:3: its corner at x 2.0, its own point cleared (state %lu, %d saved)", g_shared->icState, g_ulN);
    Pt(8) && (*(float *)(Pt(8) + 4) = 0.3f);                                              // the game moves it back
    PumpUntil([] { return AbsAt(8, 2.0f); }, 5000);
    CHECK(AbsAt(8, 2.0f) && g_ulN == 1, "moved back by the game: off the screen again, saved once");
    g_shared->icOn = 0;
    PumpUntil([] { return g_ulN == 0; }, 5000);
    CHECK(g_ulN == 0 && g_shared->icState == 0 && Original(), "turned off: its own point and width back, state 0");
    // with the Widescreen UI, a wide window
    SetWindowPos(wnd, 0, 0, 0, 800, 330, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
    g_shared->ulOn = 1;
    PumpUntil([] { return g_shared->ulState == 1 && g_ulStage == UL_GROUP_COUNT; }, 20000);
    CHECK(AbsAt(8, 0.55f) && *(float *)(cover + 0x58) == 0.095f, "Widescreen UI: the layout's cover (x 0.55, 0.095 wide)");
    g_shared->icOn = 1;
    PumpUntil([] { return AbsAt(8, 2.0f) && g_shared->icState == 1; }, 5000);
    CHECK(AbsAt(8, 2.0f) && g_shared->icState == 1 && g_shared->ulState == 1, "and the cover off: off the screen, the layout stays");
    g_shared->icOn = 0;
    PumpUntil([] { return AbsAt(8, 0.55f); }, 5000);
    CHECK(AbsAt(8, 0.55f) && g_shared->icState == 0, "cover back on: the layout's place again");
    g_shared->icOn = 1;
    PumpUntil([] { return AbsAt(8, 2.0f); }, 5000);
    g_shared->ulOn = 0;
    bool wasBack = false;
    PumpUntil([&] { wasBack |= Original(); return wasBack && AbsAt(8, 2.0f) && g_ulN == 1; }, 10000);
    CHECK(wasBack && AbsAt(8, 2.0f) && g_ulN == 1 && *(float *)(cover + 0x58) == 0.12f, "Widescreen UI off, cover still off: all put back, then only the cover off again (%d saved)", g_ulN);
    g_shared->icOn = 0;
    PumpUntil([] { return g_ulN == 0; }, 5000);
    CHECK(Original(), "and off: as the game had it");
    Verdict();
    PostThreadMessageA(mainTid, WM_QUIT, 0, 0);
    return 0;
}
int main() {
    strcpy_s(g_logPath, "cover.log"); DeleteFileA("cover.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_SET_POINT, FSetPoint); Stub(RVA_SET_ABS_POINT, FSetAbs); Stub(RVA_CLEAR_POINTS, FClear); Stub(RVA_LAYOUT_REFRESH, FRefresh);
    DWORD old; VirtualProtect(img + 0xa7c000, 0x2000, PAGE_READWRITE, &old); VirtualProtect(img + 0xaa0000, 0x20000, PAGE_READWRITE, &old);
    g_uiVtable = (DWORD)(img + RVA_UI_VTABLE); *(DWORD *)ui = g_uiVtable;
    *(DWORD *)top = (DWORD)(img + RVA_SIMPLE_TOP_VT);
    *(DWORD *)info = (DWORD)(img + 0xab0f00);
    *(DWORD *)cover = (DWORD)(img + 0xab0f08); *(BYTE **)(cover + 0x68) = top; *(float *)(cover + 0x58) = 0.12f;      // a simple frame
    FSetPoint(cover, 0, 0, (DWORD)anchor, 0, 0.01f, 0.02f, 1);                            // its own point 0
    *(BYTE **)(ui + 0x3c4) = info; *(BYTE **)(info + 0x14c) = cover;
    fakeUi = ui; g_getUi = FakeGetUi;
    mainTid = GetCurrentThreadId();
    WNDCLASSA wc = {}; wc.lpfnWndProc = DefWindowProcA; wc.lpszClassName = "Warcraft III"; wc.hInstance = GetModuleHandleA(0);
    RegisterClassA(&wc);
    wnd = CreateWindowA("Warcraft III", "Warcraft III", WS_OVERLAPPEDWINDOW, 0, 0, 400, 300, 0, 0, wc.hInstance, 0);
    ShowWindow(wnd, SW_SHOWNOACTIVATE);
    CreateThread(0, 0, Tester, 0, 0, 0);
    MSG m; while (GetMessageA(&m, 0, 0, 0) > 0) { TranslateMessage(&m); DispatchMessageA(&m); }
    Unsubclass(); DestroyWindow(wnd);
    return g_fails;
}
