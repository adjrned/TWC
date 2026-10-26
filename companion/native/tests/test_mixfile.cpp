// Another widescreen mod in the game (RenderEdge_Widescreen's mix file: Detours
// jumps at the projection +0x1554f0 and the unit bar work +0x3c6700), against
// a fake game image: Widescreen leaves the projection to it (state 4, the call
// isn't touched) and bar size leaves the width to it (height only).
#include "../twc-game.cpp"
#include "check.h"

static BYTE *img, *other;
static void Jmp(BYTE *at, BYTE *to) { at[-1] = 0xCC; at[0] = 0xE9; *(LONG *)(at + 1) = (LONG)(to - (at + 5)); }

int main() {
    strcpy_s(g_logPath, "mixfile.log"); DeleteFileA("mixfile.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    other = (BYTE *)VirtualAlloc(nullptr, 0x1000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);   // "the mix file": outside the game
    g_base = img; g_imageSize = 0x1000000;
    other[0] = 0xC3;
    char who[64];
    CHECK(!ForeignDetour(RVA_PROJECTION, who, sizeof(who)), "the game's own bytes: no other mod");
    Jmp(img + RVA_PROJECTION, img + 0x500000);
    CHECK(!ForeignDetour(RVA_PROJECTION, who, sizeof(who)), "a jmp inside the game: not another mod");
    Jmp(img + RVA_PROJECTION, other);
    BYTE *site = img + RVA_PROJECTION_CALL;
    site[0] = 0xE8, *(LONG *)(site + 1) = (LONG)((img + RVA_PROJECTION) - (site + 5));
    CHECK(ForeignDetour(RVA_PROJECTION, who, sizeof(who)), "a jmp out of the game: another mod's hook (%s)", who);
    sh.wsOn = 1; WidescreenPass();
    CHECK(sh.wsState == 4 && !g_wsApplied && SiteTarget(site) == img + RVA_PROJECTION, "Widescreen with the mix file there: left to it (state 4), the camera's call untouched");
    sh.wsOn = 0; WidescreenPass();
    CHECK(sh.wsState == 0, "off: state 0");
    // health bars: the mix file's hook on the unit bar work narrows each bar after the game's
    // (so after our update hook): our multiplier comes first and the two add up
    Jmp(img + RVA_UNIT_BAR_WORK, other);
    DWORD old; VirtualProtect(img + 0xaad000, 0x1000, PAGE_READWRITE, &old);
    static BYTE bar[0x200];
    *(DWORD *)bar = (DWORD)(img + RVA_STATBAR_VTABLE); *(DWORD *)(bar + BAR_KIND) = 5;
    *(float *)(bar + BAR_HEIGHT) = 0.004f, *(float *)(bar + BAR_WIDTH) = 0.027f;    // narrowed by the mix file already
    img[RVA_LAYOUT_REFRESH - 1] = 0xCC, img[RVA_LAYOUT_REFRESH] = 0xC2, img[RVA_LAYOUT_REFRESH + 1] = 4, img[RVA_LAYOUT_REFRESH + 2] = 0;
    int r = SizeThisBar(bar, 0.65f, 0.65f, false);
    CHECK(r == 1 && *(float *)(bar + BAR_HEIGHT) == 0.004f * 0.65f && *(float *)(bar + BAR_WIDTH) == 0.027f,
          "an update outside the game's bar work: height x0.65 (%.4f), the width as it is (%.4f)", *(float *)(bar + BAR_HEIGHT), *(float *)(bar + BAR_WIDTH));
    *(float *)(bar + BAR_WIDTH) = 0.036f;                                         // the game's bar work: the unit's own width
    r = SizeThisBar(bar, 0.65f, 0.65f, true);
    CHECK(r == 1 && fabsf(*(float *)(bar + BAR_WIDTH) - 0.036f * 0.65f) < 1e-6f, "in the game's bar work: its width x0.65 (%.4f), before the mix file narrows it", *(float *)(bar + BAR_WIDTH));
    // the mana bars, sized in that same update, are narrowed as the mix file will narrow the health bar
    g_gameWnd = CreateWindowExA(0, "STATIC", "", WS_POPUP, 0, 0, 1600, 900, nullptr, nullptr, nullptr, nullptr);
    sh.mbWidth = 1;
    float a = ManaWidth(0.036f);
    g_barFresh = true;
    float b = ManaWidth(0.036f);
    g_barFresh = false;
    CHECK(a == 0.036f && fabsf(b - 0.036f / (0.75f * 1600 / 900)) < 1e-6f, "mana bar width: outside the bar work %.4f, in it %.4f (/ 0.75 x 16:9)", a, b);
    DestroyWindow(g_gameWnd), g_gameWnd = nullptr;
    Verdict();
    return g_fails;
}
