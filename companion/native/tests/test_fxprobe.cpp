// The effect probe (layout 37), against a fake game image: the map's ground-effect entry (+229e60) and
// DestroyEffect (+22f800) detoured while fxOn (the game's own still runs, its handle passed back); an effect
// within 1000 of your hero logged with its offset and the time since your hero's cast (seen through the
// SPELL_EFFECT calls), one far away not; its end with where the hero was; off: the game's code again.
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, fxOn) == offsetof(Shared, bcWatchAlive) + 4, "layout 37");

static BYTE *img;
static BYTE *objs[16];
static void *__fastcall FakeLookup(DWORD a, DWORD) { return a < 16 ? objs[a] : nullptr; }
static float heroX = 1000, heroY = 2000;
// +082460: thiscall(position, float *xyz), ret 4 (the hero's place)
static void __fastcall FakePosition(BYTE *, int, float *out) { out[0] = heroX, out[1] = heroY, out[2] = 0; }
static int adds, dels;
static DWORD __cdecl FakeAdd(const char *, float *, float *) { return 100 + ++adds; }
static void __cdecl FakeDel(DWORD) { dels++; }
static void __fastcall FakeEffect(void *, int, void *) {}
static void Stub(DWORD rva, const void *fn) { img[rva - 1] = 0xCC, img[rva] = 0xE9, *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5)); }
static bool LogHas(const char *s) {
    FILE *f;
    if (fopen_s(&f, "fxprobe.log", "rb"))
        return false;
    static char buf[1 << 16];
    size_t n = fread(buf, 1, sizeof(buf) - 1, f);
    fclose(f);
    buf[n] = 0;
    return strstr(buf, s) != nullptr;
}

int main() {
    strcpy_s(g_logPath, "fxprobe.log"); DeleteFileA("fxprobe.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_HANDLE_LOOKUP, FakeLookup), Stub(RVA_UNIT_POSITION, FakePosition), Stub(RVA_SPELL_EFFECT, FakeEffect);
    memcpy(img + RVA_EFFECT_ADD - 1, "\xCC\x55\x8B\xEC\x8B\x55\x10\x5D\xE9", 9);      // as 1.28f starts it, then pop ebp and on to the fake
    *(LONG *)(img + RVA_EFFECT_ADD + 8) = (LONG)((BYTE *)FakeAdd - (img + RVA_EFFECT_ADD + 12));
    memcpy(img + RVA_EFFECT_DESTROY - 1, "\xCC\x55\x8B\xEC\x8B\x4D\x08\x5D\xE9", 9);
    *(LONG *)(img + RVA_EFFECT_DESTROY + 8) = (LONG)((BYTE *)FakeDel - (img + RVA_EFFECT_DESTROY + 12));
    for (DWORD rva : BC_SITES)
        img[rva] = 0xE8, *(LONG *)(img + rva + 1) = (LONG)(img + RVA_SPELL_EFFECT - (img + rva + 5));
    // you: player 1, your hero selected (its handle 3 alive)
    static BYTE state[0x200], players[16][0x300], sel[0x200], hero[0x300], handle[0x80], abl[0x100];
    *(BYTE **)(img + RVA_PLAYERS) = state, *(short *)(state + 0x28) = 1, *(int *)(state + 0x54) = 16;
    for (int i = 0; i < 16; i++)
        *(BYTE **)(state + 0x58 + i * 4) = players[i];
    *(BYTE **)(players[1] + SEL_PLAYER_SELECTION) = sel, *(BYTE **)(sel + SEL_ACTIVE) = hero;
    *(DWORD *)hero = (DWORD)(img + RVA_UNIT_VT), *(int *)(hero + UNIT_OWNER) = 1, *(DWORD *)(hero + 0x30) = 'Hlm1';
    ((DWORD *)(hero + AGENT_HANDLE))[0] = ((DWORD *)(hero + AGENT_HANDLE))[1] = 3;
    objs[3] = handle, *(BYTE **)(handle + HANDLE_OBJ) = hero, *(DWORD *)(handle + HANDLE_TAG) = '+agl';
    *(DWORD *)(abl + 0x34) = 'A0LD';
    g_getUi = [](int, int) -> void * { return (void *)1; };

    float x = 1100, y = 1950;
    DWORD h0 = ((EffectAddFn)(img + RVA_EFFECT_ADD))("x", &x, &y);
    CHECK(h0 == 101 && !g_fxAdd.on && !LogHas("effect probe:"), "off: the game's own entry, nothing noted");
    sh.fxOn = 1; FxProbePass(); BossCastPass();
    CHECK(g_fxAdd.on && g_fxDel.on && sh.fxState == 1 && img[RVA_EFFECT_ADD] == 0xE9 && img[RVA_EFFECT_DESTROY] == 0xE9 && g_bcHooked,
          "on: +229E60 and +22F800 detoured (and the SPELL_EFFECT calls, for your hero's casts)");
    ((SpellEffectFn)SiteTarget(img + BC_SITES[0]))(hero, 0, abl);
    Sleep(30);
    DWORD h1 = ((EffectAddFn)(img + RVA_EFFECT_ADD))("Abilities\\Spells\\Orb\\LightningOrb.mdl", &x, &y);
    float fx = 9000, fy = 9000;
    DWORD h2 = ((EffectAddFn)(img + RVA_EFFECT_ADD))("Far.mdl", &fx, &fy);
    CHECK(h1 == 102 && h2 == 103 && LogHas("your hero cast 'A0LD' at (1000, 2000)") && LogHas("'LightningOrb.mdl' made +100, -50 from your hero (handle 102;")
          && LogHas("ms after its 'A0LD'") && !LogHas("'Far.mdl'"), "an orb near the hero: its model, +100, -50 from it, after its 'A0LD'; one 8000 away: not logged; the handles passed back");
    heroX = 1090, heroY = 1955;
    ((EffectDestroyFn)(img + RVA_EFFECT_DESTROY))(h1);
    ((EffectDestroyFn)(img + RVA_EFFECT_DESTROY))(h2);
    CHECK(dels == 2 && LogHas("'LightningOrb.mdl' (handle 102) gone after") && LogHas("your hero 11 from it (-10, +5)"), "its end: the hero 11 from it then; the game's own DestroyEffect each time");
    sh.fxOn = 0; FxProbePass();
    CHECK(!g_fxAdd.on && !g_fxDel.on && !memcmp(img + RVA_EFFECT_ADD, "\x55\x8B\xEC\x8B\x55\x10", 6) && !memcmp(img + RVA_EFFECT_DESTROY, "\x55\x8B\xEC\x8B\x4D\x08", 6) && sh.fxState == 0,
          "off: both entries as the game's again");
    img[RVA_EFFECT_DESTROY] = 0xE9;             // another mod's
    sh.fxOn = 1; FxProbePass();
    CHECK(!g_fxAdd.on && !g_fxDel.on && g_fxBad && sh.fxState == 3 && !memcmp(img + RVA_EFFECT_ADD, "\x55\x8B\xEC\x8B\x55\x10", 6), "an entry someone else changed: refused, neither left detoured");
    Verdict();
    return g_fails;
}
