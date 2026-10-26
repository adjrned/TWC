// WFE's widescreen UI layout (layout 14), against a fake game UI: frames are
// saved before their first change (anchors, width, height), moved with the
// game's point calls on the game thread, and put back exactly when it's
// turned off or the window isn't wide; a CFrame's layout part is +0xb4.
#include "../twc-game.cpp"
#include "check.h"
static DWORD mainTid; static BYTE *img; static HWND wnd; static void *fakeUi;
static void *__fastcall FakeGetUi(int, int) { return fakeUi; }
struct Call { int kind; BYTE *lay; DWORD pt, rel, relPt; float x, y; } calls[512]; static int nCalls, refreshes, clears;
static void __fastcall FSetPoint(BYTE *lay, int, DWORD pt, DWORD rel, DWORD rp, float x, float y, DWORD) { if (nCalls < 512) calls[nCalls++] = { 2, lay, pt, rel, rp, x, y }; }
static void __fastcall FSetAbs(BYTE *lay, int, DWORD pt, float x, float y, DWORD) { if (nCalls < 512) calls[nCalls++] = { 1, lay, pt, 0, 0, x, y }; }
static void __fastcall FClear(BYTE *, int, DWORD) { clears++; }
static void __fastcall FRefresh(BYTE *, int, DWORD) { refreshes++; }
static int mmCalls; static void __fastcall FMinimap(BYTE *, int) { mmCalls++; }
static void Stub(DWORD rva, void *to) { BYTE *p = img + rva; p[-1] = 0xCC; p[0] = 0xE9; *(LONG *)(p + 1) = (LONG)((BYTE *)to - (p + 5)); }
static const Call *Find(BYTE *lay, DWORD pt) { for (int i = nCalls - 1; i >= 0; i--) if (calls[i].lay == lay && calls[i].pt == pt) return &calls[i]; return nullptr; }
static BYTE ui[0x500], minimap[0x200], peon[0x200], relPt[0x20], anchorFrame[0x20];
static void Pump(int n) { for (int k = 0; k < n; k++) { QueueDisplay(); Sleep(300); } }
static DWORD WINAPI Tester(void *) {
    g_shared->ulOn = 1; Pump(2);
    CHECK(g_shared->ulState == 1 && g_ulN >= 2, "on, a wide window: laid out (state %lu, %d frames saved)", g_shared->ulState, g_ulN);
    const Call *c = Find(minimap + 0xb4, 6), *c2 = Find(minimap + 0xb4, 2), *pc = Find(peon, 6);
    CHECK(c && c2 && c->rel == (DWORD)(ui + 0xb4) && c->x == 0.1075f && c->y == 0.007f && c2->relPt == 6 && c2->x == 0.210f && c2->y == 0.145f,
          "the minimap (a CFrame: its layout +0xb4) gets WFE's two corners on the game UI's layout");
    CHECK(pc && *(float *)(peon + 0x58) == 0.0275f && pc->x == 0.100f && pc->y == 0.173f, "the idle workers (a simple frame: itself) narrowed and moved");
    int saved = g_ulN; nCalls = 0; Pump(8);
    CHECK(g_ulN == saved && Find(minimap + 0xb4, 6), "laid out again every 2 s, nothing saved twice");
    // a 4:3 window: put back
    SetWindowPos(wnd, 0, 0, 0, 400, 330, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE); nCalls = 0; clears = 0; Pump(2);
    const Call *back = Find(minimap + 0xb4, 0);
    CHECK(g_ulN == 0 && g_shared->ulState == 2 && back && back->rel == (DWORD)anchorFrame && back->y == -0.02f && clears >= 2 && *(float *)(peon + 0x58) == 0.05f,
          "a 4:3 window: every frame put back (anchors, width), state 2");
    SetWindowPos(wnd, 0, 0, 0, 800, 330, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE); Pump(2);
    CHECK(g_shared->ulState == 1 && *(float *)(peon + 0x58) == 0.0275f, "wide again: laid out again");
    g_shared->ulOn = 0; Pump(2);
    CHECK(g_shared->ulState == 0 && g_ulN == 0 && *(float *)(peon + 0x58) == 0.05f, "off: put back");
    Verdict();
    PostThreadMessageA(mainTid, WM_QUIT, 0, 0);
    return 0;
}
int main() {
    strcpy_s(g_logPath, "uilayout.log"); DeleteFileA("uilayout.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_SET_POINT, FSetPoint); Stub(RVA_SET_ABS_POINT, FSetAbs); Stub(RVA_CLEAR_POINTS, FClear); Stub(RVA_LAYOUT_REFRESH, FRefresh);
    DWORD old; VirtualProtect(img + 0xa7d000, 0x1000, PAGE_READWRITE, &old); VirtualProtect(img + 0xaa0000, 0x20000, PAGE_READWRITE, &old);
    g_uiVtable = (DWORD)(img + RVA_UI_VTABLE); *(DWORD *)ui = g_uiVtable;
    DWORD *mmVt = (DWORD *)(img + 0xab0704); Stub(0x300000, FMinimap); mmVt[0xe4 / 4] = (DWORD)(img + 0x300000);
    *(DWORD *)minimap = (DWORD)mmVt; *(BYTE **)(minimap + 0x44) = minimap;               // a CFrame
    *(DWORD *)relPt = (DWORD)(img + RVA_REL_POINT_VT); *(BYTE **)(relPt + 4) = anchorFrame; *(float *)(relPt + 0x10) = -0.02f;
    *(BYTE **)(minimap + 0xb4 + 8) = relPt;                                              // its own point 0, relative
    *(DWORD *)peon = (DWORD)(img + 0xab0f08); *(float *)(peon + 0x58) = 0.05f;           // a simple frame
    *(BYTE **)(ui + 0x3c0) = minimap; *(BYTE **)(ui + 0x3e0) = peon;
    fakeUi = ui; g_getUi = FakeGetUi;
    mainTid = GetCurrentThreadId();
    WNDCLASSA wc = {}; wc.lpfnWndProc = DefWindowProcA; wc.lpszClassName = "Warcraft III"; wc.hInstance = GetModuleHandleA(0);
    RegisterClassA(&wc);
    wnd = CreateWindowA("Warcraft III", "Warcraft III", WS_OVERLAPPEDWINDOW, 0, 0, 800, 330, 0, 0, wc.hInstance, 0);
    ShowWindow(wnd, SW_SHOWNOACTIVATE);
    CreateThread(0, 0, Tester, 0, 0, 0);
    MSG m; while (GetMessageA(&m, 0, 0, 0) > 0) { TranslateMessage(&m); DispatchMessageA(&m); }
    Unsubclass(); DestroyWindow(wnd);
    return g_fails;
}
