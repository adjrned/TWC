// harness: hiding parts of the UI against a fake game UI
#include "../twc-game.cpp"
#include "check.h"
#include <stddef.h>
static_assert(offsetof(Shared, uiHide) == 676 && sizeof(Shared) >= 684, "layout 10");
static DWORD mainTid, gameTid; static void *fakeUi; static BYTE *img;
static void *__fastcall FakeGetUi(int, int) { return fakeUi; }
static BYTE frames[5][0x40]; static int hides[5], shows[5], afters[5], wrong;
static int Idx(void *f) { for (int i = 0; i < 5; i++) if (f == frames[i]) return i; return -1; }
static void __fastcall FHide(void *f, int) { hides[Idx(f)]++; if (GetCurrentThreadId() != gameTid) wrong++; }
static void __fastcall FShow(void *f, int) { shows[Idx(f)]++; }
static void __fastcall FAfter(void *f, int) { afters[Idx(f)]++; }
// the console: 4 regions, 3 of them CSimpleTextures, one a font string
static BYTE con[0x100], links[4][0x10], regs[4][0x20]; static int texHides, texShows, otherCalls;
static void __fastcall RHide(BYTE *r, int) { r == regs[2] ? otherCalls++ : texHides++; r[0x10] = 0; }
static void __fastcall RShow(BYTE *r, int) { r == regs[2] ? otherCalls++ : texShows++; r[0x10] = 1; }
// the world frame: its layout at +0xb4, a relative point at slot 0 and an absolute one at 8
static BYTE world[0x200], relPt[0x20], absPt[0x20], anchorFrame[0x10];
struct PtCall { int kind; BYTE *lay; DWORD pt, rel, relPt; float x, y; } ptCalls[16]; static int nPt, clears;
static void __fastcall FSetPoint(BYTE *lay, int, DWORD pt, DWORD rel, DWORD rp, float x, float y, DWORD) { if (nPt < 16) ptCalls[nPt++] = { 2, lay, pt, rel, rp, x, y }; }
static void __fastcall FSetAbs(BYTE *lay, int, DWORD pt, float x, float y, DWORD) { if (nPt < 16) ptCalls[nPt++] = { 1, lay, pt, 0, 0, x, y }; }
static void __fastcall FClear(BYTE *, int, DWORD) { clears++; }
static void Stub(DWORD rva, void *to) { BYTE *p = img + rva; p[-1] = 0xCC; p[0] = 0xE9; *(LONG *)(p + 1) = (LONG)((BYTE *)to - (p + 5)); }
static BYTE ui[0x400], ui2[0x400];
// the buff bar [[[ui+0x3c4]+0x130]+0x16c]: a CBuffBar, hidden / shown with its vtable +0x64 / +0x68
static BYTE info0[0x200], unitPanel[0x200], buffBar[0x200]; static int bHides, bShows;
static void __fastcall BHide(BYTE *b, int) { b == buffBar ? bHides++ : wrong++; }
static void __fastcall BShow(BYTE *b, int) { b == buffBar ? bShows++ : wrong++; }
static void Pump(int n) { for (int k = 0; k < n; k++) { QueueDisplay(); Sleep(260); } }
static DWORD WINAPI Tester(void *) {
    Pump(2);
    CHECK(!hides[0] && !g_oldProc, "nothing wanted: no calls, no subclass");
    g_shared->uiHide = 1 | 2; Pump(1);
    CHECK(hides[0] == 1 && hides[1] == 1 && afters[1] == 1 && !hides[2] && g_shared->uiState == 3, "time of day + minimap hidden at once, minimap +0xe4 after (state %lX)", g_shared->uiState);
    Pump(7);
    CHECK(hides[0] >= 2 && hides[0] <= 3, "hidden again about every 1.5 s (%d)", hides[0]);
    g_shared->uiHide = 2; Pump(1);
    CHECK(shows[0] == 1 && g_shared->uiState == 2, "time of day off: shown once (%d), state %lX", shows[0], g_shared->uiState);
    Pump(2);
    CHECK(shows[0] == 1, "not shown again (%d)", shows[0]);
    int h = hides[1]; fakeUi = ui2; Pump(1);
    CHECK(hides[1] == h + 1, "a new game: hidden at once again");
    g_shared->uiHide = 0x1c; Pump(1);
    CHECK(shows[1] == 1 && afters[1] >= 3 && hides[2] == 1 && hides[3] == 1 && hides[4] == 1 && g_shared->uiState == 0x1c, "minimap shown (+0xe4 after), the three simple frames hidden (state %lX)", g_shared->uiState);
    fakeUi = nullptr; Pump(1);
    CHECK((g_shared->uiState & 0x1f) == 0, "between games: state 0");
    fakeUi = ui; nPt = 0; g_shared->uiHide = 0x20; Pump(1);
    CHECK(nPt >= 2 && ptCalls[0].kind == 2 && ptCalls[0].lay == world + 0xb4 && ptCalls[0].pt == 2 && ptCalls[0].rel == (DWORD)(ui + 0xb4) && ptCalls[0].relPt == 2
          && ptCalls[1].pt == 6 && ptCalls[1].relPt == 6 && ptCalls[1].x == 0 && ptCalls[1].y == 0 && clears >= 1,
          "the world frame over the whole screen: its points cleared, top right and bottom left to the game UI's (%d calls)", nPt);
    CHECK(texHides == 3 && !otherCalls && (g_shared->uiState & 0x20) && !regs[0][0x10] && !regs[3][0x10] && regs[2][0x10], "the console's background: its 3 textures hidden, the font string left (state %lX)", g_shared->uiState);
    nPt = 0; clears = 0; g_shared->uiHide = 0x1c; Pump(1);
    CHECK(clears == 1 && nPt == 2 && ptCalls[0].kind == 2 && ptCalls[0].pt == 0 && ptCalls[0].rel == (DWORD)anchorFrame && ptCalls[0].relPt == 0 && ptCalls[0].y == -0.02f
          && ptCalls[1].kind == 1 && ptCalls[1].pt == 8 && ptCalls[1].x == 0.8f && ptCalls[1].y == 0.13f,
          "off: its own points back (cleared, then the relative one and the absolute one)");
    CHECK(texShows == 3 && !(g_shared->uiState & 0x20) && regs[0][0x10] == 1, "off: the 3 shown again");
    g_shared->uiHide = 0x1c | 0x40; Pump(1);
    CHECK(bHides == 1 && !bShows && (g_shared->uiState & 0x40), "the buff bar hidden with its +0x64, as WFE's ISBUFFBAR with its UI hidden (state %lX)", g_shared->uiState);
    g_shared->uiHide = 0x1c; Pump(1);
    CHECK(bShows == 1 && !(g_shared->uiState & 0x40), "off: shown again with its +0x68 (%d)", bShows);
    CHECK(wrong == 0, "all on the game thread");
    Verdict();
    PostThreadMessageA(mainTid, WM_QUIT, 0, 0);
    return 0;
}
int main() {
    strcpy_s(g_logPath, "uihide.log"); DeleteFileA("uihide.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(0x300000, FHide); Stub(0x300010, FShow); Stub(0x300020, FAfter);
    DWORD old; VirtualProtect(img + 0xaaa000, 0x8000, PAGE_READWRITE, &old);
    for (int i = 0; i < 5; i++) {
        DWORD *vt = (DWORD *)(img + 0xaab000 + i * 0x200);
        vt[UI_PARTS[i].hide / 4] = (DWORD)(img + 0x300000); vt[UI_PARTS[i].show / 4] = (DWORD)(img + 0x300010);
        if (UI_PARTS[i].after) vt[UI_PARTS[i].after / 4] = (DWORD)(img + 0x300020);
        *(DWORD *)frames[i] = (DWORD)vt;
        *(BYTE **)(ui + UI_PARTS[i].off) = frames[i]; *(BYTE **)(ui2 + UI_PARTS[i].off) = frames[i];
    }
    *(DWORD *)ui = *(DWORD *)ui2 = (DWORD)(img + RVA_UI_VTABLE); g_uiVtable = *(DWORD *)ui;
    Stub(RVA_REGION_HIDE, RHide); Stub(RVA_REGION_SHOW, RShow);
    VirtualProtect(img + 0xab8000, 0x2000, PAGE_READWRITE, &old);       // vtables and RTTI: data
    // RTTI: vtable[-1] -> locator (+0xc the type) -> type +8 the name
    auto rtti = [&](DWORD vtOff, DWORD colOff, const char *name) {
        DWORD *vt = (DWORD *)(img + vtOff), *col = (DWORD *)(img + colOff);
        vt[-1] = (DWORD)col; col[0] = 0; col[3] = (DWORD)(img + colOff + 0x20); strcpy_s((char *)img + colOff + 0x28, 64, name);
        return (DWORD)vt;
    };
    DWORD texVt = rtti(0xab8000, 0xab9000, ".?AVCSimpleTexture@@"), strVt = rtti(0xab8100, 0xab9100, ".?AVCSimpleFontString@@");
    *(DWORD *)con = rtti(0xab8200, 0xab9200, ".?AVCConsole@@");
    *(BYTE **)(con + CONSOLE_REGIONS) = links[0];
    for (int i = 0; i < 4; i++) {
        *(BYTE **)(links[i] + 4) = i < 3 ? links[i + 1] : nullptr; *(BYTE **)(links[i] + 8) = regs[i];
        *(DWORD *)regs[i] = i == 2 ? strVt : texVt; regs[i][0x10] = 1;
    }
    *(BYTE **)(ui + UI_CONSOLE) = con;
    Stub(RVA_SET_POINT, FSetPoint); Stub(RVA_SET_ABS_POINT, FSetAbs); Stub(RVA_CLEAR_POINTS, FClear);
    *(DWORD *)world = rtti(0xab8300, 0xab9300, ".?AVCWorldFrameWar3@@"); *(BYTE **)(ui + UI_WORLD) = world;
    VirtualProtect(img + 0xa7d000, 0x1000, PAGE_READWRITE, &old);
    *(DWORD *)relPt = (DWORD)(img + RVA_REL_POINT_VT); *(BYTE **)(relPt + 4) = anchorFrame; relPt[8] = 0; *(float *)(relPt + 0xc) = 0; *(float *)(relPt + 0x10) = -0.02f;
    *(DWORD *)absPt = (DWORD)(img + RVA_ABS_POINT_VT); *(float *)(absPt + 4) = 0.8f; *(float *)(absPt + 8) = 0.13f;
    *(BYTE **)(world + 0xb4 + 8) = relPt; *(BYTE **)(world + 0xb4 + 8 + 8 * 4) = absPt;
    Stub(0x300030, BHide); Stub(0x300040, BShow);
    DWORD *bvt = (DWORD *)rtti(RVA_BUFF_BAR_VT, 0xab9400, ".?AVCBuffBar@@");
    bvt[0x64 / 4] = (DWORD)(img + 0x300030), bvt[0x68 / 4] = (DWORD)(img + 0x300040);
    *(DWORD *)buffBar = (DWORD)bvt, *(DWORD *)info0 = *(DWORD *)unitPanel = (DWORD)(img + 0xab8400);
    *(BYTE **)(ui + 0x3c4) = info0, *(BYTE **)(info0 + 0x130) = unitPanel, *(BYTE **)(unitPanel + 0x16c) = buffBar;
    fakeUi = ui; g_getUi = FakeGetUi;
    mainTid = gameTid = GetCurrentThreadId();
    WNDCLASSA wc = {}; wc.lpfnWndProc = DefWindowProcA; wc.lpszClassName = "Warcraft III"; wc.hInstance = GetModuleHandleA(0);
    RegisterClassA(&wc);
    HWND w = CreateWindowA("Warcraft III", "Warcraft III", WS_OVERLAPPEDWINDOW, 0, 0, 200, 100, 0, 0, wc.hInstance, 0);
    ShowWindow(w, SW_SHOWNOACTIVATE);
    CreateThread(0, 0, Tester, 0, 0, 0);
    MSG m; while (GetMessageA(&m, 0, 0, 0) > 0) { TranslateMessage(&m); DispatchMessageA(&m); }
    Unsubclass(); DestroyWindow(w);
    return g_fails;
}
