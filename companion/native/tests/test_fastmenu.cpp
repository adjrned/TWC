// Fast menus (layout 16), against a fake game image: the menu animation
// +0x33a790 (its real first 6 bytes, then a body returning 1.5 s) is detoured,
// the game's own function still runs (through the copy of its first bytes),
// the glue's two backdrop models get speed 100 and the menu waits 0.01 s;
// off puts the bytes back and the speed to 1; changed bytes are refused.
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, fmOn) == 824 && offsetof(Shared, fmState) == 828 && sizeof(Shared) >= 832, "layout 16");

static BYTE *img;
static float gameTime = 1.5f;
static BYTE glue[0x200], frames[2][0x200], sprites[2][0x200], *lists[2][1];
typedef float(__fastcall *Anim)(DWORD, DWORD, DWORD, DWORD, DWORD, DWORD);

int main() {
    strcpy_s(g_logPath, "fastmenu.log"); DeleteFileA("fastmenu.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    BYTE *f = img + RVA_MENU_ANIM;
    static const BYTE body[] = { 0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x18,   // the game's own start
        0xD9, 0x05, 0, 0, 0, 0,                                         // fld dword [gameTime]
        0x8B, 0xE5, 0x5D, 0xC2, 0x10, 0x00 };                           // mov esp, ebp; pop ebp; ret 0x10
    f[-1] = 0xCC; memcpy(f, body, sizeof(body)); *(float **)(f + 8) = &gameTime;
    DWORD old; VirtualProtect(img + 0xa7a000, 0x16000, PAGE_READWRITE, &old);
    *(BYTE **)(img + DATA_GLUE) = glue;
    for (int i = 0; i < 2; i++) {
        *(DWORD *)frames[i] = (DWORD)(img + 0xa7ac24); *(int *)(frames[i] + 0x174) = 1; lists[i][0] = sprites[i]; *(BYTE ***)(frames[i] + 0x178) = lists[i];
        *(DWORD *)sprites[i] = (DWORD)(img + 0xa8266c); *(float *)(sprites[i] + SPRITE_SPEED) = 1;
        *(BYTE **)(glue + GLUE_MODELS + i * 4) = frames[i];
    }
    Anim call = (Anim)f;
    CHECK(call(4, 0, 0, 0, 0, 0) == 1.5f, "off: the game's own time (1.5 s)");
    sh.fmOn = 1; FastMenuPass();
    CHECK(g_fmHooked && sh.fmState == 1 && f[0] == 0xE9 && f[5] == 0x90, "on: its start detoured (E9 rel32, 90)");
    float t = call(4, 0, 0, 0, 0, 0);
    CHECK(t == FAST_MENU_TIME && *(float *)(sprites[0] + SPRITE_SPEED) == 100 && *(float *)(sprites[1] + SPRITE_SPEED) == 100,
          "a transition: the game's function ran, the two backdrop models at speed 100, the menu waits %.2f s", t);
    sh.fmOn = 0; FastMenuPass();
    CHECK(!g_fmHooked && sh.fmState == 0 && !memcmp(f, body, 6) && *(float *)(sprites[0] + SPRITE_SPEED) == 1 && call(4, 0, 0, 0, 0, 0) == 1.5f,
          "off: the bytes back, the models at speed 1, the game's own time again");
    f[2] = 0x90; sh.fmOn = 1; FastMenuPass();
    CHECK(!g_fmHooked && sh.fmState == 3 && f[0] == 0x55, "bytes that aren't the game's: refused, nothing written");
    Verdict();
    return g_fails;
}
