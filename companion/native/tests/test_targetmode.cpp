// harness: quickcast's click as the game opens the target mode (CTargetMode's Enter, vtable +0xaaa220
// entry +0x24, ours), and the worker's answer next to it, against a fake game image. No real clicks:
// g_click and g_gameInFront are the test's
#include "../twc-game.cpp"
#include "check.h"
static BYTE *img;
static BYTE ui[0x400], mode[0x40], other[0x40];
static void *__fastcall FakeGetUi(int, int) { return ui; }
static int enters, enterRet = 1;
static int __fastcall FakeEnter(void *, int) { enters++; return enterRet; }
static int clicks; static DWORD clickFlags;
static void FakeClick(DWORD f) { clicks++, clickFlags = f; }
static bool front = true;
static bool FakeFront() { return front; }
static void Stub(DWORD rva, void *to) { BYTE *p = img + rva; p[-1] = 0xCC; p[0] = 0xE9; *(LONG *)(p + 1) = (LONG)((BYTE *)to - (p + 5)); }
static DWORD *Slot() { return (DWORD *)(img + RVA_TARGETMODE_VT + TARGETMODE_ENTER); }
static int Enter(void *m) { return ((EnterFn)*Slot())(m, 0); }
static LONG seq;
static void Ask(DWORD ms, DWORD flags = 0) { g_shared->qcUntil = GetTickCount() + ms; g_shared->qcFlags = flags; g_shared->qcSeq = ++seq; }
int main() {
    strcpy_s(g_logPath, "targetmode.log"); DeleteFileA("targetmode.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_TARGETMODE_ENTER, FakeEnter);
    img[0x300000 - 1] = 0xCC; img[0x300000] = 0xC3;
    DWORD old; VirtualProtect(img + 0xaaa000, 0x2000, PAGE_READWRITE, &old);
    DWORD *vt = (DWORD *)(img + RVA_TARGETMODE_VT);
    for (int i = 0; i < 12; i++) vt[i] = (DWORD)(img + 0x300000);
    vt[TARGETMODE_ENTER / 4] = (DWORD)(img + RVA_TARGETMODE_ENTER);
    *(DWORD *)ui = (DWORD)(img + RVA_UI_VTABLE); g_uiVtable = *(DWORD *)ui;
    *(void **)(ui + UI_TARGET_MODE) = mode; *(DWORD *)mode = (DWORD)vt; *(DWORD *)other = (DWORD)vt;
    g_getUi = FakeGetUi; g_click = FakeClick; g_gameInFront = FakeFront;

    FollowTargetMode();
    CHECK(g_tmHooked && *Slot() == (DWORD)TargetEnter, "the target mode's Enter is ours once the probe passed");
    int r = Enter(mode);
    CHECK(r == 1 && enters == 1 && clicks == 0, "no request: the game's Enter runs, its 1 returned, no click");
    Ask(200, 1);
    r = Enter(mode);
    CHECK(r == 1 && enters == 2 && clicks == 1 && clickFlags == 1 && g_shared->qcDone == seq && g_shared->qcResult == 1 && g_shared->qcClicked == 1,
        "a request open: clicked once as the game opens it (Shift kept), answered 1 (%d clicks, done %ld)", clicks, g_shared->qcDone);
    Enter(mode);
    LONG handled = 0;
    ServeQuickcast(seq, 1, GetTickCount(), handled);
    CHECK(clicks == 1 && handled == seq && g_shared->qcAsked == 1, "the same request: no second click, by the hook or the worker (%d)", clicks);
    Ask(200);
    enterRet = 0; Enter(mode); enterRet = 1;
    CHECK(clicks == 1 && g_shared->qcDone != seq, "the game's Enter gave 0 (no target mode): no click, the request stays open");
    Enter(other);
    CHECK(clicks == 1, "another target mode object than the game UI's: no click");
    front = false; Enter(mode); front = true;
    CHECK(clicks == 1 && g_shared->qcDone != seq, "the game not in front: no click here (the worker answers 3)");
    ServeQuickcast(seq, 1, GetTickCount(), handled);
    CHECK(clicks == 2 && g_shared->qcDone == seq && handled == seq, "the worker's poll still clicks a request the hook didn't (a target mode already up)");
    Ask(0);
    Sleep(5);
    Enter(mode);
    CHECK(clicks == 2, "a request past its deadline: no click");
    g_shared->qcUntil = 0; Ask(200); g_shared->qcUntil = 0;
    Enter(mode);
    ServeQuickcast(seq, 0, GetTickCount(), handled);
    CHECK(clicks == 2 && g_shared->qcDone == seq && g_shared->qcResult == 2 && g_shared->qcCancelled == 1, "a request called off: no click, answered 2, counted as called off");
    // a fault in our part (the game UI's getter) never reaches the game: its Enter's result still returned
    g_getUi = (GetUiFn)nullptr; Ask(200);
    *(void **)&g_getUi = (void *)8;     // not code: faults
    r = Enter(mode);
    g_getUi = FakeGetUi;
    CHECK(r == 1 && clicks == 2, "the hook faulting: caught, the game's 1 returned, no click");
    // unload: the game's entry back; someone else's entry is left alone
    SwapTargetEnter(false);
    CHECK(!g_tmHooked && *Slot() == (DWORD)(img + RVA_TARGETMODE_ENTER), "off (unload): the game's Enter back in its slot");
    *Slot() = 0x12345678;
    CHECK(!SwapTargetEnter(true) && *Slot() == 0x12345678, "the slot isn't the game's (another mod): left as it is");
    Verdict();
    return g_fails;
}
