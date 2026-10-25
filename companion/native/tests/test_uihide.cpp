// harness: hiding parts of the UI against a fake game UI
#include "../twc-game.cpp"
#include "check.h"
#include <stddef.h>
static_assert(offsetof(Shared, uiHide) == 676 && sizeof(Shared) == 684, "layout 10");
static DWORD mainTid, gameTid; static void *fakeUi; static BYTE *img;
static void *__fastcall FakeGetUi(int, int) { return fakeUi; }
static BYTE frames[5][0x40]; static int hides[5], shows[5], afters[5], wrong;
static int Idx(void *f) { for (int i = 0; i < 5; i++) if (f == frames[i]) return i; return -1; }
static void __fastcall FHide(void *f, int) { hides[Idx(f)]++; if (GetCurrentThreadId() != gameTid) wrong++; }
static void __fastcall FShow(void *f, int) { shows[Idx(f)]++; }
static void __fastcall FAfter(void *f, int) { afters[Idx(f)]++; }
static void Stub(DWORD rva, void *to) { BYTE *p = img + rva; p[-1] = 0xCC; p[0] = 0xE9; *(LONG *)(p + 1) = (LONG)((BYTE *)to - (p + 5)); }
static BYTE ui[0x400], ui2[0x400];
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
