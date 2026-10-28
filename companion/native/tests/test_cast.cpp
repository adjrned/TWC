// harness: self-cast (portrait click) and the autocast toggle against a fake game image
#define GetAsyncKeyState FakeAsync
#define GetForegroundWindow FakeFg
#include "../twc-game.cpp"
#include "check.h"
#undef GetAsyncKeyState
#undef GetForegroundWindow
#include <stddef.h>
static_assert(offsetof(Shared, scHeld) == 636 && offsetof(Shared, cmdArg) == 648 && sizeof(Shared) >= 684, "layout 8");
static int heldVk; static HWND wnd;
SHORT WINAPI FakeAsync(int vk) { return vk == heldVk ? (SHORT)0x8000 : 0; }
HWND WINAPI FakeFg() { return wnd; }
static DWORD mainTid, gameTid; static void *fakeUi; static BYTE *img;
static void *__fastcall FakeGetUi(int, int) { return fakeUi; }
static int clicks, clickArg, wrongThread; static void *clickThis;
static int __fastcall FakeClick(void *t, int, int b) { clicks++, clickArg = b, clickThis = t; if (GetCurrentThreadId() != gameTid) wrongThread++; return 1; }
static int btnClicks, btnArg, btnFlagsSeen; static void *btnThis;
static int __fastcall FakeBtnClick(void *t, int, int b) { btnClicks++, btnArg = b, btnThis = t, btnFlagsSeen = *(DWORD *)((BYTE *)t + BTN_FLAGS); return 1; }
static void Stub(DWORD rva, void *to) { BYTE *p = img + rva; p[-1] = 0xCC; p[0] = 0xE9; *(LONG *)(p + 1) = (LONG)((BYTE *)to - (p + 5)); }
static BYTE ui[0x400], portrait[0x100], card[0x200], btns[12][0x200], *rowBtns[3][4], rowsTab[3][16];
static void Aim(bool on) { *(DWORD *)(ui + UI_MODE) = on ? 0x1234 : 0x99; }
static void Rounds(int n) { for (int k = 0; k < n; k++) { WatchSelfCast(Targeting()); Sleep(40); } }
static int Cmd(LONG seq, DWORD slot) { g_shared->cmd = 4; g_shared->cmdArg = slot; g_shared->cmdSeq = seq; ServeCommand(seq); return (int)g_shared->cmdResult; }
static DWORD WINAPI Tester(void *) {
    g_shared->scHeld = 1;
    Aim(true); Rounds(3);
    CHECK(clicks == 0, "aiming, key not held: no self-cast");
    g_shared->scHeld = 2; Rounds(3);
    CHECK(clicks == 1 && clickArg == 1 && clickThis == portrait && !wrongThread && g_shared->scCount == 1,
        "key pressed during the aim: portrait clicked once, with 1, on the game thread (%d)", clicks);
    Aim(false); Rounds(2); Aim(true); Rounds(3);
    CHECK(clicks == 2, "next aim with the key still held: once more (%d)", clicks);
    g_shared->scHeld = 1; Aim(false); Rounds(2); Aim(true); Rounds(3);
    CHECK(clicks == 2, "aim without the key: nothing (%d)", clicks);
    g_shared->scHeld = 0; Aim(false); Rounds(2); Aim(true); Rounds(3);
    CHECK(clicks == 2 && g_shared->scState == 0, "self-cast off: nothing (%d)", clicks);
    // autocast: slot 5 (row 1, col 1)
    int r = Cmd(1, 5);
    CHECK(r == 1 && btnClicks == 1 && btnArg == 4 && btnThis == btns[5] && (btnFlagsSeen & 2) && *(DWORD *)(btns[5] + BTN_FLAGS) == 0x10,
        "autocast slot 5: button clicked with 4, flag 2 during, flags put back (%d, flags %lX)", r, *(DWORD *)(btns[5] + BTN_FLAGS));
    *(DWORD *)(btns[7] + BTN_DATA) = 0;
    r = Cmd(2, 7);
    CHECK(r == 2 && btnClicks == 1, "empty slot 7: refused (%d)", r);
    r = Cmd(3, 12);
    CHECK(r == 2, "slot 12: refused (%d)", r);
    fakeUi = nullptr; r = Cmd(4, 5);
    CHECK(r == 2 && btnClicks == 1, "outside a game: refused (%d)", r);
    // a torn read of the game UI (its vtable wrong a few times, e.g. freed as a game ends): not a stop for good
    fakeUi = ui;
    DWORD goodVt = *(DWORD *)ui;
    *(DWORD *)ui = 0x12345678;
    int t1 = 0;
    for (int k = 0; k < 4; k++)
        t1 += Targeting();
    *(DWORD *)ui = goodVt;
    Aim(true);
    int t2 = Targeting();
    CHECK(t1 == -4 && g_getUi && g_shared->probe != 2 && t2 == 1, "4 odd reads of the game UI: no UI meanwhile, then it works again (no stop; %d, %d)", t1, t2);
    // a game UI being torn down as a game ends (its base classes' vtables meanwhile, for a long time): never a stop once seen
    *(DWORD *)ui = 0x12345678;
    for (int k = 0; k < 300; k++)
        Targeting();
    *(DWORD *)ui = goodVt;
    int t3 = Targeting();
    CHECK(g_getUi && g_shared->probe != 2 && t3 == 1, "300 odd reads after the game UI was seen (a teardown): no stop, works again after (%d)", t3);
    // a getter that never gave the game UI: wrong addresses, a stop for good after 50
    g_shared->ui = 0, *(DWORD *)ui = 0x12345678;
    for (int k = 0; k < 49; k++)
        Targeting();
    bool notYet = g_getUi != nullptr;
    Targeting();
    CHECK(notYet && !g_getUi && g_shared->probe == 2, "never seen: stopped for good at 50 odd reads, not before (%s)", g_shared->probeText);
    *(DWORD *)ui = goodVt;
    Verdict();
    PostThreadMessageA(mainTid, WM_QUIT, 0, 0);
    return 0;
}
int main() {
    strcpy_s(g_logPath, "cast.log"); DeleteFileA("cast.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_CONTROL_CLICK, FakeClick);
    img[RVA_MSG_CLEAR - 1] = 0xCC; img[RVA_MSG_CLEAR] = 0xC3;
    BYTE *clickStub = img + 0x200000; clickStub[-1] = 0xCC; Stub(0x200000, FakeBtnClick);
    DWORD old; VirtualProtect(img + 0xaaa000, 0x4000, PAGE_READWRITE, &old);
    DWORD *btnVt = (DWORD *)(img + 0xaac000); btnVt[BTN_CLICK / 4] = (DWORD)(img + 0x200000);
    *(DWORD *)portrait = (DWORD)(img + 0xaab000);
    *(DWORD *)ui = (DWORD)(img + RVA_UI_VTABLE); g_uiVtable = *(DWORD *)ui;
    *(DWORD *)(ui + UI_TARGET_MODE) = 0x1234; *(BYTE **)(ui + UI_PORTRAIT) = portrait; *(BYTE **)(ui + 0x3c8) = card;
    *(int *)(card + 0x124) = 3; *(int *)(card + 0x128) = 4; *(BYTE **)(card + 0x154) = (BYTE *)rowsTab;
    for (int i = 0; i < 12; i++) {
        *(DWORD *)btns[i] = (DWORD)btnVt; *(DWORD *)(btns[i] + BTN_DATA) = 1; *(DWORD *)(btns[i] + BTN_FLAGS) = 0x10;
        rowBtns[i / 4][i % 4] = btns[i];
    }
    for (int r = 0; r < 3; r++) { *(DWORD *)(rowsTab[r] + 4) = 4; *(BYTE ***)(rowsTab[r] + 8) = rowBtns[r]; }
    fakeUi = ui; g_getUi = FakeGetUi;
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
