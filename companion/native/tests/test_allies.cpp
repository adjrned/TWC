// Allies' abilities (WFE's ISALLYABILITYBAR), the cooldown ping and the buff reads (WFE's
// BUFFUI), against a fake game image: the observer-view function's start is detoured to
// a copy and back, the ability callback's push points at the hook, allied units count and
// enemies don't, everything is put back off; the ping line from the hovered button; the
// buff's full time by its unit (hero +0xc8, else +0xc0) and through a linked buff.
#include "../twc-game.cpp"
#include "check.h"
#include <stddef.h>
static_assert(offsetof(Shared, alOn) == 848 && offsetof(Shared, pingText) == 864 && sizeof(Shared) >= 992, "layout 18");

static BYTE *img;
static int displays, observer;
static int __fastcall FakeObserver(int, int) { return observer; }
static void __fastcall FakeDisplay(BYTE *, int, DWORD) { displays++; }
static int __fastcall FakeCallback(BYTE *, BYTE *) { return 7; }
static void Stub(DWORD rva, const void *fn) { img[rva - 1] = 0xCC, img[rva] = 0xE9, *(LONG *)(img + rva + 1) = (LONG)((BYTE *)fn - (img + rva + 5)); }
// a getter in the image: mov eax, v; ret (passes the decoder)
static DWORD IntGetter(DWORD rva, DWORD v) { BYTE *p = img + rva; p[-1] = 0xCC, p[0] = 0xB8, *(DWORD *)(p + 1) = v, p[5] = 0xC3; return (DWORD)p; }
// a timer getter: mov eax, [esp+4]; mov dword [eax], f; ret 4
static DWORD FloatGetter(DWORD rva, float f) {
    BYTE *p = img + rva; p[-1] = 0xCC;
    BYTE b[] = { 0x8B, 0x44, 0x24, 0x04, 0xC7, 0x00, 0, 0, 0, 0, 0xC2, 0x04, 0x00 };
    memcpy(b + 6, &f, 4), memcpy(p, b, sizeof(b));
    return (DWORD)p;
}

int main() {
    strcpy_s(g_logPath, "allies.log"); DeleteFileA("allies.log");
    static Shared sh; g_shared = &sh;
    img = (BYTE *)VirtualAlloc(nullptr, 0x1000000, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE);
    g_base = img; g_imageSize = 0x1000000;
    DWORD old;
    VirtualProtect(img + 0xa60000, 0x120000, PAGE_READWRITE, &old);         // vtables: data
    VirtualProtect(img + 0xd00000, 0x40000, PAGE_READWRITE, &old);          // globals
    // +0x6bffd0 as 1.28f has it: push esi; mov esi, [state]; call ...; ... ; xor eax, eax; pop esi; ret
    BYTE *f = img + RVA_SEES_ALL;
    BYTE sees[] = { 0x56, 0x8B, 0x35, 0, 0, 0, 0, 0xE8, 0, 0, 0, 0, 0x33, 0xC0, 0x5E, 0xC3 };
    *(DWORD *)(sees + 3) = (DWORD)(img + RVA_PLAYERS);
    f[-1] = 0xCC, memcpy(f, sees, sizeof(sees));
    BYTE *callee = img + 0x500000; callee[-1] = 0xCC, callee[0] = 0x33, callee[1] = 0xC0, callee[2] = 0xC3;   // xor eax, eax; ret
    *(LONG *)(f + 8) = (LONG)(callee - (f + 12));
    Stub(RVA_ABILITY_CB, FakeCallback), Stub(RVA_IS_OBSERVER, FakeObserver), Stub(RVA_ABILITY_DISPLAY, FakeDisplay);
    BYTE *push = img + RVA_ABILITY_CB_PUSH; push[0] = 0x68, *(DWORD *)(push + 1) = (DWORD)(img + RVA_ABILITY_CB);
    // players: local 1, allied with 2 (the colours' Allied: [p+0x38]+0x40 pair -> flags +0x78)
    static BYTE state[0x200], players[16][0x300], allyH[0x60], flagsObj[0x100];
    *(BYTE **)(img + RVA_PLAYERS) = state, *(short *)(state + 0x28) = 1;
    for (int i = 0; i < 16; i++)
        *(BYTE **)(state + 0x58 + i * 4) = players[i], players[i][0x30] = (BYTE)i;
    *(BYTE **)(players[1] + 0x38) = allyH, ((DWORD *)(allyH + 0x40))[0] = 5, ((DWORD *)(allyH + 0x40))[1] = 6;
    BYTE lk[] = { 0xB8, 0, 0, 0, 0, 0xC3 }; *(DWORD *)(lk + 1) = (DWORD)flagsObj;
    img[RVA_HANDLE_LOOKUP - 1] = 0xCC, memcpy(img + RVA_HANDLE_LOOKUP, lk, sizeof(lk));
    *(DWORD *)(flagsObj + 0x78) = 1u << 2;
    static BYTE mine[0x300], ally[0x300], enemy[0x300], ability[0x200], abEntry[0x20];
    for (BYTE *u : { mine, ally, enemy })
        *(DWORD *)u = (DWORD)(img + RVA_UNIT_VT);
    *(int *)(mine + UNIT_OWNER) = 1, *(int *)(ally + UNIT_OWNER) = 2, *(int *)(enemy + UNIT_OWNER) = 3;
    *(BYTE **)(ability + 0x1bc) = abEntry, *(DWORD *)(abEntry + 8) = 0x1234;

    CHECK(AlliesPatchable(), "the fake image has both places as 1.28f");
    sh.alOn = 1; AlliesPass();
    CHECK(g_alHooked && sh.alState == 1 && f[0] == 0xE9 && *(DWORD *)(push + 1) == (DWORD)AllyAbilityHook, "on: the start detoured, the callback's push points at the hook");
    SeesFn sees2 = (SeesFn)f;
    CHECK(sees2(mine, 0) == 1 && sees2(ally, 0) == 1 && sees2(enemy, 0) == 0 && sees2(nullptr, 0) == 0,
          "sees the commands of: yours yes, an ally's yes, an enemy's no, no unit no (the game's own answer 0 through the copy)");
    AbilityCbFn cb = (AbilityCbFn)(img + RVA_ABILITY_CB);
    int r1 = AllyAbilityHook(ally, ability), d1 = displays;
    int r2 = AllyAbilityHook(enemy, ability), d2 = displays;
    observer = 1; AllyAbilityHook(ally, ability); int d3 = displays; observer = 0;
    CHECK(r1 == 7 && d1 == 1 && r2 == 7 && d2 == 1 && d3 == 1, "the callback: the game's runs (returns 7), then an ally's ability display is updated, an enemy's not; observers: left to the game");
    sh.alOn = 0; AlliesPass();
    CHECK(!g_alHooked && !memcmp(f, sees, 7) && *(DWORD *)(push + 1) == (DWORD)(img + RVA_ABILITY_CB), "off: the start's 7 bytes and the push are the game's again");
    sh.alOn = 1; AlliesPass(); RestoreAll();
    CHECK(!g_alHooked && !memcmp(f, sees, 7), "RestoreAll (unload) puts them back too");

    // the ping: the hovered button (CSimpleTop's +0x16c) is a command card button
    static BYTE top[0x200], ui[0x500], card[0x200], rowT[16], btn[0x300], data[0x800], info[0x200], panel[0x200], nameFs[0x100];
    static BYTE *btns[1];
    *(DWORD *)top = (DWORD)(img + RVA_SIMPLE_TOP_VT), *(BYTE **)(img + RVA_SIMPLE_TOP) = top;
    *(BYTE **)(ui + 0x3c8) = card, *(int *)(card + 0x124) = 1, *(int *)(card + 0x128) = 1;
    *(BYTE **)(card + 0x154) = rowT, *(DWORD *)(rowT + 4) = 1, *(BYTE ***)(rowT + 8) = btns, btns[0] = btn;
    *(BYTE **)(btn + 0x190) = data, strcpy_s((char *)data + DATA_NAME, 32, "|cffffcc00Holy|r Light");
    *(DWORD *)info = *(DWORD *)panel = (DWORD)(img + 0xab0000);
    *(BYTE **)(ui + 0x3c4) = info, *(BYTE **)(info + 0x130) = panel, *(BYTE **)(panel + 0x128) = nameFs;
    *(DWORD *)nameFs = (DWORD)(img + RVA_FONTSTRING_VTABLE), *(const char **)(nameFs + FS_TEXT) = "Paladin";
    CHECK(PingCommand(ui) == 2 && !sh.pingText[0], "nothing under the cursor: no ping");
    *(BYTE **)(top + TOP_HOVER) = btn;
    HoverPass(ui);
    int pr = PingCommand(ui);
    CHECK(sh.hover == 1 && pr == 1 && !strcmp(sh.pingText, "Paladin >> Holy Light | Ready!"), "the hovered ability, no cooldown: \"%s\"", sh.pingText);
    // cooling down: [btn+0x19c], the ability [data+0x6d4] with flags 0x200, its timer's getters
    static BYTE ab[0x200], timer[0x40], model[0x10];
    DWORD *tvt = (DWORD *)(img + 0xa6f780);
    tvt[0x18 / 4] = FloatGetter(0x600000, 7.2f), tvt[0x10 / 4] = FloatGetter(0x600100, 10);
    *(DWORD *)(ab + 0xd0) = (DWORD)tvt;
    *(BYTE **)(btn + 0x19c) = model, *(BYTE **)(data + 0x6d4) = ab, *(DWORD *)(ab + 0x34) = 'AHhb', *(DWORD *)(ab + 0x20) = 0x200;
    PingCommand(ui);
    CHECK(!strcmp(sh.pingText, "Paladin >> Holy Light | Cooldown: 8"), "cooling down: \"%s\"", sh.pingText);
    *(const char **)(nameFs + FS_TEXT) = "";
    PingCommand(ui);
    CHECK(!strcmp(sh.pingText, "Holy Light | Cooldown: 8"), "no unit name: \"%s\"", sh.pingText);

    // buffs: a hero's buff takes its full time from +0xc8, another unit's from +0xc0
    static BYTE bar[0x200], bRow[16], ind[2][0x1000], buff[2][0x200], unit[2][0x300], linked[0x200], lobj[0x100];
    static BYTE *inds[2];
    DWORD *bvt = (DWORD *)(img + 0xa70000);
    bvt[0x1e8 / 4] = IntGetter(0x601000, 0), bvt[0x1c / 4] = IntGetter(0x601010, 'buff');
    DWORD *evt = (DWORD *)(img + 0xa70400);                                // the buff timer: CAgentTimerExtended-like
    evt[0x18 / 4] = FloatGetter(0x601100, 4.5f), evt[0x10 / 4] = FloatGetter(0x601200, 30);
    *(BYTE **)(panel + 0x16c) = bar, *(int *)(bar + 0x124) = 1, *(int *)(bar + 0x128) = 2;
    *(BYTE **)(bar + 0x154) = bRow, *(DWORD *)(bRow + 4) = 2, *(BYTE ***)(bRow + 8) = inds;
    for (int i = 0; i < 2; i++) {
        inds[i] = ind[i], *(DWORD *)(ind[i] + 0x90) = 1, *(DWORD *)(ind[i] + 0x94) = 1, *(BYTE **)(ind[i] + 0x978) = buff[i];
        *(DWORD *)buff[i] = (DWORD)bvt, *(DWORD *)(buff[i] + 0x84) = (DWORD)evt, *(DWORD *)(buff[i] + BUFF_ID) = 'Binf';
        *(float *)(buff[i] + 0xc0) = 20, *(float *)(buff[i] + 0xc8) = 12;
        *(BYTE **)(buff[i] + BUFF_UNIT) = unit[i], *(DWORD *)unit[i] = (DWORD)(img + RVA_UNIT_VT);
    }
    *(DWORD *)(unit[0] + 0x30) = 'Hpal', *(DWORD *)(unit[1] + 0x30) = 'hfoo';
    memset(sh.buffLeft, 0, sizeof(sh.buffLeft));
    ReadBuffs(ui);
    CHECK(sh.buffCount == 2 && sh.buffLeft[0] == 4.5f && sh.buffTotal[0] == 12 && sh.buffTotal[1] == 20 && sh.buffId[0] == 'Binf',
          "a hero's buff: %.1f of %.0f (+0xc8), a footman's: of %.0f (+0xc0), the rawcode [buff+0x34]", sh.buffLeft[0], sh.buffTotal[0], sh.buffTotal[1]);
    // a linked kind ('Bpsd'): its times come from the buff its +0x114 handle points at
    DWORD *lvt = (DWORD *)(img + 0xa70800);
    lvt[0x1e8 / 4] = bvt[0x1e8 / 4], lvt[0x1c / 4] = IntGetter(0x601020, 'Bpsd');
    DWORD *l2 = (DWORD *)(img + 0xa70c00);
    l2[0x1c / 4] = IntGetter(0x601030, 'BXXX');
    *(DWORD *)buff[1] = (DWORD)lvt, ((DWORD *)(buff[1] + BUFF_LINK))[0] = 9, ((DWORD *)(buff[1] + BUFF_LINK))[1] = 9;
    *(BYTE **)(flagsObj + 0x54) = linked, *(DWORD *)linked = (DWORD)l2;    // the lookup's object -> [+0x54]
    *(DWORD *)(linked + 0x84) = (DWORD)evt, *(float *)(linked + 0xc0) = 25, *(float *)(linked + 0xc8) = 25;
    ReadBuffs(ui);
    CHECK(sh.buffTotal[1] == 25, "a linked buff ('Bpsd'): the times of the buff it points at (%.0f)", sh.buffTotal[1]);
    Verdict();
    return g_fails;
}
