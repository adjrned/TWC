#include "../twc-game.cpp"
#include "check.h"
static void *fakeUi; static void *__fastcall FakeGetUi(int, int) { return fakeUi; }
int main() {
    strcpy_s(g_logPath, "colours.log"); DeleteFileA("colours.log");
    static Shared sh; g_shared = &sh;
    BYTE *img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    DWORD *cnt = (DWORD *)(img + 0x200000 - 32);     // counters: [0] game updates, [1] colour redraws
    // game's bar update at +0x100000: inc [cnt0]; ret 4
    BYTE upd[] = { 0xFF, 0x05, 0,0,0,0, 0xC2, 0x04, 0x00 }; *(DWORD *)(upd + 2) = (DWORD)&cnt[0]; memcpy(img + 0x100000, upd, sizeof(upd));
    // fill redraw at +0x100100: inc [cnt1]; ret
    BYTE red[] = { 0xFF, 0x05, 0,0,0,0, 0xC3 }; *(DWORD *)(red + 2) = (DWORD)&cnt[1]; memcpy(img + 0x100100, red, sizeof(red));
    // handle lookup at +0x7e090: mov eax, <flags obj>; ret
    static BYTE flagsObj[0x100]; BYTE lk[] = { 0xB8, 0,0,0,0, 0xC3 }; *(DWORD *)(lk + 1) = (DWORD)flagsObj; memcpy(img + RVA_HANDLE_LOOKUP, lk, sizeof(lk));
    // hp getter at +0x81b30: mov eax,[esp+4]; mov dword [eax], 25.0f; ret 4
    BYTE hp[] = { 0x8B, 0x44, 0x24, 0x04, 0xC7, 0x00, 0,0,0,0, 0xC2, 0x04, 0x00 }; float h25 = 25; memcpy(hp + 6, &h25, 4); memcpy(img + RVA_UNIT_HP, hp, sizeof(hp));
    *(float *)(flagsObj + 0x84) = 100;               // max hp
    *(DWORD *)(flagsObj + 0x78) = 1u << 2;           // the local player is allied with slot 2
    DWORD old; VirtualProtect(img + 0xaad000, 0x1000, PAGE_READONLY, &old);   // the vtable: read-only data
    DWORD *vt = (DWORD *)(img + RVA_STATBAR_VTABLE);
    { DWORD o2; VirtualProtect(vt, 0x100, PAGE_READWRITE, &o2); vt[STATBAR_UPDATE / 4] = (DWORD)(img + 0x100000); VirtualProtect(vt, 0x100, PAGE_READONLY, &o2); }
    VirtualProtect(img + 0xd30000, 0x3000, PAGE_READWRITE, &old);
    static BYTE state[0x200], players[16][0x40], allyH[0x60], fillVt[0x40];
    *(BYTE **)(img + RVA_PLAYERS) = (BYTE *)&state; static BYTE *stateP = state; *(BYTE ***)(img + RVA_PLAYERS) = &stateP;
    *(short *)(state + 0x28) = 1;                    // local player 1
    for (int i = 0; i < 16; i++) { *(BYTE **)(state + 0x58 + i * 4) = players[i]; players[i][0x30] = (BYTE)i; }
    *(BYTE **)(players[1] + 0x38) = allyH; ((DWORD *)(allyH + 0x40))[0] = 5, ((DWORD *)(allyH + 0x40))[1] = 6;
    *(DWORD *)(fillVt + 0x24) = (DWORD)(img + 0x100100);
    static BYTE units[5][0x100], bars[5][0x160], fills[5][0x80];
    int owners[5] = { 1, 2, 3, 12, 15 };
    for (int i = 0; i < 5; i++) {
        *(int *)(units[i] + UNIT_OWNER) = owners[i]; ((DWORD *)(units[i] + UNIT_MAXHP_HANDLE))[0] = 7, ((DWORD *)(units[i] + UNIT_MAXHP_HANDLE))[1] = 8;
        *(DWORD *)bars[i] = (DWORD)vt; *(DWORD *)(bars[i] + BAR_KIND) = 5; *(BYTE **)(bars[i] + BAR_FILL) = fills[i]; *(BYTE **)(bars[i] + BAR_UNIT) = units[i];
        *(DWORD *)fills[i] = (DWORD)fillVt;
    }
    fakeUi = nullptr; g_getUi = FakeGetUi;
    DWORD cols[5] = { 0xFF00FF00, 0xFF0080FF, 0xFFFF0000, 0xFFFF8000, 0xFF808080 };
    memcpy(g_shared->hcColours, cols, sizeof(cols));
    auto update = [&](int i) { ((BarUpdateFn)vt[STATBAR_UPDATE / 4])(bars[i], 0, units[i]); };
    auto argb = [&](int i) { BYTE *f = fills[i]; return ((DWORD)f[0x68] << 24) | ((DWORD)f[0x6b] << 16) | ((DWORD)f[0x6a] << 8) | f[0x69]; };
    g_shared->hcOn = 1; g_shared->hcMode = 0; FollowColours();
    CHECK(vt[STATBAR_UPDATE / 4] == (DWORD)BarUpdateHook && g_shared->hcState == 1, "on: the vtable entry is the hook, state %lu", g_shared->hcState);
    for (int i = 0; i < 5; i++) update(i);
    CHECK(argb(0) == 0xFF00FF00 && argb(1) == 0xFF0080FF && argb(2) == 0xFFFF0000 && argb(3) == 0xFFFF8000 && argb(4) == 0xFF808080 && cnt[0] == 5 && cnt[1] == 5,
        "by owner: %08lX %08lX %08lX %08lX %08lX; game updates %lu, redraws %lu", argb(0), argb(1), argb(2), argb(3), argb(4), cnt[0], cnt[1]);
    g_shared->hcMode = 1; update(2);
    CHECK(argb(2) == 0xFFFF7F00, "by health 25%%: %08lX", argb(2));
    g_shared->hcOn = 0; FollowColours();
    CHECK(vt[STATBAR_UPDATE / 4] == (DWORD)(img + 0x100000) && g_shared->hcState == 0, "off: the entry is the game's again, state %lu", g_shared->hcState);
    DWORD before = cnt[1]; update(0);
    CHECK(cnt[0] == 7 && cnt[1] == before, "after off: the game's update runs (%lu), no colour redraw", cnt[0]);
    Verdict();
    return g_fails;
}
