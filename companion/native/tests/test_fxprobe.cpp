// The effect probe (layout 37), against a fake game image: the map's ground / attached effects, the units
// it makes, RemoveUnit / KillUnit detoured while fxOn (the game's own still runs, its results passed back);
// an effect gone at once only counted, one that stays logged after 300 ms and when it goes (where the hero
// was); a unit made near the hero logged, its end (removed, or gone by itself, seen by the pass); your
// hero's casts by name; off: the game's code again; an entry someone else changed: refused.
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, fxOn) == offsetof(Shared, bcWatchAlive) + 4, "layout 37");

static BYTE *img;
static BYTE *objs[16];
static void *__fastcall FakeLookup(DWORD a, DWORD) { return a < 16 ? objs[a] : nullptr; }
static void __fastcall FakeStat(BYTE *at, int, float *out) { *out = *(float *)at; }
// +082460: thiscall(position, float *xyz), ret 4: the unit's place kept at its +0x200 (the position is [unit+0x164])
static void __fastcall FakePosition(BYTE *pos, int, float *out) { BYTE *u = pos - UNIT_POSITION; out[0] = *(float *)(u + 0x200), out[1] = *(float *)(u + 0x204), out[2] = 0; }
static int adds, dels, removes;
static DWORD __cdecl FakeAdd(const char *, float *, float *) { return 100 + ++adds; }
static DWORD __cdecl FakeAttach(const char *, DWORD, DWORD) { return 200 + ++adds; }
static void __cdecl FakeDel(DWORD) { dels++; }
static void __cdecl FakeRemove(DWORD) { removes++; }
static BYTE units[3][0x300];               // 0 your hero, 1 an orb dummy, 2 one far away
static BYTE *__fastcall FakeCreate(int slot, DWORD type, float *x, float *y, float *) {
    BYTE *u = units[type == 'h0OB' ? 1 : 2];
    *(DWORD *)(u + 0x30) = type, *(int *)(u + UNIT_OWNER) = slot, *(float *)(u + 0x200) = *x, *(float *)(u + 0x204) = *y;
    *(float *)(u + UNIT_HP) = 100;
    return u;
}
static void *__fastcall FakeHandleUnit(DWORD h, DWORD) { return h == 7 ? units[1] : nullptr; }
static const char *__fastcall FakeName(DWORD id, DWORD) { return id == 'A0LD' ? "|cffffcc00Lightning Dash|r" : id == 'h0OB' ? "Orb" : "Default string"; }
static void __fastcall FakeEffect(void *, int, void *) {}
static void Stub(DWORD rva, const void *fn) { img[rva - 1] = 0xCC, img[rva] = 0xE9, *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5)); }
// an entry as 1.28f starts it (pro, n bytes), then the stack put back as it was and on to the fake
static void Entry(DWORD rva, const BYTE *pro, int n, const BYTE *undo, int un, const void *fn) {
    BYTE *f = img + rva;
    f[-1] = 0xCC, memcpy(f, pro, n), memcpy(f + n, undo, un), f[n + un] = 0xE9;
    *(LONG *)(f + n + un + 1) = (LONG)((BYTE *)fn - (f + n + un + 5));
}
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
    Stub(RVA_HANDLE_LOOKUP, FakeLookup), Stub(RVA_UNIT_POSITION, FakePosition), Stub(RVA_SPELL_EFFECT, FakeEffect), Stub(RVA_UNIT_HP, FakeStat);
    Stub(RVA_HANDLE_UNIT, FakeHandleUnit), Stub(RVA_HANDLE_WIDGET, FakeHandleUnit), Stub(RVA_OBJECT_NAME, FakeName);
    // after each prologue, what it pushed taken off again: pop ebp; add esp, 4 + pop esi + pop ebp; add esp, 4 + pop ebp
    static const BYTE popEbp[] = { 0x5D }, popEsiEbp[] = { 0x83, 0xC4, 0x04, 0x5E, 0x5D }, popAttach[] = { 0x83, 0xC4, 0x04, 0x5D };
    Entry(RVA_EFFECT_ADD, g_fxAdd.pro, g_fxAdd.n, popEbp, 1, FakeAdd);
    Entry(RVA_EFFECT_DESTROY, g_fxDel.pro, g_fxDel.n, popEbp, 1, FakeDel);
    Entry(RVA_EFFECT_ATTACH, g_fxAttach.pro, g_fxAttach.n, popAttach, 4, FakeAttach);
    Entry(RVA_UNIT_CREATE, g_fxUnit.pro, g_fxUnit.n, popEsiEbp, 5, FakeCreate);
    Entry(RVA_REMOVE_UNIT, g_fxRemove.pro, g_fxRemove.n, popEbp, 1, FakeRemove);
    Entry(RVA_KILL_UNIT, g_fxKill.pro, g_fxKill.n, popEbp, 1, FakeRemove);
    for (DWORD rva : BC_SITES)
        img[rva] = 0xE8, *(LONG *)(img + rva + 1) = (LONG)(img + RVA_SPELL_EFFECT - (img + rva + 5));
    // you: player 1, your hero selected (its handle 3 alive) at (1000, 2000); units alive (100 HP, max through handle 2)
    static BYTE state[0x200], players[16][0x300], sel[0x200], handle[0x80], maxObj[0x100], abl[0x100];
    *(BYTE **)(img + RVA_PLAYERS) = state, *(short *)(state + 0x28) = 1, *(int *)(state + 0x54) = 16;
    for (int i = 0; i < 16; i++)
        *(BYTE **)(state + 0x58 + i * 4) = players[i];
    BYTE *hero = units[0];
    *(BYTE **)(players[1] + SEL_PLAYER_SELECTION) = sel, *(BYTE **)(sel + SEL_ACTIVE) = hero;
    for (BYTE *u : units)
        *(DWORD *)u = (DWORD)(img + RVA_UNIT_VT), *(float *)(u + UNIT_HP) = 100, ((DWORD *)(u + UNIT_MAXHP_HANDLE))[0] = ((DWORD *)(u + UNIT_MAXHP_HANDLE))[1] = 2;
    objs[2] = maxObj, *(float *)(maxObj + 0x84) = 100;
    *(int *)(hero + UNIT_OWNER) = 1, *(DWORD *)(hero + 0x30) = 'Hlm1', *(float *)(hero + 0x200) = 1000, *(float *)(hero + 0x204) = 2000;
    ((DWORD *)(hero + AGENT_HANDLE))[0] = ((DWORD *)(hero + AGENT_HANDLE))[1] = 3;
    objs[3] = handle, *(BYTE **)(handle + HANDLE_OBJ) = hero, *(DWORD *)(handle + HANDLE_TAG) = '+agl';
    *(DWORD *)(abl + 0x34) = 'A0LD';
    g_getUi = [](int, int) -> void * { return (void *)1; };

    float x = 1100, y = 1950;
    DWORD h0 = ((EffectAddFn)(img + RVA_EFFECT_ADD))("x", &x, &y);
    CHECK(h0 == 101 && !g_fxAdd.on && !LogHas("effect probe:"), "off: the game's own entry, nothing noted");
    sh.fxOn = 1; FxProbePass(); BossCastPass();
    bool allOn = g_bcHooked && sh.fxState == 1;
    for (CodeDetour *d : FX_DETOURS)
        allOn = allOn && d->on && img[d->rva] == 0xE9;
    CHECK(allOn, "on: the 6 entries detoured (effects, attached effects, DestroyEffect, units made, RemoveUnit, KillUnit), and the SPELL_EFFECT calls");
    ((SpellEffectFn)SiteTarget(img + BC_SITES[0]))(hero, 0, abl);
    CHECK(LogHas("your hero cast 'A0LD' (Lightning Dash) at (1000, 2000)"), "your hero's cast, by name");
    // a visual made and gone at once: only counted; an orb that stays: logged after 300 ms and when it goes
    DWORD flash = ((EffectAddFn)(img + RVA_EFFECT_ADD))("Abilities\\Weapons\\Bolt\\BoltImpact_Orange.mdl", &x, &y);
    ((EffectDestroyFn)(img + RVA_EFFECT_DESTROY))(flash);
    DWORD orb = ((EffectAddFn)(img + RVA_EFFECT_ADD))("war3mapImported\\LightningOrb.mdl", &x, &y);
    float fx = 9000, fy = 9000;
    ((EffectAddFn)(img + RVA_EFFECT_ADD))("Far.mdl", &fx, &fy);
    Sleep(320); FxProbePass();
    CHECK(!LogHas("'BoltImpact_Orange.mdl' (") && LogHas("'LightningOrb.mdl' still there after") && LogHas("+100, -50 from your hero, ") && LogHas("ms after its 'A0LD'") && !LogHas("Far.mdl"),
          "a visual gone at once: no line of its own; the orb: still there after 300 ms, +100, -50 from the hero after its 'A0LD'; one 8000 away: nothing");
    *(float *)(hero + 0x200) = 1090, *(float *)(hero + 0x204) = 1955;
    ((EffectDestroyFn)(img + RVA_EFFECT_DESTROY))(orb);
    CHECK(dels == 2 && LogHas("'LightningOrb.mdl' (+100, -50 from your hero,") && LogHas("your hero 11 from it then (-10, +5)"), "the orb's end: the hero 11 from it then; the game's own DestroyEffect each time");
    g_fxInstantAt = GetTickCount() - 2500; FxProbePass();
    CHECK(LogHas("made and gone at once (visuals) these 2 s: 'BoltImpact_Orange.mdl' x1"), "the visuals counted, a line every 2 s");
    // an orb that's a unit: made near the hero, an effect attached to it, removed; one that goes by itself
    *(float *)(hero + 0x200) = 1000, *(float *)(hero + 0x204) = 2000;
    float ux = 1150, uy = 2100, face = 0;
    BYTE *dummy = ((UnitCreateFn)(img + RVA_UNIT_CREATE))(1, 'h0OB', &ux, &uy, &face);
    DWORD att = ((EffectAttachFn)(img + RVA_EFFECT_ATTACH))("OrbFx.mdl", 7, 0);
    CHECK(dummy == units[1] && att > 200 && LogHas("unit 'h0OB' (Orb, player 1) made +150, +100 from your hero"), "a dummy unit made near the hero: logged by name, where");
    Sleep(320); FxProbePass();
    CHECK(LogHas("'OrbFx.mdl' still there after") && LogHas("(on unit 'h0OB', +150, +100"), "an effect attached to it: noted on that unit");
    ((UnitHandleFn)(img + RVA_REMOVE_UNIT))(7);
    CHECK(removes == 1 && LogHas("unit 'h0OB' removed after"), "RemoveUnit on it: its end, with where the hero was");
    dummy = ((UnitCreateFn)(img + RVA_UNIT_CREATE))(1, 'h0OB', &ux, &uy, &face);
    *(float *)(units[1] + UNIT_HP) = 0; FxProbePass();
    CHECK(LogHas("unit 'h0OB' died or went after"), "one that dies by itself (timed life): seen by the pass");
    sh.fxOn = 0; FxProbePass();
    bool back = sh.fxState == 0;
    for (CodeDetour *d : FX_DETOURS)
        back = back && !d->on && !memcmp(img + d->rva, d->pro, d->n);
    CHECK(back, "off: every entry as the game's again");
    img[RVA_KILL_UNIT] = 0xE9;                  // another mod's
    sh.fxOn = 1; FxProbePass();
    bool none = g_fxBad && sh.fxState == 3;
    for (CodeDetour *d : FX_DETOURS)
        none = none && !d->on;
    CHECK(none && !memcmp(img + RVA_EFFECT_ADD, g_fxAdd.pro, g_fxAdd.n), "an entry someone else changed: refused, none left detoured");
    Verdict();
    return g_fails;
}
