// Detailed tooltips (layout 15), against a fake game image: the damage and
// armor icons' vtable entry +0x6C is swapped for the hooks, the game's own
// update still runs first and sets the tooltip, then the body gets the extra
// lines through the game's setter (once: a body that ends with them is left),
// and off gives the entries back.
#include "../twc-game.cpp"
#include "check.h"
static_assert(offsetof(Shared, ttOn) == 816 && offsetof(Shared, ttState) == 820 && sizeof(Shared) >= 824, "layout 15");

static BYTE *img;
static void Stub(DWORD rva, const void *fn) { img[rva - 1] = 0xCC; img[rva] = 0xE9; *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5)); }
static BYTE tip[0xa40];
static bool stackOk = true;
static int sets, damageCalls, armorCalls;
static void __fastcall FakeSet(BYTE *f, int, const char *a, const char *b, const char *c) {
    sets++;
    strncpy_s((char *)f + TIP_LINE, 0x100, a, _TRUNCATE); strncpy_s((char *)f + TIP_BODY, 0x401, b, _TRUNCATE); strncpy_s((char *)f + TIP_THIRD, 0x400, c, _TRUNCATE);
}
static DWORD __fastcall FakeDamage(BYTE *icon, int, void *, void *, void *, DWORD) { damageCalls++; FakeSet(*(BYTE **)(icon + ICON_TIP), 0, "12 - 15", "Damage: 12 - 15|nRange: 600|nSpeed: Average", "Attack"); return 7; }
static DWORD __fastcall FakeArmor(BYTE *icon, int, void *, void *, void *) { armorCalls++; FakeSet(*(BYTE **)(icon + ICON_TIP), 0, "3", "Armor: 3|nMove speed: Fast", "Armor"); return 9; }
static void *__fastcall FakeGetUi(int, int) { return (void *)1; }
// the game's getters: cooldown (atk, out, i), move speed (mv, out)
static BYTE atk[0x300], mv[0x100];
static void __fastcall FakeCooldown(BYTE *a, int, float *out, DWORD i) { *out = *(float *)(a + 0x158 + 8 * i) / 1.25f; }
static void __fastcall FakeMove(BYTE *m, int, float *out) { *out = *(float *)(m + 0x70) + 20; }
static void TestUnit(BYTE *u) {
    *(BYTE **)(u + UNIT_ATTACKS) = atk; *(int *)(atk + ATTACK_ON) = 1; *(float *)(atk + 0x158) = 2.5f;
    *(BYTE **)(u + UNIT_MOVE) = mv; *(float *)(mv + 0x70) = 300;
}
static const char *DAMAGE_WANT = "|nCooldown: |cFF00FF00" "2.00 sec|r|nAttacks: |cFF00FF00" "0.500/sec|r", *ARMOR_WANT = "|nMove speed: |cFF00FF00" "320|r";

// the armor update called as the game calls it (3 stack args, the callee pops 12); esp checked after
static DWORD ArmorRaw(DWORD f, BYTE *icon, BYTE *unit) {
    DWORD r, sp0, sp1;
    __asm {
        mov sp0, esp
        push 0
        push 0
        push unit
        mov ecx, icon
        xor edx, edx
        call f
        mov r, eax
        mov sp1, esp
        mov esp, sp0
    }
    stackOk &= sp0 == sp1;
    return r;
}

int main() {
    strcpy_s(g_logPath, "tooltips.log"); DeleteFileA("tooltips.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    Stub(RVA_DAMAGE_UPDATE, FakeDamage); Stub(RVA_ARMOR_UPDATE, FakeArmor); Stub(RVA_TOOLTIP_SET, FakeSet);
    Stub(RVA_ATTACK_COOLDOWN, FakeCooldown); Stub(RVA_MOVE_SPEED, FakeMove);
    DWORD *dv = (DWORD *)(img + RVA_DAMAGE_ICON_VT), *av = (DWORD *)(img + RVA_ARMOR_ICON_VT);
    for (int i = 0; i < 40; i++) dv[i] = av[i] = (DWORD)(img + 0x100000);
    img[0x100000 - 1] = 0xCC; img[0x100000] = 0xC3;
    dv[ICON_UPDATE / 4] = (DWORD)(img + RVA_DAMAGE_UPDATE); av[ICON_UPDATE / 4] = (DWORD)(img + RVA_ARMOR_UPDATE);
    DWORD old; VirtualProtect(img + 0xaaf000, 0x1000, PAGE_READWRITE, &old); VirtualProtect(img + 0xa7c000, 0x1000, PAGE_READWRITE, &old);
    *(DWORD *)tip = (DWORD)(img + 0xa7c100);                      // the tooltip frame: an object of the game's
    static BYTE icon[0x200], unit[0x400];
    *(BYTE **)(icon + ICON_TIP) = tip;
    TestUnit(unit);
    g_getUi = FakeGetUi;
    auto damage = [&] { return ((DamageFn)dv[ICON_UPDATE / 4])(icon, 0, unit, nullptr, nullptr, 0); };
    auto armor = [&] { return ArmorRaw(av[ICON_UPDATE / 4], icon, unit); };
    damage();
    CHECK(sets == 1 && damageCalls == 1, "off: the game's update alone");
    sh.ttOn = 1; FollowTooltips();
    CHECK(g_ttHooked && sh.ttState == 1 && dv[ICON_UPDATE / 4] == (DWORD)DamageTipHook && av[ICON_UPDATE / 4] == (DWORD)ArmorTipHook, "on: both entries +0x6C wrapped");
    DWORD r = damage();
    const char *body = (const char *)tip + TIP_BODY;
    CHECK(r == 7 && damageCalls == 2 && sets == 3 && strstr(body, "Speed: Average") && strstr(body, DAMAGE_WANT) && !strcmp((char *)tip + TIP_LINE, "12 - 15") && !strcmp((char *)tip + TIP_THIRD, "Attack"),
          "the game's update, then its body with the lines: \"%s\"", body);
    int before = sets;
    TooltipAppend(icon, true, unit, 0);
    CHECK(sets == before, "a body that already has them: not set again");
    r = armor();
    CHECK(stackOk, "the armor hook pops the game's 3 stack arguments (ret 0xC): esp is where the caller left it");
    CHECK(r == 9 && armorCalls == 1 && strstr(body, "Move speed: Fast") && strstr(body, ARMOR_WANT), "armor: \"%s\"", body);
    *(int *)(atk + ATTACK_ON + 4) = 0; before = sets; ((DamageFn)dv[ICON_UPDATE / 4])(icon, 0, unit, nullptr, nullptr, 1);
    CHECK(sets == before + 1, "an attack the unit doesn't have: the game's tooltip alone");
    sh.ttOn = 0; FollowTooltips();
    CHECK(!g_ttHooked && sh.ttState == 0 && dv[ICON_UPDATE / 4] == (DWORD)(img + RVA_DAMAGE_UPDATE) && av[ICON_UPDATE / 4] == (DWORD)(img + RVA_ARMOR_UPDATE), "off: the entries are the game's again");
    sh.ttOn = 1; dv[ICON_UPDATE / 4] = (DWORD)(img + 0x100000); FollowTooltips();
    CHECK(!g_ttHooked && sh.ttState == 3, "an entry someone else changed: refused");
    Verdict();
    return g_fails;
}
