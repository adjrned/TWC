// The portrait's HP / mana lines with regen, against a fake game image: the
// update entry is found in the CPortraitButton vtable and wrapped, the game's
// own update still runs first, its two font strings get the full lines, and
// turning it off gives the entry back.
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, prOn) == 780 && sizeof(Shared) == 804, "layout 13");

static BYTE *img;
static void Stub(DWORD rva, const void *fn) {
    img[rva - 1] = 0xCC;
    img[rva] = 0xE9;
    *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5));
}
static int updates, sets;
static char lastSet[2][128];
static BYTE *strs[2];
static void __fastcall FakeUpdate(BYTE *, int) { updates++; }
static void __fastcall FakeSet(BYTE *fs, int, const char *t) { sets++; strcpy_s(lastSet[fs == strs[1]], t); }
static void __fastcall FakeState(float *st, int, float *out) { *out = *st; }
static void *__fastcall FakeLookup(DWORD a, DWORD) { return (void *)a; }
static void *__fastcall FakeGetUi(int, int) { return nullptr; }

int main() {
    strcpy_s(g_logPath, "portrait.log"); DeleteFileA("portrait.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_PORTRAIT_UPDATE, FakeUpdate); Stub(RVA_FONTSTRING_SET, FakeSet); Stub(RVA_UNIT_HP, FakeState); Stub(RVA_HANDLE_LOOKUP, FakeLookup);
    DWORD *pv = (DWORD *)(img + RVA_PORTRAIT_VTABLE), *fv = (DWORD *)(img + RVA_FONTSTRING_VTABLE);
    for (int i = 0; i < 64; i++) pv[i] = (DWORD)(img + 0x100000), fv[i] = (DWORD)(img + 0x100000);
    pv[0x30 / 4] = (DWORD)(img + RVA_PORTRAIT_UPDATE);
    DWORD old;
    VirtualProtect(img + 0xab0000, 0x1000, PAGE_READWRITE, &old); VirtualProtect(img + 0xa7d000, 0x1000, PAGE_READWRITE, &old);
    static BYTE portrait[0x300], unit[0x200], hpObj[0x100], mpObj[0x100], s0[0x100], s1[0x100];
    strs[0] = s0, strs[1] = s1;
    *(DWORD *)portrait = (DWORD)pv; *(DWORD *)s0 = (DWORD)fv; *(DWORD *)s1 = (DWORD)fv;
    *(BYTE **)(portrait + PORTRAIT_UNIT) = unit; *(BYTE **)(portrait + PORTRAIT_HP) = s0; *(BYTE **)(portrait + PORTRAIT_MP) = s1;
    *(float *)(unit + UNIT_HP) = 249.6f; *(float *)(hpObj + 0x84) = 500; *(float *)(hpObj + STAT_REGEN) = 1.5f;
    *(float *)(unit + UNIT_MANA) = 30; *(float *)(mpObj + 0x84) = 120; *(float *)(mpObj + STAT_REGEN) = -0.75f;
    ((DWORD *)(unit + UNIT_MAXHP_HANDLE))[0] = (DWORD)hpObj, ((DWORD *)(unit + UNIT_MAXHP_HANDLE))[1] = 1;
    ((DWORD *)(unit + UNIT_MAXMANA_HANDLE))[0] = (DWORD)mpObj, ((DWORD *)(unit + UNIT_MAXMANA_HANDLE))[1] = 1;
    static BYTE ui[0x400]; *(BYTE **)(ui + UI_PORTRAIT) = portrait;
    g_getUi = FakeGetUi; g_ui = ui;         // it looks once a game is on
    auto update = [&] { ((PortraitFn)pv[0x30 / 4])(portrait, 0); };
    update();
    CHECK(updates == 1 && sets == 0, "off: the game's update alone");
    sh.prOn = 1; FollowPortrait();
    CHECK(g_portraitSlot == pv + 0x30 / 4 && pv[0x30 / 4] == (DWORD)PortraitHook && g_portraitHooked, "on: the entry found (+0x30) and wrapped");
    update();
    CHECK(updates == 2 && !strcmp(lastSet[0], "250 / 500 |cFF40E040+1.5|r") && !strcmp(lastSet[1], "30 / 120 |cFFE04040-0.8|r"), "the game's update, then the lines: \"%s\", \"%s\"", lastSet[0], lastSet[1]);
    sh.prMode = 1; *(float *)(hpObj + STAT_REGEN) = 0; update();
    CHECK(!strcmp(lastSet[0], "250 / 500 (50%)"), "percent, no regen: \"%s\"", lastSet[0]);
    *(float *)(mpObj + 0x84) = 0; int before = sets; update();
    CHECK(sets == before + 1, "a unit without mana: its mana line is left to the game");
    *(DWORD *)s0 = (DWORD)pv; before = sets; update();
    CHECK(sets == before, "a line that isn't a font string: not written");
    *(BYTE **)(portrait + PORTRAIT_UNIT) = nullptr; before = sets; update();
    CHECK(sets == before && updates == 6, "no unit: nothing written, the game's update still runs");
    sh.prOn = 0; FollowPortrait();
    CHECK(pv[0x30 / 4] == (DWORD)(img + RVA_PORTRAIT_UPDATE) && !g_portraitHooked && sh.prState == 0, "off: the entry is the game's again");

    // 1.28f: not in the vtable, called directly: its call site is pointed at the hook (on the game thread)
    pv[0x30 / 4] = (DWORD)(img + 0x100000); g_portraitSlot = nullptr;
    BYTE caller[] = { 0xE8, 0, 0, 0, 0, 0xC3 };   // call update; ret
    memcpy(img + 0x200000, caller, sizeof(caller)); *(LONG *)(img + 0x200001) = (LONG)(RVA_PORTRAIT_UPDATE - 0x200005);
    sh.prOn = 1; sh.prMode = 0; *(float *)(hpObj + STAT_REGEN) = 2; *(float *)(mpObj + 0x84) = 120;
    *(DWORD *)s0 = (DWORD)fv; *(BYTE **)(portrait + PORTRAIT_UNIT) = unit;
    FollowPortrait();
    CHECK(!g_portraitSlot && g_prSites == 1 && g_prSite[0] == img + 0x200000 && !g_portraitHooked, "not in the vtable: its one call site found, nothing written yet");
    PortraitSitesPass();
    CHECK(SiteTarget(img + 0x200000) == (BYTE *)PortraitHook && g_portraitHooked, "the game thread points the call at the hook");
    int u = updates; ((PortraitFn)(img + 0x200000))(portrait, 0);
    CHECK(updates == u + 1 && !strcmp(lastSet[0], "250 / 500 |cFF40E040+2.0|r"), "through the call site: the game's update, then the line \"%s\"", lastSet[0]);
    sh.prOn = 0; FollowPortrait(); PortraitSitesPass();
    CHECK(SiteTarget(img + 0x200000) == img + RVA_PORTRAIT_UPDATE && !g_portraitHooked && sh.prState == 0, "off: the call goes to the game's update again");
    Verdict();
    return g_fails;
}
