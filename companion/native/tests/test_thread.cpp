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
