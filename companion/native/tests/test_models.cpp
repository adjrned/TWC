// The widescreen UI's model squeeze (WFE's 0x1008bfd0 / 0x10035390), against
// fake model frames: a frame's first sprite gets diag(0.725, 1, 1) (the clock
// 0.75), a second pass is the same, a turned model is left alone, and putting
// back writes the saved matrix only into a sprite the frame still holds.
#include "../twc-game.cpp"
#include "check.h"
static BYTE *img;
static BYTE ui[0x500], card[0x200], rows[3][16], btn[0x300], frame[4][0x200], spr[4][0x200], tod[0x200], tspr[0x200], other[0x200];
static BYTE *cardBtns[4], *lists[6][1];
static BYTE menu[0x200], quest[0x200], qspr[0x200];
static float *M(BYTE *s, DWORD off) { return (float *)(s + off); }
static void Frame(BYTE *f, BYTE *s, DWORD svt, int k) {
    *(DWORD *)f = (DWORD)(img + 0xa7ac24); *(int *)(f + 0x174) = 1; lists[k][0] = s; *(BYTE ***)(f + 0x178) = lists[k];
    *(DWORD *)s = (DWORD)(img + svt);
}
static void Identity(float *m, float k) { for (int i = 0; i < 9; i++) m[i] = i % 4 == 0 ? k : 0; }

int main() {
    strcpy_s(g_logPath, "models.log"); DeleteFileA("models.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    DWORD old; VirtualProtect(img + 0xa7a000, 0x10000, PAGE_READWRITE, &old); VirtualProtect(img + 0xaa0000, 0x20000, PAGE_READWRITE, &old);
    *(DWORD *)ui = (DWORD)(img + RVA_UI_VTABLE);
    *(BYTE **)(ui + 0x3c8) = card; *(DWORD *)card = (DWORD)(img + 0xaad000); *(int *)(card + 0x124) = 1; *(int *)(card + 0x128) = 1;
    *(BYTE **)(card + 0x154) = rows[0]; *(DWORD *)(rows[0] + 4) = 1; *(BYTE ***)(rows[0] + 8) = cardBtns; cardBtns[0] = btn;
    *(DWORD *)btn = (DWORD)(img + RVA_COMMAND_BUTTON_VTABLE);
    Frame(frame[0], spr[0], RVA_SPRITE_MINI_VT[0], 0); *(BYTE **)(btn + 0x19c) = frame[0];     // the cooldown sweep: a mini sprite
    Frame(frame[1], spr[1], RVA_SPRITE_UBER_VT[1], 1); *(BYTE **)(btn + 0x1a8) = frame[1];     // autocast: an uber one
    Identity(M(spr[0], 0x64), 1); Identity(M(spr[1], 0x108), 0.9f);
    Frame(tod, tspr, RVA_SPRITE_MINI_VT[1], 2); *(BYTE **)(ui + 0x3f8) = tod; Identity(M(tspr, 0x64), 1);
    UlModels(ui, ui + 0xb4);
    float *a = M(spr[0], 0x64), *b = M(spr[1], 0x108), *t = M(tspr, 0x64);
    CHECK(g_ulModelN == 3 && a[0] == 0.725f && a[4] == 1 && a[8] == 1 && b[0] == 0.725f && b[4] == 1 && t[0] == 0.75f,
          "the sweep (mini, +0x64), autocast (uber, +0x108) and the clock squeezed: %.3f %.3f %.3f (%d saved)", a[0], b[0], t[0], g_ulModelN);
    a[0] = 1; UlModels(ui, ui + 0xb4);
    CHECK(g_ulModelN == 3 && a[0] == 0.725f && g_ulModelResets == 1, "the game put one back: squeezed again, nothing saved twice");
    // a turned model: left alone
    Frame(frame[2], spr[2], RVA_SPRITE_MINI_VT[0], 3); Identity(M(spr[2], 0x64), 1); M(spr[2], 0x64)[1] = 0.5f;
    *(BYTE **)(btn + 0x1a8) = frame[2]; UlModels(ui, ui + 0xb4);
    CHECK(g_ulModelN == 3 && M(spr[2], 0x64)[0] == 1, "a turned model: left alone");
    // an unknown sprite kind: left alone
    Frame(frame[3], spr[3], 0xa7b000, 4); Identity(M(spr[3], 0x64), 1); *(BYTE **)(btn + 0x1a8) = frame[3]; UlModels(ui, ui + 0xb4);
    CHECK(g_ulModelN == 3 && M(spr[3], 0x64)[0] == 1, "a sprite of another kind: left alone");
    // put back: into the sprites still held; the autocast frame's sprite changed, so not that one
    lists[1][0] = other; *(DWORD *)other = (DWORD)(img + RVA_SPRITE_UBER_VT[0]); Identity(M(other, 0x108), 2);
    UlModelsRestore();
    CHECK(g_ulModelN == 0 && a[0] == 1 && t[0] == 1 && b[0] == 0.725f && M(other, 0x108)[0] == 2, "put back: the sweep and clock; a frame holding another sprite now isn't written");
    // the cooldown clock hidden (cdNoBadge bit 2): the sweep flattened, kept so, the Widescreen UI's squeeze leaves it, put back
    *(BYTE **)(btn + 0x1a8) = nullptr;
    SweepsPass(ui, true);
    bool flat = a[0] == 0 && a[4] == 1 && g_sweepN == 1;
    a[0] = 1; SweepsPass(ui, true);
    bool again = a[0] == 0 && g_sweepN == 1;
    UlModels(ui, ui + 0xb4);
    bool leftAlone = a[0] == 0;
    SweepsPass(ui, false);
    CHECK(flat && again && leftAlone && a[0] == 1 && g_sweepN == 0, "the clock: flattened (x 0), again after the game resets it, not squeezed by the Widescreen UI meanwhile, put back to 1");
    // hidden over a Widescreen UI squeeze: put back to the matrix the squeeze found, which it then squeezes again
    UlModels(ui, ui + 0xb4); SweepsPass(ui, true); SweepsPass(ui, false);
    CHECK(a[0] == 1, "over the Widescreen UI's squeeze: put back to its original (%.3f)", a[0]);
    Verdict();
    return g_fails;
}
