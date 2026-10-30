// The boss timers' feed (layout 36), against a fake game image: the 3 calls to the units' SPELL_EFFECT
// (+6b0fc0) pointed at ours while bcOn; an enemy's cast noted in bcRing (its type, the ability's rawcode,
// its HP then), yours and non-rawcodes not; the game's own always runs; the unit followed (bcWatch):
// its HP and whether it lives; off: the game's calls again; a call someone else changed: refused.
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, bcOn) == offsetof(Shared, bbUpState) + 4, "layout 36");

static BYTE *img;
static int effects;
static BYTE *objs[16];
static void *__fastcall FakeLookup(DWORD a, DWORD) { return a < 16 ? objs[a] : nullptr; }
static void __fastcall FakeStat(BYTE *at, int, float *out) { *out = *(float *)at; }   // the unit state +0x81b30
static void __fastcall FakeEffect(void *unit, int, void *ability) { effects++; }
static void Stub(DWORD rva, const void *fn) { img[rva - 1] = 0xCC, img[rva] = 0xE9, *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5)); }
// the game calling its SPELL_EFFECT from site i
static void Cast(int i, BYTE *unit, BYTE *ability) { ((SpellEffectFn)SiteTarget(img + BC_SITES[i]))(unit, 0, ability); }

int main() {
    strcpy_s(g_logPath, "bosscast.log"); DeleteFileA("bosscast.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_HANDLE_LOOKUP, FakeLookup), Stub(RVA_UNIT_HP, FakeStat), Stub(RVA_SPELL_EFFECT, FakeEffect);
    for (DWORD rva : BC_SITES)
        img[rva] = 0xE8, *(LONG *)(img + rva + 1) = (LONG)(img + RVA_SPELL_EFFECT - (img + rva + 5));
    // you: player 1 (no alliances); the boss: player 12's, 800 of 1000 HP (its max through handle 2)
    static BYTE state[0x200], players[16][0x300], boss[0x300], mine[0x300], maxObj[0x100], abl[0x100];
    *(BYTE **)(img + RVA_PLAYERS) = state, *(short *)(state + 0x28) = 1, *(int *)(state + 0x54) = 16;
    for (int i = 0; i < 16; i++)
        *(BYTE **)(state + 0x58 + i * 4) = players[i];
    for (BYTE *u : { boss, mine })
        *(DWORD *)u = (DWORD)(img + RVA_UNIT_VT), ((DWORD *)(u + UNIT_MAXHP_HANDLE))[0] = ((DWORD *)(u + UNIT_MAXHP_HANDLE))[1] = 2;
    *(int *)(boss + UNIT_OWNER) = 12, *(DWORD *)(boss + 0x30) = 'Nbos', *(float *)(boss + UNIT_HP) = 800;
    *(int *)(mine + UNIT_OWNER) = 1, *(DWORD *)(mine + 0x30) = 'Hpal', *(float *)(mine + UNIT_HP) = 500;
    objs[2] = maxObj, *(float *)(maxObj + 0x84) = 1000;
    *(DWORD *)(abl + 0x34) = 'A0MT';
    g_getUi = [](int, int) -> void * { return (void *)1; };

    Cast(0, boss, abl);
    CHECK(effects == 1 && !sh.bcSeq && SiteTarget(img + BC_SITES[0]) == img + RVA_SPELL_EFFECT, "off: the game's SPELL_EFFECT, nothing noted");
    sh.bcOn = 1; BossCastPass();
    bool ours = g_bcHooked && sh.bcState == 1;
    for (DWORD rva : BC_SITES)
        ours = ours && SiteTarget(img + rva) == (BYTE *)BossCastHook;
    CHECK(ours, "on: the 3 calls (+42CD27, +43F4A4, +595A76) are ours");
    Cast(1, boss, abl);
    const BcCast &c = sh.bcRing[0];
    CHECK(effects == 2 && sh.bcSeq == 1 && c.unit == (DWORD)boss && c.unitType == 'Nbos' && c.ability == 'A0MT' && c.hp == 800 && c.hpMax == 1000 && c.owner == 12 && c.at,
          "an enemy's cast: noted (its type, 'A0MT', 800 of 1000 HP, player 12), then the game's own");
    Cast(2, mine, abl);
    *(DWORD *)(abl + 0x34) = 0x12; Cast(0, boss, abl); *(DWORD *)(abl + 0x34) = 'A0MT';
    CHECK(effects == 4 && sh.bcSeq == 1, "yours, or an ability id that isn't a rawcode: not noted (the game's own all the same)");
    bool named = false;
    for (int i = 0; i < g_dmPendN; i++)
        named |= g_dmPend[i] == 'A0MT';
    CHECK(named, "its ability waits to be named with the meter's names (the game thread's pass)");
    sh.bcWatch = (DWORD)boss; BossCastPass();
    bool live = sh.bcWatchAlive == 1 && sh.bcWatchHp == 800 && sh.bcWatchMax == 1000;
    *(float *)(boss + UNIT_HP) = 0; BossCastPass();
    bool dead = !sh.bcWatchAlive && !sh.bcWatchHp;
    *(DWORD *)boss = 0; BossCastPass();
    CHECK(live && dead && !sh.bcWatchAlive, "the unit followed: 800 of 1000, alive; at 0 HP: dead; no longer a unit: gone");
    sh.bcOn = 0; BossCastPass();
    bool back = !g_bcHooked && sh.bcState == 0;
    for (DWORD rva : BC_SITES)
        back = back && SiteTarget(img + rva) == img + RVA_SPELL_EFFECT;
    CHECK(back, "off: the calls are the game's again");
    *(LONG *)(img + BC_SITES[2] + 1) += 0x40;          // another mod's call there
    sh.bcOn = 1; BossCastPass();
    CHECK(!g_bcHooked && g_bcBad && sh.bcState == 3 && SiteTarget(img + BC_SITES[0]) == img + RVA_SPELL_EFFECT, "a call someone else changed: refused, none of them touched");
    Verdict();
    return g_fails;
}
