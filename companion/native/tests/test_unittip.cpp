// The name tip over the unit under the mouse hidden (layout 26), against a fake
// game image: CUnitTip's vtable entry +0x68 (its show) is swapped for ours, the
// game's show through it is dropped while on ([+0x90] left 0) and is the game's
// own again when off; an entry someone else changed is refused.
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, utOn) == offsetof(Shared, blGame) + 32 && offsetof(Shared, utState) == offsetof(Shared, utOn) + 4, "layout 26");

static BYTE *img;
static void Stub(DWORD rva, const void *fn) { img[rva - 1] = 0xCC; img[rva] = 0xE9; *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5)); }
static int shows;
static int __fastcall FakeShow(BYTE *f, int) { shows++; *(DWORD *)(f + 0x94) = 1; return 1; }
static void *__fastcall FakeGetUi(int, int) { return (void *)1; }

int main() {
    strcpy_s(g_logPath, "unittip.log"); DeleteFileA("unittip.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_SIMPLEFRAME_SHOW, FakeShow);
    DWORD *vt = (DWORD *)(img + RVA_UNITTIP_VT);
    for (int i = 0; i < 40; i++) vt[i] = (DWORD)(img + 0x100000);
    img[0x100000 - 1] = 0xCC; img[0x100000] = 0xC3;
    vt[UNITTIP_SHOW / 4] = (DWORD)(img + RVA_SIMPLEFRAME_SHOW);
    DWORD old; VirtualProtect(img + (RVA_UNITTIP_VT & ~0xfff), 0x1000, PAGE_READWRITE, &old);   // a vtable: data, as the game's
    static BYTE tip[0x150];
    *(DWORD *)tip = (DWORD)vt;
    g_getUi = FakeGetUi;
    // the game's own show, as +0x405be0 calls it: [+0x90] = 1, then vt+0x68
    auto gameShows = [&] { *(DWORD *)(tip + 0x90) = 1, *(DWORD *)(tip + 0x94) = 0; ((ShowFn)(*(DWORD **)tip)[UNITTIP_SHOW / 4])(tip, 0); };
    gameShows();
    CHECK(shows == 1 && *(DWORD *)(tip + 0x94) == 1, "off: the name tip shows (the game's show)");
    sh.utOn = 1; FollowUnitTip();
    CHECK(g_utHooked && sh.utState == 1 && vt[UNITTIP_SHOW / 4] == (DWORD)UnitTipShow, "on: CUnitTip's vtable +0x68 is ours");
    gameShows();
    CHECK(shows == 1 && *(DWORD *)(tip + 0x94) == 0 && *(DWORD *)(tip + 0x90) == 0, "a hover: the show is dropped, not wanted shown ([+0x90] 0)");
    sh.utOn = 0; FollowUnitTip();
    CHECK(!g_utHooked && sh.utState == 0 && vt[UNITTIP_SHOW / 4] == (DWORD)(img + RVA_SIMPLEFRAME_SHOW), "off: the entry is the game's show again");
    gameShows();
    CHECK(shows == 2 && *(DWORD *)(tip + 0x94) == 1, "and the tip shows again");
    sh.utOn = 1; vt[UNITTIP_SHOW / 4] = (DWORD)(img + 0x100000); FollowUnitTip();
    CHECK(!g_utHooked && sh.utState == 3, "an entry someone else changed: refused");
    Verdict();
    return g_fails;
}
