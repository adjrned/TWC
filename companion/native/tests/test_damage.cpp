// The damage meter's feed (layout 29), against a fake game image: CUnit's vtable entry +0x120 (its
// damage) is swapped for ours; the game's own runs first and what it dealt is added to the source
// unit's owner when the target is another player's (not its own, not 0 dealt); the players' names
// as GetPlayerName reads them; off: the game's entry again; an entry someone else changed is refused.
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, dmOn) == offsetof(Shared, qkClicked) + 4, "layout 29");

static BYTE *img;
static int gameCalls;
// the game's damage: half the record's amount gets through, nothing to a unit flagged invulnerable ([+0x5c] 0x100)
static void __fastcall FakeDamage(BYTE *target, int, float *dealt, BYTE *rec, DWORD, DWORD) {
    gameCalls++;
    *dealt = *(DWORD *)(target + 0x5c) & 0x100 ? 0 : *(float *)(rec + 0x10) / 2;
}
static void *__fastcall FakeGetUi(int, int) { return (void *)1; }
static BYTE units[4][0x200];
static void Hit(int target, int source, float amount) {
    BYTE rec[0x24] = {};
    *(BYTE **)rec = units[source], *(float *)(rec + 0x10) = amount;
    float dealt = -1;
    BYTE *t = units[target];
    ((UnitDamageFn)((*(DWORD **)t)[UNIT_DAMAGE_SLOT / 4]))(t, 0, &dealt, rec, 0, 0);
}

int main() {
    strcpy_s(g_logPath, "damage.log"); DeleteFileA("damage.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    // the game's damage as 1.28f starts it (push ebp; mov ebp, esp), then on to the fake
    BYTE *f = img + RVA_UNIT_DAMAGE;
    f[-1] = 0xCC, f[0] = 0x55, f[1] = 0x8B, f[2] = 0xEC, f[3] = 0x5D, f[4] = 0xE9;
    *(LONG *)(f + 5) = (LONG)((BYTE *)FakeDamage - (f + 9));
    DWORD *vt = (DWORD *)(img + RVA_UNIT_VT);
    for (int i = 0; i < 0x60; i++) vt[i] = (DWORD)(img + 0x100000);
    img[0x100000 - 1] = 0xCC; img[0x100000] = 0xC3;
    vt[UNIT_DAMAGE_SLOT / 4] = (DWORD)f;
    DWORD old; VirtualProtect(img + (RVA_UNIT_VT & ~0xfff), 0x2000, PAGE_READWRITE, &old);   // a vtable: data, as the game's
    // units: 0 and 1 player 2's, 2 player 5's, 3 player 5's and invulnerable
    int owners[4] = { 2, 2, 5, 5 };
    for (int i = 0; i < 4; i++)
        *(DWORD *)units[i] = (DWORD)vt, *(int *)(units[i] + UNIT_OWNER) = owners[i];
    *(DWORD *)(units[3] + 0x5c) = 0x100;
    // players: the game state's list, CPlayer's slot byte +0x30 and its name string +0x24 (text [[+8]+0x1c])
    static BYTE state[0x100], pl[3][0x300], str[3][0x20];
    const char *names[3] = { "|cff540081Ruzai|r", "", "||Kaelith|n|CFF1CE6B9x" };
    for (int i = 0; i < 3; i++) {
        pl[i][0x30] = (BYTE)(i * 2 + 1);                            // slots 1, 3, 5
        *(int *)(pl[i] + PLAYER_COLOUR) = 3 + i;                    // colours: purple, yellow, orange
        *(BYTE **)(pl[i] + 0x24 + 8) = str[i], *(const char **)(str[i] + 0x1c) = names[i];
        *(BYTE **)(state + 0x58 + 4 * (i * 2 + 1)) = pl[i];
    }
    *(int *)(state + 0x54) = 12; *(short *)(state + 0x28) = 5;      // you: slot 5
    *(BYTE **)(img + RVA_PLAYERS) = state;
    g_getUi = FakeGetUi;

    Hit(2, 0, 100);
    CHECK(gameCalls == 1 && sh.dmSeq == 0, "off: the game's damage, nothing counted");
    sh.dmOn = 1; FollowDamage(10000);
    CHECK(g_dmHooked && sh.dmState == 1 && vt[UNIT_DAMAGE_SLOT / 4] == (DWORD)UnitDamage, "on: CUnit's vtable +0x120 is ours");
    CHECK(!strcmp(sh.dmName[1], "Ruzai") && !strcmp(sh.dmName[5], "|Kaelith x") && !sh.dmName[3][0] && !sh.dmName[0][0], "names as GetPlayerName reads them, the codes out: slot 1 '%s', 5 '%s', empty ones ''", sh.dmName[1], sh.dmName[5]);
    CHECK(sh.dmColour[1] == 3 && sh.dmColour[5] == 5 && sh.dmColour[0] == -1 && sh.dmLocal == 5, "colours as GetPlayerColor gives them (slot 1: %d, 5: %d, none: %d); you: slot %d", sh.dmColour[1], sh.dmColour[5], sh.dmColour[0], sh.dmLocal);
    // the map renames player 1 (its -convert: a save's owner's name, SetPlayerName): the meter follows the game
    names[0] = "|cffff8000Silverwolve", *(const char **)(str[0] + 0x1c) = names[0];
    names[1] = "Morrow", *(const char **)(str[1] + 0x1c) = names[1];
    FollowDamage(12500);
    CHECK(!strcmp(sh.dmName[1], "Silverwolve") && !strcmp(sh.dmName[3], "Morrow"), "renamed mid-game (-convert): the game's name now ('%s', '%s')", sh.dmName[1], sh.dmName[3]);
    Hit(2, 0, 100), Hit(2, 1, 50), Hit(0, 2, 30);
    CHECK(gameCalls == 4 && sh.dmTotal[2] == 75 && sh.dmHits[2] == 2 && sh.dmTotal[5] == 15 && sh.dmSeq == 3,
          "each hit after the game's own: what it dealt to the owner of the source (player 2: %.0f in %lu hits, 5: %.0f)", sh.dmTotal[2], sh.dmHits[2], sh.dmTotal[5]);
    Hit(1, 0, 100), Hit(3, 0, 100);
    CHECK(gameCalls == 6 && sh.dmTotal[2] == 75 && sh.dmSeq == 3, "its own unit, or an invulnerable one (0 dealt): not counted");
    *(int *)(units[2] + UNIT_OWNER) = 12; Hit(0, 2, 30); *(int *)(units[2] + UNIT_OWNER) = 5;
    CHECK(gameCalls == 7 && !sh.dmTotal[12] && sh.dmSeq == 3, "a neutral's unit (the creeps, slot 12): not counted");
    // layout 33: every hit in the ring (a neutral's on a player's too), with the record's details and the types
    LONG r0 = sh.dmRingSeq;
    *(DWORD *)(units[0] + 0x30) = 'Hpal', *(DWORD *)(units[2] + 0x30) = 'nogr';
    {
        BYTE rec[0x24] = {};
        *(BYTE **)rec = units[0], *(float *)(rec + REC_AMOUNT) = 40, *(DWORD *)(rec + REC_FLAGS) = 0x101;
        *(DWORD *)(rec + REC_DMG_TYPE) = 1u << 14, *(DWORD *)(rec + REC_ATK_TYPE) = 6, *(DWORD *)(rec + REC_WEAPON) = 3;
        float dealt;
        ((UnitDamageFn)vt[UNIT_DAMAGE_SLOT / 4])(units[2], 0, &dealt, rec, 0, 0);
    }
    DmHit h = sh.dmRing[r0 & (DM_RING - 1)];
    CHECK(sh.dmRingSeq == r0 + 1 && h.amount == 20 && h.from == 2 && h.to == 5 && h.srcType == 'Hpal' && h.tgtType == 'nogr' && h.target == (DWORD)units[2]
          && h.flags == (DMH_ATTACK | DMH_RANGED | DMH_SRC_HERO) && h.dmgType == 14 && h.atkType == 6 && h.weapon == 3,
          "the ring: 20 from player 2's 'Hpal' to 5's 'nogr', a ranged attack by a hero, damage type 14, attack type 6, weapon 3");
    *(int *)(units[2] + UNIT_OWNER) = 12; Hit(0, 2, 30);
    h = sh.dmRing[(r0 + 1) & (DM_RING - 1)];
    bool neutralHit = sh.dmRingSeq == r0 + 2 && h.from == 12 && h.to == 2 && h.amount == 15 && h.dmgType == 0xff;
    *(int *)(units[3] + UNIT_OWNER) = 13; *(DWORD *)(units[3] + 0x5c) = 0; Hit(3, 2, 30);
    *(int *)(units[2] + UNIT_OWNER) = 5, *(int *)(units[3] + UNIT_OWNER) = 5, *(DWORD *)(units[3] + 0x5c) = 0x100;
    CHECK(neutralHit && sh.dmRingSeq == r0 + 2 && !sh.dmTotal[12], "a neutral's hit on a player's unit: in the ring (taken), not dealt; neutral on neutral: not at all");
    // the types named on the game thread, as GetUnitName (+3782B0 stubbed)
    struct Names { static const char *__fastcall Of(DWORD id, DWORD) { return id == 'Hpal' ? "|cffffcc00Paladin|r" : "Default string"; } };
    img[RVA_OBJECT_NAME - 1] = 0xCC, img[RVA_OBJECT_NAME] = 0xE9, *(LONG *)(img + RVA_OBJECT_NAME + 1) = (LONG)((BYTE *)Names::Of - (img + RVA_OBJECT_NAME + 5));
    DamageTypesPass();
    int pal = -1, ogr = -1;
    for (int i = 0; i < sh.dmTypeN; i++)
        (sh.dmTypeId[i] == 'Hpal' ? pal : sh.dmTypeId[i] == 'nogr' ? ogr : i) = i;
    CHECK(pal >= 0 && ogr >= 0 && !strcmp(sh.dmTypeName[pal], "Paladin") && !sh.dmTypeName[ogr][0] && !g_dmPendN,
          "unit types named once each: 'Hpal' -> 'Paladin' (codes out), no name -> ''");
    LONG tn = sh.dmTypeN; Hit(2, 0, 10); DamageTypesPass();
    CHECK(sh.dmTypeN == tn, "a type already named isn't asked again");
    // your selection's active unit
    static BYTE selObj[0x200];
    *(BYTE **)(pl[2] + SEL_PLAYER_SELECTION) = selObj, *(BYTE **)(selObj + SEL_ACTIVE) = units[0];
    FollowDamage(13000);
    CHECK(sh.dmSelUnit == (DWORD)units[0] && sh.dmSelType == 'Hpal' && sh.dmSelOwner == 2, "your selection: the unit, its type and owner");
    *(BYTE **)(selObj + SEL_ACTIVE) = nullptr; FollowDamage(13100);
    CHECK(!sh.dmSelUnit && sh.dmSelOwner == -1, "nothing selected: 0");
    // the map's text lines: the 3 DisplayText calls to the game UI's +3A8EB0 pointed at ours while on
    struct Text { static void __fastcall Line(void *, int, float, float, const char *, float, DWORD) { gameCalls += 100; } };
    BYTE *ut = img + RVA_UI_TEXT; ut[-1] = 0xCC, ut[0] = 0xE9, *(LONG *)(ut + 1) = (LONG)((BYTE *)Text::Line - (ut + 5));
    for (DWORD rva : MT_SITES)
        img[rva] = 0xE8, *(LONG *)(img + rva + 1) = (LONG)(ut - (img + rva + 5));
    MapTextPass();
    bool allOurs = g_mtHooked;
    for (DWORD rva : MT_SITES)
        allOurs = allOurs && SiteTarget(img + rva) == (BYTE *)MapTextHook;
    int gc = gameCalls;
    ((UiTextFn)SiteTarget(img + MT_SITES[2]))((void *)1, 0, 0, 0, "|cffff0000Total damage:|r 1,234,567", 5, 0xFFFFFFFF);
    CHECK(allOurs && gameCalls == gc + 100 && sh.mtSeq == 1 && !strcmp(sh.mtText[0], "Total damage: 1,234,567"),
          "map text: the 3 calls are ours, the game's line shown first, kept without codes ('%s')", sh.mtText[0]);
    sh.dmOn = 0; MapTextPass();
    bool mtBack = !g_mtHooked;
    for (DWORD rva : MT_SITES)
        mtBack = mtBack && SiteTarget(img + rva) == ut;
    CHECK(mtBack, "map text off: the calls go to the game's again");
    sh.dmOn = 1; MapTextPass(); RestoreAll();
    CHECK(!g_mtHooked && SiteTarget(img + MT_SITES[0]) == ut, "and on unload");
    g_dmHooked = true, vt[UNIT_DAMAGE_SLOT / 4] = (DWORD)UnitDamage;     // (RestoreAll gave it back; on again as before)
    sh.dmOn = 0; FollowDamage(11000);
    CHECK(!g_dmHooked && sh.dmState == 0 && vt[UNIT_DAMAGE_SLOT / 4] == (DWORD)f, "off: the entry is the game's damage again");
    double t2 = sh.dmTotal[2]; int gOff = gameCalls;
    Hit(2, 0, 100);
    CHECK(gameCalls == gOff + 1 && sh.dmTotal[2] == t2, "and nothing counted");
    sh.dmOn = 1; vt[UNIT_DAMAGE_SLOT / 4] = (DWORD)(img + 0x100000); FollowDamage(12000);
    CHECK(!g_dmHooked && sh.dmState == 3, "an entry someone else changed: refused");
    Verdict();
    return g_fails;
}
