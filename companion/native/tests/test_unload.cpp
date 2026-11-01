// Unloading for a newer module (layout 13): asked through shared memory, every
// switch goes off, then the game thread gives back the rewritten projection
// call and the window, and the worker is told to free the module. And when
// someone subclassed the window after us, the module stays and carries on
// (status 1 again, so quickcast keeps working). And a second copy loaded into
// a game whose module is alive leaves it alone (LiveModuleThere).
#include "../twc-game.cpp"
#include "check.h"
static DWORD mainTid; static BYTE *img; static HWND wnd;
static void *__fastcall FakeGetUi(int, int) { return nullptr; }
static void __fastcall FakeProj(float *m, int, float, float, float, float) { m[0] = 1; }
static WNDPROC theirs;
static LRESULT CALLBACK Theirs(HWND w, UINT m, WPARAM wp, LPARAM lp) { return CallWindowProcA(theirs, w, m, wp, lp); }
static bool RunUnload(int ms) {
    for (DWORD t0 = GetTickCount(); GetTickCount() - t0 < (DWORD)ms;) {
        if (UnloadStep(GetTickCount()))
            return true;
        Sleep(50);
    }
    return false;
}
static DWORD WINAPI Tester(void *) {
    BYTE *site = img + RVA_PROJECTION_CALL;
    g_shared->wsOn = 1; QueueDisplay(); Sleep(400);
    CHECK(SiteTarget(site) == (BYTE *)ProjHook && g_oldProc, "widescreen on: the call rewritten, the window subclassed");
    g_shared->hbOn = g_shared->hnOn = g_shared->uiHide = 1;
    g_shared->unload = 1;
    CHECK(!UnloadStep(GetTickCount()) && g_shared->status == 4 && !g_shared->wsOn && !g_shared->hbOn && !g_shared->hnOn && !g_shared->uiHide,
          "asked: status 4, every switch off");
    bool freed = RunUnload(5000);
    CHECK(freed && g_unloadNow && g_finalDone == 1, "then given back on the game thread, and the worker retires it");
    CHECK(SiteTarget(site) == img + RVA_PROJECTION && (WNDPROC)GetWindowLongPtrA(wnd, GWLP_WNDPROC) == DefWindowProcA,
          "the projection call and the window are the game's again");
    // again, with someone subclassing after us: it stays
    g_unloadNow = false; g_finalDone = 0; g_shared->unload = 0; g_shared->status = 1;
    Subclass();
    theirs = (WNDPROC)SetWindowLongPtrA(wnd, GWLP_WNDPROC, (LONG_PTR)Theirs);
    g_shared->unload = 1;
    freed = RunUnload(8500);
    CHECK(!freed && g_shared->status == 1 && g_shared->unload == 2, "a window subclassed after us: the module stays and carries on (status %lu, not 5: quickcast needs 1)", g_shared->status);
    g_shared->wsOn = 1;
    bool carries = !UnloadStep(GetTickCount()) && g_shared->wsOn == 1 && g_shared->status == 1;
    CHECK(carries, "and isn't asked again: the companion's switches stay on (nothing turned off)");
    SetWindowLongPtrA(wnd, GWLP_WNDPROC, (LONG_PTR)theirs);
    // a second copy loaded into this game: the shared memory there is another module's
    static Shared other;
    other.magic = 'TWC1', other.status = 1, other.heartbeat = GetTickCount();
    bool alive = LiveModuleThere(&other);
    other.heartbeat = GetTickCount() - 5000;
    bool stale = !LiveModuleThere(&other);
    other.heartbeat = GetTickCount(), other.status = 3;
    bool gone = !LiveModuleThere(&other);
    other.status = 4;
    bool going = !LiveModuleThere(&other);
    other.status = 2;
    bool idle = LiveModuleThere(&other);
    other.status = 1, other.magic = 0;
    CHECK(alive && stale && gone && going && idle && !LiveModuleThere(&other),
          "loaded again: a module there with a moving heartbeat (or idle on another build) is left alone; a stale, unloading or gone one isn't");
    Verdict();
    PostThreadMessageA(mainTid, WM_QUIT, 0, 0);
    return 0;
}
int main() {
    strcpy_s(g_logPath, "unload.log"); DeleteFileA("unload.log");
    static Shared sh; g_shared = &sh; sh.status = 1;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    BYTE *p = img + RVA_PROJECTION; p[-1] = 0xCC; p[0] = 0x68; *(void **)(p + 1) = (void *)FakeProj; p[5] = 0xC3;   // push / ret, not a jmp out (that's another mod's hook)
    img[RVA_PROJECTION_CALL] = 0xE8; *(LONG *)(img + RVA_PROJECTION_CALL + 1) = (LONG)(RVA_PROJECTION - (RVA_PROJECTION_CALL + 5));
    g_getUi = FakeGetUi;
    mainTid = GetCurrentThreadId();
    WNDCLASSA wc = {}; wc.lpfnWndProc = DefWindowProcA; wc.lpszClassName = "Warcraft III"; wc.hInstance = GetModuleHandleA(0);
    RegisterClassA(&wc);
    wnd = CreateWindowA("Warcraft III", "Warcraft III", WS_OVERLAPPEDWINDOW, 0, 0, 640, 360, 0, 0, wc.hInstance, 0);
    ShowWindow(wnd, SW_SHOWNOACTIVATE);
    CreateThread(0, 0, Tester, 0, 0, 0);
    MSG m; while (GetMessageA(&m, 0, 0, 0) > 0) { TranslateMessage(&m); DispatchMessageA(&m); }
    DestroyWindow(wnd);
    return g_fails;
}
