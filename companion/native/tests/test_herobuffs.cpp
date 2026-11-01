// Your hero's buffs, read from the unit (ReadHeroBuffs), against a fake game image: the
// hero found from the selection, then by its remembered handle, then in the unit list; its
// ability chain walked ([unit+0x1dc], next [+0x24]), only buffs kept (vt+0x1e0 / +0x1e4 and
// a 'B...' tag), their times and the game's name from the buff UI table (colour codes out).
#include "../twc-game.cpp"
#include "check.h"

static BYTE *img;
static BYTE *objs[16];                  // handle pair (i, i) -> objs[i] (a handle object: [+0x20] dead, [+0x54] the agent, [+0xc] '+agl')
static void *__fastcall FakeLookup(DWORD a, DWORD) { return a < 16 ? objs[a] : nullptr; }
static void __fastcall FakeStat(BYTE *at, int, float *out) { *out = *(float *)at; }   // the unit state +0x81b30
static void Stub(DWORD rva, const void *fn) { img[rva - 1] = 0xCC, img[rva] = 0xE9, *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5)); }
static DWORD IntGetter(DWORD rva, DWORD v) { BYTE *p = img + rva; p[-1] = 0xCC, p[0] = 0xB8, *(DWORD *)(p + 1) = v, p[5] = 0xC3; return (DWORD)p; }
static DWORD ZeroGetter(DWORD rva) { BYTE *p = img + rva; p[-1] = 0xCC, p[0] = 0x33, p[1] = 0xC0, p[2] = 0xC3; return (DWORD)p; }
// "mov eax, 1; xor ecx, ecx; ret": not a constant getter's shape, read through the decoder and a call
static DWORD CallGetter(DWORD rva, DWORD v) { BYTE *p = img + rva; p[-1] = 0xCC, p[0] = 0xB8, *(DWORD *)(p + 1) = v, p[5] = 0x33, p[6] = 0xC9, p[7] = 0xC3; return (DWORD)p; }
static DWORD FloatGetter(DWORD rva, float f) {
    BYTE *p = img + rva; p[-1] = 0xCC;
    BYTE b[] = { 0x8B, 0x44, 0x24, 0x04, 0xC7, 0x00, 0, 0, 0, 0, 0xC2, 0x04, 0x00 };
    memcpy(b + 6, &f, 4), memcpy(p, b, sizeof(b));
    return (DWORD)p;
}
static BYTE handles[16][0x60];
static void Handle(int i, BYTE *obj) { objs[i] = handles[i], *(BYTE **)(handles[i] + HANDLE_OBJ) = obj, *(DWORD *)(handles[i] + HANDLE_TAG) = '+agl'; }
static void Pair(BYTE *at, int i) { ((DWORD *)at)[0] = i, ((DWORD *)at)[1] = i; }

int main() {
    strcpy_s(g_logPath, "herobuffs.log"); DeleteFileA("herobuffs.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    DWORD old;
    VirtualProtect(img + 0xa60000, 0x120000, PAGE_READWRITE, &old);         // vtables: data
    VirtualProtect(img + 0xd00000, 0x40000, PAGE_READWRITE, &old);          // globals
    Stub(RVA_HANDLE_LOOKUP, FakeLookup), Stub(RVA_UNIT_HP, FakeStat);
    // the local player 1 of 16, its selection
    static BYTE state[0x200], players[16][0x300], sel[0x200];
    *(BYTE **)(img + RVA_PLAYERS) = state, *(short *)(state + 0x28) = 1, *(int *)(state + 0x54) = 16;
    for (int i = 0; i < 16; i++)
        *(BYTE **)(state + 0x58 + i * 4) = players[i];
    *(BYTE **)(players[1] + SEL_PLAYER_SELECTION) = sel;
    // the hero (handle 1), a footman of yours (5), an enemy hero (6)
    static BYTE hero[0x300], foot[0x300], enemy[0x300];
    for (BYTE *u : { hero, foot, enemy })
        *(DWORD *)u = (DWORD)(img + RVA_UNIT_VT), Pair(u + UNIT_ABILITIES, -1);
    *(int *)(hero + UNIT_OWNER) = 1, *(DWORD *)(hero + 0x30) = 'Hpal', *(float *)(hero + UNIT_HP) = 500, Pair(hero + AGENT_HANDLE, 1), Handle(1, hero);
    *(int *)(foot + UNIT_OWNER) = 1, *(DWORD *)(foot + 0x30) = 'hfoo', Pair(foot + AGENT_HANDLE, 5), Handle(5, foot);
    *(int *)(enemy + UNIT_OWNER) = 3, *(DWORD *)(enemy + 0x30) = 'Hblm', Pair(enemy + AGENT_HANDLE, 6), Handle(6, enemy);
    // its chain: an ability (2), Inner Fire (3, positive, read through a call), Devotion Aura (4), Slow (7, negative), then none
    static BYTE ab[0x200], inf[0x200], aura[0x200], slow[0x200];
    DWORD *avt = (DWORD *)(img + 0xa70000), *bvt = (DWORD *)(img + 0xa70400), *auvt = (DWORD *)(img + 0xa70800), *svt = (DWORD *)(img + 0xa70c00);
    avt[0x1e0 / 4] = avt[0x1e4 / 4] = avt[0x1e8 / 4] = ZeroGetter(0x600000), avt[0x1c / 4] = IntGetter(0x600010, 'AHhb');
    bvt[0x1e0 / 4] = avt[0x1e0 / 4], bvt[0x1e4 / 4] = CallGetter(0x600020, 1), bvt[0x1e8 / 4] = avt[0x1e8 / 4], bvt[0x1c / 4] = IntGetter(0x600030, 'Binf');
    auvt[0x1e0 / 4] = avt[0x1e0 / 4], auvt[0x1e4 / 4] = IntGetter(0x600040, 1), auvt[0x1e8 / 4] = IntGetter(0x600050, 1), auvt[0x1c / 4] = IntGetter(0x600060, 'BAUR');
    svt[0x1e0 / 4] = IntGetter(0x600070, 1), svt[0x1e4 / 4] = avt[0x1e4 / 4], svt[0x1e8 / 4] = avt[0x1e8 / 4], svt[0x1c / 4] = IntGetter(0x600080, 'buff');
    DWORD *tvt = (DWORD *)(img + 0xa71000);
    tvt[0x18 / 4] = FloatGetter(0x600100, 4.5f), tvt[0x10 / 4] = FloatGetter(0x600200, 30);
    *(DWORD *)ab = (DWORD)avt, *(DWORD *)inf = (DWORD)bvt, *(DWORD *)aura = (DWORD)auvt, *(DWORD *)slow = (DWORD)svt;
    *(DWORD *)(inf + BUFF_ID) = 'Binf', *(DWORD *)(aura + BUFF_ID) = 'BHad', *(DWORD *)(slow + BUFF_ID) = 'Bslo';
    for (BYTE *b : { inf, aura, slow })
        *(DWORD *)(b + BUFF_TIMER) = (DWORD)tvt, *(BYTE **)(b + BUFF_UNIT) = hero, *(float *)(b + BUFF_DUR) = 20, *(float *)(b + BUFF_HERO_DUR) = 12;
    Pair(hero + UNIT_ABILITIES, 2), Handle(2, ab), Pair(ab + ABILITY_NEXT, 3), Handle(3, inf), Pair(inf + ABILITY_NEXT, 4), Handle(4, aura);
    Pair(aura + ABILITY_NEXT, 7), Handle(7, slow), Pair(slow + ABILITY_NEXT, -1);
    // the buff UI table: 4 buckets (bucket = id & 3: 'Binf' 2, 'BHad' 0), chained through [rec + 0x200 + 4]
    static BYTE buckets[4 * 12], rec[3][0x400];
    *(BYTE **)(img + BUFF_UI_BUCKETS) = buckets, *(DWORD *)(img + BUFF_UI_MASK) = 3;
    *(DWORD *)rec[0] = 'Binf', strcpy_s((char *)rec[0] + BUFF_UI_NAME, 64, "|cff00ff00Inner Fire|r");
    *(DWORD *)rec[1] = 'Bxx2', strcpy_s((char *)rec[1] + BUFF_UI_NAME, 64, "Other");
    *(DWORD *)rec[2] = 'BHad', strcpy_s((char *)rec[2] + BUFF_UI_NAME, 64, "Devotion|nAura ");
    for (DWORD id : { (DWORD)'Binf', (DWORD)'BHad' })
        *(DWORD *)(buckets + (id & 3) * 12) = 0x200;
    BYTE *bInf = buckets + ('Binf' & 3) * 12, *bHad = buckets + ('BHad' & 3) * 12;
    *(BYTE **)(bInf + 8) = rec[1], *(BYTE **)(rec[1] + 0x204) = rec[0], *(BYTE **)(rec[0] + 0x204) = nullptr;   // 'Binf' second in its chain
    *(BYTE **)(bHad + 8) = rec[2], *(BYTE **)(rec[2] + 0x204) = nullptr;
    *(DWORD *)(rec[1] + 0) = 'Binf' ^ 0x100;                               // same bucket, another key

    // the selection is the hero
    *(BYTE **)(sel + SEL_ACTIVE) = hero;
    sh.hrWant = 1;
    ReadHeroBuffs();
    CHECK(sh.hrHero == 'Hpal' && sh.hrAlive == 1 && sh.hrCount == 3 && sh.hrId[0] == 'Binf' && sh.hrId[1] == 'BHad' && sh.hrId[2] == 'Bslo',
          "the selected hero: 3 buffs in the unit's order, the ability left out (%lu: '%s' '%s' '%s')", sh.hrCount, IdText(sh.hrId[0]).s, IdText(sh.hrId[1]).s, IdText(sh.hrId[2]).s);
    CHECK(sh.hrFlags[0] == (1 | 4 | 8) && sh.hrFlags[1] == (1 | 2 | 4 | 8 | 16) && sh.hrFlags[2] == 1 && sh.hrLeft[0] == 4.5f && sh.hrTotal[0] == 12 && sh.hrTotal[1] == 30,
          "flags: positive (read through a call) / aura (kept up: just seen, BuffKeptUp) / negative, named; times 4.5 of 12 (the hero's +0xc8), the aura's the timer's 30");
    CHECK(!strcmp(sh.hrName[0], "Inner Fire") && !strcmp(sh.hrName[1], "Devotion Aura") && !sh.hrName[2][0],
          "names: \"%s\" (colour codes out, found second in its chain), \"%s\" (|n a space, trailing space cut), none for 'Bslo'", sh.hrName[0], sh.hrName[1]);
    // another unit selected (an enemy hero, your footman): still your hero, by its remembered handle
    *(BYTE **)(sel + SEL_ACTIVE) = enemy;
    ReadHeroBuffs();
    bool e1 = sh.hrHero == 'Hpal' && sh.hrCount == 3;
    *(BYTE **)(sel + SEL_ACTIVE) = foot;
    ReadHeroBuffs();
    CHECK(e1 && sh.hrHero == 'Hpal' && sh.hrCount == 3, "an enemy hero or your footman selected: your hero's buffs still");
    // nothing remembered, nothing selected: the unit list
    g_heroPair[0] = g_heroPair[1] = 0xFFFFFFFF, *(BYTE **)(sel + SEL_ACTIVE) = nullptr;
    static BYTE *units[3] = { enemy, foot, hero };
    *(DWORD *)(img + RVA_UNIT_LIST + 4) = 3, *(BYTE ***)(img + RVA_UNIT_LIST + 8) = units;
    ReadHeroBuffs();
    CHECK(sh.hrHero == 'Hpal' && sh.hrCount == 3, "nothing selected or remembered: your hero from the unit list");
    // the hero dead (no health): still your hero, not alive (no alerts)
    *(float *)(hero + UNIT_HP) = 0;
    ReadHeroBuffs();
    CHECK(sh.hrHero == 'Hpal' && sh.hrAlive == 0, "your hero with no health: hrAlive 0");
    *(float *)(hero + UNIT_HP) = 500;
    // the hero's handle dead (removed): no hero, the list emptied
    *(DWORD *)(handles[1] + HANDLE_DEAD) = 1;
    ReadHeroBuffs();
    CHECK(sh.hrHero == 0 && sh.hrAlive == 0 && sh.hrCount == 0 && sh.hrId[0] == 0 && !sh.hrName[0][0], "your hero's handle dead: no hero, no buffs");
    *(DWORD *)(handles[1] + HANDLE_DEAD) = 0;
    // a broken chain (an agent whose vtable isn't the game's) stops the walk
    *(DWORD *)aura = 0x1234;
    ReadHeroBuffs();
    *(DWORD *)aura = (DWORD)auvt;
    CHECK(sh.hrCount == 1 && sh.hrId[0] == 'Binf', "a chain entry that isn't a game object ends the walk (%lu)", sh.hrCount);
    // through the timers' read (on the game thread), only while asked
    sh.hrWant = 0, sh.hrCount = 77;
    ReadTimers(nullptr);
    bool notAsked = sh.hrCount == 77;
    sh.hrWant = 1;
    static BYTE ui[0x500];
    ReadTimers(ui);
    CHECK(notAsked && sh.hrCount == 3, "ReadTimers reads them only with hrWant on");
    char logText[8192] = "";
    FILE *lf;
    if (!fopen_s(&lf, "herobuffs.log", "rb"))
        logText[fread(logText, 1, sizeof(logText) - 1, lf)] = 0, fclose(lf);
    CHECK(strstr(logText, "hero buffs: your hero is 'Hpal'") && strstr(logText, "'Binf' positive, named 'Inner Fire'") && strstr(logText, "'Bslo' negative, named ''"),
          "the log: the hero, then each new buff once with its name");
    Verdict();
    return g_fails;
}
