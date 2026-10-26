#include "../twc-game.cpp"
#include "check.h"
static DWORD mainTid, clearTid; static volatile LONG cleared;
static void *fakeUi;
static void *__fastcall FakeGetUi(int, int) { return fakeUi; }
static DWORD WINAPI Tester(void *) {
    Sleep(300);
    g_shared->cmd = 1; g_shared->cmdSeq = 1; ServeCommand(1);
    CHECK(g_shared->cmdResult == 1 && g_shared->cmdDone == 1, "clear messages: result %lu, done %ld", g_shared->cmdResult, g_shared->cmdDone);
    g_shared->cmd = 2; g_shared->cmdSeq = 2; ServeCommand(2);
    CHECK(g_shared->cmdResult == 1 && g_shared->cmdDone == 2, "clear chat: result %lu, done %ld", g_shared->cmdResult, g_shared->cmdDone);
    // the overlay's timers: read on the game thread, through a time-left getter 2 calls deep (1.28f's +0x8a600)
    LONG seq = g_shared->tmSeq;
    QueueTimers();
    for (int i = 0; i < 100 && g_shared->tmSeq == seq; i++)
        Sleep(10);
    CHECK(g_shared->tmSeq != seq && g_shared->cdLeft[0] == 3.0f && g_shared->cdTotal[0] == 10.0f && !(g_shared->tmFlags & 0x100),
          "timers read on the game thread: left %.1f, total %.1f, flags %lX", g_shared->cdLeft[0], g_shared->cdTotal[0], g_shared->tmFlags);
    PostThreadMessageA(mainTid, WM_QUIT, 0, 0);
    return 0;
}
int main() {
    strcpy_s(g_logPath, "thread.log"); DeleteFileA("thread.log");
    static Shared sh; g_shared = &sh;
    BYTE *img = (BYTE *)VirtualAlloc(nullptr, 0x200000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x200000;
    // the "clear" at +0x144750: mov dword [ecx+8], 1; ret  (and remember the thread via a flag the test reads)
    BYTE clr[] = { 0xC7, 0x41, 0x08, 1, 0, 0, 0, 0xC3 }; memcpy(img + RVA_MSG_CLEAR, clr, sizeof(clr));
    // data page for vtables at +0x100000 (not executable)
    DWORD old; VirtualProtect(img + 0x100000, 0x1000, PAGE_READWRITE, &old);
    DWORD *uiVt = (DWORD *)(img + 0x100000), *frVt = (DWORD *)(img + 0x100100);
    g_uiVtable = (DWORD)uiVt;
    static BYTE ui[0x400], msgs[16], chat[16];
    *(DWORD *)ui = (DWORD)uiVt; *(BYTE **)(ui + UI_MESSAGES) = msgs; *(BYTE **)(ui + UI_CHAT) = chat;
    *(DWORD *)msgs = (DWORD)frVt; *(DWORD *)chat = (DWORD)frVt;
    // a cooldown on the command card's first button: card +0x124 rows, +0x128 columns, +0x154 the rows
    static BYTE card[0x200], btn[0x200], data[0x700], ab[0x200], *btns[1] = { btn };
    static DWORD rowsTab[4] = { 0, 1, (DWORD)btns, 0 };
    *(BYTE **)(ui + 0x3c8) = card; *(int *)(card + 0x124) = 1; *(int *)(card + 0x128) = 1; *(DWORD **)(card + 0x154) = rowsTab;
    *(DWORD *)(btn + 0x19c) = 1; *(BYTE **)(btn + 0x190) = data; *(BYTE **)(data + 0x6d4) = ab;
    *(DWORD *)(ab + 0x34) = 'AHtb'; *(DWORD *)(ab + 0x20) = 0x200;
    DWORD *tmVt = (DWORD *)(img + 0x100200); *(DWORD *)(ab + 0xd0) = (DWORD)tmVt;
    // left +0x1000: mov eax,[esp+4]; call +0x1100; ret 4 -> +0x1100: call +0x1200; ret -> +0x1200: mov dword [eax], 3.0f; ret
    BYTE left[] = { 0x8B, 0x44, 0x24, 0x04, 0xE8, 0, 0, 0, 0, 0xC2, 0x04, 0x00 }, mid[] = { 0xE8, 0, 0, 0, 0, 0xC3 },
         leaf[] = { 0xC7, 0x00, 0x00, 0x00, 0x40, 0x40, 0xC3 },
         total[] = { 0x8B, 0x44, 0x24, 0x04, 0xC7, 0x00, 0x00, 0x00, 0x20, 0x41, 0xC2, 0x04, 0x00 };   // 10.0f
    memcpy(img + 0x1000, left, sizeof(left)); *(LONG *)(img + 0x1005) = 0x1100 - 0x1009;
    memcpy(img + 0x1100, mid, sizeof(mid)); *(LONG *)(img + 0x1101) = 0x1200 - 0x1105;
    memcpy(img + 0x1200, leaf, sizeof(leaf)); memcpy(img + 0x1300, total, sizeof(total));
    tmVt[0x18 / 4] = (DWORD)(img + 0x1000); tmVt[0x10 / 4] = (DWORD)(img + 0x1300);
    fakeUi = ui; g_getUi = FakeGetUi;
    mainTid = GetCurrentThreadId();
    WNDCLASSA wc = {}; wc.lpfnWndProc = DefWindowProcA; wc.lpszClassName = "Warcraft III"; wc.hInstance = GetModuleHandleA(0);
    RegisterClassA(&wc);
    HWND w = CreateWindowA("Warcraft III", "Warcraft III", WS_OVERLAPPEDWINDOW, 0, 0, 200, 100, 0, 0, wc.hInstance, 0);
    ShowWindow(w, SW_SHOWNOACTIVATE);
    CreateThread(0, 0, Tester, 0, 0, 0);
    MSG m; while (GetMessageA(&m, 0, 0, 0) > 0) { TranslateMessage(&m); DispatchMessageA(&m); }
    CHECK(*(DWORD *)(msgs + 8) == 1 && *(DWORD *)(chat + 8) == 1 && g_gameTid == mainTid, "both frames cleared, on the window's thread (%lu)", g_gameTid);
    Unsubclass();
    CHECK((WNDPROC)GetWindowLongPtrA(w, GWLP_WNDPROC) == DefWindowProcA, "unload: the window procedure is the game's again");
    DestroyWindow(w);
    Verdict();
    return g_fails;
}
