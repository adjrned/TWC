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
    // health bars: the mix file's hook on the unit bar work -> only the height is ours
    Jmp(img + RVA_UNIT_BAR_WORK, other);
    DWORD old; VirtualProtect(img + 0xaad000, 0x1000, PAGE_READWRITE, &old);
    static BYTE bar[0x200];
    *(DWORD *)bar = (DWORD)(img + RVA_STATBAR_VTABLE); *(DWORD *)(bar + BAR_KIND) = 5;
    *(float *)(bar + BAR_HEIGHT) = 0.004f, *(float *)(bar + BAR_WIDTH) = 0.027f;    // the mix file's narrower width
    img[RVA_LAYOUT_REFRESH - 1] = 0xCC, img[RVA_LAYOUT_REFRESH] = 0xC2, img[RVA_LAYOUT_REFRESH + 1] = 4, img[RVA_LAYOUT_REFRESH + 2] = 0;
    int r = SizeThisBar(bar, 0.65f, 0.65f);
    CHECK(r == 1 && *(float *)(bar + BAR_HEIGHT) == 0.004f * 0.65f && *(float *)(bar + BAR_WIDTH) == 0.027f,
          "bar size with the mix file's bar hook: height x0.65 (%.4f), the width left as it set it (%.4f)", *(float *)(bar + BAR_HEIGHT), *(float *)(bar + BAR_WIDTH));
    Verdict();
    return g_fails;
}
